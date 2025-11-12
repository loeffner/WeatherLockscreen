--[[
    Weather Lockscreen Plugin for KOReader

    Displays weather information on the sleep screen.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local InputDialog = require("ui/widget/inputdialog")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local WeatherAPI = require("weather_api")
local WeatherUtils = require("weather_utils")

local WeatherLockscreen = WidgetContainer:extend {
    name = "weatherlockscreen",
    is_doc_only = false,
    default_location = "London",
    default_api_key = "637e03f814b440f782675255250411",
    default_temp_scale = "C",
}

local WEATHER_ICON_SIZE = 200 -- Size of the weather icon in pixels

function WeatherLockscreen:getCacheMaxAge()
    return WeatherUtils:getCacheMaxAge()
end

function WeatherLockscreen:getPluginDir()
    return WeatherUtils:getPluginDir()
end

function WeatherLockscreen:installIcons()
    return WeatherUtils:installIcons(function() return self:getPluginDir() end)
end

function WeatherLockscreen:init()
    self:installIcons()
    self.ui.menu:registerToMainMenu(self)
    self:patchScreensaver()
end

function WeatherLockscreen:addToMainMenu(menu_items)
    menu_items.weather_lockscreen = {
        text = _("Weather Lockscreen"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
        sorting_hint = "tools",
    }
end

function WeatherLockscreen:getSubMenuItems()
    local menu_items = {
        {
            text = _("Location"),
            text_func = function()
                local location = G_reader_settings:readSetting("weather_location") or self.default_location
                return T(_("Location (%1)"), location)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local location = G_reader_settings:readSetting("weather_location") or self.default_location
                local input
                input = InputDialog:new {
                    title = _("Location"),
                    input = location,
                    input_hint = _("Format: " .. self.default_location),
                    input_type = "string",
                    description = _("Enter your postal code or city name"),
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(input)
                                end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local new_value = input:getInputValue()
                                    G_reader_settings:saveSetting("weather_location", new_value)
                                    G_reader_settings:flush()
                                    logger.dbg("WeatherLockscreen: Saved location:", new_value)
                                    UIManager:close(input)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        }
                    },
                }
                UIManager:show(input)
                input:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                local style_names = {
                    default = _("Detailed"),
                    card = _("Minimal"),
                    reading = _("Cover"),
                    retro = _("Retro Analog"),
                    nightowl = _("Night Owl"),
                }
                return T(_("Display Style (%1)"), style_names[display_style])
            end,
            sub_item_table = {
                {
                    text = _("Detailed"),
                    checked_func = function()
                        local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                        return display_style == "default"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_display_style", "default")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved display style: default")
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("Minimal"),
                    checked_func = function()
                        local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                        return display_style == "card"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_display_style", "card")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved display style: card")
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("Night Owl"),
                    checked_func = function()
                        local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                        return display_style == "nightowl"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_display_style", "nightowl")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved display style: nightowl")
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("Retro Analog"),
                    checked_func = function()
                        local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                        return display_style == "retro"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_display_style", "retro")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved display style: retro")
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("Cover"),
                    checked_func = function()
                        local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                        return display_style == "reading"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_display_style", "reading")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved display style: reading")
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
            },
        },
        {
            text_func = function()
                local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or self.default_temp_scale
                return T(_("Temperature Scale (°%1)"), temp_scale)
            end,
            sub_item_table = {
                {
                    text = _("Celsius"),
                    checked_func = function()
                        local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or self
                            .default_temp_scale
                        return temp_scale == "C"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_temp_scale", "C")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved temp scale: C")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = _("Fahrenheit"),
                    checked_func = function()
                        local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or self
                            .default_temp_scale
                        return temp_scale == "F"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_temp_scale", "F")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved temp scale: F")
                        touchmenu_instance:updateItems()
                    end,
                }
            }
        },
        {
            text = _("Show header"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("weather_show_header")
            end,
            callback = function()
                local current = G_reader_settings:nilOrTrue("weather_show_header")
                G_reader_settings:saveSetting("weather_show_header", not current)
                G_reader_settings:flush()
            end,
            separator = true,
        }
    }
    -- Conditionally add content scaling menu when not in nightowl mode
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    if display_style ~= "nightowl" then
        table.insert(menu_items, {
            text = _("Override scaling"),
            checked_func = function()
                return G_reader_settings:readSetting("weather_override_scaling")
            end,
            callback = function(touchmenu_instance)
                local current = G_reader_settings:nilOrTrue("weather_override_scaling")
                G_reader_settings:saveSetting("weather_override_scaling", not current)
                touchmenu_instance.item_table = self:getSubMenuItems()
                touchmenu_instance:updateItems()
                G_reader_settings:flush()
            end,
            separator = not G_reader_settings:readSetting("weather_override_scaling") and display_style ~= "reading",
        })
        if G_reader_settings:readSetting("weather_override_scaling") then
            table.insert(menu_items, {
                text_func = function()
                    local fill_percent = tonumber(G_reader_settings:readSetting("weather_fill_percent")) or 90
                    return T(_("Content Fill (%1%)"), fill_percent)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local fill_percent = tonumber(G_reader_settings:readSetting("weather_fill_percent")) or 90
                    local spin_widget = SpinWidget:new {
                        title_text = _("Content Fill Percentage"),
                        info_text = _("How much of the available screen height should be filled (in percent)"),
                        value = fill_percent,
                        value_min = 30,
                        value_max = 130,
                        value_step = 5,
                        value_hold_step = 10,
                        default_value = display_style ~= "reading" and 90 or 60,
                        unit = "%",
                        ok_text = _("Set"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("weather_fill_percent", tostring(spin.value))
                            G_reader_settings:flush()
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                separator = display_style ~= "reading",
            })
        end
    end
    -- Conditionally add Cover scaling menu only when reading mode is selected
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    if display_style == "reading" then
        table.insert(menu_items, {
            text_func = function()
                local cover_scaling = G_reader_settings:readSetting("weather_cover_scaling") or 'stretch'
                return T(_("Cover scaling (%1)"), cover_scaling)
            end,
            sub_item_table = {
                {
                    text = _("Fit to screen"),
                    checked_func = function()
                        local cover_scaling = G_reader_settings:readSetting("weather_cover_scaling") or "fit"
                        return cover_scaling == "fit"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_cover_scaling", "fit")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved cover scaling: fit")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = _("Stretch to fill"),
                    checked_func = function()
                        local cover_scaling = G_reader_settings:readSetting("weather_cover_scaling") or "fit"
                        return cover_scaling == "stretch"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting("weather_cover_scaling", "stretch")
                        G_reader_settings:flush()
                        logger.dbg("WeatherLockscreen: Saved cover scaling: stretch")
                        touchmenu_instance:updateItems()
                    end,
                },
            },
            separator = true,
        })
    end

    table.insert(menu_items, {
        text_func = function()
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local hour_text = current_hours == 1 and _("hour") or _("hours")
            return T(_("Cache duration (%1 %2)"), current_hours, hour_text)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local spin_widget = SpinWidget:new {
                title_text = _("Cache duration"),
                info_text = _("How long weather data should remain cached"),
                value = current_hours,
                value_min = 1,
                value_max = 24,
                value_step = 1,
                value_hold_step = 2,
                unit = _("hours"),
                ok_text = _("Set"),
                callback = function(spin)
                    G_reader_settings:saveSetting("weather_cache_max_age", spin.value * 3600)
                    G_reader_settings:flush()
                    touchmenu_instance:updateItems()
                end,
            }
            UIManager:show(spin_widget)
        end,
    })

    table.insert(menu_items, {
        text = _("Clear cache"),
        keep_menu_open = true,
        callback = function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new {
                text = _("Clear cached weather data and icons?"),
                ok_text = _("Clear"),
                ok_callback = function()
                    if self:clearCache() then
                        UIManager:show(require("ui/widget/notification"):new {
                            text = _("Cache cleared"),
                        })
                    else
                        UIManager:show(require("ui/widget/notification"):new {
                            text = _("No cache to clear"),
                        })
                    end
                end,
            })
        end,
    })

    return menu_items
end

function WeatherLockscreen:patchScreensaver()
    -- Store reference to self for use in closures
    local plugin_instance = self

    -- Hook into Screensaver.show() to handle "weather" type
    local Screensaver = require("ui/screensaver")

    -- Save original show method if not already saved
    if not Screensaver._orig_show_before_weather then
        Screensaver._orig_show_before_weather = Screensaver.show
    end

    Screensaver.show = function(screensaver_instance)
        if screensaver_instance.screensaver_type == "weather" then
            logger.dbg("WeatherLockscreen: Weather screensaver activated")

            -- Close any existing screensaver widget
            if screensaver_instance.screensaver_widget then
                UIManager:close(screensaver_instance.screensaver_widget)
                screensaver_instance.screensaver_widget = nil
            end

            -- Set device to screen saver mode
            Device.screen_saver_mode = true

            -- Handle rotation if needed
            local rotation_mode = Screen:getRotationMode()
            Device.orig_rotation_mode = rotation_mode
            local bit = require("bit")
            if bit.band(Device.orig_rotation_mode, 1) == 1 then
                Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
            else
                Device.orig_rotation_mode = nil
            end

            -- Create weather widget
            local weather_widget, fallback = plugin_instance:createWeatherWidget()

            if weather_widget then
                local bg_color = Blitbuffer.COLOR_WHITE
                local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
                if display_style == "nightowl" and not fallback then
                    bg_color = G_reader_settings:isTrue("night_mode") and Blitbuffer.COLOR_WHITE or
                    Blitbuffer.COLOR_BLACK
                end

                screensaver_instance.screensaver_widget = ScreenSaverWidget:new {
                    widget = weather_widget,
                    background = bg_color,
                    covers_fullscreen = true,
                }
                screensaver_instance.screensaver_widget.modal = true
                screensaver_instance.screensaver_widget.dithered = true

                UIManager:show(screensaver_instance.screensaver_widget, "full")
                logger.dbg("WeatherLockscreen: Widget displayed")
            else
                logger.warn("WeatherLockscreen: Failed to create widget, falling back")
                screensaver_instance.screensaver_type = "disable"
                Screensaver._orig_show_before_weather(screensaver_instance)
            end
        else
            Screensaver._orig_show_before_weather(screensaver_instance)
        end
    end

    -- Patch the screensaver menu to add weather option
    -- We need to override dofile to inject our menu item
    if not _G._orig_dofile_before_weather then
        local orig_dofile = dofile
        _G._orig_dofile_before_weather = orig_dofile

        _G.dofile = function(filepath)
            local result = orig_dofile(filepath)

            -- Check if this is the screensaver menu being loaded
            if filepath and filepath:match("screensaver_menu%.lua$") then
                logger.dbg("WeatherLockscreen: Patching screensaver menu")

                if result and result[1] and result[1].sub_item_table then
                    local wallpaper_submenu = result[1].sub_item_table

                    local function genMenuItem(text, setting, value, enabled_func, separator)
                        return {
                            text = text,
                            enabled_func = enabled_func,
                            checked_func = function()
                                return G_reader_settings:readSetting(setting) == value
                            end,
                            callback = function()
                                G_reader_settings:saveSetting(setting, value)
                            end,
                            radio = true,
                            separator = separator,
                        }
                    end

                    -- Add weather option
                    local weather_item = genMenuItem(_("Show weather on sleep screen"), "screensaver_type", "weather")

                    -- Insert before "Leave screen as-is" option (position 6)
                    table.insert(wallpaper_submenu, 6, weather_item)

                    logger.dbg("WeatherLockscreen: Added weather option to screensaver menu")
                end

                -- Restore original dofile after patching
                _G.dofile = orig_dofile
                _G._orig_dofile_before_weather = nil
            end

            return result
        end
    end
end

-- Weather API functions
function WeatherLockscreen:fetchWeatherData()
    return WeatherAPI:fetchWeatherData(self)
end

function WeatherLockscreen:formatHourLabel(hour, twelve_hour_clock)
    return WeatherUtils:formatHourLabel(hour, twelve_hour_clock)
end

function WeatherLockscreen:getMoonPhaseIcon(moon_phase)
    return WeatherUtils:getMoonPhaseIcon(moon_phase)
end

function WeatherLockscreen:getIconPath(icon_url_from_api)
    return WeatherAPI:getIconPath(icon_url_from_api)
end

function WeatherLockscreen:saveWeatherCache(weather_data)
    return WeatherUtils:saveWeatherCache(weather_data)
end

function WeatherLockscreen:loadWeatherCache()
    return WeatherUtils:loadWeatherCache(function() return self:getCacheMaxAge() end)
end

function WeatherLockscreen:clearCache()
    return WeatherUtils:clearCache()
end

function WeatherLockscreen:createHeaderWidgets(header_font_size, header_margin, weather_data, text_color, is_cached)
    local header_widgets = {}
    local show_header = G_reader_settings:nilOrTrue("weather_show_header")

    if show_header and weather_data.current.location then
        table.insert(header_widgets, LeftContainer:new {
            dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
            FrameContainer:new {
                padding = header_margin,
                margin = 0,
                bordersize = 0,
                TextWidget:new {
                    text = weather_data.current.location,
                    face = Font:getFace("cfont", header_font_size),
                    fgcolor = text_color,
                },
            },
        })
    end

    if show_header and weather_data.current.timestamp then
        local timestamp = weather_data.current.timestamp
        local year, month, day, hour, min = timestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
        local formatted_time = ""
        if year and month and day and hour and min then
            local month_names = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
            local month_name = month_names[tonumber(month)] or month
            local twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")
            local hour_num = tonumber(hour)
            local time_str
            if twelve_hour_clock then
                local period = hour_num >= 12 and "PM" or "AM"
                local display_hour = hour_num % 12
                if display_hour == 0 then display_hour = 12 end
                time_str = display_hour .. ":" .. min .. " " .. period
            else
                time_str = hour .. ":" .. min
            end
            formatted_time = month_name .. " " .. tonumber(day) .. ", " .. time_str
        else
            formatted_time = timestamp
        end

        -- Add asterisk if data is cached
        if is_cached then
            formatted_time = formatted_time .. " *"
        end

        table.insert(header_widgets, RightContainer:new {
            dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
            FrameContainer:new {
                padding = header_margin,
                margin = 0,
                bordersize = 0,
                TextWidget:new {
                    text = formatted_time,
                    face = Font:getFace("cfont", header_font_size),
                    fgcolor = text_color,
                },
            },
        })
    end

    return OverlapGroup:new {
        dimen = { w = Screen:getWidth(), h = header_font_size + header_margin * 2 },
        unpack(header_widgets)
    }
end

function WeatherLockscreen:createFallbackWidget()
    logger.dbg("WeatherLockscreen: Creating fallback icon")

    local icon_size = Screen:scaleBySize(WEATHER_ICON_SIZE)

    local current_hour = tonumber(os.date("%H"))
    local is_daytime = current_hour >= 6 and current_hour < 18

    local icon_filename = is_daytime and "sun.svg" or "moon.svg"
    local icon_path = DataStorage:getDataDir() .. "/icons/" .. icon_filename

    local f = io.open(icon_path, "r")
    if f then
        f:close()
    else
        return nil
    end

    local icon_widget = ImageWidget:new {
        file = icon_path,
        width = icon_size,
        height = icon_size,
        alpha = true,
        original_in_nightmode = false
    }

    return CenterContainer:new {
        dimen = Screen:getSize(),
        VerticalGroup:new {
            align = "center",
            icon_widget,
        },
    }
end

function WeatherLockscreen:createWeatherWidget()
    logger.dbg("WeatherLockscreen: Creating widget")
    local weather_data = self:fetchWeatherData()
    local fallback = false

    if not weather_data or not weather_data.current or not weather_data.current.icon_path then
        logger.warn("WeatherLockscreen: No weather data available, trying fallback")
        fallback = true
        return self:createFallbackWidget(), fallback
    end

    -- Check display style setting
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    logger.dbg("WeatherLockscreen: Using display style: " .. display_style)

    -- Load appropriate display module
    local display_module
    if display_style == "card" then
        display_module = require("display_card")
    elseif display_style == "nightowl" then
        display_module = require("display_nightowl")
    elseif display_style == "retro" then
        display_module = require("display_retro")
    elseif display_style == "reading" then
        display_module = require("display_reading")
    else
        display_module = require("display_default")
    end

    return display_module:create(self, weather_data), fallback
end

return WeatherLockscreen
