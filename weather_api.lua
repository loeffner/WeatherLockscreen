--[[
    Weather API Module for Weather Lockscreen
    Handles fetching, processing, and caching weather data from WeatherAPI.com
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local WeatherUtils = require("weather_utils")

local WeatherAPI = {}

local function http_request_code(url, sink_table)
    local ltn12 = require("ltn12")
    local sink = ltn12.sink.table(sink_table)

    -- Try LuaSec first for HTTPS support
    local success_ssl, https = pcall(require, "ssl.https")
    if success_ssl and https and https.request then
        local _, code = https.request{ url = url, sink = sink }
        return code
    end

    -- Fallback to socket.http (may not work for https)
    local success_sock, http = pcall(require, "socket.http")
    if not success_sock or not http or not http.request then
        return nil, "no http client available"
    end
    local _, code = http.request{ url = url, sink = sink }
    return code
end

function WeatherAPI:fetchWeatherData(weather_lockscreen)
    local location = G_reader_settings:readSetting("weather_location") or weather_lockscreen.default_location
    local api_key = G_reader_settings:readSetting("weather_api_key")
    if not api_key or api_key == "" then
        api_key = weather_lockscreen.default_api_key
    end

    logger.dbg("WeatherLockscreen: Using location:", location)
    logger.dbg("WeatherLockscreen: Using API key:", api_key and (api_key:sub(1,8) .. "...") or "none")

    if not api_key or api_key == "" then
        logger.warn("WeatherLockscreen: No API key configured")
        local cached_data, is_cached = WeatherUtils:loadWeatherCache(function() return weather_lockscreen:getCacheMaxAge() end)
        if cached_data then
            cached_data.is_cached = true
        end
        return cached_data
    end

    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local json = require("json")

    -- WeatherAPI.com endpoint for forecast
    local url = string.format(
        "https://api.weatherapi.com/v1/forecast.json?key=%s&q=%s&days=2&aqi=no&alerts=no",
        api_key,
        location
    )

    logger.dbg("WeatherLockscreen: Fetching weather from API")

    local sink_table = {}
    local code, err = http_request_code(url, sink_table)
    if not code then
        logger.warn("WeatherLockscreen: HTTP request failed:", err or "unknown error")
        local cached_data, is_cached = WeatherUtils:loadWeatherCache(function() return weather_lockscreen:getCacheMaxAge() end)
        if cached_data then
            cached_data.is_cached = true
        end
        return cached_data
    end

    if code == 200 then
        local response_data = table.concat(sink_table)
        local success, result = pcall(json.decode, response_data)

        if success and result and result.current and not result.error then
            logger.dbg("WeatherLockscreen: Weather data received successfully")
            local weather_data = self:processWeatherData(weather_lockscreen, result)
            WeatherUtils:saveWeatherCache(weather_data)
            weather_data.is_cached = false
            return weather_data
        else
            logger.warn("WeatherLockscreen: Failed to parse weather data")
        end
    else
        logger.warn("WeatherLockscreen: Failed to fetch weather, HTTP code:", code)
    end

    -- Try cache if fetch failed
    local cached_data, is_cached = WeatherUtils:loadWeatherCache(function() return weather_lockscreen:getCacheMaxAge() end)
    if cached_data then
        cached_data.is_cached = true
    end
    return cached_data
end

function WeatherAPI:processWeatherData(weather_lockscreen, result)
    local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or "C"
    local twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")

    -- Process current weather
    local condition = result.current.condition.text
    local icon_path = self:getIconPath(result.current.condition.icon)

    local temperature
    if temp_scale == "C" then
        temperature = math.floor(result.current.temp_c) .. "°C"
    else
        temperature = math.floor(result.current.temp_f) .. "°F"
    end

    local feels_like
    if temp_scale == "C" then
        feels_like = math.floor(result.current.feelslike_c) .. "°C"
    else
        feels_like = math.floor(result.current.feelslike_f) .. "°F"
    end

    local current_data = {
        icon_path = icon_path,
        temperature = temperature,
        condition = condition,
        location = result.location and result.location.name or nil,
        timestamp = result.location and result.location.localtime or os.date("%Y-%m-%d %H:%M"),
        feels_like = feels_like,
        humidity = result.current.humidity and (result.current.humidity .. "%") or nil,
        wind = result.current.wind_kph and (math.floor(result.current.wind_kph) .. " km/h") or nil,
        wind_dir = result.current.wind_dir or nil,
    }

    -- Extract astronomy data
    local astronomy = nil
    if result.forecast and result.forecast.forecastday and result.forecast.forecastday[1] and result.forecast.forecastday[1].astro then
        local astro = result.forecast.forecastday[1].astro
        astronomy = {
            sunrise = astro.sunrise,
            sunset = astro.sunset,
            moonrise = astro.moonrise,
            moonset = astro.moonset,
            moon_phase = astro.moon_phase,
        }
    end

    -- Extract ALL hourly data (for extended displays)
    local hourly_today = {}
    local hourly_tomorrow = {}
    local target_hours = {6, 12, 18}  -- For basic display

    if result.forecast and result.forecast.forecastday then
        -- Today's hours
        if result.forecast.forecastday[1] and result.forecast.forecastday[1].hour then
            for _, hour_data in ipairs(result.forecast.forecastday[1].hour) do
                local hour = tonumber(hour_data.time:match("(%d+):00$"))
                if hour then
                    local h_icon_path = self:getIconPath(hour_data.condition.icon)
                    local h_temp = temp_scale == "C" 
                        and math.floor(hour_data.temp_c) .. "°"
                        or math.floor(hour_data.temp_f) .. "°"

                    -- Add all hours (not just target hours)
                    table.insert(hourly_today, {
                        hour = WeatherUtils:formatHourLabel(hour, twelve_hour_clock),
                        hour_num = hour,
                        icon_path = h_icon_path,
                        temperature = h_temp,
                        condition = hour_data.condition.text,
                    })
                end
            end
        end

        -- Tomorrow's hours
        if result.forecast.forecastday[2] and result.forecast.forecastday[2].hour then
            for _, hour_data in ipairs(result.forecast.forecastday[2].hour) do
                local hour = tonumber(hour_data.time:match("(%d+):00$"))
                if hour then
                    local h_icon_path = self:getIconPath(hour_data.condition.icon)
                    local h_temp = temp_scale == "C" 
                        and math.floor(hour_data.temp_c) .. "°"
                        or math.floor(hour_data.temp_f) .. "°"

                    table.insert(hourly_tomorrow, {
                        hour = WeatherUtils:formatHourLabel(hour, twelve_hour_clock),
                        hour_num = hour,
                        icon_path = h_icon_path,
                        temperature = h_temp,
                        condition = hour_data.condition.text,
                    })
                end
            end
        end
    end

    -- Filter for basic display (6, 12, 18 only)
    local hourly_today_basic = {}
    for _, h in ipairs(hourly_today) do
        for _, target_hour in ipairs(target_hours) do
            if h.hour_num == target_hour then
                table.insert(hourly_today_basic, h)
                break
            end
        end
    end

    local hourly_tomorrow_basic = {}
    for _, h in ipairs(hourly_tomorrow) do
        for _, target_hour in ipairs(target_hours) do
            if h.hour_num == target_hour then
                table.insert(hourly_tomorrow_basic, h)
                break
            end
        end
    end

    -- Extract forecast data
    local forecast_days = {}
    if result.forecast and result.forecast.forecastday then
        for i = 1, math.min(3, #result.forecast.forecastday) do
            local day_data = result.forecast.forecastday[i]
            if day_data and day_data.day then
                local day_name
                if i == 1 then
                    day_name = "Today"
                elseif i == 2 then
                    day_name = "Tomorrow"
                else
                    -- Parse date and get day name
                    local date_str = day_data.date
                    if date_str then
                        local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
                        if year and month and day then
                            local time = os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day)}
                            day_name = os.date("%a", time)
                        else
                            day_name = "Day " .. i
                        end
                    else
                        day_name = "Day " .. i
                    end
                end

                local high_temp = temp_scale == "C" 
                    and math.floor(day_data.day.maxtemp_c) .. "°"
                    or math.floor(day_data.day.maxtemp_f) .. "°"
                local low_temp = temp_scale == "C" 
                    and math.floor(day_data.day.mintemp_c) .. "°"
                    or math.floor(day_data.day.mintemp_f) .. "°"

                table.insert(forecast_days, {
                    day_name = day_name,
                    icon_path = self:getIconPath(day_data.day.condition.icon),
                    high_low = high_temp .. " / " .. low_temp,
                    condition = day_data.day.condition.text,
                })
            end
        end
    end

    return {
        current = current_data,
        hourly_today = hourly_today_basic,  -- 6, 12, 18 only for basic display
        hourly_tomorrow = hourly_tomorrow_basic,  -- 6, 12, 18 only for basic display
        hourly_today_all = hourly_today,  -- All hours for extended displays
        hourly_tomorrow_all = hourly_tomorrow,  -- All hours for extended displays
        forecast_days = forecast_days,
        astronomy = astronomy,
    }
end

function WeatherAPI:getIconPath(icon_url_from_api)
    if not icon_url_from_api then
        return nil
    end

    local url = icon_url_from_api
    if url:sub(1, 2) == "//" then
        url = "https:" .. url
    end

    -- Extract day/night from path and include in filename
    -- URL format: //cdn.weatherapi.com/weather/64x64/day/113.png or /night/113.png
    local day_night, filename = url:match("/([^/]+)/([^/]+)$")
    if not day_night or not filename then
        filename = url:match("([^/]+)$")
        if not filename then
            return nil
        end
        day_night = ""
    end

    -- Create unique filename with day/night prefix
    local cache_filename = day_night ~= "" and (day_night .. "_" .. filename) or filename

    local cache_dir = DataStorage:getDataDir() .. "/cache/weather-icons/"
    local cache_path = cache_dir .. cache_filename

    -- Check if already cached
    local f = io.open(cache_path, "r")
    if f then
        f:close()
        return cache_path
    end

    -- Download the icon
    logger.dbg("WeatherLockscreen: Downloading icon from:", url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local util = require("util")

    util.makePath(cache_dir)

    local sink_table = {}
    local code, err = http_request_code(url, sink_table)
    if not code then
        logger.dbg("WeatherLockscreen: Icon download failed:", err or "unknown error")
        return nil
    end

    if code == 200 then
        local icon_data = table.concat(sink_table)
        local out_file = io.open(cache_path, "wb")
        if out_file then
            out_file:write(icon_data)
            out_file:close()
            return cache_path
        end
    end

    return nil
end

return WeatherAPI
