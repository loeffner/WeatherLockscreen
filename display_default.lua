--[[
    Default Display Mode for Weather Lockscreen
    Shows detailed weather with hourly forecasts
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("l10n/gettext")
local WeatherUtils = require("weather_utils")
local DisplayHelper = require("display_helper")

local DefaultDisplay = {}

function DefaultDisplay:create(weather_lockscreen, weather_data)
    local screen_height = Screen:getHeight()

    -- Base sizes for content
    local base_current_icon_size = 300
    local base_hourly_icon_size = 120
    local base_temp_font_size = 48
    local base_condition_font_size = 36
    local base_label_font_size = 30
    local base_hour_font_size = 24
    local base_vertical_spacing = 30
    local base_horizontal_spacing = 20
    local header_font_size = Screen:scaleBySize(20)
    local header_margin = 10

    -- Header: Location and Timestamp
    local header_group = DisplayHelper:createHeaderWidgets(header_font_size, header_margin, weather_data,
        Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)
    local header_height = header_group:getSize().h

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
            original_in_nightmode = false
        }
        table.insert(current_widgets, icon_widget)

        table.insert(current_widgets, TextWidget:new {
            text = WeatherUtils:getCurrentTemp(weather_data),
            face = Font:getFace("cfont", temp_font_size),
            bold = true,
        })

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
        local today_row = DisplayHelper:buildHourlyRow(
            weather_data.hourly_today_all, WeatherUtils.target_hours,
            hourly_icon_size, hour_font_size, horizontal_spacing)
        if today_row then
            table.insert(widgets, TextWidget:new {
                text = _("Today"),
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })
            table.insert(widgets, today_row)
            table.insert(widgets, VerticalSpan:new { width = vertical_spacing })
        end

        -- Tomorrow's hourly forecast
        local tomorrow_row = DisplayHelper:buildHourlyRow(
            weather_data.hourly_tomorrow_all, WeatherUtils.target_hours,
            hourly_icon_size, hour_font_size, horizontal_spacing)
        if tomorrow_row then
            table.insert(widgets, TextWidget:new {
                text = _("Tomorrow"),
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })
            table.insert(widgets, tomorrow_row)
        end

        return VerticalGroup:new {
            align = "center",
            unpack(widgets)
        }
    end

    -- Scale content to fit available height
    local available_height = screen_height - header_height
    local weather_group = DisplayHelper:scaleToFit(buildWeatherContent, available_height)

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
