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

            -- Optimize memory: remove translations that exist in KOReader
            -- This prioritizes KOReader's translations and reduces memory usage
            if NewGetText.translation and original_translation then
                for k, v in pairs(NewGetText.translation) do
                    if original_translation[k] then
                        NewGetText.translation[k] = nil
                    end
                end
            end
        end
    else
        logger.dbg("WeatherLockscreen: Failed to load translation for lang", new_lang, "error:", err)
    end

    -- Restore original KOReader gettext state
    GetText.context = original_context
    GetText.translation = original_translation
    GetText.dirname = original_l10n_dirname
    GetText.wrapUntranslated = original_wrapUntranslated_func
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

    -- Helper to determine the comparison string based on gettext function type
    local function getCompareStr(key, args)
        if key == "gettext" then
            return args[1]
        elseif key == "pgettext" then
            return args[2]
        elseif key == "ngettext" then
            local n = args[3]
            return (new_gettext.getPlural and new_gettext.getPlural(n) == 0) and args[1] or args[2]
        elseif key == "npgettext" then
            local n = args[4]
            return (new_gettext.getPlural and new_gettext.getPlural(n) == 0) and args[2] or args[3]
        end
        return nil
    end

    -- Create metatable for proxy
    local mt = {
        __index = function(_, key)
            local value = new_gettext[key]
            if type(value) ~= "function" then
                return value
            end

            local fallback_func = gettext[key]
            return function(...)
                local args = {...}
                local msgstr = value(...)
                local compare_str = getCompareStr(key, args)

                -- If plugin translation returns untranslated string, try KOReader's translation
                if msgstr and compare_str and msgstr == compare_str then
                    if type(fallback_func) == "function" then
                        msgstr = fallback_func(...)
                    end
                end
                return msgstr
            end
        end,
        __call = function(_, msgid)
            local msgstr = new_gettext(msgid)
            -- If plugin has no translation, fall back to KOReader
            if msgstr and msgstr == msgid then
                msgstr = gettext(msgid)
            end
            return msgstr
        end
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
