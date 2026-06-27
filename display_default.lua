--[[
    Default Display Mode for Weather Lockscreen
    Shows detailed weather with hourly forecasts
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

local DefaultDisplay = {}

function DefaultDisplay:create(weather_lockscreen, weather_data)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local is_landscape = screen_width > screen_height

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

    -- Resolve which hours to show; keep each forecast compact (up to 5 per row).
    local target_hours = WeatherUtils:getHourlySelection(WeatherUtils.target_hours)
    local grid_cols = math.min(#target_hours, 5)

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

        -- Current weather block
        local current_widgets = {}
        table.insert(current_widgets, ImageWidget:new {
            file = weather_data.current.icon_path,
            width = current_icon_size,
            height = current_icon_size,
            alpha = true,
            original_in_nightmode = false
        })
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
        local current_block = VerticalGroup:new {
            align = "center",
            unpack(current_widgets)
        }

        -- Build a labelled hourly-forecast section (label + grid), or nil if no hours.
        local function buildForecastSection(label_text, hourly_data)
            local grid = DisplayHelper:buildHourlyGrid(hourly_data, target_hours, grid_cols,
                hourly_icon_size, hour_font_size, horizontal_spacing, vertical_spacing)
            if not grid then return nil end
            return VerticalGroup:new {
                align = "center",
                TextWidget:new {
                    text = label_text,
                    face = Font:getFace("cfont", label_font_size),
                    bold = true,
                },
                grid,
            }
        end

        local today_section = buildForecastSection(_("Today"), weather_data.hourly_today_all)
        local tomorrow_section = buildForecastSection(_("Tomorrow"), weather_data.hourly_tomorrow_all)

        if is_landscape then
            -- Current block on the left; the two forecasts stacked on the right
            local right_widgets = {}
            if today_section then table.insert(right_widgets, today_section) end
            if tomorrow_section then
                if #right_widgets > 0 then
                    table.insert(right_widgets, VerticalSpan:new { width = vertical_spacing })
                end
                table.insert(right_widgets, tomorrow_section)
            end
            local row = { current_block }
            if #right_widgets > 0 then
                table.insert(row, HorizontalSpan:new { width = horizontal_spacing * 3 })
                table.insert(row, VerticalGroup:new { align = "center", unpack(right_widgets) })
            end
            return HorizontalGroup:new {
                align = "center",
                unpack(row)
            }
        else
            local widgets = { current_block, VerticalSpan:new { width = vertical_spacing } }
            if today_section then
                table.insert(widgets, today_section)
                table.insert(widgets, VerticalSpan:new { width = vertical_spacing })
            end
            if tomorrow_section then
                table.insert(widgets, tomorrow_section)
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

return DefaultDisplay
