--[[
    Reading Display Mode for Weather Lockscreen
    "Hero Cover" style - Large book cover with overlay card containing book info and weather
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local ReaderUI = require("apps/reader/readerui")
local RenderImage = require("ui/renderimage")
local Geom = require("ui/geometry")
local util = require("util")
local logger = require("logger")
local datetime = require("datetime")
local _ = require("gettext")

local ReadingDisplay = {}

CARD_WIDTH = 0.8 -- Card width as fraction of screen width

function ReadingDisplay:getDocumentInfo()
    -- Get active ReaderUI instance
    local ui = ReaderUI.instance
    if not ui or not ui.document then
        logger.dbg("Reading display: No active document")
        return nil
    end

    local doc_props = ui.doc_props or {}
    local doc_settings = ui.doc_settings and ui.doc_settings.data or {}
    local state = ui.view and ui.view.state

    -- Get title and authors
    local title = doc_props.display_title or doc_props.title or "Unknown Title"
    local authors = doc_props.authors or ""
    if authors:find("\n") then
        local authors_array = util.splitToArray(authors, "\n")
        if authors_array and authors_array[1] then
            authors = authors_array[1]
            if #authors_array > 1 then
                authors = authors .. " et al."
            end
        end
    end

    -- Get page progress
    local page_no = (state and state.page) or 1
    local page_total = doc_settings.doc_pages or 1
    if page_total <= 0 then page_total = 1 end
    if page_no < 1 then page_no = 1 end
    if page_no > page_total then page_no = page_total end

    local progress = page_no / page_total

    -- Get cover image using BookInfo
    local cover_bb
    if ui.bookinfo and ui.document then
        cover_bb = ui.bookinfo:getCoverImage(ui.document)
    end

    return {
        title = title,
        authors = authors,
        page_no = page_no,
        page_total = page_total,
        progress = progress,
        cover_bb = cover_bb,
    }
end

function ReadingDisplay:create(weather_lockscreen, weather_data)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Get user fill percent (default 90)
    local fill_percent = G_reader_settings:readSetting("weather_override_scaling") and tonumber(G_reader_settings:readSetting("weather_fill_percent")) or 60
    local min_fill = math.max(50, fill_percent - 5)
    local max_fill = math.min(100, fill_percent + 5)

    -- Target height is percent of half the screen height
    local min_target_height = (screen_height * 0.5) * (min_fill / 100)
    local max_target_height = (screen_height * 0.5) * (max_fill / 100)

    -- Base sizes for card content (will be scaled down to fit target height)
    local base_title_font_size = 28
    local base_author_font_size = 22
    local base_progress_font_size = 20
    local base_temp_font_size = 38
    local base_weather_detail_font_size = 18
    local base_location_font_size = 16
    local base_weather_icon_size = 70
    local base_card_padding = 30
    local base_spacing = 18
    local base_small_spacing = 10

    -- Fixed header sizes
    local header_font_size = 16
    local header_margin = 10

    -- Get document information
    local doc_info = self:getDocumentInfo()

    if not doc_info then
        -- Fallback to weather-only display if no book is open
        logger.dbg("Reading display: No document info, falling back")
        local fallback_module = require("display_default")
        return fallback_module:create(weather_lockscreen, weather_data)
    end

    -- Background: Large book cover fitted or stretched to screen
    local background_widget
    if doc_info.cover_bb then
        local cover_bb = doc_info.cover_bb
        local cover_width = cover_bb:getWidth()
        local cover_height = cover_bb:getHeight()

        -- Get user's scaling preference
        local cover_scaling = G_reader_settings:readSetting("weather_cover_scaling") or "fit"

        -- Scale cover based on preference
        local scale
        if cover_scaling == "stretch" then
            -- Stretch to fill screen (may crop)
            scale = math.max(screen_width / cover_width, screen_height / cover_height)
        else
            -- Fit to screen (no stretching - maintains aspect ratio)
            scale = math.min(screen_width / cover_width, screen_height / cover_height)
        end

        local scaled_w = math.floor(cover_width * scale)
        local scaled_h = math.floor(cover_height * scale)

        cover_bb = RenderImage:scaleBlitBuffer(cover_bb, scaled_w, scaled_h, true)

        -- For "fit" mode, add black background behind the cover
        if cover_scaling == "fit" then
            local cover_image = ImageWidget:new {
                image = cover_bb,
                width = cover_bb:getWidth(),
                height = cover_bb:getHeight(),
                alpha = true,
            }
            local black_bg = FrameContainer:new {
                width = screen_width,
                height = screen_height,
                padding = 0,
                margin = 0,
                bordersize = 0,
                background = G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                CenterContainer:new {
                    dimen = Geom:new { w = screen_width, h = screen_height },
                    cover_image,
                }
            }
            background_widget = black_bg
        else
            background_widget = CenterContainer:new {
                dimen = Geom:new { w = screen_width, h = screen_height },
                ImageWidget:new {
                    image = cover_bb,
                    width = cover_bb:getWidth(),
                    height = cover_bb:getHeight(),
                    alpha = true,
                }
            }
        end
    end

    -- Header with location and time (if enabled)
    local header_group = weather_lockscreen:createHeaderWidgets(
        header_font_size,
        header_margin,
        weather_data,
        G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_LIGHT_GRAY,
        weather_data.is_cached
    )

    -- Overlay card at bottom

    -- Function to build card with a given scale factor
    local function buildCard(scale_factor)
        local title_font_size = math.floor(base_title_font_size * scale_factor)
        local author_font_size = math.floor(base_author_font_size * scale_factor)
        local progress_font_size = math.floor(base_progress_font_size * scale_factor)
        local temp_font_size = math.floor(base_temp_font_size * scale_factor)
        local weather_detail_font_size = math.floor(base_weather_detail_font_size * scale_factor)
        local location_font_size = math.floor(base_location_font_size * scale_factor)
        local weather_icon_size = math.floor(base_weather_icon_size * scale_factor)
        local card_padding = math.floor(base_card_padding * scale_factor)
        local spacing = math.floor(base_spacing * scale_factor)
        local small_spacing = math.floor(base_small_spacing * scale_factor)

        -- Build card content
        local card_widgets = {}

        -- Top row: Book info (left) and Weather icon + temp (right)
        local top_row = HorizontalGroup:new { align = "top" }

        -- Left side: Book title and author
        local book_info = {}
        if doc_info.title then

            local top_right_width = weather_data.current.temperature and
                TextWidget:new{
                    text = weather_data.current.temperature,
                    face = Font:getFace("cfont", temp_font_size),
                }:getSize().w or 0
                top_right_width = top_right_width + weather_icon_size
            local title_width = math.floor(screen_width * CARD_WIDTH - top_right_width - 2 * card_padding)
            table.insert(book_info, TextBoxWidget:new {
                text = doc_info.title,
                face = Font:getFace("cfont", title_font_size),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                width = title_width,
            })
        end

        if doc_info.authors and doc_info.authors ~= "" then
            table.insert(book_info, VerticalSpan:new { width = small_spacing })
            table.insert(book_info, TextWidget:new {
                text = doc_info.authors,
                face = Font:getFace("cfont", author_font_size),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                -- max_width = math.floor(screen_width * CARD_WIDTH - 2 * card_padding),
            })
        end

        table.insert(top_row, VerticalGroup:new {
            align = "left",
            unpack(book_info)
        })

        table.insert(top_row, HorizontalSpan:new { width = spacing })

        -- Right side: Weather icon and temperature
        local weather_group = HorizontalGroup:new { align = "center" }

        if weather_data.current.icon_path then
            table.insert(weather_group, ImageWidget:new {
                file = weather_data.current.icon_path,
                width = weather_icon_size,
                height = weather_icon_size,
                alpha = true,
                original_in_nightmode = false
            })
            table.insert(weather_group, HorizontalSpan:new { width = small_spacing })
        end

        if weather_data.current.temperature then
            table.insert(weather_group, TextWidget:new {
                text = weather_data.current.temperature,
                face = Font:getFace("cfont", temp_font_size),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            })
        end

        table.insert(top_row, weather_group)

        table.insert(card_widgets, top_row)
        table.insert(card_widgets, VerticalSpan:new { width = spacing })

        -- Middle row: Progress bar and percentage
        if doc_info.progress then
            local progress_row = HorizontalGroup:new { align = "center" }

            local progress_bar_width = math.floor(screen_width * (CARD_WIDTH - 0.05) - 2 * card_padding)
            table.insert(progress_row, ProgressWidget:new {
                width = progress_bar_width,
                height = math.floor(12 * scale_factor),
                percentage = doc_info.progress,
                margin_v = 0,
                margin_h = 0,
                radius = math.floor(6 * scale_factor),
                bordersize = 0,
                bgcolor = Blitbuffer.COLOR_GRAY_9,
                fillcolor = Blitbuffer.COLOR_BLACK,
            })

            table.insert(progress_row, HorizontalSpan:new { width = spacing })

            local percentage_text = string.format("%i%%", math.floor(doc_info.progress * 100 + 0.5))
            table.insert(progress_row, TextWidget:new {
                text = percentage_text,
                face = Font:getFace("cfont", progress_font_size),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            })

            table.insert(card_widgets, progress_row)
            table.insert(card_widgets, VerticalSpan:new { width = spacing })
        end

        -- Bottom row: Page info (left) and Weather/Location/Time (right)
        -- I just can't get it aligned with the title. :(

        local bottom_row = HorizontalGroup:new { align = "top" }

        -- Left: Page numbers
        local page_text = ""
        if doc_info.page_no and doc_info.page_total then
            page_text = string.format("Page %i of %i", doc_info.page_no, doc_info.page_total)
        table.insert(bottom_row, TextWidget:new{
                text = page_text,
                face = Font:getFace("cfont", progress_font_size),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
        end

        -- Spacer to push right content to the right
    local left_width = page_text ~= "" and TextWidget:new{
        text = page_text,
        face = Font:getFace("cfont", progress_font_size),
    }:getSize().w or 0

        local right_content = {}

        -- Weather condition
        if weather_data.current.condition then
            table.insert(right_content, TextWidget:new {
                text = weather_data.current.condition,
                face = Font:getFace("cfont", weather_detail_font_size),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
        end

        -- Location and time
        local current_time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        local location = G_reader_settings:readSetting("weather_location") or "Unknown"
        local location_time = string.format("%s • %s", location, current_time)

        table.insert(right_content, TextWidget:new {
            text = location_time,
            face = Font:getFace("cfont", location_font_size),
            fgcolor = Blitbuffer.COLOR_GRAY_3,
        })

        local right_group = VerticalGroup:new {
            align = "right",
            unpack(right_content)
        }

        local right_width = right_group:getSize().w
        local spacer_width = math.max(0, screen_width * CARD_WIDTH - left_width - right_width - 2 * card_padding)

        table.insert(bottom_row, HorizontalSpan:new { width = spacer_width })
        table.insert(bottom_row, right_group)

        table.insert(card_widgets, bottom_row)

        -- Create the overlay card with white background and black border
        return FrameContainer:new {
            padding = card_padding,
            padding_top = card_padding,
            padding_right = card_padding,
            padding_bottom = card_padding,
            padding_left = card_padding,
            margin = 0,
            bordersize = math.floor(2 * scale_factor),
            background = Blitbuffer.COLOR_WHITE,
            radius = math.floor(15 * scale_factor),
            VerticalGroup:new(card_widgets),
        }
    end

    -- Build card at scale 1.0 and measure height
    local card_scale = 1.0
    local card = buildCard(card_scale)
    local card_height = card:getSize().h

    -- Rescale if height is outside [min_target_height, max_target_height]
    if card_height > max_target_height then
        card_scale = max_target_height / card_height
        logger.dbg("Reading display: Card height", card_height, "exceeds max", max_target_height, "- rebuilding with scale", card_scale)
        card = buildCard(card_scale)
    elseif card_height < min_target_height then
        card_scale = min_target_height / card_height
        logger.dbg("Reading display: Card height", card_height, "below min", min_target_height, "- rebuilding with scale", card_scale)
        card = buildCard(card_scale)
    end

    -- Position card at bottom of screen
    local card_container = BottomContainer:new {
        dimen = Geom:new { w = screen_width, h = screen_height },
        CenterContainer:new {
            dimen = Geom:new { w = screen_width, h = card:getSize().h + math.floor(40 * card_scale) },
            card,
        }
    }

    -- Combine background and overlay
    if background_widget then
        return OverlapGroup:new {
            dimen = Screen:getSize(),
            background_widget,
            card_container,
            header_group,
        }
    else
        -- Fallback: if no cover, use light gray background
        return OverlapGroup:new {
            dimen = Screen:getSize(),
            FrameContainer:new {
                width = screen_width,
                height = screen_height,
                padding = 0,
                margin = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_GRAY_E,
            },
            card_container,
            header_group,
        }
    end
end

return ReadingDisplay
