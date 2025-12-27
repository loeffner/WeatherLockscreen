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
local WeatherUtils = require("weather_utils")

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

    table.insert(menu_items, self:getCacheMenuItem(plugin_instance))
    table.insert(menu_items, self:getRtcModeMenuItem(plugin_instance))
    table.insert(menu_items, self:getDashboardModeMenuItem(plugin_instance))

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

    -- Check for special commands (debug on/off, etc.)
    if WeatherUtils:handleSpecialCommand(query) then
        if touchmenu_instance then
            touchmenu_instance.item_table = WeatherMenu:getSubMenuItems(plugin_instance)
            touchmenu_instance:updateItems()
        end
        return
    end

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
            touchmenu_instance:updateItems()
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

function WeatherMenu:getCacheMenuItem(plugin_instance)
    local sub_items = {}

    -- Only show min update delay in debug mode
    if G_reader_settings:isTrue("weather_debug_options") then
        table.insert(sub_items, {
            text_func = function()
                local current_minutes = math.floor(WeatherUtils:getMinDelayBetweenUpdates() / 60)
                return T(_("Minimum Cache duration") .. " (" .. current_minutes .. " " .. _("minutes") .. ")")
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local current_minutes = math.floor(WeatherUtils:getMinDelayBetweenUpdates() / 60)
                local spin_widget = SpinWidget:new {
                    title_text = _("Minimum Cache duration"),
                    info_text = _("Minimum time between API requests when locking device. Within this period, cached data is used automatically."),
                    value = current_minutes,
                    value_min = 0,
                    value_max = 60,
                    value_step = 5,
                    value_hold_step = 15,
                    unit = _("minutes"),
                    ok_text = _("Save"),
                    callback = function(spin)
                        G_reader_settings:saveSetting("weather_min_update_delay", spin.value * 60)
                        G_reader_settings:flush()
                        touchmenu_instance:updateItems()
                    end,
                }
                UIManager:show(spin_widget)
            end,
            help_text = _("Debug: Controls minimum time between API requests. Does not affect periodic refresh intervals."),
        })
    end

    table.insert(sub_items, {
        text_func = function()
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local hour_text = current_hours == 1 and _("hour") or _("hours")
            return T(_("Maximum Cache duration") .. " (" .. current_hours .. " " .. hour_text .. ")")
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            local current_hours = math.floor((G_reader_settings:readSetting("weather_cache_max_age") or 3600) / 3600)
            local spin_widget = SpinWidget:new {
                title_text = _("Maximum Cache duration"),
                info_text = _("When offline, cached weather data up to this age will be shown. Older data displays a fallback icon instead."),
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
    })

    table.insert(sub_items, {
        text = _("Clear cache"),
        keep_menu_open = true,
        callback = function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new {
                text = _("Clear cached weather data and icons?"),
                ok_text = _("Delete"),
                ok_callback = function()
                    if WeatherUtils:clearCache() then
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

    return {
        text = _("Cache Settings"),
        sub_item_table = sub_items,
        separator = true,
    }
end


function WeatherMenu:getRtcModeMenuItem(plugin_instance)
    return {
        text_func = function()
            local can_schedule_wakeup = WeatherUtils:canScheduleWakeup()
            local wifi_turn_on = WeatherUtils:wifiEnableActionTurnOn()
            local interval = WeatherUtils:getPeriodicRefreshInterval("rtc")
            if not can_schedule_wakeup then
                -- Check if this is a Kobo device (which could be enabled)
                local Device = require("device")
                if Device:isKobo() then
                    return _("Active Sleep (Kobo experimental - hold for help)")
                end
                return _("Active Sleep (Unsupported device)")
            elseif wifi_turn_on == false then
                    return _("Active Sleep (Enable Wi-Fi 'Turn on' first)")
            elseif interval <= 0 then
                return _("Active Sleep (Tap to set interval)")
            else
                return _("Active Sleep") .. " (" .. _("Lock to Start") .. ": " .. (interval < 3600 and (interval / 60 .. " " .. _("min")) or (interval / 3600 .. " " .. _("h"))) .. ")"
            end
        end,
        enabled_func = function()
            return WeatherUtils:periodicRefreshSupported()
        end,
        sub_item_table_func = function()
            local items = {
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 0, _("Off")),
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 1800, _("30 minutes")),
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 3600, _("1 hour")),
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 10800, _("3 hours")),
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 21600, _("6 hours")),
                self:getPeriodicRefreshOption(plugin_instance, "rtc", 43200, _("12 hours")),
            }
            -- Add custom interval option only in debug mode
            if G_reader_settings:isTrue("weather_debug_options") then
                table.insert(items, self:getCustomIntervalOption(plugin_instance, "rtc"))
            end

            table.insert(items, {
                text_func = function()
                    local min_batt = WeatherUtils:getActiveSleepMinBattery()
                    if min_batt > 0 then
                        return T(_("Min battery (%1%)"), min_batt)
                    end
                    return _("Min battery (Off)")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local current = WeatherUtils:getActiveSleepMinBattery()
                    local spin_widget = SpinWidget:new {
                        title_text = _("Active Sleep"),
                        info_text = _("Disable Active Sleep below this battery level. Set to 0 to turn off."),
                        value = current,
                        value_min = 0,
                        value_max = 100,
                        value_step = 1,
                        ok_text = _("Save"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("weather_active_sleep_min_battery", spin.value)
                            G_reader_settings:flush()
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                separator = true,
            })
            return items
        end,
        help_text = _("Device wakes from sleep to refresh weather data. Saves power compared to the dashboard.\n\nSupported devices: Kindle. Kobo (experimental) see README for more information."),
    }
end

function WeatherMenu:getDashboardModeMenuItem(plugin_instance)
    return {
        text_func = function()
            local interval = WeatherUtils:getPeriodicRefreshInterval("dashboard")
            if interval > 0 then
                return _("Dashboard") .. " (" .. _("Hold to Start") .. ": " .. (interval < 3600 and (interval / 60 .. " " .. _("min")) or (interval / 3600 .. " " .. _("h"))) .. ")"
            else
                return _("Dashboard (Tap to set interval)")
            end
        end,
        -- Hold to start dashboard
        hold_callback = function()
            local interval = WeatherUtils:getPeriodicRefreshInterval("dashboard")
            if interval > 0 then
                local WeatherDashboard = require("weather_dashboard")
                WeatherDashboard:start(plugin_instance)
            end
        end,
        -- Tap to open interval settings
        sub_item_table_func = function()
            local items = {
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 0, _("Off")),
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 1800, _("30 minutes")),
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 3600, _("1 hour")),
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 10800, _("3 hours")),
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 21600, _("6 hours")),
                self:getPeriodicRefreshOption(plugin_instance, "dashboard", 43200, _("12 hours")),
            }
            -- Add custom interval option only in debug mode
            if G_reader_settings:isTrue("weather_debug_options") then
                table.insert(items, self:getCustomIntervalOption(plugin_instance, "dashboard"))
            end
            return items
        end,
        help_text = _("Shows weather fullscreen and refreshes periodically. Works on all devices. Tap screen to dismiss. Uses more battery than regular sleep screen."),
        separator = true,
    }
end

function WeatherMenu:getPeriodicRefreshOption(plugin_instance, type, interval, label)
    return {
        text = label,
        checked_func = function()
            return WeatherUtils:getPeriodicRefreshInterval(type) == interval
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            plugin_instance:setPeriodicRefreshInterval(interval, type, touchmenu_instance)
        end,
    }
end

function WeatherMenu:getCustomIntervalOption(plugin_instance, type)
    local preset_intervals = {0, 1800, 3600, 10800, 21600, 43200}

    local function isCustomInterval()
        local current = WeatherUtils:getPeriodicRefreshInterval(type)
        for _, preset in ipairs(preset_intervals) do
            if current == preset then
                return false
            end
        end
        return current > 0
    end

    local function formatInterval(seconds)
        if seconds < 3600 then
            return T(_("%1 min"), math.floor(seconds / 60))
        elseif seconds % 3600 == 0 then
            local hours = math.floor(seconds / 3600)
            return T(_("%1 h"), hours)
        else
            local hours = math.floor(seconds / 3600)
            local mins = math.floor((seconds % 3600) / 60)
            return T(_("%1 h %2 min"), hours, mins)
        end
    end

    return {
        text_func = function()
            if isCustomInterval() then
                local interval = WeatherUtils:getPeriodicRefreshInterval(type)
                return T(_("Custom (%1)"), formatInterval(interval))
            else
                return _("Custom…")
            end
        end,
        checked_func = isCustomInterval,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local DoubleSpinWidget = require("ui/widget/doublespinwidget")
            local current_interval = WeatherUtils:getPeriodicRefreshInterval(type)
            if current_interval == 0 then current_interval = 1800 end -- Default to 30 min

            local current_hours = math.floor(current_interval / 3600)
            local current_minutes = math.floor((current_interval % 3600) / 60)

            local spin_widget = DoubleSpinWidget:new {
                title_text = _("Custom refresh interval"),
                info_text = _("Set hours and minutes for the refresh interval."),
                left_text = _("Hours"),
                right_text = _("Minutes"),
                left_value = current_hours,
                left_min = 0,
                left_max = 24,
                left_step = 1,
                left_hold_step = 3,
                left_default = 0,
                right_value = current_minutes,
                right_min = 0,
                right_max = 59,
                right_step = 1,
                right_hold_step = 15,
                right_default = 30,
                ok_text = _("Save"),
                callback = function(left_value, right_value)
                    local interval_seconds = (left_value * 3600) + (right_value * 60)
                    if interval_seconds < 60 then
                        interval_seconds = 60 -- Minimum 1 minute
                    end
                    plugin_instance:setPeriodicRefreshInterval(interval_seconds, type, touchmenu_instance)
                end,
            }
            UIManager:show(spin_widget)
        end,
        separator = true,
    }
end

return WeatherMenu
