--[[
    Utility Functions for Weather Lockscreen
    Helper functions for time formatting, icon paths, caching, and icon installation
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")

local WeatherUtils = {}


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
        ["Third Quarter"] = "last_quarter.svg",
        ["Waning Crescent"] = "waning_crescent.svg",
    }

    local icon_file = phase_map[moon_phase]
    if not icon_file then
        -- Default to new moon if phase not recognized
        icon_file = "new_moon.svg"
    end

    local icon_path = DataStorage:getDataDir() .. "/icons/moonphases/" .. icon_file

    -- Check if file exists
    local f = io.open(icon_path, "r")
    if f then
        f:close()
        return icon_path
    end

    return nil
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

-- This function was inspired by Project: Title. Thanks!
function WeatherUtils:installIcons(plugin_dir_func)
    local icons_path = DataStorage:getDataDir() .. "/icons"
    local icons_list = {
        "sun",
        "moon",
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
        local plugin_dir = plugin_dir_func()
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

function WeatherUtils:loadWeatherCache(get_max_age_func)
    local cache_file = DataStorage:getDataDir() .. "/cache/weather-lockscreen.json"
    local f = io.open(cache_file, "r")
    if not f then
        return nil, false
    end

    local content = f:read("*all")
    f:close()

    local json = require("json")
    local success, cache_data = pcall(json.decode, content)
    if not success or not cache_data or not cache_data.timestamp or not cache_data.data then
        return nil, false
    end

    local age = os.time() - cache_data.timestamp
    if age > get_max_age_func() then
        logger.dbg("WeatherLockscreen: Cache too old")
        return nil, false
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

return WeatherUtils
