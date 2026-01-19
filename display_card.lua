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
local WeatherUtils = require("weather_utils")
local DisplayHelper = require("display_helper")

local CardDisplay = {}

function CardDisplay:create(weather_lockscreen, weather_data)
    -- Base sizes (DPI-independent)
    local base_icon_size = 250
    local base_temp_font_size = 60
    local base_condition_font_size = 28
    local base_detail_font_size = 22
    local base_spacing = 25
    local header_font_size = Screen:scaleBySize(20)
    local header_margin = 10
    local top_bottom_margin = 50

    local screen_height = Screen:getHeight()

    -- Function to build card content with given scale factor
    local function buildCardContent(scale_factor)
        -- Apply scale factor to all sizes
        local icon_size = math.floor(base_icon_size * scale_factor)
        local temp_font_size = math.floor(base_temp_font_size * scale_factor)
        local condition_font_size = math.floor(base_condition_font_size * scale_factor)
        local detail_font_size = math.floor(base_detail_font_size * scale_factor)
        local spacing = math.floor(base_spacing * scale_factor)

        -- Main content
        local widgets = {}

        -- Weather icon
        if weather_data.current.icon_path then
            table.insert(widgets, ImageWidget:new {
                file = weather_data.current.icon_path,
                width = icon_size,
                height = icon_size,
                alpha = true,
                original_in_nightmode = false
            })
            table.insert(widgets, VerticalSpan:new { width = spacing })
        end

        -- Temperature
        table.insert(widgets, TextWidget:new {
            text = WeatherUtils:getCurrentTemp(weather_data),
            face = Font:getFace("cfont", temp_font_size),
            bold = true,
        })
        table.insert(widgets, VerticalSpan:new { width = math.floor(spacing * 0.3) })

        -- Condition
        table.insert(widgets, TextWidget:new {
            text = weather_data.current.condition,
            face = Font:getFace("cfont", condition_font_size),
        })
        table.insert(widgets, VerticalSpan:new { width = spacing })

        -- High/Low if available
        table.insert(widgets, TextWidget:new {
            text = WeatherUtils:getForecastHighLow(weather_data.forecast_days[1]),
            face = Font:getFace("cfont", detail_font_size),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })

        return VerticalGroup:new {
            align = "center",
            unpack(widgets)
        }
    end

    -- Build content at scale 1.0 to measure actual size
    local content_scale = 1.0
    local weather_group = buildCardContent(content_scale)
    local content_height = weather_group:getSize().h

    -- Calculate header height
    local header_group = DisplayHelper:createHeaderWidgets(header_font_size, header_margin, weather_data, Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)
    local header_height = header_group:getSize().h

    -- Calculate available height
    local available_height = screen_height - header_height - top_bottom_margin

    -- Get user fill percent (default 90)
    local fill_percent = G_reader_settings:readSetting("weather_override_scaling") and tonumber(G_reader_settings:readSetting("weather_fill_percent")) or 90
    local min_fill = math.max(50, fill_percent - 5)
    local max_fill = math.min(100, fill_percent + 5)

    local min_target_height = available_height * (min_fill / 100)
    local max_target_height = available_height * (max_fill / 100)

    -- Determine the scale factor
    if content_height > max_target_height then
        -- Content too large, scale down to max_fill
        content_scale = max_target_height / content_height
        weather_group = buildCardContent(content_scale)
    elseif content_height < min_target_height then
        -- Content too small, scale up to min_fill
        content_scale = min_target_height / content_height
        weather_group = buildCardContent(content_scale)
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

return CardDisplay
