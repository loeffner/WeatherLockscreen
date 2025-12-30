--[[
    Calendar Display Mode for Weather Lockscreen
    E-Ink optimized layout showing today's events with weather

    Layout Structure:
    - HEADER (overlay): Location + timestamp (using DisplayHelper)
    - DATE: Today's date centered
    - WEATHER_BLOCK: Icon + temp + condition + high/low
    - EVENT_LIST: "TODAY" header + event cards
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local WeatherUtils = require("weather_utils")
local CalendarAPI = require("calendar_api")
local DisplayHelper = require("display_helper")

local CalendarDisplay = {}

-- Format time range for event display
local function formatTimeRange(event, twelve_hour_clock)
    if event.all_day then
        return "ALL DAY"
    end

    local start_info = os.date("*t", event.start_time)
    local start_str

    if twelve_hour_clock then
        local period = start_info.hour >= 12 and "PM" or "AM"
        local hour = start_info.hour % 12
        if hour == 0 then hour = 12 end
        if start_info.min == 0 then
            start_str = string.format("%d %s", hour, period)
        else
            start_str = string.format("%d:%02d %s", hour, start_info.min, period)
        end
    else
        start_str = string.format("%02d:%02d", start_info.hour, start_info.min)
    end

    -- Add end time if available
    if event.end_time then
        local end_info = os.date("*t", event.end_time)
        local end_str

        if twelve_hour_clock then
            local period = end_info.hour >= 12 and "PM" or "AM"
            local hour = end_info.hour % 12
            if hour == 0 then hour = 12 end
            if end_info.min == 0 then
                end_str = string.format("%d %s", hour, period)
            else
                end_str = string.format("%d:%02d %s", hour, end_info.min, period)
            end
        else
            end_str = string.format("%02d:%02d", end_info.hour, end_info.min)
        end

        return start_str .. " – " .. end_str
    end

    return start_str
end

function CalendarDisplay:create(weather_lockscreen, weather_data, calendar_data)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Calculate scale factor based on screen size
    local scale = math.min(screen_width, screen_height) / 600

    -- Margins
    local h_margin = math.floor(24 * scale)
    local content_width = screen_width - (h_margin * 2)

    -- Spacing
    local spacing_large = math.floor(16 * scale)
    local spacing_medium = math.floor(10 * scale)
    local spacing_small = math.floor(5 * scale)

    -- Font sizes
    local font_very_large = math.max(32, math.floor(42 * scale))
    local font_large = math.max(18, math.floor(22 * scale))
    local font_medium = math.max(14, math.floor(17 * scale))
    local font_small = math.max(12, math.floor(14 * scale))
    local font_very_small = math.max(10, math.floor(11 * scale))

    local weather_icon_size = math.floor(font_very_large * 1.4)
    local card_padding = spacing_medium

    -- Get events for today
    local today_events = {}
    if calendar_data and calendar_data.events then
        today_events = CalendarAPI:getEventsForToday(calendar_data.events)
        logger.dbg("CalendarDisplay: Events for today:", #today_events)
    end

    local twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")

    -- Helper function to get weather icon for a specific hour
    local function getHourlyWeatherIcon(event_start_time)
        if not weather_data or not event_start_time then return nil end
        local time_info = os.date("*t", event_start_time)
        local event_hour = time_info.hour

        -- Check if event is today or tomorrow
        local now = os.date("*t")
        local is_today = (time_info.year == now.year and time_info.yday == now.yday)
        local is_tomorrow = (time_info.yday == now.yday + 1) or
            (now.yday == 365 and time_info.yday == 1 and time_info.year == now.year + 1)

        local hourly_data = nil
        if is_today and weather_data.hourly_today_all then
            hourly_data = weather_data.hourly_today_all
        elseif is_tomorrow and weather_data.hourly_tomorrow_all then
            hourly_data = weather_data.hourly_tomorrow_all
        end

        if hourly_data then
            for _, hour_entry in ipairs(hourly_data) do
                if hour_entry.hour_num == event_hour then
                    return hour_entry.icon_path
                end
            end
        end
        return nil
    end

    -- Separate all-day events from timed events
    local all_day_events = {}
    local timed_events = {}
    for _, event in ipairs(today_events) do
        if event.all_day then
            table.insert(all_day_events, event)
        else
            table.insert(timed_events, event)
        end
    end

    -- Function to build event card
    local function buildEventCard(event, is_all_day_group, all_day_list)
        local card_widgets = {}

        if is_all_day_group then
            -- All-day grouped card
            table.insert(card_widgets, TextWidget:new {
                text = "ALL DAY",
                face = Font:getFace("cfont", font_small),
                bold = true,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
            table.insert(card_widgets, VerticalSpan:new { width = spacing_small })

            local max_shown = math.min(#all_day_list, 3)
            for i = 1, max_shown do
                local ev = all_day_list[i]
                local title = ev.summary or "Untitled"
                local max_text_width = content_width - card_padding * 2
                local prefix = #all_day_list > 1 and "• " or ""

                if ev.location and ev.location ~= "" then
                    local combined = prefix .. title .. " • " .. ev.location
                    local combined_widget = TextWidget:new {
                        text = combined,
                        face = Font:getFace("cfont", font_medium),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                    }
                    if combined_widget:getSize().w <= max_text_width then
                        -- Fits on one line - use HorizontalGroup for different colors
                        table.insert(card_widgets, HorizontalGroup:new {
                            TextWidget:new {
                                text = prefix .. title .. " • ",
                                face = Font:getFace("cfont", font_medium),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            },
                            TextWidget:new {
                                text = ev.location,
                                face = Font:getFace("cfont", font_medium),
                                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                            },
                        })
                        combined_widget:free()
                    else
                        -- Too long - separate lines
                        combined_widget:free()
                        table.insert(card_widgets, TextWidget:new {
                            text = prefix .. title,
                            face = Font:getFace("cfont", font_medium),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            max_width = max_text_width,
                        })
                        local loc_prefix = #all_day_list > 1 and "   " or ""
                        table.insert(card_widgets, TextWidget:new {
                            text = loc_prefix .. ev.location,
                            face = Font:getFace("cfont", font_small),
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                            max_width = max_text_width,
                        })
                    end
                else
                    table.insert(card_widgets, TextWidget:new {
                        text = prefix .. title,
                        face = Font:getFace("cfont", font_medium),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        max_width = max_text_width,
                    })
                end
                if i < max_shown then
                    table.insert(card_widgets, VerticalSpan:new { width = spacing_small })
                end
            end
            if #all_day_list > max_shown then
                table.insert(card_widgets, TextWidget:new {
                    text = string.format("+ %d more", #all_day_list - max_shown),
                    face = Font:getFace("cfont", font_small),
                    fgcolor = Blitbuffer.COLOR_GRAY,
                })
            end
        else
            -- Timed event card
            -- Time row with optional weather icon after time
            local time_icon_size = math.floor(font_small * 1.5)
            local hourly_icon = getHourlyWeatherIcon(event.start_time)
            if hourly_icon then
                -- White circular background to make icon visible on gray card
                local icon_bg_padding = math.floor(2 * scale)
                local icon_with_bg = FrameContainer:new {
                    padding = icon_bg_padding,
                    margin = 0,
                    bordersize = 0,
                    radius = math.floor((time_icon_size + icon_bg_padding * 2) / 2),
                    background = Blitbuffer.COLOR_WHITE,
                    ImageWidget:new {
                        file = hourly_icon,
                        width = time_icon_size,
                        height = time_icon_size,
                        alpha = true,
                    },
                }
                table.insert(card_widgets, HorizontalGroup:new {
                    align = "center",
                    TextWidget:new {
                        text = formatTimeRange(event, twelve_hour_clock),
                        face = Font:getFace("cfont", font_small),
                        bold = true,
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    },
                    HorizontalSpan:new { width = spacing_small },
                    icon_with_bg,
                })
            else
                table.insert(card_widgets, TextWidget:new {
                    text = formatTimeRange(event, twelve_hour_clock),
                    face = Font:getFace("cfont", font_small),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                })
            end
            table.insert(card_widgets, VerticalSpan:new { width = spacing_small })
            -- Title and location - inline if fits, otherwise separate lines
            local title = event.summary or "Untitled"
            local max_text_width = content_width - card_padding * 2
            if event.location and event.location ~= "" then
                local combined = title .. " • " .. event.location
                local combined_widget = TextWidget:new {
                    text = combined,
                    face = Font:getFace("cfont", font_medium),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
                if combined_widget:getSize().w <= max_text_width then
                    -- Fits on one line - use HorizontalGroup for different colors
                    table.insert(card_widgets, HorizontalGroup:new {
                        TextWidget:new {
                            text = title .. " • ",
                            face = Font:getFace("cfont", font_medium),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                        },
                        TextWidget:new {
                            text = event.location,
                            face = Font:getFace("cfont", font_medium),
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        },
                    })
                    combined_widget:free()
                else
                    -- Too long - separate lines
                    combined_widget:free()
                    table.insert(card_widgets, TextWidget:new {
                        text = title,
                        face = Font:getFace("cfont", font_medium),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        max_width = max_text_width,
                    })
                    table.insert(card_widgets, TextWidget:new {
                        text = event.location,
                        face = Font:getFace("cfont", font_small),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        max_width = max_text_width,
                    })
                end
            else
                table.insert(card_widgets, TextWidget:new {
                    text = title,
                    face = Font:getFace("cfont", font_medium),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = max_text_width,
                })
            end
        end

        return FrameContainer:new {
            width = content_width,
            padding = card_padding,
            margin = 0,
            bordersize = 0,
            radius = math.floor(4 * scale),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            VerticalGroup:new { align = "left", unpack(card_widgets) },
        }
    end

    -- Function to build content with given max_timed parameter
    local function buildContent(max_timed)
        local widgets = {}

        -- DATE BAR (centered)
        table.insert(widgets, VerticalSpan:new { width = spacing_large })
        table.insert(widgets, CenterContainer:new {
            dimen = { w = content_width, h = font_large + spacing_small },
            TextWidget:new {
                text = os.date("%a, %d %B %Y"),
                face = Font:getFace("cfont", font_large),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        })
        table.insert(widgets, VerticalSpan:new { width = spacing_medium })

        -- WEATHER BLOCK (centered)
        if weather_data and weather_data.current then
            local temp_row = HorizontalGroup:new { align = "center" }
            if weather_data.current.icon_path then
                table.insert(temp_row, ImageWidget:new {
                    file = weather_data.current.icon_path,
                    width = weather_icon_size,
                    height = weather_icon_size,
                    alpha = true,
                })
                table.insert(temp_row, HorizontalSpan:new { width = spacing_small })
            end
            table.insert(temp_row, TextWidget:new {
                text = WeatherUtils:getCurrentTemp(weather_data, true),
                face = Font:getFace("cfont", font_very_large),
                bold = true,
            })
            table.insert(widgets, CenterContainer:new {
                dimen = { w = content_width, h = weather_icon_size },
                temp_row,
            })

            if weather_data.current.condition then
                table.insert(widgets, CenterContainer:new {
                    dimen = { w = content_width, h = font_medium + spacing_small },
                    TextWidget:new {
                        text = weather_data.current.condition,
                        face = Font:getFace("cfont", font_medium),
                        max_width = content_width,
                    },
                })
            end
            if weather_data.forecast_days and weather_data.forecast_days[1] then
                local fc = weather_data.forecast_days[1]
                table.insert(widgets, CenterContainer:new {
                    dimen = { w = content_width, h = font_small + spacing_small },
                    TextWidget:new {
                        text = "↑" .. WeatherUtils:getForecastHigh(fc) .. "  ↓" .. WeatherUtils:getForecastLow(fc),
                        face = Font:getFace("cfont", font_small),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    },
                })
            end
        end

        table.insert(widgets, VerticalSpan:new { width = spacing_large })

        -- EVENT SECTION HEADER (left aligned)
        table.insert(widgets, TextWidget:new {
            text = "TODAY",
            face = Font:getFace("cfont", font_small),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
        table.insert(widgets, VerticalSpan:new { width = spacing_medium })

        -- EVENTS
        local total_shown = 0
        if #today_events == 0 then
            table.insert(widgets, TextWidget:new {
                text = "No events scheduled.",
                face = Font:getFace("cfont", font_medium),
                fgcolor = Blitbuffer.COLOR_GRAY,
            })
        else
            -- All-day events card
            if #all_day_events > 0 then
                table.insert(widgets, buildEventCard(nil, true, all_day_events))
                table.insert(widgets, VerticalSpan:new { width = spacing_medium })
                total_shown = math.min(#all_day_events, 3)
            end

            -- Timed events
            local timed_to_show = math.min(#timed_events, max_timed)
            for i = 1, timed_to_show do
                table.insert(widgets, buildEventCard(timed_events[i], false, nil))
                table.insert(widgets, VerticalSpan:new { width = spacing_medium })
                total_shown = total_shown + 1
            end

            -- More events indicator
            local total_events = #all_day_events + #timed_events
            local hidden = total_events - total_shown
            if hidden > 0 then
                table.insert(widgets, TextWidget:new {
                    text = string.format("+ %d more events", hidden),
                    face = Font:getFace("cfont", font_small),
                    fgcolor = Blitbuffer.COLOR_GRAY,
                })
            end
        end

        return VerticalGroup:new { align = "left", unpack(widgets) }
    end

    -- Build header first to know its height
    local header_group
    local is_cached = (weather_data and weather_data.is_cached) or (calendar_data and calendar_data.is_cached)
    if weather_data and weather_data.current then
        header_group = DisplayHelper:createHeaderWidgets(
            font_very_small, spacing_small, weather_data,
            Blitbuffer.COLOR_DARK_GRAY, is_cached
        )
    else
        header_group = OverlapGroup:new {
            dimen = { w = screen_width, h = font_very_small + spacing_small * 2 },
        }
    end
    local header_height = header_group:getSize().h

    -- Available height for content
    local available_height = screen_height - header_height - spacing_large

    -- Try building with different max_timed values until it fits
    local content
    local max_timed = math.min(#timed_events, 5)

    repeat
        content = buildContent(max_timed)
        local content_height = content:getSize().h
        if content_height <= available_height or max_timed <= 1 then
            break
        end
        max_timed = max_timed - 1
    until max_timed < 1

    -- Wrap in container
    local main_container = FrameContainer:new {
        width = screen_width,
        height = screen_height,
        padding = 0,
        padding_top = header_height,
        padding_left = h_margin,
        padding_right = h_margin,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    return OverlapGroup:new {
        dimen = Screen:getSize(),
        main_container,
        header_group,
    }
end

return CalendarDisplay
