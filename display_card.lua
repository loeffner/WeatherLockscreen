--[[
    Card Display Mode for Weather Lockscreen
    Clean minimal card-style display
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
local WeatherUtils = require("utils")

local CardDisplay = {}

function CardDisplay:create(weather_lockscreen, weather_data)
    -- Start with large base sizes (independent of DPI)
    local base_icon_size = 250
    local base_temp_font_size = 60
    local base_condition_font_size = 28
    local base_detail_font_size = 22
    local base_spacing = 25
    local header_font_size = 16
    local header_margin = 10
    local top_bottom_margin = 150  -- Larger margins for centered look

    -- Estimate total required height with base sizes
    local elements = {
        base_icon_size,
        base_spacing,
        base_temp_font_size,
        math.floor(base_spacing * 0.3),
        base_condition_font_size,
        base_spacing,
        base_detail_font_size,
    }

    -- Calculate scale factor using utility function
    local screen_height = Screen:getHeight()
    local content_scale = WeatherUtils:scaleToScreenHeight(
    screen_height,
        { elements = elements },
        top_bottom_margin,
        header_font_size,
        header_margin
    )

    -- Apply scale factor to all sizes
    local icon_size = math.floor(base_icon_size * content_scale)
    local temp_font_size = math.floor(base_temp_font_size * content_scale)
    local condition_font_size = math.floor(base_condition_font_size * content_scale)
    local detail_font_size = math.floor(base_detail_font_size * content_scale)
    local spacing = math.floor(base_spacing * content_scale)    -- Header: Location and Timestamp
    local header_group = weather_lockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data, Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)

    -- Main content
    local widgets = {}

    -- Weather icon
    if weather_data.current.icon_path then
        table.insert(widgets, ImageWidget:new{
            file = weather_data.current.icon_path,
            width = icon_size,
            height = icon_size,
            alpha = true,
        })
        table.insert(widgets, VerticalSpan:new{ width = spacing })
    end

    -- Temperature
    if weather_data.current.temperature then
        table.insert(widgets, TextWidget:new{
            text = weather_data.current.temperature,
            face = Font:getFace("cfont", temp_font_size),
            bold = true,
        })
        table.insert(widgets, VerticalSpan:new{ width = math.floor(spacing * 0.3) })
    end

    -- Condition
    if weather_data.current.condition then
        table.insert(widgets, TextWidget:new{
            text = weather_data.current.condition,
            face = Font:getFace("cfont", condition_font_size),
        })
        table.insert(widgets, VerticalSpan:new{ width = spacing })
    end

    -- High/Low if available
    if weather_data.forecast_days and weather_data.forecast_days[1] and weather_data.forecast_days[1].high_low then
        table.insert(widgets, TextWidget:new{
            text = weather_data.forecast_days[1].high_low,
            face = Font:getFace("cfont", detail_font_size),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
    end

    local weather_group = VerticalGroup:new{
        align = "center",
        unpack(widgets)
    }

    local main_content = CenterContainer:new{
        dimen = Screen:getSize(),
        weather_group,
    }

    return OverlapGroup:new{
        dimen = Screen:getSize(),
        main_content,
        header_group,
    }
end

return CardDisplay
