--[[
    Calendar API Module for Weather Lockscreen
    Handles fetching and parsing ICS calendar data
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local util = require("util")

local CalendarAPI = {}

-- HTTP request helper (reused pattern from weather_api.lua)
local function http_request_code(url, sink_table)
  local ltn12 = require("ltn12")
  local sink = ltn12.sink.table(sink_table)

  -- Try LuaSec first for HTTPS support
  local success_ssl, https = pcall(require, "ssl.https")
  if success_ssl and https and https.request then
    local _, code = https.request { url = url, sink = sink }
    return code
  end

  -- Fallback to socket.http (may not work for https)
  local success_sock, http = pcall(require, "socket.http")
  if not success_sock or not http or not http.request then
    return nil, "no http client available"
  end
  local _, code = http.request { url = url, sink = sink }
  return code
end

-- Unfold ICS lines (lines starting with space/tab are continuations)
local function unfoldLines(ics_content)
  -- Replace CRLF with LF for consistency
  ics_content = ics_content:gsub("\r\n", "\n")
  -- Unfold: remove newline followed by space or tab
  ics_content = ics_content:gsub("\n[ \t]", "")
  return ics_content
end

-- Parse a date string from ICS format
-- Handles: 20241225 (DATE), 20241225T090000 (local datetime), 20241225T090000Z (UTC)
local function parseICSDate(date_str)
  if not date_str then return nil, false end

  local all_day = false
  local year, month, day, hour, min, sec

  -- Check for all-day date format: YYYYMMDD
  if #date_str == 8 and date_str:match("^%d+$") then
    year = tonumber(date_str:sub(1, 4))
    month = tonumber(date_str:sub(5, 6))
    day = tonumber(date_str:sub(7, 8))
    hour, min, sec = 0, 0, 0
    all_day = true
    -- Check for datetime format: YYYYMMDDTHHMMSS or YYYYMMDDTHHMMSSZ
  elseif date_str:match("^%d+T%d+") then
    year = tonumber(date_str:sub(1, 4))
    month = tonumber(date_str:sub(5, 6))
    day = tonumber(date_str:sub(7, 8))
    hour = tonumber(date_str:sub(10, 11))
    min = tonumber(date_str:sub(12, 13))
    sec = tonumber(date_str:sub(14, 15)) or 0
    -- Note: We ignore 'Z' (UTC) for now - treating all times as local
  else
    logger.warn("CalendarAPI: Unknown date format:", date_str)
    return nil, false
  end

  if not year or not month or not day then
    return nil, false
  end

  local timestamp = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour or 0,
    min = min or 0,
    sec = sec or 0
  })

  return timestamp, all_day
end

-- Unescape ICS text values
local function unescapeText(text)
  if not text then return nil end
  -- ICS escaping: \, -> comma, \; -> semicolon, \n -> newline, \\ -> backslash
  text = text:gsub("\\,", ",")
  text = text:gsub("\\;", ";")
  text = text:gsub("\\n", "\n")
  text = text:gsub("\\N", "\n")
  text = text:gsub("\\\\", "\\")
  return text
end

-- Parse a single VEVENT block into an event table
local function parseVEvent(vevent_content)
  local event = {}

  for line in vevent_content:gmatch("[^\n]+") do
    -- ICS format: PROPERTY;PARAM=VALUE;PARAM2=VALUE2:actual_value
    -- Or simply: PROPERTY:actual_value
    -- We need to extract the property name and the value after the LAST colon

    -- Find the property name (everything before first : or ;)
    local prop = line:match("^([^:;]+)")
    if not prop then goto continue end

    -- Find the actual value (everything after the last colon in the property part)
    -- The line format is: PROP;params:value or PROP:value
    local value = line:match(":([^:]*%S.*)$") or line:match(":(.*)$")
    if not value then goto continue end

    -- Check if line has parameters (contains ; before :)
    local has_value_date_param = line:match("^[^:]*VALUE=DATE[^:]*:")

    if prop == "SUMMARY" then
      event.summary = unescapeText(value)
    elseif prop == "DESCRIPTION" then
      event.description = unescapeText(value)
    elseif prop == "LOCATION" then
      event.location = unescapeText(value)
    elseif prop == "UID" then
      event.uid = value
    elseif prop == "DTSTART" then
      event.start_time, event.all_day = parseICSDate(value)
      -- Force all_day if VALUE=DATE parameter present
      if has_value_date_param then
        event.all_day = true
      end
    elseif prop == "DTEND" then
      event.end_time = parseICSDate(value)
    end

    ::continue::
  end

  return event
end

-- Parse ICS content string into array of events
function CalendarAPI:parseICS(ics_content)
  if not ics_content or ics_content == "" then
    return {}
  end

  -- Unfold continuation lines
  local unfolded = unfoldLines(ics_content)

  local events = {}

  -- Extract all VEVENT blocks
  for vevent in unfolded:gmatch("BEGIN:VEVENT(.-)END:VEVENT") do
    local event = parseVEvent(vevent)
    if event.summary and event.start_time then
      table.insert(events, event)
    end
  end

  logger.dbg("CalendarAPI: Parsed", #events, "events from ICS")
  return events
end

-- Filter events for a specific date (returns events occurring on that day)
function CalendarAPI:getEventsForDate(events, target_date)
  if not events or #events == 0 then
    return {}
  end

  -- Get start and end of target day
  local target_info = os.date("*t", target_date)
  local day_start = os.time({
    year = target_info.year,
    month = target_info.month,
    day = target_info.day,
    hour = 0,
    min = 0,
    sec = 0
  })
  local day_end = day_start + 86400 -- 24 hours

  local filtered = {}
  for _, event in ipairs(events) do
    local start_time = event.start_time
    local end_time = event.end_time or (start_time + (event.all_day and 86400 or 3600))

    -- Event occurs on target day if:
    -- - Event starts before day ends AND
    -- - Event ends after day starts
    if start_time < day_end and end_time > day_start then
      table.insert(filtered, event)
    end
  end

  -- Sort by start time, all-day events first
  table.sort(filtered, function(a, b)
    if a.all_day and not b.all_day then return true end
    if not a.all_day and b.all_day then return false end
    return a.start_time < b.start_time
  end)

  return filtered
end

-- Get events for today
function CalendarAPI:getEventsForToday(events)
  return self:getEventsForDate(events, os.time())
end

-- Get events for tomorrow
function CalendarAPI:getEventsForTomorrow(events)
  return self:getEventsForDate(events, os.time() + 86400)
end

-- Save calendar data to cache
function CalendarAPI:saveCache(calendar_data)
  local cache_file = DataStorage:getDataDir() .. "/cache/calendar-lockscreen.json"
  local cache_dir = DataStorage:getDataDir() .. "/cache/"
  util.makePath(cache_dir)

  local cache_data = {
    timestamp = os.time(),
    data = calendar_data
  }

  local json = require("json")
  local f = io.open(cache_file, "w")
  if f then
    f:write(json.encode(cache_data))
    f:close()
    logger.dbg("CalendarAPI: Cache saved")
    return true
  end
  return false
end

-- Load calendar data from cache
function CalendarAPI:loadCache(max_age)
  local cache_file = DataStorage:getDataDir() .. "/cache/calendar-lockscreen.json"
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
    logger.dbg("CalendarAPI: Cache too old (", age, "seconds)")
    return nil
  end

  logger.dbg("CalendarAPI: Loaded from cache (age:", age, "seconds)")
  return cache_data.data, true
end

-- Clear calendar cache
function CalendarAPI:clearCache()
  local cache_file = DataStorage:getDataDir() .. "/cache/calendar-lockscreen.json"
  if util.fileExists(cache_file) then
    os.remove(cache_file)
    logger.dbg("CalendarAPI: Cache cleared")
    return true
  end
  return false
end

-- Fetch calendar data from URL
-- Accepts single URL string or array of URLs
function CalendarAPI:fetchCalendarData(calendar_urls, force_refresh)
  -- Normalize to array
  local urls = calendar_urls
  if type(calendar_urls) == "string" then
    urls = { calendar_urls }
  end

  if not urls or #urls == 0 or (urls[1] == "") then
    logger.dbg("CalendarAPI: No calendar URL configured")
    return nil
  end

  local cache_max_age = G_reader_settings:readSetting("calendar_cache_max_age") or 3600

  -- Check cache first (unless force refresh)
  if not force_refresh then
    local cached_data, is_cached = self:loadCache(cache_max_age)
    if cached_data then
      cached_data.is_cached = true
      return cached_data
    end
  end

  logger.info("CalendarAPI: Fetching", #urls, "calendar(s)")

  local all_events = {}
  local any_success = false

  for i, url in ipairs(urls) do
    if url and url ~= "" then
      logger.dbg("CalendarAPI: Fetching calendar", i, "from:", url:sub(1, 50) .. "...")

      local sink_table = {}
      local code, err = http_request_code(url, sink_table)

      if code == 200 then
        local ics_content = table.concat(sink_table)
        local events = self:parseICS(ics_content)

        -- Add events from this calendar
        for _, event in ipairs(events) do
          table.insert(all_events, event)
        end

        logger.dbg("CalendarAPI: Calendar", i, "returned", #events, "events")
        any_success = true
      else
        logger.warn("CalendarAPI: Failed to fetch calendar", i, "code:", code or "nil", "err:", err or "nil")
      end
    end
  end

  if any_success then
    -- Sort all events by start time
    table.sort(all_events, function(a, b)
      return (a.start_time or 0) < (b.start_time or 0)
    end)

    local calendar_data = {
      events = all_events,
      fetch_timestamp = os.time(),
      is_cached = false,
      url_count = #urls,
    }

    -- Save to cache
    self:saveCache(calendar_data)

    return calendar_data
  else
    logger.warn("CalendarAPI: All calendar fetches failed")
    -- Try cache on error
    local cached_data = self:loadCache(cache_max_age * 24)
    if cached_data then
      cached_data.is_cached = true
      return cached_data
    end
    return nil
  end
end

-- Format event time for display
function CalendarAPI:formatEventTime(event, twelve_hour_clock)
  if event.all_day then
    return "All Day"
  end

  local time_info = os.date("*t", event.start_time)
  local hour = time_info.hour
  local min = time_info.min

  if twelve_hour_clock then
    local period = hour >= 12 and "PM" or "AM"
    local display_hour = hour % 12
    if display_hour == 0 then display_hour = 12 end
    if min == 0 then
      return string.format("%d %s", display_hour, period)
    else
      return string.format("%d:%02d %s", display_hour, min, period)
    end
  else
    return string.format("%02d:%02d", hour, min)
  end
end

return CalendarAPI
