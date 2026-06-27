--[[
    Display Helper Functions for Weather Lockscreen Plugin

    Provides utility functions for creating various widget types.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local Device = require("device")
local Screen = Device.screen
local DataStorage = require("datastorage")
local util = require("util")
local ImageWidget = require("ui/widget/imagewidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local logger = require("logger")
local WeatherUtils = require("weather_utils")

local DisplayHelper = {}

function DisplayHelper:createHeaderWidgets(header_font_size, header_margin, weather_data, text_color, is_cached)
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
            local time_obj = os.time { year = tonumber(year), month = tonumber(month), day = tonumber(day) }
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

--- Build content with a build function, measure it, and rescale to fit available height.
--- @param buildFunc function(scale_factor) → widget  Builder that creates the content widget at the given scale.
--- @param available_height number  The pixel height the content should fit into.
--- @param default_fill number|nil  Default fill percentage when override is off (default 90).
--- @param available_width number|nil  Optional pixel width cap (used by width-dominated landscape layouts).
--- @return widget, number  The (possibly rebuilt) widget and the final scale factor.
function DisplayHelper:scaleToFit(buildFunc, available_height, default_fill, available_width)
    default_fill = default_fill or 90

    local widget = buildFunc(1.0)
    local content_size = widget:getSize()
    local content_height = content_size.h
    local content_width = content_size.w

    local fill_percent = G_reader_settings:readSetting("weather_override_scaling")
        and tonumber(G_reader_settings:readSetting("weather_fill_percent"))
        or default_fill
    local min_fill = math.max(50, fill_percent - 5)
    local max_fill = math.min(100, fill_percent + 5)

    local min_target = available_height * (min_fill / 100)
    local max_target = available_height * (max_fill / 100)

    local scale = 1.0
    if content_height > max_target then
        scale = max_target / content_height
    elseif content_height < min_target then
        scale = min_target / content_height
    end

    -- Landscape layouts are width-dominated: never let content overflow the width.
    if available_width and content_width > 0 then
        local width_max_scale = (available_width * (max_fill / 100)) / content_width
        if scale > width_max_scale then
            scale = width_max_scale
        end
    end

    if scale ~= 1.0 then
        widget = buildFunc(scale)
    end

    return widget, scale
end

--- Build a single hourly forecast column (hour label, icon, temperature).
local function buildHourColumn(hour_data, icon_size, font_size)
    local col = {}
    table.insert(col, TextWidget:new {
        text = hour_data.hour,
        face = Font:getFace("cfont", font_size),
    })
    if hour_data.icon_path then
        table.insert(col, ImageWidget:new {
            file = hour_data.icon_path,
            width = icon_size,
            height = icon_size,
            alpha = true,
            original_in_nightmode = false,
        })
    end
    table.insert(col, TextWidget:new {
        text = WeatherUtils:getHourlyTemp(hour_data, false),
        face = Font:getFace("cfont", font_size),
    })
    return VerticalGroup:new {
        align = "center",
        unpack(col),
    }
end

--- Build a grid of hourly forecast columns, wrapping into rows of `cols` columns.
--- @param hourly_data table  Array of hour entries (each with hour, hour_num, icon_path, temp_c, temp_f).
--- @param target_hours table  Array of hour numbers to include (e.g. {6, 12, 18}).
--- @param cols number|nil  Columns per row; nil or <= 0 puts every column in a single row.
--- @param icon_size number  Pixel size for the weather icons.
--- @param font_size number  Font size for the hour label and temperature text.
--- @param h_spacing number  Horizontal spacing between columns.
--- @param v_spacing number|nil  Vertical spacing between rows (default 0).
--- @return widget|nil  VerticalGroup of HorizontalGroup rows (or a single HorizontalGroup), or nil if no hours matched.
function DisplayHelper:buildHourlyGrid(hourly_data, target_hours, cols, icon_size, font_size, h_spacing, v_spacing)
    if not hourly_data or #hourly_data == 0 then return nil end
    v_spacing = v_spacing or 0

    -- Build a fast lookup set from target_hours
    local target_set = {}
    for _, h in ipairs(target_hours) do target_set[h] = true end

    -- Collect matching columns in chronological order
    local columns = {}
    for _, hour_data in ipairs(hourly_data) do
        if target_set[hour_data.hour_num] then
            table.insert(columns, buildHourColumn(hour_data, icon_size, font_size))
        end
    end

    if #columns == 0 then return nil end
    if not cols or cols <= 0 then cols = #columns end

    -- Chunk columns into rows of `cols`
    local rows = {}
    local row = {}
    for i, column in ipairs(columns) do
        if #row > 0 then
            table.insert(row, HorizontalSpan:new { width = h_spacing })
        end
        table.insert(row, column)
        if i % cols == 0 or i == #columns then
            table.insert(rows, HorizontalGroup:new { align = "center", unpack(row) })
            row = {}
        end
    end

    if #rows == 1 then
        return rows[1]
    end

    local grid = {}
    for i, r in ipairs(rows) do
        if i > 1 then
            table.insert(grid, VerticalSpan:new { width = v_spacing })
        end
        table.insert(grid, r)
    end
    return VerticalGroup:new { align = "center", unpack(grid) }
end

--- Build a single horizontal row of hourly forecast columns.
--- Thin wrapper over buildHourlyGrid for callers that want all hours in one row.
--- @param hourly_data table  Array of hour entries.
--- @param target_hours table  Array of hour numbers to include (e.g. {6, 12, 18}).
--- @param icon_size number  Pixel size for the weather icons.
--- @param font_size number  Font size for the hour label and temperature text.
--- @param spacing number  Horizontal spacing between columns.
--- @return widget|nil  HorizontalGroup widget, or nil if no hours matched.
function DisplayHelper:buildHourlyRow(hourly_data, target_hours, icon_size, font_size, spacing)
    return self:buildHourlyGrid(hourly_data, target_hours, nil, icon_size, font_size, spacing, 0)
end

function DisplayHelper:createLoadingWidget()
    logger.dbg("WeatherLockscreen: Creating loading icon")

    local icon_size = Screen:scaleBySize(200)

    local icon_filename = "hourglass.svg"
    local icon_path = DataStorage:getDataDir() .. "/icons/" .. icon_filename

    if not util.pathExists(icon_path) then
        logger.warn("WeatherLockscreen: Loading icon file not found:", icon_path)
        return nil
    end

    local icon_widget = ImageWidget:new {
        file = icon_path,
        width = icon_size,
        height = icon_size,
        alpha = true,
        original_in_nightmode = false
    }

    return FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        CenterContainer:new {
            dimen = Screen:getSize(),
            VerticalGroup:new {
                align = "center",
                icon_widget,
            },
        },
    }
end

return DisplayHelper
