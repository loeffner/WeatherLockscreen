--[[
    Weather Lockscreen Plugin for KOReader

    Displays weather information on the sleep screen.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Dispatcher = require("dispatcher")
local WakeupMgr = require("device/wakeupmgr")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local logger = require("logger")
local _ = require("l10n/gettext")
local WeatherAPI = require("weather_api")
local WeatherUtils = require("weather_utils")
local WeatherMenu = require("weather_menu")
local WeatherDashboard = require("weather_dashboard")
local DisplayHelper = require("display_helper")

local WeatherLockscreen = WidgetContainer:extend {
    name = "weatherlockscreen",
    default_location = "London",
    default_api_key = "637e03f814b440f782675255250411",
    default_temp_scale = "C",
    refresh = false,
    simulated_wakeup = false,
    wakeup_mgr = nil,
    rtc_wakeup_scheduled = false,
    rtcRefreshCallback = nil,
    rtcRescheduleCallback = nil,
    hourglass_widget = nil,
    loading_widget = nil,
    saved_frontlight_intensity = nil,
    -- Dashboard mode support
    dashboard_mode_enabled = false,
    dashboard_refresh_task = nil,
    dashboard_widget = nil,
}

function WeatherLockscreen:onDispatcherRegisterActions()
    Dispatcher:registerAction("weather_dashboard_toggle", {
        category = "none",
        event = "ToggleWeatherDashboard",
        title = _("Weather dashboard"),
        general = true,
    })
    Dispatcher:registerAction("weather_clear_cache", {
        category = "none",
        event = "ClearWeatherCache",
        title = _("Clear weather cache"),
        general = true,
    })
end

-- Initialize default settings if not already set
-- This ensures the plugin works correctly on first run
function WeatherLockscreen:initDefaultSettings()
    local defaults = {
        -- Core settings
        weather_location = self.default_location,
        weather_location_name = self.default_location,
        weather_temp_scale = self.default_temp_scale,
        weather_display_style = "default",

        -- Display settings
        weather_show_header = true, -- nilOrTrue default is true
        weather_override_scaling = false,
        weather_fill_percent = 90,
        weather_cover_scaling = "zoom",

        -- Cache settings
        weather_cache_max_age = 3600,    -- 1 hour
        weather_min_update_delay = 1800, -- 30 minutes

        -- Periodic refresh settings
        weather_periodic_refresh_rtc = 0,       -- Off by default
        weather_periodic_refresh_dashboard = 0, -- Off by default
        weather_active_sleep_min_battery = 20,

        -- Debug Options
        weather_debug_options = false, -- Off by default
    }

    local settings_changed = false
    for setting, default_value in pairs(defaults) do
        if G_reader_settings:readSetting(setting) == nil then
            G_reader_settings:saveSetting(setting, default_value)
            settings_changed = true
            logger.dbg("WeatherLockscreen: Initialized setting", setting, "to", default_value)
        end
    end

    if settings_changed then
        G_reader_settings:flush()
        logger.info("WeatherLockscreen: Default settings initialized")
    end
end

function WeatherLockscreen:init()
    self:initDefaultSettings()
    self:onDispatcherRegisterActions()
    WeatherUtils:installIcons()
    self.ui.menu:registerToMainMenu(self)
    self:patchDofile()
    self:patchScreensaver()

    -- Check if device supports RTC wakeup for periodic refresh
    local can_schedule_wakeup = WeatherUtils:canScheduleWakeup()

    if can_schedule_wakeup then
        -- Use device's WakeupMgr if available (properly configured on Kindle with MockRTC)
        -- Otherwise create our own
        if Device.wakeup_mgr then
            self.wakeup_mgr = Device.wakeup_mgr
            logger.dbg("WeatherLockscreen: Using device WakeupMgr")
        end
    else
        logger.info("WeatherLockscreen: RTC wakeup not available, dashboard mode available for all devices")
    end

    self.rtcRefreshCallback = function()
        logger.info("WeatherLockscreen: RTC periodic refresh triggered")
        WeatherLockscreen.refresh = true

        if Device:isKobo() then
            -- Schedule redraw on the UI loop to avoid running a full Screensaver refresh while
            -- we're still in the scheduled wakeup guard path.
            UIManager:scheduleIn(0, function()
                local Screensaver = require("ui/screensaver")
                local ss_type = G_reader_settings:readSetting("screensaver_type")
                if Device.screen_saver_mode and ss_type == "weather" then
                    Screensaver:show()
                else
                    logger.info("WeatherLockscreen: Skipping screensaver redraw on scheduled wakeup")
                end
            end)
        else -- Device is Kindle
            WeatherUtils:toggleSuspend()
            self.simulated_wakeup = true
        end
    end

    -- Dashboard mode refresh task (must be instance-specific for UIManager)
    self.dashboard_refresh_task = function()
        WeatherDashboard:showWidget(self)
    end
end

function WeatherLockscreen:onToggleWeatherDashboard()
    logger.info("WeatherLockscreen: Dashboard toggle triggered")
    if self.dashboard_mode_enabled then
        WeatherDashboard:stop(self)
    else
        WeatherDashboard:start(self)
    end
    return true
end

function WeatherLockscreen:onClearWeatherCache()
    logger.info("WeatherLockscreen: Clear cache triggered")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")

    if WeatherUtils:clearCache() then
        UIManager:show(InfoMessage:new {
            text = _("Weather cache cleared"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new {
            text = _("No cache to clear"),
            timeout = 2,
        })
    end
    return true
end

function WeatherLockscreen:addToMainMenu(menu_items)
    menu_items.weather_lockscreen = {
        text = _("Weather Lockscreen"),
        sub_item_table_func = function()
            return WeatherMenu:getSubMenuItems(self)
        end,
        sorting_hint = "tools",
    }
end

function WeatherLockscreen:setPeriodicRefreshInterval(interval, type, touchmenu_instance)
    if interval == 0 or WeatherUtils:periodicRefreshEnabled(type) then
        if type == "rtc" then
            G_reader_settings:saveSetting("weather_periodic_refresh_rtc", interval)
        else
            G_reader_settings:saveSetting("weather_periodic_refresh_dashboard", interval)
        end
        G_reader_settings:flush()
        touchmenu_instance:updateItems()
    else
        local ConfirmBox = require("ui/widget/confirmbox")
        local warning_msg = ""
        if type == "rtc" then
            warning_msg = _(
                "Active sleep will wake the device from sleep to update weather data.\nThis will increase power consumption while the device is locked.\n\nContinue?")
        else
            warning_msg = _(
                "The dashboard will keep the device awake and regularly update weather data.\nThis will increase power consumption while the dashboard is active.\n\nContinue?")
        end
        UIManager:show(ConfirmBox:new {
            text = warning_msg,
            ok_text = _("Enable"),
            ok_callback = function()
                if type == "rtc" then
                    G_reader_settings:saveSetting("weather_periodic_refresh_rtc", interval)
                else
                    G_reader_settings:saveSetting("weather_periodic_refresh_dashboard", interval)
                end
                G_reader_settings:flush()
                touchmenu_instance:updateItems()
            end,
        })
    end
end

function WeatherLockscreen:patchScreensaver()
    -- Store reference to self for use in closures
    local plugin_instance = self

    -- Hook into Screensaver.show() to handle "weather" type
    local Screensaver = require("ui/screensaver")

    -- Save original show method if not already saved
    if not Screensaver._orig_show_before_weather then
        Screensaver._orig_show_before_weather = Screensaver.show
    end

    Screensaver.show = function(screensaver_instance)
        local ss_type = G_reader_settings:readSetting("screensaver_type")
        if ss_type == "weather" then
            screensaver_instance.screensaver_type = "weather"
            logger.dbg("WeatherLockscreen: Weather screensaver activated")

            -- Schedule periodic refresh when screen locks
            plugin_instance:schedulePeriodicRefresh()

            -- Close any existing screensaver widget
            if screensaver_instance.screensaver_widget then
                UIManager:close(screensaver_instance.screensaver_widget)
                screensaver_instance.screensaver_widget = nil
            end

            -- Set device to screen saver mode first
            Device.screen_saver_mode = true

            -- Handle rotation if needed
            local rotation_mode = Screen:getRotationMode()
            Device.orig_rotation_mode = rotation_mode
            local bit = require("bit")
            if bit.band(Device.orig_rotation_mode, 1) == 1 then
                Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
            else
                Device.orig_rotation_mode = nil
            end

            -- Show loading icon while fetching weather data
            screensaver_instance.hourglass_widget = DisplayHelper:createLoadingWidget()
            if screensaver_instance.hourglass_widget then
                UIManager:show(screensaver_instance.hourglass_widget, "full")
                logger.dbg("WeatherLockscreen: Loading widget displayed")
            end

            -- Define function to create and show weather widget
            local function screensaverShow()
                -- Close loading widget first
                if screensaver_instance.hourglass_widget then
                    UIManager:close(screensaver_instance.hourglass_widget)
                    screensaver_instance.hourglass_widget = nil
                    logger.dbg("WeatherLockscreen: Loading widget closed")
                end

                logger.dbg("WeatherLockscreen: Creating widget")
                local weather_widget, fallback = plugin_instance:createWeatherWidget()

                if weather_widget then
                    logger.dbg("WeatherLockscreen: Weather widget created successfully")
                    local bg_color = Blitbuffer.COLOR_WHITE
                    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                    if display_style == "nightowl" and not fallback then
                        bg_color = G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_WHITE or
                            Blitbuffer.COLOR_BLACK
                    end

                    screensaver_instance.screensaver_widget = ScreenSaverWidget:new {
                        widget = weather_widget,
                        background = bg_color,
                        covers_fullscreen = true,
                    }
                    screensaver_instance.screensaver_widget.modal = true
                    screensaver_instance.screensaver_widget.dithered = true

                    UIManager:show(screensaver_instance.screensaver_widget, "full")
                    logger.dbg("WeatherLockscreen: Widget displayed")
                else
                    logger.warn("WeatherLockscreen: Failed to create widget, falling back")
                    screensaver_instance.screensaver_type = "disable"
                    Screensaver._orig_show_before_weather(screensaver_instance)
                end
            end
            -- Create weather widget
            if WeatherUtils:wifiEnableActionTurnOn() then
                -- TODO: See if we want to use the cache before turning on the wifi (needs refactoring)
                logger.dbg("WeatherLockscreen: Creating widget (will wait for network if needed)")

                -- Use safe wrapper to go online with proper error handling
                WeatherUtils:safeGoOnlineToRun(
                    function()
                        logger.dbg("WeatherLockscreen: Network is online, showing screensaver")
                        screensaverShow()
                    end,
                    function()
                        -- Fallback: show screensaver anyway with potentially cached data
                        logger.dbg("WeatherLockscreen: Network connection failed, showing screensaver with cached data")
                        screensaverShow()
                    end,
                    true -- suppress network messages
                )
            else
                logger.dbg("WeatherLockscreen: Creating widget (will not wait for network)")
                screensaverShow()
            end
        else
            logger.dbg("WeatherLockscreen: Non-weather screensaver activated, calling original show")
            Screensaver._orig_show_before_weather(screensaver_instance)
        end
    end
end

function WeatherLockscreen:patchDofile()
    -- Patch the screensaver menu to add weather option
    -- We need to override dofile to inject our menu item
    if not _G._orig_dofile_before_weather then
        local orig_dofile = dofile
        _G._orig_dofile_before_weather = orig_dofile

        _G.dofile = function(filepath)
            local result = orig_dofile(filepath)

            -- Check if this is the screensaver menu being loaded
            if filepath and filepath:match("screensaver_menu%.lua$") then
                logger.dbg("WeatherLockscreen: Patching screensaver menu")

                if result and result[1] and result[1].sub_item_table then
                    local wallpaper_submenu = result[1].sub_item_table

                    local function genMenuItem(text, setting, value, enabled_func, separator)
                        return {
                            text = text,
                            enabled_func = enabled_func,
                            checked_func = function()
                                return G_reader_settings:readSetting(setting) == value
                            end,
                            callback = function()
                                G_reader_settings:saveSetting(setting, value)
                            end,
                            radio = true,
                            separator = separator,
                        }
                    end

                    -- Add weather option
                    local weather_item = genMenuItem(_("Show weather on sleep screen"), "screensaver_type", "weather")

                    -- Insert before "Leave screen as-is" option (position 6)
                    table.insert(wallpaper_submenu, 6, weather_item)

                    logger.dbg("WeatherLockscreen: Added weather option to screensaver menu")
                end

                -- Restore original dofile after patching
                _G.dofile = orig_dofile
                _G._orig_dofile_before_weather = nil
            end

            return result
        end
    end
end

function WeatherLockscreen:createWeatherWidget()
    logger.dbg("WeatherLockscreen: Creating widget")
    local weather_data = WeatherAPI:fetchWeatherData(self)
    local fallback = false

    if not weather_data or not weather_data.current or not weather_data.current.icon_path then
        logger.warn("WeatherLockscreen: No weather data available, trying fallback")
        fallback = true
        return DisplayHelper:createFallbackWidget(), fallback
    end

    -- Check display style setting
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    logger.dbg("WeatherLockscreen: Using display style: " .. display_style)

    -- Load appropriate display module
    local display_module
    if display_style == "card" then
        display_module = require("display_card")
    elseif display_style == "nightowl" then
        display_module = require("display_nightowl")
    elseif display_style == "retro" then
        display_module = require("display_retro")
    elseif display_style == "reading" then
        display_module = require("display_reading")
    else
        display_module = require("display_default")
    end

    return display_module:create(self, weather_data), fallback
end

function WeatherLockscreen:schedulePeriodicRefresh()
    -- Cancel any existing RTC wakeup
    if self.rtc_wakeup_scheduled and self.wakeup_mgr then
        self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = false
    end

    local interval = WeatherUtils:getPeriodicRefreshInterval("rtc")
    if interval == 0 then
        logger.dbg("WeatherLockscreen: Periodic refresh disabled")
        return
    end

    local wifi_turn_on = WeatherUtils:wifiEnableActionTurnOn()
    if wifi_turn_on == false then
        logger.dbg("WeatherLockscreen: Periodic refresh disabled due to Wi-Fi action setting")
        return
    end

    local min_batt = WeatherUtils:getActiveSleepMinBattery()
    if min_batt > 0 then
        local capacity = WeatherUtils:getBatteryCapacity()
        if capacity and capacity < min_batt then
            logger.info("WeatherLockscreen: Periodic refresh disabled due to low battery (", capacity, "<", min_batt, ")")
            return
        end
    end

    -- Try RTC scheduling if WakeupMgr is available
    if self.wakeup_mgr then
        logger.info("WeatherLockscreen: Scheduling RTC-based periodic refresh every", interval, "seconds")

        -- Add task to WakeupMgr queue
        -- On Kindle, this will be picked up by powerd during ReadyToSuspend
        self.wakeup_mgr:addTask(interval, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = true
    else
        logger.warn("WeatherLockscreen: WakeupMgr not available")
    end
end

function WeatherLockscreen:onSuspend()
    logger.dbg("WeatherLockscreen: Device suspending")

    -- Let dashboard handle suspend if active
    if not WeatherDashboard:onSuspend(self) then
        -- Save current frontlight intensity and turn off
        WeatherUtils:suspendFrontlight(self)
    end
end

function WeatherLockscreen:onResume()
    logger.dbg("WeatherLockscreen: Device resuming")

    -- Check if we woke up due to an RTC alarm and execute the action
    if self.simulated_wakeup then
        -- Cancel any existing RTC wakeup
        if not Device:isKobo() and self.rtc_wakeup_scheduled and self.wakeup_mgr then
            self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
            self.rtc_wakeup_scheduled = false
        end

        -- Reset the flag
        self.simulated_wakeup = false
        logger.info("WeatherLockscreen: Woke up from scheduled RTC alarm")

        -- Close any existing loading widget
        if self.loading_widget then
            UIManager:close(self.loading_widget)
            self.loading_widget = nil
            logger.dbg("WeatherLockscreen: Closed existing loading widget")
        end

        -- Show loading widget during refresh
        self.loading_widget = DisplayHelper:createLoadingWidget()
        if self.loading_widget then
            UIManager:show(self.loading_widget, "full")
            logger.dbg("WeatherLockscreen: Loading widget displayed during RTC refresh")
        end

        -- Trigger suspend again after refresh completes
        UIManager:scheduleIn(10, function()
            logger.info("WeatherLockscreen: Triggering suspend after refresh")
            WeatherUtils:toggleSuspend()
        end)
    else
        logger.dbg("WeatherLockscreen: Manual wakeup, not from RTC alarm")
        -- Close any existing loading widget
        if self.loading_widget then
            UIManager:close(self.loading_widget)
            self.loading_widget = nil
            logger.dbg("WeatherLockscreen: Closed existing loading widget")
        end

        if not WeatherDashboard:onResume(self) then
            -- Resume frontlight intensity
            WeatherUtils:resumeFrontlight(self)
        end
    end
end

function WeatherLockscreen:onCloseWidget()
    -- Stop dashboard mode
    if self.dashboard_mode_enabled then
        WeatherDashboard:stop(self)
    end

    -- Cancel RTC wakeup tasks on close
    if self.rtc_wakeup_scheduled and self.wakeup_mgr then
        logger.dbg("WeatherLockscreen: Cancelling RTC periodic refresh on close")
        self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = false
    end
end

return WeatherLockscreen
