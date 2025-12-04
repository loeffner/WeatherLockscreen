--[[
    Dashboard Mode for Weather Lockscreen Plugin

    Handles dashboard mode functionality including widget display,
    refresh scheduling, and lifecycle management.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local UIManager = require("ui/uimanager")
local PluginShare = require("pluginshare")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local WeatherUtils = require("weather_utils")
local logger = require("logger")

local WeatherDashboard = {}

function WeatherDashboard:start(weather_lockscreen)
    if weather_lockscreen.dashboard_mode_enabled then
        logger.info("WeatherLockscreen: Dashboard mode already active")
        return
    end

    logger.info("WeatherLockscreen: Starting dashboard mode")
    weather_lockscreen.dashboard_mode_enabled = true

    -- Prevent device from auto-suspending
    PluginShare.pause_auto_suspend = true
    UIManager:preventStandby()
    logger.info("WeatherLockscreen: Device sleep prevented")

    -- Suspend frontlight intensity
    WeatherUtils:suspendFrontlight(weather_lockscreen)

    -- Show weather widget immediately
    self:showWidget(weather_lockscreen)
end

function WeatherDashboard:stop(weather_lockscreen)
    if not weather_lockscreen.dashboard_mode_enabled then
        logger.dbg("WeatherLockscreen: Dashboard mode already stopped")
        return
    end

    logger.info("WeatherLockscreen: Stopping dashboard mode")

    -- Restore frontlight intensity
    WeatherUtils:resumeFrontlight(weather_lockscreen)

    -- Unschedule any pending refresh
    if weather_lockscreen.dashboard_refresh_task then
        UIManager:unschedule(weather_lockscreen.dashboard_refresh_task)
    end

    -- Close the dashboard widget
    if weather_lockscreen.dashboard_widget then
        UIManager:close(weather_lockscreen.dashboard_widget)
        weather_lockscreen.dashboard_widget = nil
    end

    weather_lockscreen.dashboard_mode_enabled = false

    -- Re-enable auto-suspend
    PluginShare.pause_auto_suspend = false
    UIManager:allowStandby()
    logger.info("WeatherLockscreen: Device sleep re-enabled")
end

function WeatherDashboard:showWidget(weather_lockscreen)
    if not weather_lockscreen.dashboard_mode_enabled then
        logger.dbg("WeatherLockscreen: Dashboard mode disabled, not showing widget")
        return
    end

    logger.info("WeatherLockscreen: Showing dashboard widget")

    -- Close existing widget if any
    if weather_lockscreen.dashboard_widget then
        UIManager:close(weather_lockscreen.dashboard_widget)
        weather_lockscreen.dashboard_widget = nil
        logger.dbg("WeatherLockscreen: Closed existing dashboard widget")
    end

    -- Force refresh to fetch new data
    weather_lockscreen.refresh = true

    -- Create weather widget
    local weather_widget, fallback = weather_lockscreen:createWeatherWidget()
    if not weather_widget then
        logger.warn("WeatherLockscreen: Failed to create weather widget")
        self:stop(weather_lockscreen)
        return
    end

    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    local bg_color = Blitbuffer.COLOR_WHITE
    if display_style == "nightowl" and not fallback then
        bg_color = G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    end

    -- Create a simple background container instead of ScreenSaverWidget
    local background_widget = FrameContainer:new {
        background = bg_color,
        bordersize = 0,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        dithered = true,
        weather_widget,
    }

    local Input = Device.input
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Capture references for closures
    local plugin_instance = weather_lockscreen
    local dashboard_module = self

    weather_lockscreen.dashboard_widget = InputContainer:new {
        dimen = {
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        background_widget,
    }

    -- Add tap handler to close and stop dashboard mode (anonymous function like TRMNL)
    weather_lockscreen.dashboard_widget.onTapClose = function()
        logger.info("WeatherLockscreen: Dashboard dismissed by tap")
        dashboard_module:stop(plugin_instance)
        return true
    end

    -- Add key press handler for non-touch devices (anonymous function like TRMNL)
    weather_lockscreen.dashboard_widget.onAnyKeyPressed = function()
        logger.info("WeatherLockscreen: Dashboard dismissed by key press")
        dashboard_module:stop(plugin_instance)
        return true
    end

    -- Register tap gesture for touch devices
    if Device:isTouchDevice() then
        weather_lockscreen.dashboard_widget.ges_events = {
            TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0, y = 0,
                        w = screen_width,
                        h = screen_height,
                    }
                }
            }
        }
    end

    -- Register key events for non-touch devices
    if Device:hasKeys() then
        weather_lockscreen.dashboard_widget.key_events = {
            AnyKeyPressed = { { Input.group.Any } }
        }
    end

    UIManager:show(weather_lockscreen.dashboard_widget)

    -- Trigger screen refresh (like TRMNL does)
    UIManager:setDirty(weather_lockscreen.dashboard_widget, "full")
    UIManager:forceRePaint()
    logger.info("WeatherLockscreen: Dashboard widget displayed")

    -- Schedule next refresh
    self:scheduleNextRefresh(weather_lockscreen)
end

function WeatherDashboard:scheduleNextRefresh(weather_lockscreen)
    if not weather_lockscreen.dashboard_mode_enabled then
        return
    end

    local interval = WeatherUtils:getPeriodicRefreshInterval("dashboard")
    if interval > 0 then
        logger.info("WeatherLockscreen: Scheduling next dashboard refresh in", interval, "seconds")
        UIManager:scheduleIn(interval, weather_lockscreen.dashboard_refresh_task)
    else
        logger.warn("WeatherLockscreen: Dashboard mode enabled but interval is 0, stopping")
        self:stop(weather_lockscreen)
    end
end

function WeatherDashboard:onSuspend(weather_lockscreen)
    -- Unschedule dashboard mode task during suspend
    if weather_lockscreen.dashboard_mode_enabled and weather_lockscreen.dashboard_refresh_task then
        UIManager:unschedule(weather_lockscreen.dashboard_refresh_task)
        logger.dbg("WeatherLockscreen: Dashboard refresh task unscheduled for suspend")
        return true -- Indicates dashboard handled suspend
    end
    return false
end

function WeatherDashboard:onResume(weather_lockscreen)
    -- Stop dashboard if it was active before resume
    if weather_lockscreen.dashboard_mode_enabled and weather_lockscreen.dashboard_refresh_task then
        self:stop(weather_lockscreen)
        return true -- Indicates dashboard handled resume
    end
    return false
end

return WeatherDashboard
