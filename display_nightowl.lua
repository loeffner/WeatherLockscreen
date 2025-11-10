--[[
    Night Owl Display Mode for Weather Lockscreen
    Dark background with moon phase
--]]

local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")

local NightOwlDisplay = {}

function NightOwlDisplay:create(weather_lockscreen, weather_data)
    local header_font_size = Screen:scaleBySize(16)
    local moon_font_size = Screen:scaleBySize(22)
    local moon_icon_size = Screen:scaleBySize(250)
    local header_margin = Screen:scaleBySize(10)

    -- Header: Location and Timestamp (inverted colors for dark mode)
    local header_group = weather_lockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data, Blitbuffer.COLOR_LIGHT_GRAY, weather_data.is_cached)

    -- Main content - centered moon icon
    local moon_icon_widget = nil
    if weather_data.astronomy and weather_data.astronomy.moon_phase then
        local moon_icon_path = weather_lockscreen:getMoonPhaseIcon(weather_data.astronomy.moon_phase)
        if moon_icon_path then
            moon_icon_widget = CenterContainer:new{
                dimen = Screen:getSize(),
                ImageWidget:new{
                    file = moon_icon_path,
                    width = moon_icon_size,
                    height = moon_icon_size,
                    alpha = false,
                    original_in_nightmode = true
                }
            }
        end
    end

    -- Bottom text - moon phase name
    local bottom_text_widget = nil
    if weather_data.astronomy and weather_data.astronomy.moon_phase then
        local bottom_margin = Screen:scaleBySize(30)
        bottom_text_widget = FrameContainer:new{
            padding = 0,
            margin = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_BLACK,
            CenterContainer:new{
                dimen = { w = Screen:getWidth(), h = moon_font_size + bottom_margin * 2 },
                TextWidget:new{
                    text = weather_data.astronomy.moon_phase,
                    face = Font:getFace("cfont", moon_font_size),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_LIGHT_GRAY,
                }
            },
            invert = G_reader_settings:isTrue("night_mode")
        }
    end

    local content_layers = {}
    if moon_icon_widget then
        table.insert(content_layers, moon_icon_widget)
    end
    table.insert(content_layers, header_group)
    if bottom_text_widget then
        table.insert(content_layers, RightContainer:new{
            dimen = Screen:getSize(),
            ignore = "height",
            BottomContainer:new{
                dimen = Screen:getSize(),
                bottom_text_widget,
            }
        })
    end

    return OverlapGroup:new{
        dimen = Screen:getSize(),
        unpack(content_layers)
    }
end

return NightOwlDisplay
