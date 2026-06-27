--[[
    Day Display Mode for Weather Lockscreen
    Day-focused display with expanded hourly forecasts and feels-like temperature
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("l10n/gettext")
local WeatherUtils = require("weather_utils")
local DisplayHelper = require("display_helper")

local DayDisplay = {}

function DayDisplay:create(weather_lockscreen, weather_data)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local is_landscape = screen_width > screen_height

    -- Base sizes for content
    local base_current_icon_size = 300
    local base_hourly_icon_size = 120
    local base_temp_font_size = 48
    local base_temp_feels_like_font_size = 30
    local base_condition_font_size = 36
    local base_hour_font_size = 24
    local base_vertical_spacing = 30
    local base_horizontal_spacing = 20
    local header_font_size = Screen:scaleBySize(20)
    local header_margin = 10

    -- Header: Location and Timestamp
    local header_group = DisplayHelper:createHeaderWidgets(header_font_size, header_margin, weather_data,
        Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)
    local header_height = header_group:getSize().h

    -- Resolve which hours to show and how to wrap them into a grid.
    -- Landscape aims for 2 rows beside the current block; portrait keeps up to 5 per row.
    local target_hours = WeatherUtils:getHourlySelection(WeatherUtils.target_hours_expand)
    local hour_count = #target_hours
    local grid_cols = is_landscape and math.ceil(hour_count / 2) or math.min(hour_count, 5)

    -- Function to build the weather content with a given scale factor
    local function buildWeatherContent(scale_factor)
        local current_icon_size = math.floor(base_current_icon_size * scale_factor)
        local hourly_icon_size = math.floor(base_hourly_icon_size * scale_factor)
        local temp_font_size = math.floor(base_temp_font_size * scale_factor)
        local temp_feels_like_font_size = math.floor(base_temp_feels_like_font_size * scale_factor)
        local condition_font_size = math.floor(base_condition_font_size * scale_factor)
        local hour_font_size = math.floor(base_hour_font_size * scale_factor)
        local vertical_spacing = math.floor(base_vertical_spacing * scale_factor)
        local horizontal_spacing = math.floor(base_horizontal_spacing * scale_factor)

        -- Current weather block
        local current_widgets = {}
        if weather_data.current.icon_path then
            table.insert(current_widgets, ImageWidget:new {
                file = weather_data.current.icon_path,
                width = current_icon_size,
                height = current_icon_size,
                alpha = true,
                original_in_nightmode = false
            })
        end
        table.insert(current_widgets, TextWidget:new {
            text = WeatherUtils:getCurrentTemp(weather_data),
            face = Font:getFace("cfont", temp_font_size),
            bold = true,
        })
        table.insert(current_widgets, TextWidget:new {
            text = WeatherUtils:getCurrentTempFeelsLike(weather_data),
            face = Font:getFace("cfont", temp_feels_like_font_size),
        })
        if weather_data.current.condition then
            table.insert(current_widgets, TextWidget:new {
                text = weather_data.current.condition,
                face = Font:getFace("cfont", condition_font_size),
            })
        end
        local current_block = VerticalGroup:new {
            align = "center",
            unpack(current_widgets)
        }

        -- Today's hourly forecast grid
        local hourly_grid = DisplayHelper:buildHourlyGrid(
            weather_data.hourly_today_all, target_hours, grid_cols,
            hourly_icon_size, hour_font_size, horizontal_spacing, vertical_spacing)

        if is_landscape then
            -- Current block on the left, hourly grid on the right
            local row = { current_block }
            if hourly_grid then
                table.insert(row, HorizontalSpan:new { width = horizontal_spacing * 3 })
                table.insert(row, hourly_grid)
            end
            return HorizontalGroup:new {
                align = "center",
                unpack(row)
            }
        else
            local widgets = { current_block }
            if hourly_grid then
                table.insert(widgets, VerticalSpan:new { width = vertical_spacing })
                table.insert(widgets, hourly_grid)
            end
            return VerticalGroup:new {
                align = "center",
                unpack(widgets)
            }
        end
    end

    -- Scale content to fit available height (and width in landscape)
    local available_height = screen_height - header_height
    local weather_group = DisplayHelper:scaleToFit(buildWeatherContent, available_height, nil,
        is_landscape and screen_width or nil)

    local main_content = CenterContainer:new {
        dimen = Screen:getSize(),
        weather_group,
    }

    return OverlapGroup:new {
        dimen = Screen:getSize(),
        main_content,
        header_group,
    }
end

return DayDisplay
