--[[
    Default Display Mode for Weather Lockscreen
    Shows detailed weather with hourly forecasts
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local WeatherUtils = require("utils")

local DefaultDisplay = {}

function DefaultDisplay:create(weather_lockscreen, weather_data)
    local screen_height = Screen:getHeight()
    local screen_width = Screen:getWidth()
    
    -- Base sizes for content
    local base_current_icon_size = 300
    local base_hourly_icon_size = 120
    local base_temp_font_size = 48
    local base_condition_font_size = 36
    local base_label_font_size = 30
    local base_hour_font_size = 24
    local base_vertical_spacing = 30
    local base_horizontal_spacing = 20
    local header_font_size = 16
    local header_margin = 10
    local top_bottom_margin = 100

    -- Header: Location and Timestamp
    local header_group = weather_lockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data,
        Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)
    
    -- Calculate header height
    local header_height = (header_font_size + header_margin) * 2

    -- Function to build the weather content with a given scale factor
    local function buildWeatherContent(scale_factor)
        local current_icon_size = math.floor(base_current_icon_size * scale_factor)
        local hourly_icon_size = math.floor(base_hourly_icon_size * scale_factor)
        local temp_font_size = math.floor(base_temp_font_size * scale_factor)
        local condition_font_size = math.floor(base_condition_font_size * scale_factor)
        local label_font_size = math.floor(base_label_font_size * scale_factor)
        local hour_font_size = math.floor(base_hour_font_size * scale_factor)
        local vertical_spacing = math.floor(base_vertical_spacing * scale_factor)
        local horizontal_spacing = math.floor(base_horizontal_spacing * scale_factor)

        local widgets = {}

        -- Current weather
        local current_widgets = {}

        local icon_widget = ImageWidget:new {
            file = weather_data.current.icon_path,
            width = current_icon_size,
            height = current_icon_size,
            alpha = true,
        }
        table.insert(current_widgets, icon_widget)

        if weather_data.current.temperature then
            table.insert(current_widgets, TextWidget:new {
                text = weather_data.current.temperature,
                face = Font:getFace("cfont", temp_font_size),
                bold = true,
            })
        end

        if weather_data.current.condition then
            table.insert(current_widgets, TextWidget:new {
                text = weather_data.current.condition,
                face = Font:getFace("cfont", condition_font_size),
            })
        end

        table.insert(widgets, VerticalGroup:new {
            align = "center",
            unpack(current_widgets)
        })

        table.insert(widgets, VerticalSpan:new { width = vertical_spacing })

        -- Today's hourly forecast
        if weather_data.hourly_today and #weather_data.hourly_today > 0 then
            table.insert(widgets, TextWidget:new {
                text = "Today",
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })

            local today_row = {}
            for i, hour_data in ipairs(weather_data.hourly_today) do
                if i > 1 then
                    table.insert(today_row, HorizontalSpan:new { width = horizontal_spacing })
                end

                local hour_widgets = {}
                table.insert(hour_widgets, TextWidget:new {
                    text = hour_data.hour,
                    face = Font:getFace("cfont", hour_font_size),
                })

                if hour_data.icon_path then
                    table.insert(hour_widgets, ImageWidget:new {
                        file = hour_data.icon_path,
                        width = hourly_icon_size,
                        height = hourly_icon_size,
                        alpha = true,
                    })
                end

                table.insert(hour_widgets, TextWidget:new {
                    text = hour_data.temperature,
                    face = Font:getFace("cfont", hour_font_size),
                })

                table.insert(today_row, VerticalGroup:new {
                    align = "center",
                    unpack(hour_widgets)
                })
            end

            table.insert(widgets, HorizontalGroup:new {
                align = "center",
                unpack(today_row)
            })

            table.insert(widgets, VerticalSpan:new { width = vertical_spacing })
        end

        -- Tomorrow's hourly forecast
        if weather_data.hourly_tomorrow and #weather_data.hourly_tomorrow > 0 then
            table.insert(widgets, TextWidget:new {
                text = "Tomorrow",
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })

            local tomorrow_row = {}
            for i, hour_data in ipairs(weather_data.hourly_tomorrow) do
                if i > 1 then
                    table.insert(tomorrow_row, HorizontalSpan:new { width = horizontal_spacing })
                end

                local hour_widgets = {}
                table.insert(hour_widgets, TextWidget:new {
                    text = hour_data.hour,
                    face = Font:getFace("cfont", hour_font_size),
                })

                if hour_data.icon_path then
                    table.insert(hour_widgets, ImageWidget:new {
                        file = hour_data.icon_path,
                        width = hourly_icon_size,
                        height = hourly_icon_size,
                        alpha = true,
                    })
                end

                table.insert(hour_widgets, TextWidget:new {
                    text = hour_data.temperature,
                    face = Font:getFace("cfont", hour_font_size),
                })

                table.insert(tomorrow_row, VerticalGroup:new {
                    align = "center",
                    unpack(hour_widgets)
                })
            end

            table.insert(widgets, HorizontalGroup:new {
                align = "center",
                unpack(tomorrow_row)
            })
        end

        return VerticalGroup:new {
            align = "center",
            unpack(widgets)
        }
    end

    -- Build content with initial scale of 1.0 and measure it
    local content_scale = 1.0
    local weather_group = buildWeatherContent(content_scale)
    local content_height = weather_group:getSize().h
    local available_height = screen_height - header_height - top_bottom_margin

    -- If content is too tall, rebuild with reduced scale
    if content_height > available_height then
        content_scale = available_height / content_height
        weather_group = buildWeatherContent(content_scale)
    end

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

return DefaultDisplay
