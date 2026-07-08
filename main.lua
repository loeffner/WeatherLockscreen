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
    -- One-shot: the next screensaver show is a periodic (active-sleep) refresh,
    -- so skip the loading icon even when no widget is currently on screen.
    active_sleep_refresh = false,
    -- When true, fetchWeatherData renders the last cache instantly without any
    -- network access (used for the instant cache-first show on RTC wake).
    prefer_cache = false,
    -- Our own reference to the screensaver widget showing our weather content,
    -- used as a safety net to close it on plugin teardown. Refreshes swap the
    -- widget's content in place, so at most one such widget exists at a time.
    weather_screensaver_widget = nil,
    -- Charging-refresh: while on external power the device won't deep-suspend
    -- (so RTC wakes never fire); refresh via a UIManager timer instead. Active
    -- while plugged in with an effective (charging or base) interval set.
    charging_refresh_active = false,
    chargingRefreshCallback = nil,
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
        weather_override_rotation = false, -- when false, use KOReader's rotation
        weather_orientation = 0, -- Screen rotation mode 0-3 (0 = upright portrait); day/default only
        weather_override_scaling = false,
        weather_fill_percent = 90,
        weather_cover_scaling = "zoom",

        -- Cache settings
        weather_cache_max_age = 3600,    -- 1 hour
        weather_min_update_delay = 1800, -- 30 minutes

        -- Periodic refresh settings
        weather_periodic_refresh_rtc = 0,                -- Off by default
        weather_periodic_refresh_dashboard = 0,          -- Off by default
        weather_periodic_refresh_rtc_charging = 0,       -- 0 = use base interval
        weather_periodic_refresh_dashboard_charging = 0, -- 0 = use base interval
        weather_active_sleep_min_battery = 20,

        -- Fallback settings (when weather data unavailable)
        weather_fallback_type = "cover", -- Default: show book cover

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
        -- Must be set on the instance: a successful fetch clears the instance
        -- field, which would shadow a class-level write on every later read.
        self.refresh = true
        -- Mark the upcoming screensaver show as a refresh so it skips the loading
        -- icon (on Kobo this re-show happens just below; on Kindle it happens
        -- after the wake, re-affirmed in onResume).
        self.active_sleep_refresh = true

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

    -- Charging-refresh timer task (must be instance-specific for UIManager)
    self.chargingRefreshCallback = function()
        -- Stop if the weather sleep screen is no longer up, or we're off power.
        if not (Device.screen_saver_mode
                and G_reader_settings:readSetting("screensaver_type") == "weather")
            or not WeatherUtils:isOnExternalPower() then
            self:exitChargingRefresh()
            return
        end
        logger.info("WeatherLockscreen: Charging-refresh timer fired")
        self.refresh = true
        self.active_sleep_refresh = true
        require("ui/screensaver"):show()
        self:armChargingTimer()
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

function WeatherLockscreen:setPeriodicRefreshInterval(interval, type, touchmenu_instance, charging)
    local setting_key
    if charging then
        setting_key = type == "rtc"
            and "weather_periodic_refresh_rtc_charging"
            or "weather_periodic_refresh_dashboard_charging"
    else
        setting_key = type == "rtc"
            and "weather_periodic_refresh_rtc"
            or "weather_periodic_refresh_dashboard"
    end

    local function applyInterval()
        G_reader_settings:saveSetting(setting_key, interval)
        G_reader_settings:flush()
        touchmenu_instance:updateItems()
    end

    -- The charging override doesn't need the power-consumption warning (the base
    -- interval already prompted for it), so apply it directly.
    if charging or interval == 0 or WeatherUtils:periodicRefreshEnabled(type) then
        applyInterval()
    else
        local ConfirmBox = require("ui/widget/confirmbox")
        local warning_msg
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
            ok_callback = applyInterval,
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

            -- Schedule periodic refresh when screen locks (RTC on battery, or a
            -- standby timer while charging since the device won't deep-suspend).
            plugin_instance:scheduleRefresh()

            -- Detect an in-place refresh: a screensaver widget is already on
            -- screen (e.g. a periodic refresh re-entering Screensaver:show), or
            -- the active-sleep path flagged this show as a refresh (on Kindle the
            -- wake destroys the widget, so widget-presence alone can't detect
            -- it). A refresh keeps the current display up, without loading icon.
            local is_refresh = screensaver_instance.screensaver_widget ~= nil
                or plugin_instance.active_sleep_refresh
            -- Consume the one-shot active-sleep flag.
            plugin_instance.active_sleep_refresh = false

            -- Set device to screen saver mode first
            Device.screen_saver_mode = true

            -- Apply the configured orientation only when no screensaver widget
            -- is currently up: ScreenSaverWidget:onCloseWidget is what restores
            -- Device.orig_rotation_mode, so the saved rotation must span exactly
            -- one widget's lifetime.
            if not screensaver_instance.screensaver_widget then
                Device.orig_rotation_mode = WeatherUtils:applyOrientation()
            end

            -- Show the loading icon only on the initial show (nothing of ours is
            -- displayed yet). On a refresh the existing weather stays up instead.
            if not is_refresh then
                screensaver_instance.hourglass_widget = DisplayHelper:createLoadingWidget()
                if screensaver_instance.hourglass_widget then
                    UIManager:show(screensaver_instance.hourglass_widget, "full")
                    logger.dbg("WeatherLockscreen: Loading widget displayed")
                end
            end

            -- Define function to create and show weather widget
            local function screensaverShow()
                logger.dbg("WeatherLockscreen: Creating widget")
                local weather_widget = plugin_instance:createWeatherWidget()

                -- The screensaver widget currently on screen, if any (ours or a
                -- fallback one created through the original show). Closing a
                -- ScreenSaverWidget has global side effects, even when it is no
                -- longer on the window stack: onCloseWidget restores the
                -- rotation, broadcasts OutOfScreenSaver and resets
                -- Device.screen_saver_mode via Screensaver:cleanup. So a refresh
                -- must never close it while the sleep screen stays up -- it
                -- swaps the widget's content in place instead.
                local on_screen = screensaver_instance.screensaver_widget

                local function closeLoadingWidget()
                    if screensaver_instance.hourglass_widget then
                        UIManager:close(screensaver_instance.hourglass_widget)
                        screensaver_instance.hourglass_widget = nil
                        logger.dbg("WeatherLockscreen: Loading widget closed")
                    end
                end

                if weather_widget then
                    logger.dbg("WeatherLockscreen: Weather widget created successfully")
                    local bg_color = Blitbuffer.COLOR_WHITE
                    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                    if display_style == "nightowl" then
                        bg_color = G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_WHITE or
                            Blitbuffer.COLOR_BLACK
                    end

                    if on_screen then
                        -- In-place refresh: replace the content of the widget
                        -- already on screen (its structure is always
                        -- ScreenSaverWidget[1] = FrameContainer{ content }).
                        local frame = on_screen[1]
                        if frame[1] and frame[1].free then
                            frame[1]:free()
                        end
                        frame[1] = weather_widget
                        frame.background = bg_color
                        on_screen.widget = weather_widget
                        plugin_instance.weather_screensaver_widget = on_screen
                        UIManager:setDirty(on_screen, "full")
                        logger.dbg("WeatherLockscreen: Widget refreshed in place")
                    else
                        local new_widget = ScreenSaverWidget:new {
                            widget = weather_widget,
                            background = bg_color,
                            covers_fullscreen = true,
                        }
                        new_widget.modal = true
                        new_widget.dithered = true
                        screensaver_instance.screensaver_widget = new_widget
                        plugin_instance.weather_screensaver_widget = new_widget

                        UIManager:show(new_widget, "full")
                        logger.dbg("WeatherLockscreen: Widget displayed")
                    end

                    -- Close the loading widget (only shown on the initial show)
                    -- after the weather is up, so there's never a blank frame.
                    closeLoadingWidget()
                elseif on_screen then
                    -- Refresh failed but something is still on screen (stale
                    -- weather marked with *, or a fallback): keep it. Running
                    -- the fallback here would spawn a new screensaver widget on
                    -- every failed refresh without ever closing the previous
                    -- one, stacking them up for the user to dismiss.
                    closeLoadingWidget()
                    logger.warn("WeatherLockscreen: No weather data on refresh, keeping current display")
                else
                    -- Close the loading widget before falling back
                    closeLoadingWidget()

                    plugin_instance.weather_screensaver_widget = nil

                    -- Use configured fallback screensaver type
                    local fallback_type = G_reader_settings:readSetting("weather_fallback_type") or "cover"
                    logger.warn("WeatherLockscreen: No weather data, using fallback:", fallback_type)

                    -- Reset state we've already set up so original screensaver can set it properly
                    Device.screen_saver_mode = false
                    if Device.orig_rotation_mode then
                        Screen:setRotationMode(Device.orig_rotation_mode)
                        Device.orig_rotation_mode = nil
                    end

                    -- Temporarily set screensaver type to fallback (don't flush to disk)
                    G_reader_settings:saveSetting("screensaver_type", fallback_type)

                    -- Let KOReader's screensaver handle setup and display
                    Screensaver:setup()
                    Screensaver._orig_show_before_weather(screensaver_instance)

                    -- Restore weather as the screensaver type (don't flush to disk)
                    G_reader_settings:saveSetting("screensaver_type", "weather")
                end
            end
            -- Create weather widget
            if WeatherUtils:wifiEnableActionTurnOn() and not plugin_instance.prefer_cache then
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

    if not weather_data or not weather_data.current or not weather_data.current.icon_path then
        logger.warn("WeatherLockscreen: No weather data available, using fallback")
        return nil, true -- Signal to use fallback screensaver
    end

    -- A refresh is pending until a fresh fetch clears self.refresh (cache-first
    -- renders and failed fetches leave it set). Surfacing it in the header lets
    -- the display show a "refreshing, please wait" line in place of the location.
    weather_data.refreshing = self.refresh and true or false

    -- Check display style setting
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    logger.dbg("WeatherLockscreen: Using display style: " .. display_style)

    -- Load appropriate display module
    local display_modules = {
        card = "display_card",
        day = "display_day",
        nightowl = "display_nightowl",
        retro = "display_retro",
        reading = "display_reading",
    }
    local display_module = require(display_modules[display_style] or "display_default")

    return display_module:create(self, weather_data), false
end

-- Choose the refresh mechanism based on power state. On external power the
-- device won't deep-suspend (Kindle), so RTC wakes never fire; refresh via a
-- UI timer instead. On battery we use RTC active sleep.
function WeatherLockscreen:scheduleRefresh()
    -- The effective interval falls back to the base one when no charging
    -- override is set, so plugging in never silently disables the refresh.
    -- The Wi-Fi gate mirrors schedulePeriodicRefresh.
    if WeatherUtils:isOnExternalPower()
        and WeatherUtils:getEffectiveRefreshInterval("rtc") > 0
        and WeatherUtils:wifiEnableActionTurnOn() then
        -- Cancel any RTC wakeup; it can't fire while charging anyway.
        if self.rtc_wakeup_scheduled and self.wakeup_mgr then
            self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
            self.rtc_wakeup_scheduled = false
        end
        self:enterChargingRefresh()
    else
        self:exitChargingRefresh()
        self:schedulePeriodicRefresh()
    end
end

-- (Re)arm the standby refresh timer for the charging interval.
function WeatherLockscreen:armChargingTimer()
    UIManager:unschedule(self.chargingRefreshCallback)
    local interval = WeatherUtils:getEffectiveRefreshInterval("rtc")
    if interval <= 0 then return end
    logger.dbg("WeatherLockscreen: Arming charging-refresh timer in", interval, "seconds")
    UIManager:scheduleIn(interval, self.chargingRefreshCallback)
end

-- Enter charging-refresh mode: prevent deep suspend (but leave standby allowed,
-- for low power) and arm the refresh timer.
function WeatherLockscreen:enterChargingRefresh()
    if not self.charging_refresh_active then
        self.charging_refresh_active = true
        local PluginShare = require("pluginshare")
        PluginShare.pause_auto_suspend = true
        logger.info("WeatherLockscreen: Entered charging-refresh mode (deep suspend paused, standby allowed)")
    end
    self:armChargingTimer()
end

-- Leave charging-refresh mode: drop the timer and re-allow deep suspend.
function WeatherLockscreen:exitChargingRefresh()
    if not self.charging_refresh_active then return end
    self.charging_refresh_active = false
    UIManager:unschedule(self.chargingRefreshCallback)
    local PluginShare = require("pluginshare")
    PluginShare.pause_auto_suspend = false
    logger.info("WeatherLockscreen: Exited charging-refresh mode")
end

function WeatherLockscreen:schedulePeriodicRefresh()
    -- Cancel any existing RTC wakeup
    if self.rtc_wakeup_scheduled and self.wakeup_mgr then
        self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = false
    end

    local interval = WeatherUtils:getEffectiveRefreshInterval("rtc")
    logger.info("WeatherLockscreen: RTC interval base=", WeatherUtils:getPeriodicRefreshInterval("rtc"),
        "charging_override=", WeatherUtils:getChargingRefreshInterval("rtc"),
        "on_power=", WeatherUtils:isOnExternalPower(), "-> effective=", interval)
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

-- Re-evaluate the charging-aware refresh interval when the power state changes
-- (e.g. the user plugs in after locking). Without this, a new interval would
-- only take effect at the next scheduled wake.
function WeatherLockscreen:onPowerStateChanged()
    -- Active Sleep: re-pick the refresh mechanism if the weather screensaver is
    -- active (RTC on battery, standby timer while charging).
    if Device.screen_saver_mode and G_reader_settings:readSetting("screensaver_type") == "weather" then
        logger.dbg("WeatherLockscreen: Power state changed, re-evaluating refresh mechanism")
        self:scheduleRefresh()
    end
    -- Dashboard: reschedule the next refresh to the new interval.
    if self.dashboard_mode_enabled then
        logger.dbg("WeatherLockscreen: Power state changed, rescheduling dashboard refresh")
        if self.dashboard_refresh_task then
            UIManager:unschedule(self.dashboard_refresh_task)
        end
        WeatherDashboard:scheduleNextRefresh(self)
    end
end

function WeatherLockscreen:onCharging()
    self:onPowerStateChanged()
end

function WeatherLockscreen:onNotCharging()
    self:onPowerStateChanged()
end

function WeatherLockscreen:onSuspend()
    logger.dbg("WeatherLockscreen: Device suspending")

    -- Let dashboard handle suspend if active
    if not WeatherDashboard:onSuspend(self) then
        -- Save current frontlight intensity and turn off
        WeatherUtils:suspendFrontlight(self)
    end
end

-- Close the weather screensaver widget we track, but only while KOReader still
-- knows it as the active screensaver widget. UIManager:close fires CloseWidget
-- even for widgets no longer on the window stack, and re-running
-- ScreenSaverWidget:onCloseWidget on a dead widget would clobber the rotation
-- and Device.screen_saver_mode a second time.
function WeatherLockscreen:closeWeatherScreensaver()
    if self.weather_screensaver_widget then
        local Screensaver = require("ui/screensaver")
        if Screensaver.screensaver_widget == self.weather_screensaver_widget then
            -- Screensaver:cleanup (via onCloseWidget) nils KOReader's reference
            UIManager:close(self.weather_screensaver_widget)
            logger.dbg("WeatherLockscreen: Closed weather screensaver widget")
        end
        self.weather_screensaver_widget = nil
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

        -- Close any existing loading widget.
        if self.loading_widget then
            UIManager:close(self.loading_widget)
            self.loading_widget = nil
            logger.dbg("WeatherLockscreen: Closed existing loading widget")
        end

        -- Cache-first refresh: on a Kindle RTC wake the screensaver widget is
        -- gone (the library is showing). Re-display the last cached weather
        -- instantly (no network, no loading icon) so weather stays on screen,
        -- then fetch fresh data and swap it in place, then re-suspend.
        local Screensaver = require("ui/screensaver")

        -- Step 1: instant cached render (prefer_cache short-circuits the network).
        self.active_sleep_refresh = true
        self.prefer_cache = true
        Screensaver:show()
        self.prefer_cache = false

        -- Step 2: fetch fresh data and swap in place (the existing cached widget
        -- stays visible during the Wi-Fi connect; no loading icon). Re-affirm the
        -- flag in case step 1 had no cache to show (so we still skip the icon).
        self.active_sleep_refresh = true
        self.refresh = true
        Screensaver:show()

        -- Step 3: retry until the fetch succeeds, then re-suspend. Right after
        -- wake, Wi-Fi reports online before routing is actually up and the fetch
        -- fails with "Network is unreachable" -- on-device the route can take
        -- ~10s to appear, so a single retry is not enough. self.refresh stays
        -- set until a fetch succeeds; re-suspend as soon as it does (or after
        -- the last attempt), instead of a fixed delay.
        local retries = 0
        local function retryOrSuspend()
            -- The user woke the device (or switched wallpaper) in the meantime:
            -- it's theirs now, don't put it back to sleep.
            if not (Device.screen_saver_mode
                    and G_reader_settings:readSetting("screensaver_type") == "weather") then
                logger.info("WeatherLockscreen: Sleep screen gone, skipping re-suspend")
                return
            end
            if self.refresh and retries < 3 then
                retries = retries + 1
                logger.info("WeatherLockscreen: Refresh incomplete, retrying fetch, attempt", retries)
                self.active_sleep_refresh = true
                Screensaver:show()
                UIManager:scheduleIn(5, retryOrSuspend)
                return
            end
            logger.info("WeatherLockscreen: Triggering suspend after refresh")
            WeatherUtils:toggleSuspend()
        end
        UIManager:scheduleIn(5, retryOrSuspend)
    else
        logger.dbg("WeatherLockscreen: Manual wakeup, not from RTC alarm")
        -- Close any existing loading widget
        if self.loading_widget then
            UIManager:close(self.loading_widget)
            self.loading_widget = nil
            logger.dbg("WeatherLockscreen: Closed existing loading widget")
        end

        -- Tear down only when the sleep screen is really over. On wakes that
        -- keep it up -- plugging in the sleeping device, or screensaver_delay
        -- configurations -- Device.screen_saver_mode is still set and KOReader
        -- has not closed the widget; the charging-refresh guard handles those.
        if not Device.screen_saver_mode then
            self:exitChargingRefresh()
            self:closeWeatherScreensaver()
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

    -- Stop the charging-refresh timer and close any lingering weather widget
    self:exitChargingRefresh()
    self:closeWeatherScreensaver()

    -- Cancel RTC wakeup tasks on close
    if self.rtc_wakeup_scheduled and self.wakeup_mgr then
        logger.dbg("WeatherLockscreen: Cancelling RTC periodic refresh on close")
        self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = false
    end
end

return WeatherLockscreen
