--[[
    Utility Functions for Weather Lockscreen
    Helper functions for time formatting, icon paths, caching, and icon installation
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("l10n/gettext")

local WeatherUtils = {}

-- Get temperature scale setting
function WeatherUtils:getTempScale()
    return G_reader_settings:readSetting("weather_temp_scale") or "C"
end

-- Format temperature from weather data based on user settings
function WeatherUtils:formatTemp(temp_c, temp_f, with_unit)
    if not temp_c or not temp_f then
        return nil
    end

    local temp_scale = self:getTempScale()
    if with_unit == nil then with_unit = true end

    if temp_scale == "C" then
        return with_unit and (temp_c .. "°C") or (temp_c .. "°")
    else
        return with_unit and (temp_f .. "°F") or (temp_f .. "°")
    end
end

-- Get current temperature formatted
function WeatherUtils:getCurrentTemp(weather_data, with_unit)
    if not weather_data or not weather_data.current then
        return nil
    end
    return self:formatTemp(weather_data.current.temp_c, weather_data.current.temp_f, with_unit)
end

-- Get hourly temperature formatted
function WeatherUtils:getHourlyTemp(hour_data, with_unit)
    if not hour_data then
        return nil
    end
    return self:formatTemp(hour_data.temp_c, hour_data.temp_f, with_unit)
end

-- Get forecast high/low formatted
function WeatherUtils:getForecastHighLow(day_data)
    if not day_data or not day_data.high_c or not day_data.low_c then
        return nil
    end

    local temp_scale = self:getTempScale()
    if temp_scale == "C" then
        return day_data.high_c .. "° / " .. day_data.low_c .. "°"
    else
        return day_data.high_f .. "° / " .. day_data.low_f .. "°"
    end
end

-- Get raw temperature value (number only, for calculations)
function WeatherUtils:getTempValue(weather_data)
    if not weather_data or not weather_data.current then
        return nil
    end

    local temp_scale = self:getTempScale()
    return temp_scale == "C" and weather_data.current.temp_c or weather_data.current.temp_f
end

function WeatherUtils:formatHourLabel(hour, twelve_hour_clock)
    if twelve_hour_clock then
        if hour == 0 then
            return "12 AM"
        elseif hour < 12 then
            return hour .. " AM"
        elseif hour == 12 then
            return "12 PM"
        else
            return (hour - 12) .. " PM"
        end
    else
        return hour .. ":00"
    end
end

function WeatherUtils:getMoonPhaseIcon(moon_phase)
    if not moon_phase then
        return nil
    end

    -- Map moon phase names to icon files
    local phase_map = {
        ["New Moon"] = "new_moon.svg",
        ["Waxing Crescent"] = "waxing_crescent.svg",
        ["First Quarter"] = "first_quarter.svg",
        ["Waxing Gibbous"] = "waxing_gibbous.svg",
        ["Full Moon"] = "full_moon.svg",
        ["Waning Gibbous"] = "waning_gibbous.svg",
        ["Last Quarter"] = "last_quarter.svg",
        ["Waning Crescent"] = "waning_crescent.svg",
    }

    local icon_file = phase_map[moon_phase]
    if not icon_file then
        -- Default to new moon if phase not recognized
        icon_file = "new_moon.svg"
    end

    local icon_path = DataStorage:getDataDir() .. "/icons/moonphases/" .. icon_file

    -- Check if file exists
    if util.pathExists(icon_path) then
        return icon_path
    end

    return nil
end

function WeatherUtils:translateMoonPhase(moon_phase)
    if not moon_phase then
        return nil
    end

    -- Translate moon phase name using plugin localization
    local _ = require("l10n/gettext")
    return _(moon_phase)
end

function WeatherUtils:getPluginDir()
    local callerSource = debug.getinfo(2, "S").source
    if callerSource:find("^@") then
        return callerSource:gsub("^@(.*)/[^/]*", "%1")
    end
end

function WeatherUtils:getCacheMaxAge()
    return G_reader_settings:readSetting("weather_cache_max_age") or 3600  -- Default: 1 hour
end

function WeatherUtils:getMinDelayBetweenUpdates()
    return G_reader_settings:readSetting("weather_min_update_delay") or 1800  -- Default: 30 minutes
end

-- This function was inspired by Project: Title. Thanks!
function WeatherUtils:installIcons()
    local icons_path = DataStorage:getDataDir() .. "/icons"
    local icons_list = {
        "sun",
        "moon",
        "hourglass",
    }

    -- Moon phase icons (used in night owl mode)
    local moonphases_path = DataStorage:getDataDir() .. "/icons/moonphases"
    local moonphases_list = {
        "new_moon",
        "waxing_crescent",
        "first_quarter",
        "waxing_gibbous",
        "full_moon",
        "waning_gibbous",
        "last_quarter",
        "waning_crescent",
    }

    -- Arrow icons for wind direction (used in retro analog mode)
    local arrows_path = DataStorage:getDataDir() .. "/icons/arrows"
    local arrows_list = {
        "arrow_n",
        "arrow_ne",
        "arrow_e",
        "arrow_se",
        "arrow_s",
        "arrow_sw",
        "arrow_w",
        "arrow_nw",
    }

    local function checkicons()
        logger.dbg("WeatherLockscreen: Checking for icons")
        local icons_found = true
        for _, icon in ipairs(icons_list) do
            local icon_file = icons_path .. "/" .. icon .. ".svg"
            if not util.fileExists(icon_file) then
                icons_found = false
                break
            end
        end
        if icons_found then
            logger.dbg("WeatherLockscreen: All icons found")
            return true
        else
            return false
        end
    end

    local function checkmoonphases()
        logger.dbg("WeatherLockscreen: Checking for moon phase icons")
        local moonphases_found = true
        for _, moonphase in ipairs(moonphases_list) do
            local moonphase_file = moonphases_path .. "/" .. moonphase .. ".svg"
            if not util.fileExists(moonphase_file) then
                moonphases_found = false
                break
            end
        end
        if moonphases_found then
            logger.dbg("WeatherLockscreen: All moon phase icons found")
            return true
        else
            return false
        end
    end

    local function checkarrows()
        logger.dbg("WeatherLockscreen: Checking for arrow icons")
        local arrows_found = true
        for _, arrow in ipairs(arrows_list) do
            local arrow_file = arrows_path .. "/" .. arrow .. ".svg"
            if not util.fileExists(arrow_file) then
                arrows_found = false
                break
            end
        end
        if arrows_found then
            logger.dbg("WeatherLockscreen: All arrow icons found")
            return true
        else
            return false
        end
    end

    if checkicons() and checkmoonphases() and checkarrows() then return true end

    local result
    if not util.directoryExists(icons_path) then
        result = util.makePath(icons_path .. "/")
        logger.dbg("WeatherLockscreen: Creating icons folder")
        if not result then return false end
    end

    if not util.directoryExists(moonphases_path) then
        result = util.makePath(moonphases_path .. "/")
        logger.dbg("WeatherLockscreen: Creating moonphases folder")
        if not result then return false end
    end

    if not util.directoryExists(arrows_path) then
        result = util.makePath(arrows_path .. "/")
        logger.dbg("WeatherLockscreen: Creating arrows folder")
        if not result then return false end
    end

    if util.directoryExists(icons_path) then
        local plugin_dir = self:getPluginDir()
        if not plugin_dir then
            logger.warn("WeatherLockscreen: plugin dir unknown; cannot copy bundled icons")
            return false
        end

        for _, icon in ipairs(icons_list) do
            -- check icon files one at a time, and only copy when missing
            -- this will preserve custom icons set by the user
            local icon_file = icons_path .. "/" .. icon .. ".svg"
            if not util.fileExists(icon_file) then
                local bundled_icon_file = plugin_dir .. "/icons/" .. icon .. ".svg"
                if util.fileExists(bundled_icon_file) then
                    logger.dbg("WeatherLockscreen: Copying icon " .. icon)
                    ffiUtil.copyFile(bundled_icon_file, icon_file)
                else
                    logger.warn("WeatherLockscreen: bundled icon missing: " .. bundled_icon_file)
                end
            end
        end

        for _, moonphase in ipairs(moonphases_list) do
            -- check moonphase files one at a time, and only copy when missing
            -- this will preserve custom moonphases set by the user
            local moonphase_file = moonphases_path .. "/" .. moonphase .. ".svg"
            if not util.fileExists(moonphase_file) then
                local bundled_moonphase_file = plugin_dir .. "/icons/moonphases/" .. moonphase .. ".svg"
                if util.fileExists(bundled_moonphase_file) then
                    logger.dbg("WeatherLockscreen: Copying moon phase " .. moonphase)
                    ffiUtil.copyFile(bundled_moonphase_file, moonphase_file)
                else
                    logger.warn("WeatherLockscreen: bundled moon phase missing: " .. bundled_moonphase_file)
                end
            end
        end

        for _, arrow in ipairs(arrows_list) do
            -- check arrow files one at a time, and only copy when missing
            -- this will preserve custom arrows set by the user
            local arrow_file = arrows_path .. "/" .. arrow .. ".svg"
            if not util.fileExists(arrow_file) then
                local bundled_arrow_file = plugin_dir .. "/icons/arrows/" .. arrow .. ".svg"
                if util.fileExists(bundled_arrow_file) then
                    logger.dbg("WeatherLockscreen: Copying arrow " .. arrow)
                    ffiUtil.copyFile(bundled_arrow_file, arrow_file)
                else
                    logger.warn("WeatherLockscreen: bundled arrow missing: " .. bundled_arrow_file)
                end
            end
        end
    end

    if checkicons() and checkmoonphases() and checkarrows() then return true end
    return false
end

function WeatherUtils:saveWeatherCache(weather_data)
    local cache_file = DataStorage:getDataDir() .. "/cache/weather-lockscreen.json"
    local cache_dir = DataStorage:getDataDir() .. "/cache/"
    util.makePath(cache_dir)

    local cache_data = {
        timestamp = os.time(),
        data = weather_data
    }

    local json = require("json")
    local f = io.open(cache_file, "w")
    if f then
        f:write(json.encode(cache_data))
        f:close()
        return true
    end
    return false
end

function WeatherUtils:loadWeatherCache(max_age)
    local cache_file = DataStorage:getDataDir() .. "/cache/weather-lockscreen.json"
    local f = io.open(cache_file, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()

    local json = require("json")
    local success, cache_data = pcall(json.decode, content)
    if not success or not cache_data or not cache_data.timestamp or not cache_data.data then
        return nil
    end

    local age = os.time() - cache_data.timestamp
    if age > max_age then
        logger.dbg("WeatherLockscreen: Cache too old")
        return nil
    end

    return cache_data.data, true
end

function WeatherUtils:clearCache()
    local cache_file = DataStorage:getDataDir() .. "/cache/weather-lockscreen.json"
    local icons_cache_dir = DataStorage:getDataDir() .. "/cache/weather-icons/"

    local cleared = false

    -- Remove cached weather data
    if util.fileExists(cache_file) then
        os.remove(cache_file)
        logger.dbg("WeatherLockscreen: Removed cached weather data")
        cleared = true
    end

    -- Remove cached weather icons directory
    if util.directoryExists(icons_cache_dir) then
        -- Remove all files in the directory
        local lfs = require("libs/libkoreader-lfs")
        for entry in lfs.dir(icons_cache_dir) do
            if entry ~= "." and entry ~= ".." then
                local file_path = icons_cache_dir .. entry
                logger.dbg("WeatherLockscreen: Removed ", file_path)
                os.remove(file_path)
            end
        end
        -- Remove the directory itself
        lfs.rmdir(icons_cache_dir)
        logger.dbg("WeatherLockscreen: Removed cached weather icons")
        cleared = true
    end

    return cleared
end

function WeatherUtils:wifiEnableActionTurnOn()
    local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action") or "prompt"
    return wifi_enable_action == "turn_on"
end

function WeatherUtils:getBatteryCapacity()
    local Device = require("device")
    local Powerd = Device and Device:getPowerDevice()
    if not Powerd or not Powerd.getCapacity then
        return nil
    end

    local ok, capacity = pcall(function()
        return Powerd:getCapacity()
    end)
    if not ok or type(capacity) ~= "number" then
        return nil
    end

    return capacity
end

function WeatherUtils:getActiveSleepMinBattery()
    local v = G_reader_settings:readSetting("weather_active_sleep_min_battery")
    if type(v) == "number" then
        return v
    end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then
            return n
        end
    end
    return 0
end

-- Check if a search query is a special command and handle it
-- Returns true if the query was a command (and was handled), false otherwise
-- Special commands:
--   "debug on" / "debug enable" - Enable debug options
--   "debug off" / "debug disable" - Disable debug options
function WeatherUtils:handleSpecialCommand(query)
    if not query then return false end

    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local query_lower = query:lower()

    if query_lower == "debug on" or query_lower == "debug enable" then
        G_reader_settings:saveSetting("weather_debug_options", true)
        G_reader_settings:flush()
        UIManager:show(InfoMessage:new {
            text = _("Debug options enabled"),
            timeout = 2,
        })
        logger.info("WeatherLockscreen: Debug options enabled via search command")
        return true
    elseif query_lower == "debug off" or query_lower == "debug disable" then
        G_reader_settings:saveSetting("weather_debug_options", false)
        G_reader_settings:flush()
        UIManager:show(InfoMessage:new {
            text = _("Debug options disabled"),
            timeout = 2,
        })
        logger.info("WeatherLockscreen: Debug options disabled via search command")
        return true
    end

    return false
end

-- Safely try to go online and run a callback
-- This wraps NetworkMgr:goOnlineToRun() with proper error handling to avoid crashes
-- from race conditions in KOReader's network initialization code.
-- @param callback function - The callback to run when online
-- @param fallback_callback function - Optional callback to run if going online fails
-- @param suppress_network_messages boolean - Whether to suppress network-related InfoMessages (default: true)
-- @param call_after_wifi_action boolean - Whether to call afterWifiAction when done (respects wifi_disable_action setting, default: false)
function WeatherUtils:safeGoOnlineToRun(callback, fallback_callback, suppress_network_messages, call_after_wifi_action)
    local UIManager = require("ui/uimanager")
    local NetworkMgr = require("ui/network/manager")

    if suppress_network_messages == nil then
        suppress_network_messages = true
    end

    -- First check if we're already online - no need to do anything
    if NetworkMgr:isOnline() then
        logger.dbg("WeatherLockscreen: Already online, running callback directly")
        if callback then
            callback()
        end
        -- Don't call afterWifiAction if we were already online - we didn't enable Wi-Fi
        return true
    end

    -- If wifi_enable_action is not "turn_on", we can't auto-connect
    if not self:wifiEnableActionTurnOn() then
        logger.dbg("WeatherLockscreen: wifi_enable_action is not 'turn_on', running fallback")
        if fallback_callback then
            fallback_callback()
        elseif callback then
            -- Run callback anyway, it will use cached data if available
            callback()
        end
        return false
    end

    -- Set up message suppression if requested
    local orig_uimanager_show
    if suppress_network_messages then
        orig_uimanager_show = UIManager.show
        UIManager.show = function(self, widget, refresh_type, refresh_region, x, y)
            -- Suppress InfoMessage widgets with network-related text
            if widget and widget.text and type(widget) == "table" and widget.modal ~= nil then
                local text_lower = widget.text:lower()
                if text_lower:find("connect") or text_lower:find("wi%-fi") or text_lower:find("network") or text_lower:find("waiting") or text_lower:find("scanning") then
                    logger.dbg("WeatherLockscreen: Suppressed network info message:", widget.text)
                    return
                end
            end
            return orig_uimanager_show(self, widget, refresh_type, refresh_region, x, y)
        end
    end

    -- Restore function for cleanup
    local function restoreUIManager()
        if suppress_network_messages and orig_uimanager_show then
            UIManager.show = orig_uimanager_show
            orig_uimanager_show = nil -- Prevent double-restore
        end
    end

    -- Helper to call afterWifiAction if requested (respects user's wifi_disable_action setting)
    -- Note: We skip if wifi_disable_action is "prompt" because this plugin is designed
    -- for unattended operation (weather display that updates periodically without user interaction)
    local function maybeAfterWifiAction()
        if not call_after_wifi_action then
            return
        end

        local wifi_disable_action = G_reader_settings:readSetting("wifi_disable_action") or "prompt"
        if wifi_disable_action == "prompt" then
            -- Don't call afterWifiAction when set to "prompt" - that would require user interaction
            -- For an unattended weather display, we treat "prompt" as "leave_on" (do nothing)
            logger.dbg("WeatherLockscreen: wifi_disable_action is 'prompt', skipping afterWifiAction to avoid user interaction")
            return
        end

        logger.dbg("WeatherLockscreen: Calling afterWifiAction (wifi_disable_action=" .. wifi_disable_action .. ")")
        NetworkMgr:afterWifiAction()
    end

    -- Track whether callback was called
    local callback_invoked = false

    -- Try to go online with pcall to catch any crashes from KOReader's network code
    local pcall_success, go_online_result = pcall(function()
        return NetworkMgr:goOnlineToRun(function()
            callback_invoked = true
            restoreUIManager()
            logger.dbg("WeatherLockscreen: Network is online, running callback")
            if callback then
                callback()
            end
            maybeAfterWifiAction()
        end)
    end)

    if not pcall_success then
        -- A crash occurred (e.g., lipc error in kindleGetSavedNetworks)
        logger.warn("WeatherLockscreen: goOnlineToRun crashed:", go_online_result)
        restoreUIManager()

        -- Try to recover - wait a bit and check if we're online anyway
        -- The crash might have happened after Wi-Fi was enabled but during network list scan
        UIManager:scheduleIn(2, function()
            if NetworkMgr:isOnline() then
                logger.info("WeatherLockscreen: Recovered - network came online after crash")
                if callback then
                    callback()
                end
                maybeAfterWifiAction()
            else
                logger.warn("WeatherLockscreen: Could not recover network connection, running fallback")
                if fallback_callback then
                    fallback_callback()
                elseif callback then
                    -- Run callback anyway with potentially cached data
                    callback()
                end
                -- Don't call afterWifiAction if we failed to connect
            end
        end)
        return false
    end

    -- goOnlineToRun returned without crash
    -- Check if it returned false (failed to connect) and callback wasn't invoked
    if go_online_result == false and not callback_invoked then
        logger.dbg("WeatherLockscreen: goOnlineToRun returned false, connection failed")
        restoreUIManager()
        if fallback_callback then
            fallback_callback()
        elseif callback then
            callback()
        end
        -- Don't call afterWifiAction if connection failed
        return false
    end

    -- If we get here and callback wasn't invoked yet, schedule cleanup
    -- goOnlineToRun might still be waiting for network
    if not callback_invoked then
        -- Schedule a timeout cleanup in case the callback is never called
        UIManager:scheduleIn(35, function()
            if not callback_invoked then
                logger.warn("WeatherLockscreen: Network connection timed out (35s)")
                restoreUIManager()
                if fallback_callback then
                    fallback_callback()
                elseif callback then
                    callback()
                end
                -- Don't call afterWifiAction on timeout
            end
        end)
    end

    return true
end

function WeatherUtils:getPeriodicRefreshInterval(type)
    if type == "rtc" then
        return G_reader_settings:readSetting("weather_periodic_refresh_rtc") or 0
    end
    return G_reader_settings:readSetting("weather_periodic_refresh_dashboard") or 0
end

function WeatherUtils:canScheduleWakeup()
    local Device = require("device")

    -- By default, only Kindle is supported (tested)
    -- Kobo support is experimental - enabled when debug mode is on
    if Device:isKindle() then
        return true
    end

    if Device:isKobo() then
        -- Allow Kobo RTC wakeup when debug mode is enabled
        return G_reader_settings:isTrue("weather_debug_options")
    end

    return false
end

function WeatherUtils:periodicRefreshSupported()
    return WeatherUtils:canScheduleWakeup()
end

function WeatherUtils:periodicRefreshEnabled(type)
    if type == "rtc" then
        return WeatherUtils:periodicRefreshSupported() and WeatherUtils:getPeriodicRefreshInterval(type) > 0
    else
        return WeatherUtils:getPeriodicRefreshInterval(type) > 0
    end
end

-- Save current frontlight intensity and turn off
function WeatherUtils:suspendFrontlight(plugin_instance)
    local Device = require("device")
    if Device:hasFrontlight() and not plugin_instance.saved_frontlight_intensity then
        local Powerd = Device:getPowerDevice()
        plugin_instance.saved_frontlight_intensity = Powerd:frontlightIntensity()
        logger.dbg("WeatherLockscreen: Saved frontlight intensity:", plugin_instance.saved_frontlight_intensity)
        Powerd:setIntensity(0)
        logger.dbg("WeatherLockscreen: Frontlight turned off")
    end
end

-- Resume frontlight intensity
function WeatherUtils:resumeFrontlight(plugin_instance)
    local Device = require("device")
    -- Restore frontlight intensity on real button press and reset saved value
    if Device:hasFrontlight() and plugin_instance.saved_frontlight_intensity then
        local Powerd = Device:getPowerDevice()
        Powerd:setIntensity(plugin_instance.saved_frontlight_intensity)
        logger.dbg("WeatherLockscreen: Restored frontlight intensity to:", plugin_instance.saved_frontlight_intensity)
        plugin_instance.saved_frontlight_intensity = nil
        logger.dbg("WeatherLockscreen: Reset saved frontlight intensity")
    end
end

-- Trigger device suspend/resume via power device API
function WeatherUtils:toggleSuspend()
    local Device = require("device")
    local Powerd = Device:getPowerDevice()
    if Powerd and Powerd.toggleSuspend then
        Powerd:toggleSuspend()
        logger.info("WeatherLockscreen: Suspend triggered via toggleSuspend()")
        return
    end

    if Device and Device.suspend then
        Device:suspend()
        logger.info("WeatherLockscreen: Suspend triggered via Device:suspend()")
        return
    end

    logger.warn("WeatherLockscreen: Unable to suspend device (no toggleSuspend or suspend API)")
end

function WeatherUtils:koLangAsWeatherAPILang()
    local lang_locale = G_reader_settings:readSetting("language") or "en"
    return WeatherUtils.lang_map[lang_locale] or "en"
end

WeatherUtils.target_hours = { 6, 12, 18 } -- For basic display

-- Static KOReader to WeatherAPI language code mapping
WeatherUtils.lang_map = {
    ar = "ar",         -- Arabic
    bg_BG = "bg",      -- Bulgarian
    bn = "bn",         -- Bengali
    C = "en",          -- C (default to English)
    cs = "cs",         -- Czech
    da = "da",         -- Danish
    de = "de",         -- German
    el = "el",         -- Greek
    en_GB = "en",      -- Englush (GB)
    en_US = "en",      -- Englush (US)
    es = "es",         -- Spanish
    fi = "fi",         -- Finnish
    fr = "fr",         -- French
    hi = "hi",         -- Hindi
    hu = "hu",         -- Hungarian
    it_IT = "it",      -- Italian
    ja = "ja",         -- Japanese
    ko_KR = "ko",      -- Korean
    nl_NL = "nl",      -- Dutch
    pl = "pl",         -- Polish
    pt_PT = "pt",      -- Portuguese
    pt_BR = "pt",      -- Portuguese (WeatherAPI only supports one pt variant. I think, its better to use it than to default to english)
    ro = "ro",         -- Romanian
    ro_MD = "ro",      -- Romanian (WeatherAPI only supports one ro variant. I think, its better to use it than to default to english)
    ru = "ru",         -- Russian
    si = "si",         -- Sinhalese
    sk = "sk",         -- Slovak
    sr = "sr",         -- Serbian
    sv = "sv",         -- Swedish
    ta = "ta",         -- Tamil
    te = "te",         -- Telugu
    tr = "tr",         -- Turkish
    uk = "uk",         -- Ukrainian
    ur = "ur",         -- Urdu
    vi = "vi",         -- Vietnamese
    zh_CN = "zh",      -- Chinese Simplified
    zh_TW = "zh_tw",   -- Chinese Traditional
    --  koreader does not support the following languages, but WeatherAPI does, they remain unsupported for now
    jv = "jv",         -- Javanese
    mr = "mr",         -- Marathi
    pa = "pa",         -- Punjabi
    zh_cmn = "zh_cmn", -- Mandarin
    zh_hsn = "zh_hsn", -- Xiang
    zh_wuu = "zh_wuu", -- Wu (Shanghainese)
    zh_yue = "zh_yue", -- Yue (Cantonese)
    zu = "zu",         -- Zulu
}

return WeatherUtils
