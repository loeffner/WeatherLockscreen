--[[
    Weather Lockscreen Plugin for KOReader

    Displays weather information on the sleep screen.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local Blitbuffer = require("ffi/blitbuffer")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local logger = require("logger")
local _ = require("l10n/gettext")
local WeatherAPI = require("weather_api")
local WeatherUtils = require("weather_utils")
local WeatherMenu = require("weather_menu")

local WeatherLockscreen = WidgetContainer:extend {
    name = "weatherlockscreen",
    is_doc_only = false,
    default_location = "London",
    default_api_key = "637e03f814b440f782675255250411",
    default_temp_scale = "C",
    refresh = false,
    periodic_refresh_task = nil,
}

function WeatherLockscreen:init()
    WeatherUtils:installIcons()
    self.ui.menu:registerToMainMenu(self)
    self:patchDofile()
    self:patchScreensaver()
end

function WeatherLockscreen:getPeriodicRefreshInterval()
    return G_reader_settings:readSetting("weather_periodic_refresh") or 0
end

function WeatherLockscreen:schedulePeriodicRefresh()
    -- Cancel any existing scheduled refresh
    if self.periodic_refresh_task then
        UIManager:unschedule(self.periodic_refresh_task)
        self.periodic_refresh_task = nil
    end

    local wifi_turn_on = WeatherUtils:wifiEnableActionTurnOn()
    if wifi_turn_on == false then
        logger.dbg("WeatherLockscreen: Periodic refresh disabled due to Wi-Fi action setting")
        return
    end

    local interval = self:getPeriodicRefreshInterval()
    if interval == 0 then
        logger.dbg("WeatherLockscreen: Periodic refresh disabled")
        return
    end

    logger.dbg("WeatherLockscreen: Scheduling periodic refresh every", interval, "seconds")

    self.periodic_refresh_task = function()
        logger.dbg("WeatherLockscreen: Periodic refresh triggered")
        self:performPeriodicRefresh()
        -- Reschedule the next refresh
        self:schedulePeriodicRefresh()
    end

    UIManager:scheduleIn(interval, self.periodic_refresh_task)
end

function WeatherLockscreen:performPeriodicRefresh()
    logger.dbg("WeatherLockscreen: Starting periodic weather refresh")

    -- Check if we should try to connect to network
    local NetworkMgr = require("ui/network/manager")
    local was_connected = NetworkMgr:isConnected()

    if not was_connected then
        logger.dbg("WeatherLockscreen: Not connected, attempting silent connection...")
        -- Try to turn on WiFi without user prompts
        NetworkMgr:turnOnWifi(function()
            logger.dbg("WeatherLockscreen: WiFi enabled successfully")
            self:doPeriodicRefresh()
        end, function()
            logger.warn("WeatherLockscreen: Failed to enable WiFi")
        end)
    else
        self:doPeriodicRefresh()
    end
end

function WeatherLockscreen:doPeriodicRefresh()
    logger.dbg("WeatherLockscreen: Fetching weather data for periodic refresh")

    -- Force refresh by setting the flag
    self.refresh = true

    -- Use the normal screensaver flow to ensure proper unlock behavior
    local Screensaver = require("ui/screensaver")
    Screensaver.screensaver_type = "weather"
    Screensaver:show(Screensaver)
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
        if screensaver_instance.screensaver_type == "weather" then
            logger.dbg("WeatherLockscreen: Weather screensaver activated")

            -- Close any existing screensaver widget
            if screensaver_instance.screensaver_widget then
                UIManager:close(screensaver_instance.screensaver_widget)
                screensaver_instance.screensaver_widget = nil
            end

            -- Set device to screen saver mode
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

            -- Create weather widget
            local weather_widget, fallback = plugin_instance:createWeatherWidget()

            if weather_widget then
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
        else
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

function WeatherLockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data, text_color, is_cached)
    return WeatherUtils:createHeaderWidgets(header_font_size, header_margin, weather_data, text_color, is_cached)
end

function WeatherLockscreen:fetchWeatherData()
    return WeatherAPI:fetchWeatherData(self)
end

function WeatherLockscreen:clearCache()
    return WeatherUtils:clearCache()
end

function WeatherLockscreen:createFallbackWidget()
    logger.dbg("WeatherLockscreen: Creating fallback icon")

    local icon_size = Screen:scaleBySize(200)

    local current_hour = tonumber(os.date("%H"))
    local is_daytime = current_hour >= 6 and current_hour < 18

    local icon_filename = is_daytime and "sun.svg" or "moon.svg"
    local icon_path = DataStorage:getDataDir() .. "/icons/" .. icon_filename

    local f = io.open(icon_path, "r")
    if f then
        f:close()
    else
        return nil
    end

    local icon_widget = ImageWidget:new {
        file = icon_path,
        width = icon_size,
        height = icon_size,
        alpha = true,
        original_in_nightmode = false
    }

    return CenterContainer:new {
        dimen = Screen:getSize(),
        VerticalGroup:new {
            align = "center",
            icon_widget,
        },
    }
end

function WeatherLockscreen:createWeatherWidget()
    logger.dbg("WeatherLockscreen: Creating widget")
    local weather_data = self:fetchWeatherData()
    local fallback = false

    if not weather_data or not weather_data.current or not weather_data.current.icon_path then
        logger.warn("WeatherLockscreen: No weather data available, trying fallback")
        fallback = true
        return self:createFallbackWidget(), fallback
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

function WeatherLockscreen:onSuspend()
    self:schedulePeriodicRefresh()
    logger.dbg("WeatherLockscreen: Device suspended")
end

function WeatherLockscreen:onResume()
    -- Reschedule if needed after resume
    logger.dbg("WeatherLockscreen: Device resuming")
    if self.periodic_refresh_task then
        logger.dbg("WeatherLockscreen: Cancelling periodic refresh on resume")
        UIManager:unschedule(self.periodic_refresh_task)
        self.periodic_refresh_task = nil
    end
end

function WeatherLockscreen:onCloseWidget()
    -- Clean up scheduled task when plugin is closed
    if self.periodic_refresh_task then
        logger.dbg("WeatherLockscreen: Cancelling periodic refresh on close")
        UIManager:unschedule(self.periodic_refresh_task)
        self.periodic_refresh_task = nil
    end
end

return WeatherLockscreen
