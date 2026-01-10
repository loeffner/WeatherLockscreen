--[[
    Calendar Display Mode for Weather Lockscreen
    E-Ink optimized layout showing today's events with weather

    Layout Structure:
    - HEADER (overlay): Location + timestamp (using DisplayHelper)
    - DATE + WEATHER: Combined header with date and weather info
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
local Size = require("ui/size")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local WeatherUtils = require("weather_utils")
local CalendarAPI = require("calendar_api")
local DisplayHelper = require("display_helper")
local _ = require("l10n/gettext")

local CalendarDisplay = {}

-- Day and month name tables for localization
-- These are wrapped with _() so they can be translated
local DAY_NAMES = {
    [0] = _("Sunday"),
    [1] = _("Monday"),
    [2] = _("Tuesday"),
    [3] = _("Wednesday"),
    [4] = _("Thursday"),
    [5] = _("Friday"),
    [6] = _("Saturday"),
}

local MONTH_NAMES = {
    [1] = _("January"),
    [2] = _("February"),
    [3] = _("March"),
    [4] = _("April"),
    [5] = _("May"),
    [6] = _("June"),
    [7] = _("July"),
    [8] = _("August"),
    [9] = _("September"),
    [10] = _("October"),
    [11] = _("November"),
    [12] = _("December"),
}

-- Format time range for event display
local function formatTimeRange(event, twelve_hour_clock)
    if event.all_day then
        return "ALL DAY", nil
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

    -- Get end time if available
    local end_str = nil
    if event.end_time then
        local end_info = os.date("*t", event.end_time)

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
    end

    return start_str, end_str
end

function CalendarDisplay:create(weather_lockscreen, weather_data, calendar_data)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Base scale factor from screen size
    local base_scale = math.min(screen_width, screen_height) / 600

    -- Margins (fixed, not scaled)
    local h_margin = math.floor(24 * base_scale)
    local content_width = screen_width - (h_margin * 2)

    -- Get events for today
    local today_events = {}
    if calendar_data and calendar_data.events then
        today_events = CalendarAPI:getEventsForToday(calendar_data.events)
        logger.dbg("CalendarDisplay: Events for today:", #today_events)
    end

    local twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")
    local past_events_mode = G_reader_settings:readSetting("calendar_past_events") or "fade"

    -- Check if event is in the past
    local function isEventPast(event)
        local now = os.time()
        if event.all_day then
            local end_time = event.end_time or (event.start_time + 86400)
            return end_time < now
        else
            local end_time = event.end_time or (event.start_time + 3600)
            return end_time < now
        end
    end

    -- Separate all-day events from timed events, handling past events
    local all_day_events = {}
    local timed_events = {}
    for _, event in ipairs(today_events) do
        local is_past = isEventPast(event)
        if past_events_mode == "hide" and is_past then
            -- Skip past events
        else
            event.is_past = is_past
            if event.all_day then
                table.insert(all_day_events, event)
            else
                table.insert(timed_events, event)
            end
        end
    end

    -- Function to build content with given scale and max_timed
    -- Base sizes (designed for ~1000px screen, scaled by content_scale)
    -- Reduced by ~10% for more compact layout
    local base_spacing_large = 20
    local base_spacing_medium = 12
    local base_spacing_small = 6
    local base_font_very_large = 56
    local base_font_large = 28
    local base_font_medium = 21
    local base_font_small = 17
    local base_card_padding = 12

    local function buildContent(content_scale, max_timed)
        -- Spacing scaled by content_scale
        local spacing_large = math.floor(base_spacing_large * content_scale)
        local spacing_medium = math.floor(base_spacing_medium * content_scale)
        local spacing_small = math.floor(base_spacing_small * content_scale)

        -- Font sizes scaled by content_scale (with minimum values)
        local font_very_large = math.max(28, math.floor(base_font_very_large * content_scale))
        local font_large = math.max(16, math.floor(base_font_large * content_scale))
        local font_medium = math.max(14, math.floor(base_font_medium * content_scale))
        local font_small = math.max(12, math.floor(base_font_small * content_scale))

        local weather_icon_size = math.floor(font_very_large * 1.4)
        local card_padding = math.floor(base_card_padding * content_scale)

        -- Helper function to get weather icon for a specific hour
        local function getHourlyWeatherIcon(event_start_time)
            if not weather_data or not event_start_time then return nil end
            local time_info = os.date("*t", event_start_time)
            local event_hour = time_info.hour

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

        -- Function to build event card
        local function buildEventCard(event, is_all_day_group, all_day_list)
            local card_widgets = {}

            -- Determine colors based on past event status
            local is_past = event.is_past or (is_all_day_group and all_day_list[1] and all_day_list[1].is_past)
            local title_color = Blitbuffer.COLOR_BLACK
            local subtitle_color = Blitbuffer.COLOR_DARK_GRAY
            local muted_color = Blitbuffer.COLOR_GRAY

            if is_past and past_events_mode == "fade" then
                title_color = Blitbuffer.COLOR_GRAY
                subtitle_color = Blitbuffer.COLOR_GRAY
                muted_color = Blitbuffer.COLOR_GRAY
            end

            if is_all_day_group then
                -- All-day grouped card
                table.insert(card_widgets, TextWidget:new {
                    text = "ALL DAY",
                    face = Font:getFace("cfont", font_small),
                    bold = true,
                    fgcolor = subtitle_color,
                })
                table.insert(card_widgets, VerticalSpan:new { width = spacing_small })

                local max_shown = math.min(#all_day_list, 3)
                for i = 1, max_shown do
                    local ev = all_day_list[i]
                    local ev_title_color = title_color
                    local ev_subtitle_color = subtitle_color
                    if ev.is_past and past_events_mode == "fade" then
                        ev_title_color = Blitbuffer.COLOR_GRAY
                        ev_subtitle_color = Blitbuffer.COLOR_GRAY
                    end

                    local title = ev.summary or "Untitled"
                    local max_text_width = content_width - card_padding * 2
                    local prefix = #all_day_list > 1 and "• " or ""

                    if ev.location and ev.location ~= "" then
                        local combined = prefix .. title .. " • " .. ev.location
                        local combined_widget = TextWidget:new {
                            text = combined,
                            face = Font:getFace("cfont", font_medium),
                            fgcolor = ev_title_color,
                        }
                        if combined_widget:getSize().w <= max_text_width then
                            table.insert(card_widgets, HorizontalGroup:new {
                                TextWidget:new {
                                    text = prefix .. title .. " • ",
                                    face = Font:getFace("cfont", font_medium),
                                    fgcolor = ev_title_color,
                                },
                                TextWidget:new {
                                    text = ev.location,
                                    face = Font:getFace("cfont", font_medium),
                                    fgcolor = ev_subtitle_color,
                                },
                            })
                            combined_widget:free()
                        else
                            combined_widget:free()
                            table.insert(card_widgets, TextWidget:new {
                                text = prefix .. title,
                                face = Font:getFace("cfont", font_medium),
                                fgcolor = ev_title_color,
                                max_width = max_text_width,
                            })
                            local loc_prefix = #all_day_list > 1 and "   " or ""
                            table.insert(card_widgets, TextWidget:new {
                                text = loc_prefix .. ev.location,
                                face = Font:getFace("cfont", font_small),
                                fgcolor = ev_subtitle_color,
                                max_width = max_text_width,
                            })
                        end
                    else
                        table.insert(card_widgets, TextWidget:new {
                            text = prefix .. title,
                            face = Font:getFace("cfont", font_medium),
                            fgcolor = ev_title_color,
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
                        fgcolor = muted_color,
                    })
                end
            else
                -- Timed event card with two-line layout:
                -- Starttime │ Bold Title              [icon]
                -- Endtime   │ @ Location              [icon]
                local hourly_icon = getHourlyWeatherIcon(event.start_time)

                local estimated_icon_size = math.floor(50 * content_scale)
                local icon_area_width = hourly_icon and (estimated_icon_size + spacing_small) or 0
                local text_area_width = content_width - card_padding * 2 - icon_area_width

                -- Get start and end times separately
                local start_time, end_time = formatTimeRange(event, twelve_hour_clock)
                local title = event.summary or "Untitled"

                -- Calculate time column width based on longer time string
                local time_font = Font:getFace("cfont", font_small)
                local start_width = TextWidget:new { text = start_time, face = time_font }:getSize().w
                local end_width = end_time and TextWidget:new { text = end_time, face = time_font }:getSize().w or 0
                local time_column_width = math.max(start_width, end_width) + spacing_small

                -- Separator and content column widths
                local separator_width = spacing_small * 2
                local content_column_width = text_area_width - time_column_width - separator_width

                -- Build two-line text content
                local left_content = VerticalGroup:new { align = "left" }

                -- Line 1: Start time │ Title
                local line1 = HorizontalGroup:new { align = "center" }
                table.insert(line1, TextWidget:new {
                    text = start_time,
                    face = time_font,
                    fgcolor = subtitle_color,
                })
                table.insert(line1, HorizontalSpan:new { width = time_column_width - start_width })
                table.insert(line1, TextWidget:new {
                    text = "│",
                    face = time_font,
                    fgcolor = muted_color,
                })
                table.insert(line1, HorizontalSpan:new { width = spacing_small })
                table.insert(line1, TextWidget:new {
                    text = title,
                    face = Font:getFace("cfont", font_medium),
                    bold = true,
                    fgcolor = title_color,
                    max_width = content_column_width,
                })
                table.insert(left_content, line1)

                -- Line 2: End time │ Location (only if we have end time or location)
                local has_line2 = end_time or (event.location and event.location ~= "")
                if has_line2 then
                    table.insert(left_content, VerticalSpan:new { width = spacing_small })
                    local line2 = HorizontalGroup:new { align = "center" }

                    -- End time (or empty space if no end time)
                    if end_time then
                        local end_time_width = TextWidget:new { text = end_time, face = time_font }:getSize().w
                        table.insert(line2, TextWidget:new {
                            text = end_time,
                            face = time_font,
                            fgcolor = subtitle_color,
                        })
                        table.insert(line2, HorizontalSpan:new { width = time_column_width - end_time_width })
                    else
                        table.insert(line2, HorizontalSpan:new { width = time_column_width })
                    end

                    table.insert(line2, TextWidget:new {
                        text = "│",
                        face = time_font,
                        fgcolor = muted_color,
                    })
                    table.insert(line2, HorizontalSpan:new { width = spacing_small })

                    if event.location and event.location ~= "" then
                        table.insert(line2, TextWidget:new {
                            text = "@ ",
                            face = Font:getFace("cfont", font_small),
                            fgcolor = muted_color,
                        })
                        table.insert(line2, TextWidget:new {
                            text = event.location,
                            face = Font:getFace("cfont", font_small),
                            fgcolor = subtitle_color,
                            max_width = content_column_width - spacing_medium * 2,
                        })
                    end

                    table.insert(left_content, line2)
                end

                -- Store for icon layout handling
                if hourly_icon then
                    event.left_content = left_content
                    event.hourly_icon = hourly_icon
                    event.estimated_icon_size = estimated_icon_size
                    event.text_area_width = text_area_width
                else
                    -- No icon, just add the content
                    for _, widget in ipairs(left_content) do
                        table.insert(card_widgets, widget)
                    end
                end
            end

            -- Build the card
            if event.left_content then
                -- Special layout for timed events with weather icon
                local left_content = event.left_content
                local hourly_icon = event.hourly_icon
                local text_area_width = event.text_area_width
                local left_height = left_content:getSize().h

                -- Use a fixed icon size for consistency across cards
                local icon_size = event.estimated_icon_size
                -- Card height is the max of text height and icon size
                local card_height = math.max(left_height, icon_size)

                -- Card inner width (without padding)
                local inner_width = content_width - card_padding * 2

                -- Use OverlapGroup to position icon at far right
                local card_content = OverlapGroup:new {
                    dimen = { w = inner_width, h = card_height },
                    -- Left: text content (left-aligned, vertically offset to center)
                    FrameContainer:new {
                        width = text_area_width,
                        height = card_height,
                        padding = 0,
                        padding_top = math.floor((card_height - left_height) / 2),
                        margin = 0,
                        bordersize = 0,
                        left_content,
                    },
                    -- Right: icon (positioned at right edge, vertically centered)
                    FrameContainer:new {
                        padding = 0,
                        margin = 0,
                        bordersize = 0,
                        padding_left = inner_width - icon_size,
                        CenterContainer:new {
                            dimen = { w = icon_size, h = card_height },
                            ImageWidget:new {
                                file = hourly_icon,
                                width = icon_size,
                                height = icon_size,
                                alpha = true,
                            },
                        },
                    },
                }

                return FrameContainer:new {
                    width = content_width,
                    padding = card_padding,
                    margin = 0,
                    bordersize = Size.border.thin,
                    color = Blitbuffer.COLOR_GRAY,
                    radius = math.floor(4 * content_scale),
                    background = Blitbuffer.COLOR_GRAY_E,
                    card_content,
                }
            else
                return FrameContainer:new {
                    width = content_width,
                    padding = card_padding,
                    margin = 0,
                    bordersize = Size.border.thin,
                    color = Blitbuffer.COLOR_GRAY,
                    radius = math.floor(4 * content_scale),
                    background = Blitbuffer.COLOR_GRAY_E,
                    VerticalGroup:new { align = "left", unpack(card_widgets) },
                }
            end
        end

        local widgets = {}

        -- PAGE HEADER: Clean horizontal layout
        -- Left: Large day number | Month + Weekday stacked
        -- Right: Temp + Condition stacked | Icon
        table.insert(widgets, VerticalSpan:new { width = spacing_small })

        -- Build the date info
        local date_info = os.date("*t")
        local day_name = DAY_NAMES[date_info.wday - 1]
        local month_name = MONTH_NAMES[date_info.month]

        -- Large day number
        local day_number_widget = TextWidget:new {
            text = tostring(date_info.day),
            face = Font:getFace("cfont", font_very_large),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local day_number_height = day_number_widget:getSize().h

        -- Month and weekday stacked (to the right of day number)
        local date_text_column = VerticalGroup:new { align = "left" }
        table.insert(date_text_column, TextWidget:new {
            text = string.upper(month_name),
            face = Font:getFace("cfont", font_medium),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        })
        table.insert(date_text_column, TextWidget:new {
            text = day_name,
            face = Font:getFace("cfont", font_small),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })

        -- Left side: day number + text column, vertically centered
        local date_text_height = date_text_column:getSize().h
        local left_section = HorizontalGroup:new { align = "center" }
        table.insert(left_section, day_number_widget)
        table.insert(left_section, HorizontalSpan:new { width = spacing_medium })
        table.insert(left_section, CenterContainer:new {
            dimen = { w = date_text_column:getSize().w, h = day_number_height },
            date_text_column,
        })

        local left_section_width = left_section:getSize().w

        -- Right side: Weather info (if available)
        local right_section = nil
        local right_section_width = 0

        if weather_data and weather_data.current then
            -- Weather icon size to match day number height
            local header_icon_size = day_number_height

            -- Temperature and condition stacked
            local weather_text = VerticalGroup:new { align = "right" }
            table.insert(weather_text, TextWidget:new {
                text = WeatherUtils:getCurrentTemp(weather_data, true),
                face = Font:getFace("cfont", font_medium),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            })
            if weather_data.current.condition then
                table.insert(weather_text, TextWidget:new {
                    text = weather_data.current.condition,
                    face = Font:getFace("cfont", font_small),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                })
            end

            -- Icon widget
            local icon_widget = nil
            if weather_data.current.icon_path then
                icon_widget = ImageWidget:new {
                    file = weather_data.current.icon_path,
                    width = header_icon_size,
                    height = header_icon_size,
                    alpha = true,
                }
            end

            -- Combine text and icon, vertically centered
            local weather_text_height = weather_text:getSize().h
            right_section = HorizontalGroup:new { align = "center" }
            table.insert(right_section, CenterContainer:new {
                dimen = { w = weather_text:getSize().w, h = day_number_height },
                weather_text,
            })
            if icon_widget then
                table.insert(right_section, HorizontalSpan:new { width = spacing_small })
                table.insert(right_section, icon_widget)
            end

            right_section_width = right_section:getSize().w
        end

        -- Build the header row content
        local header_row = HorizontalGroup:new { align = "center" }
        table.insert(header_row, left_section)

        if right_section then
            local spacer_width = content_width - left_section_width - right_section_width - card_padding * 2
            table.insert(header_row, HorizontalSpan:new { width = spacer_width })
            table.insert(header_row, right_section)
        end

        -- Wrap header in a framed container
        table.insert(widgets, FrameContainer:new {
            width = content_width,
            padding = card_padding,
            margin = 0,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            radius = math.floor(4 * content_scale),
            background = Blitbuffer.COLOR_GRAY_E,
            header_row,
        })

        table.insert(widgets, VerticalSpan:new { width = spacing_large })

        -- EVENT SECTION HEADER (left aligned)
        table.insert(widgets, TextWidget:new {
            text = "TODAY",
            face = Font:getFace("cfont", font_small),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
        table.insert(widgets, VerticalSpan:new { width = spacing_medium })

        -- EVENT CARDS
        if #all_day_events > 0 or #timed_events > 0 then
            -- All-day events card (grouped)
            if #all_day_events > 0 then
                table.insert(widgets, buildEventCard(all_day_events[1], true, all_day_events))
                table.insert(widgets, VerticalSpan:new { width = spacing_medium })
            end

            -- Timed event cards
            local shown_timed = math.min(#timed_events, max_timed)
            for i = 1, shown_timed do
                table.insert(widgets, buildEventCard(timed_events[i], false, nil))
                if i < shown_timed then
                    table.insert(widgets, VerticalSpan:new { width = spacing_medium })
                end
            end

            -- Show "more events" indicator
            local total_events = #all_day_events + #timed_events
            local hidden = total_events - (#all_day_events > 0 and 1 or 0) - shown_timed
            if hidden > 0 then
                table.insert(widgets, VerticalSpan:new { width = spacing_small })
                table.insert(widgets, TextWidget:new {
                    text = string.format("+ %d more events", hidden),
                    face = Font:getFace("cfont", font_small),
                    fgcolor = Blitbuffer.COLOR_GRAY,
                })
            end
        else
            table.insert(widgets, TextWidget:new {
                text = "No events scheduled",
                face = Font:getFace("cfont", font_medium),
                fgcolor = Blitbuffer.COLOR_GRAY,
            })
        end

        return VerticalGroup:new { align = "left", unpack(widgets) }
    end

    -- Build header first to know its height
    local font_very_small = math.max(10, math.floor(11 * base_scale))
    local spacing_small = math.floor(5 * base_scale)
    local spacing_large = math.floor(16 * base_scale)

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

    -- Get user scaling preferences
    -- fill_percent is treated as a scale multiplier: 90 = 0.9x, 100 = 1.0x, 110 = 1.1x
    local override_scaling = G_reader_settings:isTrue("weather_override_scaling")
    local fill_percent = override_scaling and
        tonumber(G_reader_settings:readSetting("weather_fill_percent")) or 100

    -- Build content with initial scale and measure it
    -- Apply user's scale multiplier (90% = 0.9x, 100% = 1.0x, 110% = 1.1x)
    local content_scale = fill_percent / 100
    local max_timed = math.min(#timed_events, 5)
    local content = buildContent(content_scale, max_timed)
    local content_height = content:getSize().h

    -- Reduce events if content exceeds available height
    while content_height > available_height and max_timed > 1 do
        max_timed = max_timed - 1
        content:free()
        content = buildContent(content_scale, max_timed)
        content_height = content:getSize().h
    end

    -- Final check: if still too large, scale down to fit
    if content_height > available_height then
        local fit_scale = available_height / content_height * 0.95
        content_scale = content_scale * fit_scale
        content:free()
        content = buildContent(content_scale, max_timed)
    end

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
