--[[
    Utility Functions for Weather Lockscreen
    Helper functions for time formatting, icon paths, caching, and icon installation
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")

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
    local f = io.open(icon_path, "r")
    if f then
        f:close()
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

function WeatherUtils:createHeaderWidgets(header_font_size, header_margin, weather_data, text_color, is_cached)
    local Screen = require("device").screen
    local Font = require("ui/font")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local TextWidget = require("ui/widget/textwidget")
    local OverlapGroup = require("ui/widget/overlapgroup")

    local header_widgets = {}
    local show_header = G_reader_settings:nilOrTrue("weather_show_header")

    if show_header and weather_data.current.location then
        table.insert(header_widgets, LeftContainer:new {
            dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
            FrameContainer:new {
                padding = header_margin,
                margin = 0,
                bordersize = 0,
                TextWidget:new {
                    text = weather_data.current.location,
                    face = Font:getFace("cfont", header_font_size),
                    fgcolor = text_color,
                },
            },
        })
    end

    if show_header and weather_data.current.timestamp then
        local timestamp = weather_data.current.timestamp
        local year, month, day, hour, min = timestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
        local formatted_time = ""
        if year and month and day and hour and min then
            -- Use os.date for localized month abbreviation
            local time_obj = os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day)}
            local date_str = os.date("%b %d", time_obj)
            local twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")
            local hour_num = tonumber(hour)
            local time_str
            if twelve_hour_clock then
                local period = hour_num >= 12 and "PM" or "AM"
                local display_hour = hour_num % 12
                if display_hour == 0 then display_hour = 12 end
                time_str = display_hour .. ":" .. min .. " " .. period
            else
                time_str = hour .. ":" .. min
            end
            formatted_time = date_str .. ", " .. time_str
        else
            formatted_time = timestamp
        end

        -- Add asterisk if data is cached
        if is_cached then
            formatted_time = formatted_time .. " *"
        end

        table.insert(header_widgets, RightContainer:new {
            dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
            FrameContainer:new {
                padding = header_margin,
                margin = 0,
                bordersize = 0,
                TextWidget:new {
                    text = formatted_time,
                    face = Font:getFace("cfont", header_font_size),
                    fgcolor = text_color,
                },
            },
        })
    end

    return OverlapGroup:new {
        dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
        unpack(header_widgets)
    }
end

WeatherUtils.target_hours = { 6, 12, 18 } -- For basic display

function WeatherUtils:wifiEnableActionTurnOn()
    local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action") or "prompt"
    return wifi_enable_action == "turn_on"
end

function WeatherUtils:periodic_refresh_enabled()
    local wifi_turn_on = WeatherUtils:wifiEnableActionTurnOn()
    local interval = self:getPeriodicRefreshInterval()
    return not wifi_turn_on or interval == 0
end


function WeatherUtils:koLangAsWeatherAPILang()
    local lang_locale = G_reader_settings:readSetting("language") or "en"
    return WeatherUtils.lang_map[lang_locale] or "en"
end

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
