--[[
    Update checker / installer for Weather Lockscreen

    Checks GitHub's latest release at most once a day (only right after a
    successful live weather fetch, so Wi-Fi is known to be up), remembers an
    available update in settings, notifies once per new version, and can
    download + swap in the release zip and restart KOReader.

    Version comparison and the download helper are adapted from
    storefront.koplugin by ultimatejimmy (GPLv3):
    https://github.com/ultimatejimmy/storefront.koplugin

    Author: Andreas Lösel
    License: GNU AGPL v3
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local _ = require("l10n/gettext")
local T = require("ffi/util").template
local WeatherUtils = require("weather_utils")

local WeatherUpdate = {}

local RELEASES_URL = "https://api.github.com/repos/loeffner/WeatherLockscreen/releases/latest"
local ASSET_PATTERN = "^weatherlockscreen%.koplugin.*%.zip$"
local CHECK_INTERVAL = 24 * 60 * 60 -- seconds
local MAX_NOTES_LEN = 600

-- Resolved at load time: debug.getinfo inside getPluginDir sees this file.
local plugin_dir = WeatherUtils:getPluginDir()

---------------------------------------------------------------------------
-- Version comparison (adapted from Storefront storefront_utils.lua)
---------------------------------------------------------------------------

local function parseVersion(v_str)
    if not v_str then
        return { nums = {}, pre = nil }
    end
    v_str = tostring(v_str):gsub("^[vV]%-?", "")
    local main_str, pre_str = v_str:match("^([%d%.]+)%-?(.*)$")
    local nums = {}
    if main_str and main_str ~= "" then
        for part in main_str:gmatch("%d+") do
            table.insert(nums, tonumber(part) or 0)
        end
    end

    local pre = nil
    if main_str and pre_str and pre_str ~= "" then
        local pre_type, pre_num = pre_str:match("^([a-zA-Z]+)%.?(%d*)$")
        if not pre_type then
            pre_type, pre_num = pre_str, "0"
        end
        local ranks = { dev = 1, alpha = 2, beta = 3, preview = 4, rc = 5 }
        pre = {
            rank = ranks[pre_type:lower()] or 0,
            name = pre_type:lower(),
            num = tonumber(pre_num) or 0,
        }
    end
    return { nums = nums, pre = pre }
end

--- True when version string a is strictly newer than b.
function WeatherUpdate.isVersionNewer(a, b)
    if not a or not b or a == "" or b == "" or a == b then
        return false
    end
    local d1, d2 = parseVersion(a), parseVersion(b)
    if #d1.nums == 0 or #d2.nums == 0 then
        return false
    end
    for i = 1, math.max(#d1.nums, #d2.nums) do
        local x, y = d1.nums[i] or 0, d2.nums[i] or 0
        if x ~= y then
            return x > y
        end
    end
    -- Same numbers: a release beats any pre-release of it.
    if not d1.pre and d2.pre then return true end
    if d1.pre and not d2.pre then return false end
    if d1.pre and d2.pre then
        if d1.pre.rank ~= d2.pre.rank then return d1.pre.rank > d2.pre.rank end
        if d1.pre.name ~= d2.pre.name then return d1.pre.name > d2.pre.name end
        return d1.pre.num > d2.pre.num
    end
    return false
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Read the `version` field of a _meta.lua without executing it.
local function readMetaVersion(dir)
    local f = io.open(dir .. "/_meta.lua", "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content and content:match("version%s*=%s*[\"']([^\"']+)[\"']")
end

function WeatherUpdate:getCurrentVersion()
    return plugin_dir and readMetaVersion(plugin_dir)
end

local function pathExists(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") ~= nil
end

--- HTTP GET via KOReader's socket stack (handles https and redirects).
-- Returns the numeric status code (or nil) and an error string.
local function httpGet(url, sink, accept, block_timeout, total_timeout)
    local http = require("socket.http")
    local socket = require("socket")
    local socketutil = require("socketutil")

    socketutil:set_timeout(block_timeout, total_timeout)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            method = "GET",
            sink = sink,
            redirect = true,
            headers = {
                ["User-Agent"] = socketutil.USER_AGENT or "KOReader-WeatherLockscreen",
                ["Accept"] = accept,
            },
        })
    end)
    socketutil:reset_timeout()

    if not ok then
        return nil, tostring(code)
    end
    if not headers then
        return nil, tostring(status or code or "network error")
    end
    return tonumber(code), status
end

--- Download url to local_path via a temp file (adapted from Storefront).
local function downloadToFile(url, local_path)
    local socketutil = require("socketutil")
    local temp_path = local_path .. ".tmp"
    os.remove(temp_path)

    local file, err = io.open(temp_path, "wb")
    if not file then
        return false, err or "cannot open file for writing"
    end

    local code, status = httpGet(url, socketutil.file_sink(file),
        "application/octet-stream, */*",
        socketutil.FILE_BLOCK_TIMEOUT or 15, socketutil.FILE_TOTAL_TIMEOUT or 180)
    pcall(function() file:close() end)

    if code ~= 200 then
        os.remove(temp_path)
        return false, status or ("HTTP " .. tostring(code))
    end

    os.remove(local_path)
    if not os.rename(temp_path, local_path) then
        os.remove(temp_path)
        return false, "cannot save downloaded file"
    end
    return true
end

--- Extract a zip into dest_dir, stripping its single root directory
-- (weatherlockscreen.koplugin/). Uses ffi/archiver directly, since
-- Device:unpackArchive doesn't exist in older KOReader releases.
local function unpackStrippingRoot(archive, dest_dir)
    local ok_req, Archiver = pcall(require, "ffi/archiver")
    if not ok_req then
        return false, "ffi/archiver not available"
    end
    local reader = Archiver.Reader:new()
    if not reader:open(archive) then
        return false, reader.err or "cannot open archive"
    end
    local ok, err = true, nil
    for entry in reader:iterate() do
        local rel = entry.path:match("^[^/]+/(.*)$")
        -- Skip the root directory itself and anything outside it.
        if rel and rel ~= "" then
            if not reader:extractToPath(entry.path, dest_dir .. "/" .. rel) then
                ok, err = false, reader.err or ("cannot extract " .. entry.path)
                break
            end
        end
    end
    reader:close()
    return ok, err
end

--- Turn a GitHub release body into short plain text for a dialog: keep only
-- the hand-written part (drop GitHub's auto-generated notes) and strip the
-- Markdown/HTML that KOReader would show literally.
function WeatherUpdate.cleanReleaseNotes(body)
    if type(body) ~= "string" then
        return ""
    end
    local text = body:gsub("\r", "")
    -- GitHub's generated notes start with one of these; cut at the first.
    for _, marker in ipairs{ "\n#+%s*What's Changed", "\n#+%s*New Contributors", "\n%*%*Full Changelog%*%*" } do
        local pos = ("\n" .. text):find(marker)
        if pos then
            text = text:sub(1, pos - 1)
        end
    end
    text = text:gsub("<[^>]+>", "")                    -- HTML tags (images etc.)
               :gsub("!%[[^%]]*%]%([^%)]*%)", "")       -- Markdown images
               :gsub("%[([^%]]*)%]%([^%)]*%)", "%1")    -- links -> link text
               :gsub("%*%*([^*]+)%*%*", "%1")           -- bold
               :gsub("`([^`]*)`", "%1")                 -- inline code
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^%s*#+%s*", "")               -- headings
                   :gsub("^%s*[%*%-]%s+", "• ")         -- bullets
                   :gsub("%s+$", "")
        table.insert(lines, line)
    end
    text = table.concat(lines, "\n"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if #text > MAX_NOTES_LEN then
        -- Cut on a UTF-8 character boundary.
        local cut = MAX_NOTES_LEN
        while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
            cut = cut - 1
        end
        text = text:sub(1, cut) .. "…"
    end
    return text
end

local function clearAvailableUpdate()
    G_reader_settings:saveSetting("weather_update_available_version", "")
    G_reader_settings:saveSetting("weather_update_download_url", "")
    G_reader_settings:saveSetting("weather_update_notes", "")
end

---------------------------------------------------------------------------
-- Checking
---------------------------------------------------------------------------

--- Query GitHub for the latest release and record whether it is newer.
-- Synchronous; only call while online. Never raises.
function WeatherUpdate:checkForUpdate()
    local ok, err = pcall(function()
        local current = self:getCurrentVersion()
        if not current then
            logger.warn("WeatherLockscreen: Update check skipped, cannot read installed version")
            return
        end

        local socketutil = require("socketutil")
        local json = require("json")
        local body = {}
        local code, status = httpGet(RELEASES_URL, socketutil.table_sink(body),
            "application/vnd.github+json", 5, 10)
        -- Record the attempt even on failure, so an outage doesn't add a
        -- GitHub request to every weather fetch.
        G_reader_settings:saveSetting("weather_update_last_check", os.time())

        if code ~= 200 then
            logger.warn("WeatherLockscreen: Update check failed:", code, status)
            return
        end

        local decoded, release = pcall(json.decode, table.concat(body))
        if not decoded or type(release) ~= "table" or not release.tag_name then
            logger.warn("WeatherLockscreen: Update check got an unexpected response")
            return
        end

        local download_url
        for _, asset in ipairs(release.assets or {}) do
            if asset.name and asset.name:match(ASSET_PATTERN) then
                download_url = asset.browser_download_url
                break
            end
        end

        if download_url and WeatherUpdate.isVersionNewer(release.tag_name, current) then
            local notes = WeatherUpdate.cleanReleaseNotes(release.body)
            logger.info("WeatherLockscreen: Update available:", release.tag_name, "(installed:", current .. ")")
            G_reader_settings:saveSetting("weather_update_available_version", release.tag_name)
            G_reader_settings:saveSetting("weather_update_download_url", download_url)
            G_reader_settings:saveSetting("weather_update_notes", notes)
        else
            logger.dbg("WeatherLockscreen: No update available, latest is", release.tag_name)
            clearAvailableUpdate()
        end
    end)
    G_reader_settings:flush()
    if not ok then
        logger.warn("WeatherLockscreen: Update check error:", err)
    end
end

--- Check for updates if enabled and the last check is old enough.
-- Called right after a successful live weather fetch.
function WeatherUpdate:maybeCheck()
    if not G_reader_settings:nilOrTrue("weather_update_check") then
        return
    end
    local last = G_reader_settings:readSetting("weather_update_last_check") or 0
    if os.time() - last < CHECK_INTERVAL then
        return
    end
    self:checkForUpdate()
end

--- The version of a known, still-applicable update, or nil.
function WeatherUpdate:getAvailableVersion()
    local available = G_reader_settings:readSetting("weather_update_available_version")
    if not available or available == "" then
        return nil
    end
    -- Guards against stale settings, e.g. after a manual install.
    if not WeatherUpdate.isVersionNewer(available, self:getCurrentVersion()) then
        return nil
    end
    return available
end

---------------------------------------------------------------------------
-- Installing
---------------------------------------------------------------------------

local function doInstall(version, url)
    local ffiutil = require("ffi/util")

    if not plugin_dir then
        return false, "cannot locate plugin directory"
    end

    local staging_dir = plugin_dir .. ".update"
    local backup_dir = plugin_dir .. ".old"
    local zip_path = DataStorage:getDataDir() .. "/cache/weatherlockscreen-update.zip"
    require("util").makePath(DataStorage:getDataDir() .. "/cache")

    -- Leftovers from an interrupted earlier attempt.
    if pathExists(staging_dir) then ffiutil.purgeDir(staging_dir) end
    if pathExists(backup_dir) then ffiutil.purgeDir(backup_dir) end

    local ok, err = downloadToFile(url, zip_path)
    if not ok then
        return false, T(_("Download failed: %1"), tostring(err))
    end

    ok, err = unpackStrippingRoot(zip_path, staging_dir)
    os.remove(zip_path)
    if not ok then
        logger.warn("WeatherLockscreen: Extracting update failed:", err)
        if pathExists(staging_dir) then ffiutil.purgeDir(staging_dir) end
        return false, err or _("Extracting the update failed.")
    end

    local staged_version = readMetaVersion(staging_dir)
    if not pathExists(staging_dir .. "/main.lua") or staged_version ~= version then
        ffiutil.purgeDir(staging_dir)
        logger.warn("WeatherLockscreen: Staged update invalid, version:", staged_version)
        return false, _("The downloaded update is not valid.")
    end

    -- Swap directories (same filesystem, so these are cheap renames).
    ok, err = os.rename(plugin_dir, backup_dir)
    if not ok then
        ffiutil.purgeDir(staging_dir)
        return false, tostring(err)
    end
    ok, err = os.rename(staging_dir, plugin_dir)
    if not ok then
        os.rename(backup_dir, plugin_dir) -- roll back
        ffiutil.purgeDir(staging_dir)
        return false, tostring(err)
    end
    ffiutil.purgeDir(backup_dir)
    return true
end

function WeatherUpdate:install()
    local NetworkMgr = require("ui/network/manager")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")

    local version = G_reader_settings:readSetting("weather_update_available_version")
    local url = G_reader_settings:readSetting("weather_update_download_url")
    if not version or version == "" or not url or url == "" then
        return
    end

    NetworkMgr:runWhenOnline(function()
        local msg = InfoMessage:new{ text = T(_("Downloading Weather Lockscreen %1…"), version) }
        UIManager:show(msg)
        UIManager:forceRePaint()

        local pok, ok, err = pcall(doInstall, version, url)
        UIManager:close(msg)

        if pok and ok then
            logger.info("WeatherLockscreen: Updated to", version)
            clearAvailableUpdate()
            G_reader_settings:flush()
            UIManager:askForRestart(T(_("Weather Lockscreen has been updated to %1. Restart KOReader now?"), version))
        else
            local reason = pok and err or ok
            logger.warn("WeatherLockscreen: Update failed:", reason)
            UIManager:show(InfoMessage:new{
                text = T(_("Updating Weather Lockscreen failed:\n%1"), tostring(reason)),
            })
        end
    end)
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

function WeatherUpdate:showUpdateDialog()
    local version = self:getAvailableVersion()
    if not version then
        return
    end
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")

    local text = T(_("Weather Lockscreen %1 is available (installed: %2)."),
        version, self:getCurrentVersion() or "?")
    local notes = G_reader_settings:readSetting("weather_update_notes")
    if notes and notes ~= "" then
        text = text .. "\n\n" .. notes
    end

    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Update now"),
        cancel_text = _("Later"),
        ok_callback = function()
            self:install()
        end,
    })
end

--- Show the update popup once per new version, never on the sleep screen.
function WeatherUpdate:maybeNotify()
    local Device = require("device")
    if Device.screen_saver_mode then
        return
    end
    local version = self:getAvailableVersion()
    if not version or G_reader_settings:readSetting("weather_update_notified_version") == version then
        return
    end
    G_reader_settings:saveSetting("weather_update_notified_version", version)
    G_reader_settings:flush()
    self:showUpdateDialog()
end

return WeatherUpdate
