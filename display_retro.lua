--[[
    Retro Analog Display Mode for Weather Lockscreen
    Vintage weather station with gauges
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
local DataStorage = require("datastorage")

local RetroAnalogDisplay = {}

function RetroAnalogDisplay:create(weather_lockscreen, weather_data)
    -- Base sizes (DPI-independent)
    local base_title_font_size = 36
    local base_gauge_font_size = 40
    local base_label_font_size = 24
    local base_small_font_size = 20
    local base_arrow_size = 100
    local base_spacing = 40
    local base_small_spacing = 16
    local header_font_size = 16
    local header_margin = 10
    local top_bottom_margin = 100

    local screen_height = Screen:getHeight()

    -- Extract temperature value for thermometer
    local temp_value = weather_data.current.temperature
    local temp_num = tonumber(temp_value:match("(-?%d+)"))
    local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or "C"

    -- Build retro weather content with given scale factor
    local function buildRetroContent(scale_factor)
        -- Apply scale to all sizes
        local title_font_size = math.floor(base_title_font_size * scale_factor)
        local gauge_font_size = math.floor(base_gauge_font_size * scale_factor)
        local label_font_size = math.floor(base_label_font_size * scale_factor)
        local small_font_size = math.floor(base_small_font_size * scale_factor)
        local arrow_size = math.floor(base_arrow_size * scale_factor)
        local spacing = math.floor(base_spacing * scale_factor)
        local small_spacing = math.floor(base_small_spacing * scale_factor)

        -- Create humidity/pressure gauge
        local function createHumidityGauge()
            local humidity = weather_data.current.humidity or "0%"
            local hum_num = tonumber(humidity:match("(%d+)")) or 0

            -- Bar gauge style
            local bar_length = 10
            local filled = math.floor(hum_num / 10)
            local bar = ""
            for i = 1, bar_length do
                bar = bar .. (i <= filled and "█" or "░")
            end

            local gauge_widgets = {}

            table.insert(gauge_widgets, TextWidget:new{
                text = "HUMIDITY",
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })
            table.insert(gauge_widgets, VerticalSpan:new{ width = small_spacing })

            table.insert(gauge_widgets, TextWidget:new{
                text = bar,
                face = Font:getFace("ffont", label_font_size),
            })
            table.insert(gauge_widgets, VerticalSpan:new{ width = small_spacing })

            table.insert(gauge_widgets, TextWidget:new{
                text = humidity,
                face = Font:getFace("cfont", gauge_font_size),
                bold = true,
            })

            return VerticalGroup:new{
                align = "center",
                unpack(gauge_widgets)
            }
        end

        -- Build the layout
        local widgets = {}

        local border_line = "═══════════════════════"
        table.insert(widgets, TextWidget:new{
            text = border_line,
            face = Font:getFace("ffont", small_font_size),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })

        -- Condition text
        if weather_data.current.condition then
            table.insert(widgets, TextWidget:new{
                text = weather_data.current.condition:upper(),
                face = Font:getFace("cfont", math.floor(title_font_size * 1.2)),
                bold = true,
            })
            table.insert(widgets, VerticalSpan:new{ width = spacing })
        end

        -- Create combined temperature and wind display with aligned rows
        if temp_num then
            local wind_speed = weather_data.current.wind or "0 km/h"
            local wind_dir = weather_data.current.wind_dir or ""

            -- Get arrow SVG path
            local function getArrowPath(direction)
                local dir_map = {
                    N   = "n",
                    NNE = "ne", NE = "ne", ENE = "ne",
                    E   = "e",
                    ESE = "se", SE = "se", SSE = "se",
                    S   = "s",
                    SSW = "sw", SW = "sw", WSW = "sw",
                    W   = "w",
                    WNW = "nw", NW = "nw", NNW = "nw"
                }

                local arrow_dir = dir_map[direction]
                if not arrow_dir then return nil end

                -- Use installed arrows from data directory
                local arrow_path = DataStorage:getDataDir() .. "/icons/arrows/arrow_" .. arrow_dir .. ".svg"
                local f = io.open(arrow_path, "r")
                if f then
                    f:close()
                    return arrow_path
                end
                return nil
            end

            local arrow_path = getArrowPath(wind_dir)

            -- Row 1: Labels (TEMPERATURE | WIND)
            local labels_row = {}
            table.insert(labels_row, TextWidget:new{
                text = "TEMPERATURE",
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })
            table.insert(labels_row, HorizontalSpan:new{ width = spacing * 3 })
            table.insert(labels_row, TextWidget:new{
                text = "WIND",
                face = Font:getFace("cfont", label_font_size),
                bold = true,
            })

            table.insert(widgets, HorizontalGroup:new{
                align = "center",
                unpack(labels_row)
            })
            table.insert(widgets, VerticalSpan:new{ width = small_spacing })

            -- Row 2: Middle content (thermometer bars | arrow)
            local temp_c = temp_num
            if temp_scale == "F" then
                temp_c = (temp_num - 32) * 5 / 9
            end

            local segments = {
                {temp = 40, label = "40°"},
                {temp = 30, label = "30°"},
                {temp = 20, label = "20°"},
                {temp = 10, label = "10°"},
                {temp = 0, label = "0°"},
                {temp = -10, label = "-10°"}
            }

            local thermo_widgets = {}
            for _, seg in ipairs(segments) do
                local marker = temp_c >= seg.temp and "▓" or "░"
                -- Use right-aligned label for better alignment
                local line = string.format("%4s ║%s║", seg.label, marker)
                table.insert(thermo_widgets, TextWidget:new{
                    text = line,
                    face = Font:getFace("ffont", small_font_size),
                    fgcolor = temp_c >= seg.temp and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
                })
            end

            local thermo_group = VerticalGroup:new{
                align = "right",
                unpack(thermo_widgets)
            }

            local arrow_widget
            if arrow_path then
                arrow_widget = ImageWidget:new{
                    file = arrow_path,
                    width = arrow_size,
                    height = arrow_size,
                    alpha = true,
                    original_in_nightmode = false
                }
            else
                arrow_widget = TextWidget:new{
                    text = wind_dir ~= "" and wind_dir or "---",
                    face = Font:getFace("cfont", gauge_font_size),
                }
            end

            local middle_row = {}
            table.insert(middle_row, thermo_group)
            table.insert(middle_row, HorizontalSpan:new{ width = spacing * 3 })
            table.insert(middle_row, arrow_widget)

            table.insert(widgets, HorizontalGroup:new{
                align = "center",
                unpack(middle_row)
            })
            table.insert(widgets, VerticalSpan:new{ width = small_spacing })

            -- Row 3: Values (temperature | wind speed)
            local values_row = {}
            table.insert(values_row, HorizontalSpan:new{ width = spacing * 1.1 })
            table.insert(values_row, TextWidget:new{
                text = temp_value,
                face = Font:getFace("cfont", gauge_font_size),
                bold = true,
            })
            table.insert(values_row, HorizontalSpan:new{ width = spacing * 3 })
            table.insert(values_row, TextWidget:new{
                text = wind_speed,
                face = Font:getFace("cfont", gauge_font_size),
                bold = true,
            })

            table.insert(widgets, HorizontalGroup:new{
                align = "center",
                unpack(values_row)
            })
        end

        -- Humidity gauge
        if weather_data.current.humidity then
            table.insert(widgets, VerticalSpan:new{ width = spacing})
            table.insert(widgets, createHumidityGauge())
        end

        -- Decorative border lines
        table.insert(widgets, VerticalSpan:new{ width = spacing })
        table.insert(widgets, TextWidget:new{
            text = border_line,
            face = Font:getFace("ffont", small_font_size),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })

        return VerticalGroup:new{
            align = "center",
            unpack(widgets)
        }
    end

    -- Build content at scale 1.0 to measure actual size
    local content_scale = 1.0
    local weather_group = buildRetroContent(content_scale)
    local content_height = weather_group:getSize().h

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
        weather_group = buildRetroContent(content_scale)
    elseif content_height < min_target_height then
        -- Content too small, scale up to min_fill
        content_scale = min_target_height / content_height
        weather_group = buildRetroContent(content_scale)
    end

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

return RetroAnalogDisplay
