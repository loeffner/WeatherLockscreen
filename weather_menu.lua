--[[
    Menu Items for Weather Lockscreen Plugin

    Handles menu generation for the Weather Lockscreen plugin.

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local logger = require("logger")
local _ = require("l10n/gettext")
local T = require("ffi/util").template
local WeatherAPI = require("weather_api")

local WeatherMenu = {}

function WeatherMenu:getSubMenuItems(plugin_instance)
    local menu_items = {
        self:getLocationMenuItem(plugin_instance),
        self:getDisplayStyleMenuItem(plugin_instance),
        self:getTemperatureScaleMenuItem(plugin_instance),
        self:getShowHeaderMenuItem(),
    }

    -- Conditionally add content scaling menu when not in nightowl mode
    local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
    if display_style ~= "nightowl" then
        table.insert(menu_items, self:getOverrideScalingMenuItem(plugin_instance, display_style))
        if G_reader_settings:readSetting("weather_override_scaling") then
            table.insert(menu_items, self:getContentFillMenuItem(display_style))
        end
    end

    -- Conditionally add Cover scaling menu only when reading mode is selected
    if display_style == "reading" then
        table.insert(menu_items, self:getCoverScalingMenuItem())
    end

    table.insert(menu_items, self:getCacheDurationMenuItem())
    table.insert(menu_items, self:getClearCacheMenuItem(plugin_instance))

    return menu_items
end

function WeatherMenu:getLocationMenuItem(plugin_instance)
    return {
        text = _("Location"),
        text_func = function()
            local location = G_reader_settings:readSetting("weather_location") or plugin_instance.default_location
            local location_name = G_reader_settings:readSetting("weather_location_name") or location
            return T(_("Location") .. " (" .. location_name .. ")")
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showLocationSearchDialog(plugin_instance, touchmenu_instance)
        end,
    }
end

function WeatherMenu:showLocationSearchDialog(plugin_instance, touchmenu_instance)
    local location_name = G_reader_settings:readSetting("weather_location_name") or plugin_instance.default_location
    local input
    input = InputDialog:new {
        title = _("Location"),
        input = location_name,
        input_hint = _("City, postal code, or coordinates"),
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
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = input:getInputValue()
                        UIManager:close(input)
                        if query and query ~= "" then
                            self:searchAndShowLocations(plugin_instance, touchmenu_instance, query)
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(input)
    input:onShowKeyboard()
end

function WeatherMenu:searchAndShowLocations(plugin_instance, touchmenu_instance, query)
    local InfoMessage = require("ui/widget/infomessage")

    -- Show searching message
    local searching_msg = InfoMessage:new {
        text = _("Searching..."),
        timeout = 0.5,
    }
    UIManager:show(searching_msg)
    UIManager:forceRePaint()

    -- Get API key
    local api_key = G_reader_settings:readSetting("weather_api_key")
    if not api_key or api_key == "" then
        api_key = plugin_instance.default_api_key
    end

    -- Search for locations
    local locations, err = WeatherAPI:searchLocations(query, api_key)

    UIManager:close(searching_msg)

    if not locations then
        UIManager:show(InfoMessage:new {
            text = T(_("Location search failed: %1"), err or _("Unknown error")),
            timeout = 3,
        })
        return
    end

    -- Show location picker
    self:showLocationPicker(plugin_instance, touchmenu_instance, locations, query)
end

function WeatherMenu:showLocationPicker(plugin_instance, touchmenu_instance, locations, original_query)
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")

    local buttons = {}

    for i, loc in ipairs(locations) do
        -- Format location display: "Name, Region, Country"
        local display_parts = {}
        if loc.name then table.insert(display_parts, loc.name) end
        if loc.region and loc.region ~= "" and loc.region ~= loc.name then
            table.insert(display_parts, loc.region)
        end
        if loc.country then table.insert(display_parts, loc.country) end

        local display_text = table.concat(display_parts, ", ")

        -- Each location is a row with one button
        table.insert(buttons, {
            {
                text = display_text,
                callback = function()
                    UIManager:close(self.location_dialog)
                    self.location_dialog = nil

                    -- Use lat,lon as the location identifier (most precise)
                    local location_value = string.format("%.4f,%.4f", loc.lat, loc.lon)
                    local location_name = loc.name or original_query

                    G_reader_settings:saveSetting("weather_location", location_value)
                    G_reader_settings:saveSetting("weather_location_name", location_name)
                    G_reader_settings:flush()
                    plugin_instance.refresh = true
                    logger.dbg("WeatherLockscreen: Saved location:", location_value, "as", location_name)

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        })
    end

    -- Add "Search again" button at the bottom
    table.insert(buttons, {
        {
            text = _("Search again"),
            callback = function()
                UIManager:close(self.location_dialog)
                self.location_dialog = nil
                self:showLocationSearchDialog(plugin_instance, touchmenu_instance)
            end,
        },
    })


    local title_str = T(_("Select Location (%1 results)"), #locations)
    if #locations == 1 then
        title_str = _("Select Location (1 result)")
    end

    self.location_dialog = ButtonDialogTitle:new {
        title = title_str,
        buttons = buttons,
    }

    UIManager:show(self.location_dialog)
end

function WeatherMenu:getDisplayStyleMenuItem(plugin_instance)
    return {
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
            self:getDisplayStyleOption(plugin_instance, "default", _("Detailed")),
            self:getDisplayStyleOption(plugin_instance, "card", _("Minimal")),
            self:getDisplayStyleOption(plugin_instance, "nightowl", _("Night Owl")),
            self:getDisplayStyleOption(plugin_instance, "retro", _("Retro Analog")),
            self:getDisplayStyleOption(plugin_instance, "reading", _("Cover")),
        },
    }
end

function WeatherMenu:getDisplayStyleOption(plugin_instance, style_value, style_label)
    return {
        text = style_label,
        checked_func = function()
            local display_style = G_reader_settings:readSetting("weather_display_style") or "default"
            return display_style == style_value
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("weather_display_style", style_value)
            G_reader_settings:flush()
            logger.dbg("WeatherLockscreen: Saved display style:", style_value)
            if touchmenu_instance then
                touchmenu_instance.item_table = WeatherMenu:getSubMenuItems(plugin_instance)
                touchmenu_instance:updateItems()
            end
        end,
    }
end

function WeatherMenu:getTemperatureScaleMenuItem(plugin_instance)
    return {
        text_func = function()
            local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or plugin_instance.default_temp_scale
            return T(_("Temperature Scale") .. " (°" .. temp_scale .. ")")
        end,
        sub_item_table = {
            {
                text = _("Celsius"),
                checked_func = function()
                    local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or plugin_instance.default_temp_scale
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
                    local temp_scale = G_reader_settings:readSetting("weather_temp_scale") or plugin_instance.default_temp_scale
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
    }
end

function WeatherMenu:getShowHeaderMenuItem()
    return {
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
end

function WeatherMenu:getOverrideScalingMenuItem(plugin_instance, display_style)
    return {
        text = _("Override scaling"),
        checked_func = function()
            return G_reader_settings:readSetting("weather_override_scaling") or false
        end,
        callback = function(touchmenu_instance)
            local current = G_reader_settings:readSetting("weather_override_scaling") or false
            G_reader_settings:saveSetting("weather_override_scaling", not current)
            touchmenu_instance.item_table = WeatherMenu:getSubMenuItems(plugin_instance)
            touchmenu_instance:updateItems()
            G_reader_settings:flush()
        end,
        separator = not G_reader_settings:readSetting("weather_override_scaling") and display_style ~= "reading",
    }
end

function WeatherMenu:getContentFillMenuItem(display_style)
    return {
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
                info_text = _("How much of the available screen height should be filled?"),
                value = fill_percent,
                value_min = 30,
                value_max = 130,
                value_step = 5,
                value_hold_step = 10,
                default_value = display_style ~= "reading" and 90 or 60,
                unit = "%",
                ok_text = _("Save"),
                callback = function(spin)
                    G_reader_settings:saveSetting("weather_fill_percent", tostring(spin.value))
                    G_reader_settings:flush()
                    touchmenu_instance:updateItems()
                end,
            }
            UIManager:show(spin_widget)
        end,
        separator = display_style ~= "reading",
    }
end

function WeatherMenu:getCoverScalingMenuItem()
    return {
        text_func = function()
            local cover_scaling = _(G_reader_settings:readSetting("weather_cover_scaling") or 'zoom')
            return T(_("Cover scaling") .. " (" .. cover_scaling .. ")")
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
                text = _("Zoom to fill"),
                checked_func = function()
                    local cover_scaling = G_reader_settings:readSetting("weather_cover_scaling") or "fit"
                    return cover_scaling == "zoom"
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("weather_cover_scaling", "zoom")
                    G_reader_settings:flush()
                    logger.dbg("WeatherLockscreen: Saved cover scaling: zoom")
                    touchmenu_instance:updateItems()
                end,
            },
        },
        separator = true,
    }
end

function WeatherMenu:getCacheDurationMenuItem()
    return {
        text_func = function()
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local hour_text = current_hours == 1 and _("hour") or _("hours")
            return T(_("Cache duration") .. " (" .. current_hours .. " " .. hour_text .. ")")
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local spin_widget = SpinWidget:new {
                title_text = _("Cache duration"),
                info_text = _("How long should weather data remain cached?"),
                value = current_hours,
                value_min = 1,
                value_max = 24,
                value_step = 1,
                value_hold_step = 2,
                unit = _("hours"),
                ok_text = _("Save"),
                callback = function(spin)
                    G_reader_settings:saveSetting("weather_cache_max_age", spin.value * 3600)
                    G_reader_settings:flush()
                    touchmenu_instance:updateItems()
                end,
            }
            UIManager:show(spin_widget)
        end,
    }
end

function WeatherMenu:getClearCacheMenuItem(plugin_instance)
    return {
        text = _("Clear cache"),
        keep_menu_open = true,
        callback = function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new {
                text = _("Clear cached weather data and icons?"),
                ok_text = _("Delete"),
                ok_callback = function()
                    if plugin_instance:clearCache() then
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
    }
end

return WeatherMenu
