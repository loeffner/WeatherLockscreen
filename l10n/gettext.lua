--[[
    Custom gettext implementation for WeatherLockscreen plugin
    Adapted from ProjectTitle plugin by joshuacant

    This module wraps KOReader's gettext to load plugin-specific translations
    from the l10n/ directory while falling back to KOReader's translations
    when the plugin doesn't have a specific translation.
--]]

local util = require("util")
local GetText = require("gettext")
local logger = require("logger")

-- Determine plugin directory from this file's location
local full_source_path = debug.getinfo(1, "S").source
if full_source_path:sub(1, 1) == "@" then
    full_source_path = full_source_path:sub(2)
end
local lib_path, _ = util.splitFilePathName(full_source_path)
local plugin_path = lib_path:gsub("/+", "/"):gsub("[\\/]l10n[\\/]", "")

local NewGetText = {
    dirname = string.format("%s/l10n", plugin_path)
}

local changeLang = function(new_lang)
    -- Save original KOReader gettext state
    local original_l10n_dirname = GetText.dirname
    local original_context = GetText.context
    local original_translation = GetText.translation
    local original_wrapUntranslated_func = GetText.wrapUntranslated
    local original_getPlural = GetText.getPlural
    local original_current_lang = GetText.current_lang

    -- Temporarily point to plugin's l10n directory
    GetText.dirname = NewGetText.dirname

    -- Try to load plugin's translation file
    local ok, err = pcall(GetText.changeLang, new_lang)
    if ok then
        if (GetText.translation and next(GetText.translation) ~= nil) or
           (GetText.context and next(GetText.context) ~= nil) then
            -- Deep copy the loaded translation
            NewGetText = util.tableDeepCopy(GetText)

        end
    else
        logger.dbg("WeatherLockscreen: Failed to load translation for lang", new_lang, "error:", err)
    end

    -- Restore original KOReader gettext state
    GetText.context = original_context
    GetText.translation = original_translation
    GetText.dirname = original_l10n_dirname
    GetText.wrapUntranslated = original_wrapUntranslated_func
    GetText.getPlural = original_getPlural
    GetText.current_lang = original_current_lang

    original_translation = nil
    original_context = nil
end

local function createGetTextProxy(new_gettext, gettext)
    -- Verify that plugin translation loaded successfully
    if not (new_gettext.wrapUntranslated and new_gettext.translation and new_gettext.current_lang) then
        logger.dbg("WeatherLockscreen: Plugin translation not loaded, using KOReader defaults for lang", gettext.current_lang)
        return gettext
    end

    -- Look up plugin entries directly: copied gettext functions retain
    -- closures over KOReader's original translation tables.
    local function lookup(kind, ...)
        local args = {...}
        local has_context = kind == "pgettext" or kind == "npgettext"
        local has_plural = kind == "ngettext" or kind == "npgettext"
        local msgid = args[has_context and 2 or 1]
        local translations
        if has_context then
            translations = new_gettext.context[args[1]]
        else
            translations = new_gettext.translation
        end
        local value = translations and translations[msgid]
        if has_plural then
            local n = args[has_context and 4 or 3]
            value = type(value) == "table" and value[new_gettext.getPlural(n)] or nil
        elseif kind == "gettext" and type(value) == "table" then
            value = value[0]
        end
        -- A translation identical to msgid is still a valid catalog entry.
        if type(value) == "string" and value ~= "" then
            return value
        end
        if kind == "gettext" then
            return gettext(msgid)
        end
        return gettext[kind](...)
    end

    local mt = {
        __index = function(_, key)
            if key == "gettext" or key == "pgettext"
                or key == "ngettext" or key == "npgettext" then
                return function(...)
                    return lookup(key, ...)
                end
            end
            return new_gettext[key]
        end,
        __call = function(_, msgid)
            return lookup("gettext", msgid)
        end,
    }

    return setmetatable({
        -- Debug function to dump translation data (for development/debugging)
        debug_dump = function()
            local new_lang = new_gettext.current_lang
            local dump_path = string.format("%s/%s/%s", new_gettext.dirname, new_lang, "debug_logs.lua")
            require("luasettings"):open(dump_path):saveSetting("po", new_gettext):flush()
            logger.info("WeatherLockscreen: Translation debug dump saved to", dump_path)
        end
    }, mt)
end

-- Load translations for current language
local current_lang = GetText.current_lang or G_reader_settings:readSetting("language")
if current_lang then
    changeLang(current_lang)
end

return createGetTextProxy(NewGetText, GetText)
