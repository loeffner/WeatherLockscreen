--[[
    Display Helper Functions for Weather Lockscreen Plugin

    Provides utility functions for creating various widget types.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local Device = require("device")
local Screen = Device.screen
local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local logger = require("logger")

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

function DisplayHelper:createFallbackWidget()
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

function DisplayHelper:createLoadingWidget()
    logger.dbg("WeatherLockscreen: Creating loading icon")

    local icon_size = Screen:scaleBySize(200)

    local icon_filename = "hourglass.svg"
    local icon_path = DataStorage:getDataDir() .. "/icons/" .. icon_filename

    local f = io.open(icon_path, "r")
    if f then
        f:close()
    else
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
