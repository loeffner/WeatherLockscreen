--[[
    Forecast Display Mode for Weather Lockscreen
    Shows today's high/low at top, tomorrow and day after side by side below
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("l10n/gettext")

local ForecastDisplay = {}

function ForecastDisplay:create(weather_lockscreen, weather_data)
    -- Base sizes (DPI-independent)
    local base_today_icon_size = 180
    local base_today_day_font = 32
    local base_today_temp_font = 56
    local base_today_condition_font = 24

    local base_future_icon_size = 140
    local base_future_day_font = 28
    local base_future_temp_font = 40
    local base_future_condition_font = 20

    local base_spacing = 20
    local base_day_spacing = 30
    local header_font_size = 16
    local header_margin = 10
    local top_bottom_margin = 50

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Function to build forecast content with given scale factor
    local function buildForecastContent(scale_factor)
        -- Apply scale factor to all sizes
        local today_icon_size = math.floor(base_today_icon_size * scale_factor)
        local today_day_font = math.floor(base_today_day_font * scale_factor)
        local today_temp_font = math.floor(base_today_temp_font * scale_factor)
        local today_condition_font = math.floor(base_today_condition_font * scale_factor)

        local future_icon_size = math.floor(base_future_icon_size * scale_factor)
        local future_day_font = math.floor(base_future_day_font * scale_factor)
        local future_temp_font = math.floor(base_future_temp_font * scale_factor)
        local future_condition_font = math.floor(base_future_condition_font * scale_factor)

        local spacing = math.floor(base_spacing * scale_factor)
        local day_spacing = math.floor(base_day_spacing * scale_factor)

        -- Helper function to create a day forecast widget
        local function createDayWidget(day_data, icon_size, day_font, temp_font, condition_font)
            local widgets = {}

            -- Day name
            table.insert(widgets, TextWidget:new{
                text = day_data.day_name,
                face = Font:getFace("cfont", day_font, true),
            })
            table.insert(widgets, VerticalSpan:new{ width = spacing })

            -- Weather icon
            if day_data.icon_path then
                table.insert(widgets, ImageWidget:new{
                    file = day_data.icon_path,
                    width = icon_size,
                    height = icon_size,
                    alpha = true,
                    original_in_nightmode = false
                })
                table.insert(widgets, VerticalSpan:new{ width = spacing })
            end

            -- High / Low temperatures
            table.insert(widgets, TextWidget:new{
                text = day_data.high_low,
                face = Font:getFace("cfont", temp_font, true),
            })
            table.insert(widgets, VerticalSpan:new{ width = math.floor(spacing * 0.5) })

            -- Condition
            if day_data.condition then
                table.insert(widgets, TextWidget:new{
                    text = day_data.condition,
                    face = Font:getFace("cfont", condition_font),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                })
            end

            return VerticalGroup:new{
                align = "center",
                unpack(widgets)
            }
        end

        local content_widgets = {}

        -- Today's forecast (top, larger)
        if weather_data.forecast_days and weather_data.forecast_days[1] then
            local today_widget = createDayWidget(
                weather_data.forecast_days[1],
                today_icon_size,
                today_day_font,
                today_temp_font,
                today_condition_font
            )
            table.insert(content_widgets, today_widget)
            table.insert(content_widgets, VerticalSpan:new{ width = day_spacing })
        end

        -- Separator line
        local line_width = math.floor(screen_width * 0.6)
        table.insert(content_widgets, CenterContainer:new{
            dimen = { w = screen_width, h = 2 },
            LineWidget:new{
                dimen = { w = line_width, h = 2 },
                background = Blitbuffer.COLOR_GRAY,
            }
        })
        table.insert(content_widgets, VerticalSpan:new{ width = day_spacing })

        -- Tomorrow and day after (bottom, side by side, smaller)
        if weather_data.forecast_days and weather_data.forecast_days[2] and weather_data.forecast_days[3] then
            local tomorrow_widget = createDayWidget(
                weather_data.forecast_days[2],
                future_icon_size,
                future_day_font,
                future_temp_font,
                future_condition_font
            )

            local day_after_widget = createDayWidget(
                weather_data.forecast_days[3],
                future_icon_size,
                future_day_font,
                future_temp_font,
                future_condition_font
            )

            -- Add horizontal spacing between the two days
            local horizontal_spacing = math.floor(spacing * 3)

            local future_days = HorizontalGroup:new{
                align = "center",
                tomorrow_widget,
                HorizontalSpan:new{ width = horizontal_spacing },
                day_after_widget,
            }

            table.insert(content_widgets, CenterContainer:new{
                dimen = { w = screen_width, h = future_days:getSize().h },
                future_days,
            })
        end

        return VerticalGroup:new{
            align = "center",
            unpack(content_widgets)
        }
    end

    -- Build content at scale 1.0 to measure actual size
    local content_scale = 1.0
    local forecast_group = buildForecastContent(content_scale)
    local content_height = forecast_group:getSize().h

    -- Calculate header height
    local header_group = weather_lockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data, Blitbuffer.COLOR_DARK_GRAY, weather_data.is_cached)
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
        forecast_group = buildForecastContent(content_scale)
    elseif content_height < min_target_height then
        -- Content too small, scale up to min_fill
        content_scale = min_target_height / content_height
        forecast_group = buildForecastContent(content_scale)
    end

    local main_content = CenterContainer:new{
        dimen = Screen:getSize(),
        forecast_group,
    }

    return OverlapGroup:new{
        dimen = Screen:getSize(),
        main_content,
        header_group,
    }
end

return ForecastDisplay
