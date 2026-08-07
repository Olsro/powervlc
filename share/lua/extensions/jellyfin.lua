--[[
 jellyfin.lua : Jellyfin browser extension for PowerVLC

 Browse a Jellyfin server (movies, series, seasons, episodes, and the
 live TV line-up), then play either the original file (direct play) or
 an HLS stream transcoded at the chosen quality, without ever leaving
 VLC.

 The user flow follows the JellyDinosaur front-end
 (https://github.com/Olsro/jellydinosaur): server, then API key OR
 username/password, then library / details / playback options.

 Uses only plain dialog widgets (no HTML) so it renders correctly on
 every interface, including the legacy Mac OS X one.

 Copyright (C) 2026 the PowerVLC team

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
--]]

local json = nil

local READ_CHUNK = 65536

-- Sent to Jellyfin both when authenticating and on every stream URL.
-- DEVICE_NAME is what the server shows in its dashboard and in the
-- session list, so it says PowerVLC rather than passing for VLC.
local DEVICE_ID = "PowerVLC"
local DEVICE_NAME = "PowerVLC"
local CLIENT_NAME = "PowerVLC"
-- Asked of the core rather than repeated here: a version written in a
-- script is a version that stops being true.
local function client_version()
  if vlc.misc and vlc.misc.product_version then
    local ok, version = pcall(vlc.misc.product_version)
    if ok and version and version ~= "" then
      return version
    end
  end
  return "?"
end
-- Shown in the Jellyfin dashboard next to transcoding sessions
local TRANSCODE_REASON = "User decided to transcode this content"

            --[[ Translations ]]--

-- One file per language under share/lua/i18n/jellyfin/, and only the one
-- in use is ever read: seventeen catalogues parsed at every activation, to
-- keep one, is not free on the machines this fork exists for. English sits
-- underneath, string by string, so an untranslated key shows in English
-- rather than as a hole.
-- ⚠ Le catalogue ne peut PAS être chargé ici. Le scanner charge ce fichier
-- dans un état Lua nu pour y lire descriptor() : aucune bibliothèque de base,
-- et require() y est un bouchon qui rend nil (vlclua_dummy_require, dans
-- modules/lua/extension.c). Tout appel de bibliothèque au niveau du fichier
-- tue donc l'extension avant même qu'elle soit listée -- « attempt to index a
-- nil value » au scan, extension absente du menu. La table reste vide ici et
-- se remplit dans activate(), qui tourne dans un état complet : tous les
-- lang.x du fichier sont inchangés, ils lisent à travers __index.
local lang = {}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("jellyfin") })
end

            --[[ Quality presets ]]--

-- Same H.264 ladders as JellyDinosaur: each bitrate stays under the VBV
-- cap of its level/profile, refFrames climbs with quality. Levels and
-- profiles are strings because that is what the Jellyfin URL carries.
-- Read low to high, the way a viewer thinks about them; which entry is
-- shown is chosen with set_value, not by the order.
local RESOLUTIONS = { "240", "360", "480", "720", "1080" }
local DEFAULT_RESOLUTION = "480"
local DEFAULT_QUALITY = "high"
local RESOLUTION_MAX_WIDTH = {
  ["240"] = "426", ["360"] = "640", ["480"] = "854",
  ["720"] = "1280", ["1080"] = "1920",
}
local QUALITY_KEYS = { "low", "medium", "high", "veryhigh" }

-- Audio bitrates offered, low to high
local AUDIO_BITRATES = { 128000, 192000, 256000 }
local DEFAULT_AUDIO_BITRATE = 256000

-- Sample rate always asked of the server, deliberately not a setting.
--
-- The built-in output of the Macs this fork exists for runs at 44 100 Hz
-- (measured on a 700 MHz iBook G3 under Mac OS X 10.2: "audio output: VLC is
-- looking for f32b 44100 Hz Stereo"), while a film's soundtrack is almost
-- always 48 000 Hz. Left alone, VLC therefore resamples every frame on the
-- CPU with its cubic interpolator -- about 1.3 % of that machine, on a CPU
-- with none to spare, plus roughly 8 % more AAC to decode for the extra
-- samples. Asking the server for CD rate deletes that stage outright, and
-- ffmpeg's resampler on the server is better than the one it replaces.
--
-- No control for it: the right value follows from the sound card, not from
-- taste, so there is nothing for the user to arbitrate -- and where it is
-- not needed (a machine genuinely running at 48 kHz) the cost is one
-- resample on hardware fast enough not to feel it.
local AUDIO_SAMPLE_RATE = 44100

-- Maximum bit rate per H.264 level (Annex A, table A-1), in bit/s, for
-- the baseline and main profiles; the high profile raises the ceiling by
-- a quarter. Beyond it the encoder clamps anyway, so the field does too.
local H264_LEVEL_MAX_BITRATE = {
  ["3.0"] = 10000000,
  ["3.1"] = 14000000,
  ["4.0"] = 20000000,
}

local QUALITY_PRESETS = {
  ["240"] = {
    low      = { bitrate = 350000,   audio = 128000, level = "3.0", profile = "baseline", refs = 1 },
    medium   = { bitrate = 700000,   audio = 192000, level = "3.0", profile = "baseline", refs = 3 },
    high     = { bitrate = 1400000,  audio = 256000, level = "3.1", profile = "high",     refs = 5 },
    veryhigh = { bitrate = 2100000,  audio = 256000, level = "3.1", profile = "high",     refs = 16 },
  },
  ["360"] = {
    low      = { bitrate = 600000,   audio = 128000, level = "3.0", profile = "baseline", refs = 1 },
    medium   = { bitrate = 1200000,  audio = 192000, level = "3.1", profile = "baseline", refs = 3 },
    high     = { bitrate = 2400000,  audio = 256000, level = "3.1", profile = "high",     refs = 5 },
    veryhigh = { bitrate = 3500000,  audio = 256000, level = "3.1", profile = "high",     refs = 16 },
  },
  ["480"] = {
    low      = { bitrate = 1200000,  audio = 128000, level = "3.0", profile = "baseline", refs = 1 },
    medium   = { bitrate = 2400000,  audio = 192000, level = "3.1", profile = "baseline", refs = 3 },
    high     = { bitrate = 4800000,  audio = 256000, level = "3.1", profile = "high",     refs = 5 },
    veryhigh = { bitrate = 7000000,  audio = 256000, level = "3.1", profile = "high",     refs = 16 },
  },
  ["720"] = {
    low      = { bitrate = 2400000,  audio = 128000, level = "3.1", profile = "baseline", refs = 1 },
    medium   = { bitrate = 4800000,  audio = 192000, level = "3.1", profile = "baseline", refs = 3 },
    high     = { bitrate = 9500000,  audio = 256000, level = "3.1", profile = "high",     refs = 5 },
    veryhigh = { bitrate = 14000000, audio = 256000, level = "3.1", profile = "high",     refs = 16 },
  },
  ["1080"] = {
    low      = { bitrate = 3500000,  audio = 128000, level = "3.1", profile = "baseline", refs = 1 },
    medium   = { bitrate = 7000000,  audio = 192000, level = "3.1", profile = "baseline", refs = 3 },
    high     = { bitrate = 14000000, audio = 256000, level = "4.0", profile = "high",     refs = 5 },
    veryhigh = { bitrate = 21000000, audio = 256000, level = "4.0", profile = "high",     refs = 16 },
  },
}
            --[[ State ]]--

local app = {
  server = nil,        -- normalized base URL of the connected server
  token = nil,         -- API key, or the AccessToken a login returned
  last_server = "https://",
  last_key = "",
  last_user = "",
  remember = false,

  all_items = {},      -- every Movie/Series of the library
  category = "Movie",  -- current library tab: "Movie" or "Series"
  shown = {},          -- list row id -> item currently displayed
  genres = {},         -- genre dropdown id -> genre name

  channels = nil,      -- live TV line-up, fetched on the first visit
  channels_shown = {}, -- live list row id -> channel
  channels_epg = false, -- a channel says what is on right now: guide column
  live_source_id = nil, -- media source the tuner was opened on
  live_stream_id = nil, -- what keeps that tuner tuned

  series = nil,        -- item of the series being browsed
  seasons = {},        -- season list row id -> season item
  season = nil,        -- season being browsed
  episodes = {},       -- episode list row id -> episode item
  seasons_count = 0,   -- back target: 1 season goes straight to library

  -- Sections start folded: opened all at once they make a window taller
  -- than a small screen, and each visit usually needs only one of them.
  -- What the user leaves open is remembered.
  show_desc = false,
  show_direct = false,
  show_transcode = false,

  media = nil,         -- item opened in the playback view
  audio_tracks = {},   -- dropdown id -> stream index
  sub_tracks = {},     -- dropdown id -> stream index
  runtime_ticks = nil, -- duration of the opened media
}

local dlg = nil
local ui = {}

            --[[ VLC entry points ]]--

function descriptor()
  return {
    title = "Jellyfin",
    version = "1.0",
    author = "PowerVLC",
    url = "https://jellyfin.org/",
    shortdesc = "Jellyfin",
    description = "Browse a Jellyfin server and play its movies, "
               .. "series and live TV channels, either as-is or "
               .. "transcoded at the chosen quality (HLS).",
    capabilities = {}
  }
end

function activate()
  load_lang()
  vlc.msg.dbg("[Jellyfin] Welcome")
  json = require("dkjson")
  load_settings()
  show_connect()
end

function deactivate()
  vlc.msg.dbg("[Jellyfin] Bye")
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

            --[[ Helpers ]]--

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- Long work has to say it is still there. The core watches the extension
-- thread and, after ten seconds without a sign of life, offers to kill
-- it -- and kills it outright when it cannot even show that question.
-- A slow server or a big library is not a hung script.
local function still_alive()
  if vlc.keep_alive then
    pcall(vlc.keep_alive)
  end
end

local function set_message(text)
  if ui.message then
    ui.message:set_text(text or "")
    -- push the update to the interface NOW: without this, a message set
    -- right before a blocking network call only shows once the call ends
    if dlg then
      dlg:update()
    end
  end
end

-- HTTP(S) GET through VLC's stream layer.
-- Returns the raw body or nil, error-string.
local function get_body(url)
  vlc.msg.dbg("[Jellyfin] GET " .. url)
  local ok, stream, msg = pcall(vlc.stream, url)
  if not ok or not stream then
    return nil, tostring(msg or stream or "stream error")
  end
  local parts = {}
  while true do
    still_alive()
    local chunk = stream:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      break
    end
    table.insert(parts, chunk)
  end
  local body = table.concat(parts)
  if #body == 0 then
    return nil, "empty response"
  end
  return body
end

local function esc(value)
  return vlc.strings.encode_uri_component(tostring(value))
end

-- GET an API endpoint, ApiKey included, decoded as JSON.
-- params is an ordered list of "Name=value" strings (already encoded).
local function api_get(path, params)
  local url = app.server .. path .. "?ApiKey=" .. esc(app.token)
  for _, p in ipairs(params or {}) do
    url = url .. "&" .. p
  end
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  local obj, _, jerr = json.decode(body)
  if obj == nil then
    return nil, tostring(jerr or "invalid JSON")
  end
  return obj
end

-- POST an API endpoint the same way, for the few calls that are not a
-- GET. Everything goes in the query string and the body stays empty:
-- the endpoints used here take their arguments either way, and it saves
-- encoding a JSON document to say one word.
local function api_post(path, params)
  if not (vlc.http and vlc.http.post) then
    -- technical, and left in English on purpose: it names the binding
    -- that is missing, which is not something to translate
    return nil, "no vlc.http"
  end
  local url = app.server .. path .. "?ApiKey=" .. esc(app.token)
  for _, p in ipairs(params or {}) do
    url = url .. "&" .. p
  end
  vlc.msg.dbg("[Jellyfin] POST " .. url)
  local status, answer = vlc.http.post(url, "", "application/json")
  if not status then
    return nil, tostring(answer)
  end
  if status ~= 200 then
    return nil, "HTTP " .. status
  end
  local obj, _, jerr = json.decode(answer or "")
  if type(obj) ~= "table" then
    return nil, tostring(jerr or "invalid JSON")
  end
  return obj
end

-- one table cell: tabs are the column separator, so strip them
local function cell(s)
  return (string.gsub(tostring(s or "?"), "[\t\r\n\031]", " "))
end

-- A cell the interface must sort on a real value rather than on its
-- label: "display\031key". Numbers then sort numerically whatever
-- their displayed form.
local function sortable(display, key)
  if not key then
    return cell(display)
  end
  return cell(display) .. "\031" .. tostring(key)
end

-- 10 000 000 ticks per second on Jellyfin
local function format_ticks(ticks)
  if type(ticks) ~= "number" or ticks <= 0 then
    return nil
  end
  local total = math.floor(ticks / 10000000)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function format_bytes(bytes)
  if type(bytes) ~= "number" or bytes <= 0 then
    return nil
  end
  if bytes >= 1073741824 then
    return string.format("%.1f", bytes / 1073741824) .. " GiB"
  end
  if bytes >= 1048576 then
    return math.floor(bytes / 1048576) .. " MiB"
  end
  return math.floor(bytes / 1024) .. " KiB"
end

local function format_bitrate(bps)
  if type(bps) ~= "number" or bps <= 0 then
    return nil
  end
  if bps >= 1000000 then
    return string.format("%.1f", bps / 1000000) .. " Mb/s"
  end
  return math.floor(bps / 1000) .. " kb/s"
end

-- Searching for "odyssee" must find "L'Odyssée": accents are folded on
-- both sides. string.lower only knows ASCII, so the upper-case forms are
-- listed too -- each is two bytes in UTF-8, matched as a whole.
local ACCENT_FOLD = {
  ["à"]="a", ["â"]="a", ["ä"]="a", ["á"]="a", ["ã"]="a", ["å"]="a",
  ["À"]="a", ["Â"]="a", ["Ä"]="a", ["Á"]="a", ["Ã"]="a", ["Å"]="a",
  ["ç"]="c", ["Ç"]="c",
  ["è"]="e", ["é"]="e", ["ê"]="e", ["ë"]="e",
  ["È"]="e", ["É"]="e", ["Ê"]="e", ["Ë"]="e",
  ["ì"]="i", ["í"]="i", ["î"]="i", ["ï"]="i",
  ["Ì"]="i", ["Í"]="i", ["Î"]="i", ["Ï"]="i",
  ["ñ"]="n", ["Ñ"]="n",
  ["ò"]="o", ["ó"]="o", ["ô"]="o", ["õ"]="o", ["ö"]="o",
  ["Ò"]="o", ["Ó"]="o", ["Ô"]="o", ["Õ"]="o", ["Ö"]="o",
  ["ù"]="u", ["ú"]="u", ["û"]="u", ["ü"]="u",
  ["Ù"]="u", ["Ú"]="u", ["Û"]="u", ["Ü"]="u",
  ["ý"]="y", ["ÿ"]="y", ["Ý"]="y",
  ["æ"]="ae", ["Æ"]="ae", ["œ"]="oe", ["Œ"]="oe", ["ß"]="ss",
}

-- vlc.strings.fold is the very folding the playlist search field uses,
-- and it reaches much further than the table above: Latin Extended-A,
-- decomposed accents, typographic quotes and dashes. The table stays as
-- the fallback for a build that predates it.
local function fold_accents(s)
  s = s or ""
  local core_fold = vlc.strings and vlc.strings.fold
  if core_fold then
    local ok, folded = pcall(core_fold, s)
    if ok and folded then
      return folded
    end
  end
  s = string.lower(s)
  return (string.gsub(s, "[\194-\223][\128-\191]", function(c)
    return ACCENT_FOLD[c] or c
  end))
end

-- Long overviews would stretch the dialog: keep the first words only
local function shorten(text, max)
  text = trim(string.gsub(text or "", "%s+", " "))
  if #text <= max then
    return text
  end
  local cut = string.sub(text, 1, max)
  -- never cut inside a UTF-8 sequence (continuation bytes are 8x/Bx)
  while #cut > 0 and string.byte(cut, #cut) >= 128
                 and string.byte(cut, #cut) < 192 do
    cut = string.sub(cut, 1, #cut - 1)
  end
  cut = string.match(cut, "^(.*)%s%S*$") or cut
  return cut .. "…"
end

-- vlc.clipboard is this fork's native API (macOS + Windows); on other
-- platforms it reports failure and the URL stays selectable in the field.
local function copy_to_clipboard(text)
  if vlc.clipboard and vlc.clipboard.set then
    return vlc.clipboard.set(text)
  end
  return false
end

function close_dlg()
  if dlg ~= nil then
    dlg:hide()
    -- Delete here and now rather than leaving it to the garbage
    -- collector: the finalizer blocks until the interface has destroyed
    -- the window, and a finalizer runs at whatever allocation happens to
    -- trigger a collection -- possibly in the middle of building the
    -- next dialog.
    dlg:delete()
  end
  dlg = nil
  ui = {}
end

            --[[ Saved connection ]]--

local function normalize_server_url(url)
  url = trim(url)
  if url == "" or url == "https://" or url == "http://" then
    return nil
  end
  if not string.match(url, "^https?://") then
    url = "https://" .. url
  end
  return (string.gsub(url, "/+$", ""))
end


-- Same idea as JellyDinosaur's "remember" checkbox, in two halves: the
-- secret (API key, or the token a sign-in returned) goes to the system
-- keystore -- Keychain on macOS, Secret Service or KWallet on Linux, an
-- encrypted store on Windows -- and only what is not secret, the address
-- and the account name, to a small file next to VLC's other user data.
-- The password itself is never kept anywhere.
local KEYSTORE_USER = "api-key"
local KEYSTORE_LABEL = "PowerVLC — Jellyfin"

local function settings_path()
  local dir = vlc.config.userdatadir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/jellyfin.json"
end

-- The keystore indexes on the server, so each Jellyfin gets its own
-- entry and switching between two servers keeps both keys.
local function keystore_service(server)
  return "jellyfin-powervlc://" .. string.gsub(server or "", "^%w+://", "")
end

local function have_keystore()
  return vlc.keystore ~= nil and vlc.keystore.find ~= nil
end

local function load_secret(server)
  if not have_keystore() then
    return nil
  end
  return vlc.keystore.find(keystore_service(server), KEYSTORE_USER)
end

local function save_secret(server, secret)
  if not have_keystore() then
    return false
  end
  -- store() replaces an entry with the same key, so no need to remove first
  if not vlc.keystore.store(keystore_service(server), KEYSTORE_USER,
                            secret, KEYSTORE_LABEL) then
    return false
  end
  -- Prove it can be read back before trusting it: macOS lets an
  -- application that is not signed with a stable identity write to the
  -- Keychain, then refuses to let it read what it wrote. An entry we
  -- cannot use is worse than none, so drop it and say so.
  if load_secret(server) ~= secret then
    vlc.keystore.remove(keystore_service(server), KEYSTORE_USER)
    return false
  end
  return true
end

local function forget_secret(server)
  if have_keystore() then
    vlc.keystore.remove(keystore_service(server), KEYSTORE_USER)
  end
end

-- Transcoding choices are not secret and not per-server: they describe
-- what this machine can play, so they live in the settings file and are
-- restored the next time a content is opened.
local function load_prefs(obj)
  local p = obj.transcode
  if type(p) ~= "table" then
    return
  end
  app.prefs_touched = true
  if type(p.resolution) == "string" and QUALITY_PRESETS[p.resolution] then
    app.pref_resolution = p.resolution
  end
  if type(p.quality) == "string" then
    for _, key in ipairs(QUALITY_KEYS) do
      if key == p.quality then
        app.pref_quality = key
      end
    end
  end
  if type(p.bitrate) == "number" and p.bitrate > 0 then
    app.pref_bitrate = math.floor(p.bitrate)
  end
  if type(p.audio_bitrate) == "number" then
    for _, rate in ipairs(AUDIO_BITRATES) do
      if rate == p.audio_bitrate then
        app.pref_audio_bitrate = p.audio_bitrate
      end
    end
  end
  -- which sections were left open
  if type(p.show_desc) == "boolean" then app.show_desc = p.show_desc end
  if type(p.show_direct) == "boolean" then app.show_direct = p.show_direct end
  if type(p.show_transcode) == "boolean" then
    app.show_transcode = p.show_transcode
  end
end

function load_settings()
  local path = settings_path()
  if not path then
    return
  end
  local f = io.open(path, "r")
  if not f then
    return
  end
  local body = f:read("*a")
  f:close()
  local obj = json.decode(body or "")
  if type(obj) ~= "table" then
    return
  end
  load_prefs(obj)
  if type(obj.server) == "string" and obj.server ~= "" then
    app.last_server = obj.server
  end
  if type(obj.username) == "string" then
    app.last_user = obj.username
  end
  app.remember = obj.remember and true or false

  -- Secrets written by an earlier version sat in this very file; move
  -- them to the keystore and take them out of the clear.
  if type(obj.token) == "string" and obj.token ~= "" then
    if save_secret(app.last_server, obj.token) then
      app.last_key = obj.token
      obj.token = nil
      local out = io.open(path, "w")
      if out then
        out:write(json.encode({ server = app.last_server,
                                username = app.last_user,
                                remember = app.remember }, { indent = true }))
        out:close()
      end
    else
      app.last_key = obj.token
    end
  elseif app.remember then
    app.last_key = load_secret(app.last_server) or ""
    -- The keystore took it but will not give it back -- on macOS an
    -- application that is not signed with a stable identity can write to
    -- the Keychain and still be denied when it reads. It can happen on a
    -- later run only, so give up on it for good rather than lose the key
    -- again: from now on this server is saved as clear text.
    if app.last_key == "" and obj.keystore then
      app.secret_denied = true
      app.keystore_broken = true
      forget_secret(app.last_server)
    end
  end
  if obj.keystore_broken then
    app.keystore_broken = true
  end
end

-- What goes in the file besides the connection: kept apart so that
-- saving the transcoding choices never touches the credentials.
local function prefs_table()
  -- nothing chosen yet: an empty table would be written out as an empty
  -- JSON array, which is not what would be read back. Folding a section
  -- counts as a choice, so a flag rather than a look at the values --
  -- those are booleans, and false is a choice too.
  if not app.prefs_touched then
    return nil
  end
  return {
    resolution = app.pref_resolution,
    quality = app.pref_quality,
    bitrate = app.pref_bitrate,
    audio_bitrate = app.pref_audio_bitrate,
    show_desc = app.show_desc,
    show_direct = app.show_direct,
    show_transcode = app.show_transcode,
  }
end

-- Called whenever a transcoding setting changes. The connection part of
-- the file is left exactly as it was, including when nothing is
-- remembered: the settings then live on their own.
function save_prefs()
  app.prefs_touched = true
  local path = settings_path()
  if not path then
    return
  end
  local obj = {}
  local f = io.open(path, "r")
  if f then
    obj = json.decode(f:read("*a") or "") or {}
    f:close()
  end
  obj.transcode = prefs_table()

  f = io.open(path, "w")
  if not f then
    return
  end
  f:write(json.encode(obj, { indent = true }))
  f:close()
end

function save_settings()
  local path = settings_path()
  if not path then
    return
  end
  if not app.remember then
    forget_secret(app.server)
    -- the transcoding choices are not a credential: they stay
    local f = io.open(path, "w")
    if f then
      f:write(json.encode({ transcode = prefs_table() }, { indent = true }))
      f:close()
    end
    return
  end

  local stored = not app.keystore_broken and save_secret(app.server, app.token)
  -- Falling back to the clear-text file is a choice the user gets to see:
  -- the warning is shown on the very screen the connection lands on.
  app.secret_plain = not stored
  local f = io.open(path, "w")
  if not f then
    return
  end
  f:write(json.encode({
    server = app.server,
    username = app.last_user,
    -- only ever written when the keystore turned the secret down: better
    -- a remembered connection than a silently forgotten one
    token = (not stored) and app.token or nil,
    keystore = stored or nil,
    keystore_broken = app.keystore_broken or nil,
    transcode = prefs_table(),
    remember = true,
  }, { indent = true }))
  f:close()
end

            --[[ View 1: connection ]]--

-- Titles and overviews are long; the natural width of the widgets
-- truncates them. Ask for room up front (a hint: the user can still
-- resize, and the interface may need more).
local DIALOG_WIDTH = 720
local DIALOG_HEIGHT = 460

-- Overview: how many characters fit on a line, and how many lines are
-- worth showing before it stops being a summary. Sized for the widest
-- font any interface uses (the legacy one, around 11 points a character)
-- so that the paragraph never drags the window past DIALOG_WIDTH.
-- Where the lines break is the interface's business; how much text there
-- is, is ours. Past this a synopsis stops being a summary.
local OVERVIEW_MAX_CHARS = 420
-- Bounds asked of the server. Both matter: a poster is 2:3 and a height
-- alone would do, but an episode is illustrated by a still from it, and
-- 16:9 at that height would be wider than the text beside it. A third of
-- the dialog is as much as a picture may take.
local ARTWORK_HEIGHT = 260
local ARTWORK_WIDTH = 220

-- Where the server lives, then how to sign in: two separate steps, and
-- one button per authentication method rather than a single button that
-- has to guess which of the two the user meant.
function show_connect()
  close_dlg()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(DIALOG_WIDTH, 0)

  dlg:add_label(lang.sec_server, 1, 1, 3, 1)
  dlg:add_label(lang.lbl_server, 1, 2, 1, 1)
  -- Enter in the address field goes on with whichever method is filled in
  ui.server = dlg:add_text_input(app.last_server, 2, 2, 2, 1, click_connect)
  dlg:add_label(lang.hint_server, 1, 3, 3, 1)

  dlg:add_label(lang.sec_api_key, 1, 4, 3, 1)
  dlg:add_label(lang.lbl_api_key, 1, 5, 1, 1)
  ui.api_key = dlg:add_text_input(app.last_key, 2, 5, 2, 1, click_connect_key)

  dlg:add_label(lang.sec_account, 1, 6, 3, 1)
  dlg:add_label(lang.lbl_username, 1, 7, 1, 1)
  ui.username = dlg:add_text_input(app.last_user, 2, 7, 2, 1,
                                   click_connect_account)
  dlg:add_label(lang.lbl_password, 1, 8, 1, 1)
  ui.password = dlg:add_password("", 2, 8, 2, 1, click_connect_account)

  ui.remember = dlg:add_check_box(lang.chk_remember, app.remember, 1, 9, 3, 1)
  dlg:add_button(lang.btn_forget, click_forget, 1, 10, 3, 1)
  -- both ways to sign in sit together, right under the forget button
  dlg:add_button(lang.btn_connect_key, click_connect_key, 1, 11, 1, 1)
  dlg:add_button(lang.btn_connect_account, click_connect_account, 2, 11, 2, 1)
  ui.message = dlg:add_label("", 1, 12, 3, 1)
  dlg:show()
  if app.secret_denied then
    set_message(lang.msg_keystore_denied)
  end
end

-- Empties the fields and the file behind them, so that nothing of this
-- server is left on the machine.
function click_forget()
  app.remember = false
  -- the entry is filed under the server, so forget it before losing it
  forget_secret(normalize_server_url(ui.server:get_text()) or app.last_server)
  forget_secret(app.server)
  app.last_server = "https://"
  app.last_key = ""
  app.last_user = ""
  local path = settings_path()
  if path then
    os.remove(path)
  end
  ui.server:set_text(app.last_server)
  ui.api_key:set_text("")
  ui.username:set_text("")
  ui.password:set_text("")
  ui.remember:set_checked(false)
  set_message(lang.msg_forgotten)
end

-- POST /Users/AuthenticateByName; its AccessToken is then used exactly
-- like an API key (same ApiKey= parameter on every other request).
local function login_with_password(server, user, pass)
  if not (vlc.http and vlc.http.post) then
    return nil, lang.msg_no_http_post
  end
  local auth = 'MediaBrowser Client="' .. CLIENT_NAME
            .. '", Device="' .. DEVICE_NAME
            .. '", DeviceId="' .. DEVICE_ID
            .. '", Version="' .. client_version() .. '"'
  local status, body = vlc.http.post(server .. "/Users/AuthenticateByName",
    json.encode({ Username = user, Pw = pass }),
    "application/json", auth)
  if not status then
    return nil, lang.msg_login_fail .. tostring(body)
  end
  if status == 401 then
    return nil, lang.msg_bad_credentials
  end
  if status ~= 200 then
    return nil, lang.msg_login_fail .. "HTTP " .. status
  end
  local obj = json.decode(body)
  if type(obj) ~= "table" or type(obj.AccessToken) ~= "string" then
    return nil, lang.msg_login_fail .. "AccessToken?"
  end
  return obj.AccessToken
end

-- Enter in the address field: continue with whichever method carries
-- something, the key first since a remembered connection comes back as
-- a token in that very field.
function click_connect()
  if trim(ui.api_key:get_text()) ~= "" then
    click_connect_key()
  else
    click_connect_account()
  end
end

function click_connect_key()
  local key = trim(ui.api_key:get_text())
  if key == "" then
    set_message(lang.msg_enter_key)
    return
  end
  -- A Jellyfin AccessToken is used exactly like an API key, so a
  -- remembered account connection also comes back through here.
  connect(key, nil)
end

function click_connect_account()
  local user = trim(ui.username:get_text())
  local pass = ui.password:get_text()
  if user == "" or pass == "" then
    set_message(lang.msg_enter_account)
    return
  end
  connect(nil, { user = user, pass = pass })
end

-- key is an API key or a token; account is { user, pass }. Exactly one
-- of the two is given.
function connect(key, account)
  local server = normalize_server_url(ui.server:get_text())
  if not server then
    set_message(lang.msg_enter_server)
    return
  end
  app.remember = ui.remember:get_checked()
  app.last_server = server
  app.last_user = account and account.user or app.last_user

  -- Same first step as JellyDinosaur: /System/Ping needs no key and
  -- tells a wrong address apart from wrong credentials.
  set_message(lang.msg_pinging)
  local body, err = get_body(server .. "/System/Ping")
  if not body then
    set_message(lang.msg_ping_fail .. tostring(err))
    return
  end
  if not string.find(body, "Jellyfin", 1, true) then
    set_message(lang.msg_not_jellyfin)
    return
  end

  -- An account signs in; otherwise the key is used as-is. The library
  -- request below is what actually validates the key (again like
  -- JellyDinosaur, whose API key path has no separate check).
  if account then
    set_message(lang.msg_logging_in)
    local token, lerr = login_with_password(server, account.user, account.pass)
    if not token then
      set_message(lerr)
      return
    end
    app.token = token
  else
    app.token = key
    app.last_key = key
  end
  app.server = server

  set_message(lang.msg_loading_library)
  local obj, gerr = api_get("/Items", {
    "IncludeItemTypes=Movie,Series",
    "Recursive=true",
    "StartIndex=0",
    "SortBy=SortName,ProductionYear",
    "SortOrder=Ascending",
    "Fields=Genres,Overview",
  })
  if not obj or type(obj.Items) ~= "table" then
    -- The stream layer only reports "could not open": ask the server
    -- again without any key to tell a refused key (the usual case, and
    -- a saved token does get revoked) from a network failure.
    if get_body(server .. "/System/Ping") then
      set_message(lang.msg_bad_key)
    else
      set_message(lang.msg_library_fail .. tostring(gerr or "?"))
    end
    return
  end

  app.all_items = obj.Items
  -- another server has another line-up: fetched again on the first visit
  app.channels = nil
  save_settings()
  app.category = "Movie"
  show_library()
end

            --[[ View 2: library ]]--

local function category_items()
  local items = {}
  for _, item in ipairs(app.all_items) do
    if item.Type == app.category then
      table.insert(items, item)
    end
  end
  return items
end

-- The genre dropdown is rebuilt for the current category, like
-- JellyDinosaur's per-category genre filter.
local function fill_genres()
  app.genres = {}
  ui.genre:clear()
  ui.genre:add_value(lang.all_genres, 1)
  local seen, names = {}, {}
  local walked = 0
  for _, item in ipairs(category_items()) do
    walked = walked + 1
    if walked % 500 == 0 then
      still_alive()
    end
    for _, g in ipairs(item.Genres or {}) do
      if not seen[g] then
        seen[g] = true
        table.insert(names, g)
      end
    end
  end
  table.sort(names)
  for i, name in ipairs(names) do
    app.genres[i + 1] = name
    ui.genre:add_value(name, i + 1)
  end
end

-- Filters are applied when the list is (re)filled: the search field on
-- Enter, the genre dropdown through the Filter button — dropdowns have
-- no change callback.
local function fill_library()
  app.shown = {}
  ui.items:clear()
  local query = fold_accents(trim(ui.search:get_text()))
  local genre = app.genres[ui.genre:get_value()]

  local items = category_items()
  local shown = 0
  local seen_rows = 0
  for _, item in ipairs(items) do
    -- a library of a few thousand titles takes a while to walk: say so
    -- to the watchdog rather than be taken for a hung script
    seen_rows = seen_rows + 1
    if seen_rows % 500 == 0 then
      still_alive()
    end
    local ok = true
    if query ~= "" then
      local hay = fold_accents(item.Name or "")
      ok = string.find(hay, query, 1, true) ~= nil
    end
    if ok and genre then
      ok = false
      for _, g in ipairs(item.Genres or {}) do
        if g == genre then
          ok = true
          break
        end
      end
    end
    if ok then
      shown = shown + 1
      app.shown[shown] = item
      ui.items:add_value(
        cell(item.Name) .. "\t"
        .. sortable(item.ProductionYear or "", item.ProductionYear or 0)
        .. "\t" .. cell(table.concat(item.Genres or {}, ", ")),
        shown)
    end
  end
  set_message(string.format(lang.msg_count, shown, #items))
end

function show_library()
  close_dlg()
  dlg = vlc.dialog(lang.title_library)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  -- the two categories work like JellyDinosaur's Movies/Series entries;
  -- live TV sits beside them but is a view of its own -- a channel has
  -- no year and no genre, and what it shows is what is on right now
  dlg:add_button(lang.btn_movies, click_movies, 1, 1, 1, 1)
  dlg:add_button(lang.btn_series, click_series, 2, 1, 1, 1)
  dlg:add_button(lang.btn_live, click_live, 3, 1, 1, 1)
  dlg:add_label(lang.lbl_search, 1, 2, 1, 1)
  -- filters as the user types, no button to press: bursts of keystrokes
  -- are folded into a single pass by the command queue
  ui.search = dlg:add_text_input("", 2, 2, 2, 1, fill_library, fill_library)
  dlg:add_label(lang.lbl_genre, 1, 3, 1, 1)
  ui.genre = dlg:add_dropdown(2, 3, 2, 1, fill_library)
  -- double-clicking an item opens it (movie playback / series seasons)
  ui.items = dlg:add_list(1, 4, 3, 1, click_open_item)
  ui.items:set_text(lang.col_title .. "\t" .. lang.col_year
                    .. "\t" .. lang.col_genres)
  -- the order is stated rather than inherited from the server: a library
  -- should read the same way every time it is opened, whatever the API
  -- happened to return first. Survives a refill, so saying it once is
  -- enough; the user can still re-sort by clicking a column header.
  ui.items:set_sort(1, true)
  dlg:add_button(lang.btn_open, click_open_item, 1, 5, 1, 1)
  dlg:add_button(lang.btn_change_server, show_connect, 2, 5, 1, 1)
  ui.message = dlg:add_label("", 1, 6, 3, 1)
  fill_genres()
  fill_library()
  dlg:show()
  -- Said once, on the screen the connection lands on: the key had to be
  -- written in the clear because the keystore would not keep it.
  if app.secret_plain then
    set_message(string.format(lang.msg_secret_plain,
                              settings_path() or "?"))
    app.secret_plain = false
  end
end

function click_movies()
  app.category = "Movie"
  fill_genres()
  fill_library()
end

function click_series()
  app.category = "Series"
  fill_genres()
  fill_library()
end

local function selected_row(list, store)
  for id in pairs(list:get_selection()) do
    if store[id] then
      return store[id]
    end
  end
  return nil
end

function click_open_item()
  local item = selected_row(ui.items, app.shown)
  if not item then
    set_message(lang.msg_select_first)
    return
  end
  if item.Type == "Series" then
    open_series(item)
  else
    open_playback(item, nil)
  end
end

            --[[ View 2b: live TV ]]--

-- A channel is not a file: no duration, no track list, no year, and its
-- own two ways of being played. Everything that has to tell them apart
-- asks the item itself rather than carrying a flag along.
local function is_live(media)
  return media ~= nil and media.Type == "TvChannel"
end

-- Channel numbers are strings, and "10" sorts before "9" as text. The
-- rows carry the number as their sort key so the column reads the way a
-- remote control does; a channel without one goes to the end.
local function channel_number_key(ch)
  return tonumber(ch.Number or ch.ChannelNumber or "") or 999999
end

-- "2026-08-07T18:47:48.0000000Z" -> "18:47" in the machine's own time.
-- The epoch is worked out here rather than handed to os.time, which
-- reads its fields as local time and would need the offset guessed back;
-- os.date then does the one conversion that is left, with the zone rules
-- of the platform. Jellyfin dates the guide in UTC, always.
local function iso_to_clock(iso)
  local y, mo, d, h, mi = string.match(tostring(iso or ""),
                                       "^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then
    return nil
  end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  -- days since 1970-01-01, by the civil-calendar algorithm: March-based
  -- years make the leap day the last of them, so no month table is needed
  local year = y - ((mo <= 2) and 1 or 0)
  local era = math.floor(year / 400)
  local yoe = year - era * 400
  local doy = math.floor((153 * (mo + ((mo > 2) and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  local days = era * 146097 + doe - 719468
  return os.date("%H:%M",
                 days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60)
end

-- What is on the channel right now, when the server has a guide at all.
local function now_on_air(ch)
  local p = ch.CurrentProgram
  if type(p) ~= "table" then
    return ""
  end
  local text = p.Name or ""
  if p.EpisodeTitle and p.EpisodeTitle ~= "" then
    text = text .. " — " .. p.EpisodeTitle
  end
  local from, to = iso_to_clock(p.StartDate), iso_to_clock(p.EndDate)
  if from and to then
    text = text .. " (" .. from .. "–" .. to .. ")"
  end
  return text
end

-- Fetched once per connection: a tuner line-up does not change while a
-- window is open, and several hundred channels are enough JSON that
-- parsing them again on every visit would be felt.
local function fetch_channels()
  if app.channels then
    return true
  end
  set_message(lang.msg_loading_channels)
  local obj, err = api_get("/LiveTv/Channels", {
    "SortBy=SortName",
    "SortOrder=Ascending",
    -- what is on right now, and nothing else: a guide the server does
    -- not have costs nothing, and every other field is JSON this machine
    -- would have to parse for all of the line-up
    "AddCurrentProgram=true",
    "EnableUserData=false",
    "EnableImageTypes=Primary",
    "ImageTypeLimit=1",
  })
  if not obj or type(obj.Items) ~= "table" then
    set_message(lang.msg_live_fail .. tostring(err or "?"))
    return false
  end
  app.channels = obj.Items
  -- A server without a guide answers with channels and no programme at
  -- all; the column is then a column of blanks, so it is not shown.
  app.channels_epg = false
  for _, ch in ipairs(obj.Items) do
    if type(ch.CurrentProgram) == "table" then
      app.channels_epg = true
      break
    end
  end
  return true
end

local function fill_channels()
  app.channels_shown = {}
  ui.channels:clear()
  local query = fold_accents(trim(ui.live_search:get_text()))
  local shown, seen = 0, 0
  for _, ch in ipairs(app.channels or {}) do
    -- a line-up runs to several hundred entries: same watchdog courtesy
    -- as the library list
    seen = seen + 1
    if seen % 500 == 0 then
      still_alive()
    end
    local ok = true
    if query ~= "" then
      ok = string.find(fold_accents(ch.Name or ""), query, 1, true) ~= nil
    end
    if ok then
      shown = shown + 1
      app.channels_shown[shown] = ch
      local row = sortable(ch.Number or ch.ChannelNumber or "",
                           channel_number_key(ch))
              .. "\t" .. cell(ch.Name)
      if app.channels_epg then
        row = row .. "\t" .. cell(now_on_air(ch))
      end
      ui.channels:add_value(row, shown)
    end
  end
  set_message(string.format(lang.msg_channel_count, shown,
                            #(app.channels or {})))
end

function click_live()
  if not fetch_channels() then
    return
  end
  -- Nothing to open a window on: a server with no tuner says so where
  -- the button was pressed rather than in an empty list.
  if #app.channels == 0 then
    set_message(lang.msg_no_live)
    return
  end
  show_live()
end

function show_live()
  close_dlg()
  dlg = vlc.dialog(lang.title_live)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  dlg:add_label(lang.lbl_search, 1, 1, 1, 1)
  ui.live_search = dlg:add_text_input("", 2, 1, 2, 1,
                                      fill_channels, fill_channels)
  ui.channels = dlg:add_list(1, 2, 3, 1, click_open_channel)
  local head = lang.col_number .. "\t" .. lang.col_channel
  if app.channels_epg then
    head = head .. "\t" .. lang.col_now
  end
  ui.channels:set_text(head)
  -- by channel number, through the sort key: 2 before 10
  ui.channels:set_sort(1, true)
  dlg:add_button(lang.btn_open, click_open_channel, 1, 3, 1, 1)
  dlg:add_button(lang.btn_back_library, show_library, 2, 3, 1, 1)
  ui.message = dlg:add_label("", 1, 4, 3, 1)
  fill_channels()
  dlg:show()
end

function click_open_channel()
  local ch = selected_row(ui.channels, app.channels_shown)
  if not ch then
    set_message(lang.msg_select_first)
    return
  end
  open_playback(ch, nil)
end

-- A tuner has to be told to tune before anything can be asked of it:
-- PlaybackInfo hands out an OpenToken, LiveStreams/Open turns it into a
-- live stream id, and both URLs then carry that id and the media source
-- it names -- not the channel's own.
--
-- ⚠⚠⚠ This is not paperwork. On a tuner that pulls from the local
-- network (udpxy relaying multicast, measured) the server answers
-- NOTHING without it: the direct stream gives 0 byte in 40 s and
-- live.m3u8 is cut off by the reverse proxy after 60 s (504). The same
-- URLs, opened first, serve a real TS in 6 s. What made this look
-- unnecessary is that another tuner -- an m3u playlist of remote HLS --
-- did serve both with no opening at all, cold channels included.
--
-- The stream is never closed: the extension is not told when playback
-- stops, and closing one the player is still reading would kill it. The
-- server reaps an idle live stream on its own (and this one's
-- LiveStreams/Close answers 400 anyway).
local function open_live_stream(channel)
  app.live_source_id, app.live_stream_id, app.live_container = nil, nil, nil
  local info, err = api_get("/Items/" .. channel.Id .. "/PlaybackInfo", {})
  local source = info and type(info.MediaSources) == "table"
                 and info.MediaSources[1] or nil
  if not source then
    return nil, tostring(err or "?")
  end
  -- a source that hands out no token is used as it stands
  if type(source.OpenToken) ~= "string" then
    return source, nil
  end
  still_alive()
  local obj, perr = api_post("/LiveStreams/Open",
                             { "openToken=" .. esc(source.OpenToken) })
  if not obj or type(obj.MediaSource) ~= "table" then
    -- Say so: the fallback below only works on the tuners that never
    -- needed this, and elsewhere playback would simply never start.
    return source, tostring(perr or "?")
  end
  app.live_source_id = obj.MediaSource.Id
  app.live_stream_id = obj.MediaSource.LiveStreamId
  -- What the tuner actually hands over, which decides how it can be
  -- played untouched (see direct_play_url). Only known once opened: the
  -- item says nothing, and PlaybackInfo alone answers null.
  app.live_container = string.lower(tostring(obj.MediaSource.Container or ""))
  -- Opening probes the source, so this is also the only description of
  -- the channel there is: codec and size, where the item had none.
  return obj.MediaSource, nil
end

-- What the URLs must name: the media source the tuner was opened on,
-- and the stream that keeps it open. A channel that needed no opening
-- falls back to its own id, which is what an m3u tuner answers to.
local function live_source_params()
  local params = "&mediaSourceId=" .. esc(app.live_source_id or app.media.Id)
  if app.live_stream_id then
    params = params .. "&liveStreamId=" .. esc(app.live_stream_id)
  end
  return params
end

            --[[ View 3: seasons and episodes ]]--

local function season_label(season)
  if season.Name and season.Name ~= "" then
    return season.Name
  end
  return string.format(lang.season_fmt, season.IndexNumber or 0)
end

function open_series(item)
  set_message(lang.msg_loading_seasons)
  local obj, err = api_get("/Shows/" .. item.Id .. "/Seasons", {})
  if not obj or type(obj.Items) ~= "table" then
    set_message(lang.msg_library_fail .. tostring(err or "?"))
    return
  end
  app.series = item
  app.seasons = {}
  app.seasons_count = #obj.Items
  for i, season in ipairs(obj.Items) do
    app.seasons[i] = season
  end
  if app.seasons_count == 0 then
    set_message(lang.msg_no_content)
    return
  end
  -- a single season would make this view a one-line detour: skip it
  if app.seasons_count == 1 then
    open_season(app.seasons[1])
    return
  end
  show_seasons()
end

function show_seasons()
  close_dlg()
  dlg = vlc.dialog(lang.title_seasons)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  dlg:add_label(cell(app.series.Name), 1, 1, 3, 1)
  ui.seasons = dlg:add_list(1, 2, 3, 1, click_open_season)
  ui.seasons:set_text(lang.col_season)
  -- by season number: the rows carry it as their sort key, so this orders
  -- them 1, 2, ... 10 and not 1, 10, 2
  ui.seasons:set_sort(1, true)
  for i, season in ipairs(app.seasons) do
    ui.seasons:add_value(
      sortable(season_label(season), season.IndexNumber or i), i)
  end
  dlg:add_button(lang.btn_open, click_open_season, 1, 3, 1, 1)
  dlg:add_button(lang.btn_back_library, show_library, 2, 3, 1, 1)
  ui.message = dlg:add_label("", 1, 4, 3, 1)
  dlg:show()
end

function click_open_season()
  local season = selected_row(ui.seasons, app.seasons)
  if not season then
    set_message(lang.msg_select_first)
    return
  end
  open_season(season)
end

function open_season(season)
  set_message(lang.msg_loading_episodes)
  local obj, err = api_get("/Shows/" .. app.series.Id .. "/Episodes",
                           { "seasonId=" .. esc(season.Id) })
  if not obj or type(obj.Items) ~= "table" then
    set_message(lang.msg_library_fail .. tostring(err or "?"))
    return
  end
  app.season = season
  app.episodes = {}
  for i, ep in ipairs(obj.Items) do
    app.episodes[i] = ep
  end
  show_episodes()
end

function show_episodes()
  close_dlg()
  dlg = vlc.dialog(lang.title_episodes)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  dlg:add_label(cell(app.series.Name) .. " — " .. cell(season_label(app.season)),
                1, 1, 3, 1)
  ui.episodes = dlg:add_list(1, 2, 3, 1, click_open_episode)
  ui.episodes:set_text(lang.col_number .. "\t" .. lang.col_episode
                       .. "\t" .. lang.col_duration)
  -- in broadcast order, which is the only order an episode list should
  -- ever open in; numeric through the sort key, so 2 comes before 10
  ui.episodes:set_sort(1, true)
  for i, ep in ipairs(app.episodes) do
    ui.episodes:add_value(
      sortable(ep.IndexNumber or "", ep.IndexNumber or 0) .. "\t"
      .. cell(ep.Name) .. "\t"
      .. sortable(format_ticks(ep.RunTimeTicks) or "", ep.RunTimeTicks or 0),
      i)
  end
  if #app.episodes == 0 then
    set_message(lang.msg_no_content)
  end
  dlg:add_button(lang.btn_open, click_open_episode, 1, 3, 1, 1)
  local back_label = (app.seasons_count > 1) and lang.btn_back_seasons
                                              or lang.btn_back_library
  dlg:add_button(back_label, click_episodes_back, 2, 3, 1, 1)
  ui.message = dlg:add_label("", 1, 4, 3, 1)
  dlg:show()
end

function click_episodes_back()
  if app.seasons_count > 1 then
    show_seasons()
  else
    show_library()
  end
end

function click_open_episode()
  local ep = selected_row(ui.episodes, app.episodes)
  if not ep then
    set_message(lang.msg_select_first)
    return
  end
  open_playback(ep, app.series)
end

            --[[ View 4: playback ]]--

-- One compact line about the original file, out of PlaybackInfo: what
-- JellyDinosaur spreads over its "Fichier"/"Vidéo" blocks, boiled down
-- to what matters when choosing between direct play and transcoding.
local function media_source_summary(source, label)
  if not source then
    return nil
  end
  local parts = {}
  if source.Container then
    table.insert(parts, tostring(source.Container))
  end
  local size = format_bytes(source.Size)
  if size then
    table.insert(parts, size)
  end
  for _, s in ipairs(source.MediaStreams or {}) do
    if s.Type == "Video" then
      local video = tostring(s.Codec or "?")
      if s.Width and s.Height then
        video = video .. " " .. s.Width .. "x" .. s.Height
      end
      local rate = format_bitrate(s.BitRate)
      if rate then
        video = video .. " — " .. rate
      end
      table.insert(parts, video)
      break
    end
  end
  if #parts == 0 then
    return nil
  end
  return (label or lang.lbl_original) .. table.concat(parts, " — ")
end

-- The poster, saved next to the other user data because the image widget
-- takes a file rather than bytes. One file at a time: the previous one
-- goes as soon as another item is opened.
local function fetch_artwork(item, series)
  local owner = item
  local tag = item.ImageTags and item.ImageTags.Primary
  if not tag and series then
    -- an episode rarely has its own poster; the series always does
    owner = series
    tag = series.ImageTags and series.ImageTags.Primary
  end
  local dir = vlc.config.userdatadir()
  if not tag or not dir or dir == "" then
    return nil
  end

  -- the bounds are part of the name: a file kept from a version that
  -- asked for another size must not be taken for this one
  local path = dir .. "/jellyfin-art-" .. owner.Id .. "-"
            .. ARTWORK_WIDTH .. "x" .. ARTWORK_HEIGHT .. ".jpg"
  -- already fetched for this item: opening it again costs nothing
  local cached = io.open(path, "rb")
  if cached then
    local size = cached:seek("end")
    cached:close()
    if size and size > 128 then
      app.art_path = path
      return path
    end
  end

  set_message(lang.msg_loading_art)
  local url = app.server .. "/Items/" .. owner.Id .. "/Images/Primary?"
           .. "format=Jpg&maxHeight=" .. ARTWORK_HEIGHT
           .. "&maxWidth=" .. ARTWORK_WIDTH
           .. "&tag=" .. esc(tag) .. "&ApiKey=" .. esc(app.token)
  local body = get_body(url)
  if not body or #body < 128 then
    return nil
  end

  local f = io.open(path, "wb")
  if not f then
    return nil
  end
  f:write(body)
  f:close()

  -- Jellyfin honours the bounds and the format asked for above, so this
  -- costs nothing on the usual path: a JPEG is left exactly as it came,
  -- and a G3 is not made to decode and re-encode a picture that was
  -- already right. Anything else -- a proxy that converted to WebP, a
  -- server that ignored the request -- goes through the core instead,
  -- which is both what keeps the picture from dictating the window size
  -- and what makes it displayable at all on the older machines.
  local head = io.open(path, "rb")
  local magic = head and head:read(3) or ""
  if head then
    head:close()
  end
  local is_jpeg = magic == "\255\216\255"
  if not is_jpeg and vlc.misc and vlc.misc.image_scale then
    local converted = path .. ".conv"
    local ok, width = pcall(vlc.misc.image_scale, path, converted,
                            ARTWORK_WIDTH, ARTWORK_HEIGHT)
    if ok and width then
      os.remove(path)
      os.rename(converted, path)
    else
      os.remove(converted)
    end
  end

  if app.art_path and app.art_path ~= path then
    os.remove(app.art_path)
  end
  app.art_path = path
  return path
end

-- media = the playable item (a movie, or an episode); series is set
-- for episodes and only used for labels.
function open_playback(media, series)
  set_message(lang.msg_loading_info)

  -- the real audio/subtitle tracks of this very file
  --
  -- A channel has none to give -- its streams come numbered -1, which is
  -- not an index anything may be asked for -- so this opens the tuner
  -- instead, which is what makes a channel playable at all.
  local audio, subs = {}, {}
  local source = nil
  app.live_warning = nil
  app.live_source_id, app.live_stream_id = nil, nil
  if is_live(media) then
    source, app.live_warning = open_live_stream(media)
  else
    local obj = api_get("/Items/" .. media.Id .. "/PlaybackInfo", {})
    if obj and type(obj.MediaSources) == "table" and obj.MediaSources[1] then
      source = obj.MediaSources[1]
      for _, s in ipairs(source.MediaStreams or {}) do
        local label = s.DisplayTitle
        if not label or label == "" then
          label = (s.Language or "?") .. " (" .. (s.Codec or "?") .. ")"
        end
        if s.Type == "Audio" then
          table.insert(audio, { index = s.Index, label = label })
        elseif s.Type == "Subtitle" then
          table.insert(subs, { index = s.Index, label = label })
        end
      end
    end
  end

  app.media = media
  app.media_series = series
  app.media_source = source
  app.runtime_ticks = media.RunTimeTicks
    or (source and source.RunTimeTicks) or nil
  app.artwork = fetch_artwork(media, series)
  show_playback(audio, subs)
end

local function playback_title()
  local media = app.media
  if app.media_series then
    local nums = ""
    if app.season and app.season.IndexNumber then
      nums = string.format(lang.season_fmt, app.season.IndexNumber) .. " "
    end
    if media.IndexNumber then
      nums = nums .. lang.episode_abbrev .. media.IndexNumber .. " — "
    end
    return cell(app.media_series.Name) .. " — " .. nums .. cell(media.Name)
  end
  local year = media.ProductionYear and (" (" .. media.ProductionYear .. ")")
            or ""
  return cell(media.Name) .. year
end


-- A section header: a button whose chevron says whether the block below
-- it is open. There is no disclosure widget in the dialog API, and a
-- button is what a script can give a title and a callback.
local function section_title(label, expanded)
  return (expanded and "\226\150\188 " or "\226\150\182 ") .. label
end

-- The poster keeps a column of its own for the whole height of the
-- view: it belongs to the item, not to any one section, so folding a
-- section never takes it away. Spanning everything rather than the
-- title block also spares the layout a hole in the middle when the
-- picture is taller than what stands beside it. The interface keeps it
-- to a third of the window and never blows it up past its own size.
local function place_artwork(rows)
  if app.artwork then
    -- The bounds are stated, so the layout knows the size the picture is
    -- meant to take even if what arrived is bigger than was asked for:
    -- an image is never what decides how large the window is.
    dlg:add_image(app.artwork, 5, 1, 1, rows, ARTWORK_WIDTH, ARTWORK_HEIGHT)
  end
end

-- Track pickers, or the first track of each when the section holding
-- them is folded away.
local function selected_streams()
  local a = ui.audio and app.audio_tracks[ui.audio:get_value()]
  local s = ui.subs and app.sub_tracks[ui.subs:get_value()]
  return a or 0, s or -1
end

-- Index of a value in a list, or nil: the id an entry was added with.
local function index_of(list, wanted)
  for i, v in ipairs(list) do
    if v == wanted then
      return i
    end
  end
  return nil
end

-- Resolution and quality drop-downs -> the matching preset. The
-- controls are only there while the transcoding section is unfolded;
-- what was remembered stands in for them otherwise.
local function selected_resolution()
  local id = ui.resolution and ui.resolution:get_value()
  return (id and RESOLUTIONS[id]) or app.pref_resolution
      or DEFAULT_RESOLUTION
end

function preset_of_selection()
  local res = selected_resolution()
  local id = ui.quality and ui.quality:get_value()
  local key = (id and QUALITY_KEYS[id]) or app.pref_quality
           or DEFAULT_QUALITY
  return QUALITY_PRESETS[res][key]
end

-- The field is in Mb/s, everything else in bit/s. Two decimals at most,
-- trailing zeros dropped: one decimal would turn the 350 kb/s of the
-- lowest preset into 0.3 or 0.4, and that value is what gets sent.
function bps_to_mbps(bps)
  local s = string.format("%.2f", bps / 1000000)
  s = string.gsub(s, "(%.%d-)0+$", "%1")
  return (string.gsub(s, "%.$", ""))
end

local function mbps_to_bps(text)
  local n = tonumber((string.gsub(trim(text or ""), ",", ".")))
  return n and math.floor(n * 1000000) or nil
end

local function level_max_bitrate(preset)
  local base = H264_LEVEL_MAX_BITRATE[preset.level]
  if not base then
    return nil
  end
  -- cpbBrVclFactor of the high profile
  return (preset.profile == "high") and math.floor(base * 5 / 4) or base
end

-- Reads the bitrate field, quietly correcting a value the encoder would
-- refuse (or silently clamp), and says so in the status line.
local function selected_bitrate()
  local preset = preset_of_selection()
  if not ui.bitrate then
    return app.pref_bitrate or preset.bitrate, nil
  end
  local bps = mbps_to_bps(ui.bitrate:get_text())
  local complaint = nil

  if not bps or bps <= 0 then
    bps = preset.bitrate
    complaint = string.format(lang.msg_bitrate_low, bps_to_mbps(bps))
  else
    local ceiling = level_max_bitrate(preset)
    if ceiling and bps > ceiling then
      bps = ceiling
      complaint = string.format(lang.msg_bitrate_high, bps_to_mbps(ceiling),
                                lang.unit_bitrate, preset.level, preset.profile)
    end
  end

  -- Always write the value back, so the field shows exactly what will be
  -- asked of the server (a comma becomes a dot, a capped value shrinks).
  ui.bitrate:set_text(bps_to_mbps(bps))
  return bps, complaint
end

local function selected_audio_bitrate()
  local id = ui.audio_bitrate and ui.audio_bitrate:get_value()
  return (id and AUDIO_BITRATES[id]) or app.pref_audio_bitrate
      or DEFAULT_AUDIO_BITRATE
end

-- Remembers the transcoding choices as they are on screen.
function remember_prefs()
  app.prefs_touched = true
  app.pref_resolution = selected_resolution()
  local id = ui.quality and ui.quality:get_value()
  app.pref_quality = (id and QUALITY_KEYS[id]) or app.pref_quality
                  or DEFAULT_QUALITY
  app.pref_audio_bitrate = selected_audio_bitrate()
  if ui.bitrate then
    app.pref_bitrate = mbps_to_bps(ui.bitrate:get_text()) or app.pref_bitrate
  end
  save_prefs()
end


-- Folding a section rebuilds the view: the dialog is then sized to what
-- it now shows, which is the point of folding it.
local function rebuild_playback()
  show_playback(app.audio_list or {}, app.sub_list or {})
end

function click_toggle_desc()
  app.show_desc = not app.show_desc
  save_prefs()
  rebuild_playback()
end

function click_toggle_direct()
  app.show_direct = not app.show_direct
  save_prefs()
  rebuild_playback()
end

function click_toggle_transcode()
  app.show_transcode = not app.show_transcode
  save_prefs()
  rebuild_playback()
end

function show_playback(audio, subs)
  app.audio_list, app.sub_list = audio, subs
  close_dlg()
  dlg = vlc.dialog(lang.title_play)
  dlg:set_size(DIALOG_WIDTH, 0)
  local media = app.media
  local row = 1

  dlg:add_label(playback_title(), 1, row, 4, 1) row = row + 1

  local meta = {}
  if is_live(media) then
    table.insert(meta, lang.lbl_live)
    if media.Number or media.ChannelNumber then
      table.insert(meta, lang.col_number .. " "
                   .. cell(media.Number or media.ChannelNumber))
    end
  else
    table.insert(meta, app.media_series and lang.lbl_series or lang.lbl_movie)
  end
  local dur = format_ticks(app.runtime_ticks)
  if dur then
    table.insert(meta, dur)
  end
  local genres = (app.media_series or media).Genres
  if genres and #genres > 0 then
    table.insert(meta, table.concat(genres, ", "))
  end
  dlg:add_label(cell(table.concat(meta, " — ")), 1, row, 4, 1) row = row + 1

  -- Each block folds away behind its own header: all three open at once
  -- make for a window taller than a small screen, and most of the time
  -- only one of them is being used.
  local overview = media.Overview
    or (app.media_series and app.media_series.Overview)
  if overview and overview ~= "" then
    dlg:add_button(section_title(lang.sec_desc, app.show_desc),
                   click_toggle_desc, 1, row, 4, 1)
    row = row + 1
    if app.show_desc then
      -- One label, no line breaks of our own: the interface wraps it to
      -- whatever width the window gives it, so it reflows on a resize
      -- and reads as a paragraph. Only its length is our business.
      dlg:add_label(cell(shorten(overview, OVERVIEW_MAX_CHARS)), 1, row, 4, 1)
      row = row + 1
    end
  end

  -- Direct play: none of the settings below apply to it, the file
  -- leaves the server untouched. For a channel it is the broadcast as
  -- it arrives, which the server only puts back into one container.
  local live = is_live(media)
  dlg:add_button(section_title(live and lang.sec_direct_live
                                     or lang.sec_direct, app.show_direct),
                 click_toggle_direct, 1, row, 4, 1)
  row = row + 1
  if app.show_direct then
    -- On a channel the summary is what opening the tuner probed --
    -- codec and picture size -- so it is worth as much there as the
    -- file line is on a film, under its own label.
    local summary = media_source_summary(app.media_source,
                                         live and lang.lbl_stream or nil)
    if summary then
      dlg:add_label(cell(summary), 1, row, 4, 1) row = row + 1
    end
    dlg:add_label(live and lang.hint_direct_live or lang.hint_direct,
                  1, row, 4, 1) row = row + 1
    dlg:add_button(live and lang.btn_play_direct_live or lang.btn_play_direct,
                   click_play_direct, 1, row, 2, 1)
    dlg:add_button(lang.btn_copy_direct, click_copy_direct, 3, row, 2, 1)
    row = row + 1
  end

  -- Then transcoding, with every setting that only concerns it.
  dlg:add_button(section_title(lang.sec_transcode, app.show_transcode),
                 click_toggle_transcode, 1, row, 4, 1)
  row = row + 1
  if not app.show_transcode then
    dlg:add_button(lang.btn_back, click_playback_back, 1, row, 1, 1)
    row = row + 1
    ui.link = dlg:add_text_input("", 1, row, 4, 1)
    row = row + 1
    ui.message = dlg:add_label("", 1, row, 4, 1)
    place_artwork(row)
    dlg:show()
    show_live_warning()
    return
  end
  -- Said where the choice is made: transcoding a channel gives one
  -- audio track and no subtitles, and no setting here changes that. The
  -- server's own view of a live source is a single placeholder stream
  -- numbered -1, so it writes its ffmpeg line without any -map and with
  -- -sn (read from its transcode log): ffmpeg then takes the broadcast's
  -- first audio track and drops the rest, whatever index is asked for.
  dlg:add_label(live and lang.hint_transcode_live or lang.hint_transcode,
                1, row, 4, 1) row = row + 1

  -- Two empty pickers would be worse than none: a channel carries no
  -- track list, so the row is left out and the server picks the tracks.
  if not live then
    dlg:add_label(lang.lbl_audio, 1, row, 1, 1)
    ui.audio = dlg:add_dropdown(2, row, 1, 1)
    app.audio_tracks = {}
    for i, t in ipairs(audio) do
      app.audio_tracks[i] = t.index
      ui.audio:add_value(cell(t.label), i)
    end
    dlg:add_label(lang.lbl_subtitles, 3, row, 1, 1)
    ui.subs = dlg:add_dropdown(4, row, 1, 1)
    app.sub_tracks = {}
    ui.subs:add_value(lang.no_subtitle, 1)
    for i, t in ipairs(subs) do
      app.sub_tracks[i + 1] = t.index
      ui.subs:add_value(cell(t.label), i + 1)
    end
    row = row + 1
  end

  -- Changing either of these refills the bitrate from the preset and
  -- refreshes the estimate on the spot.
  -- Lists read low to high; what was chosen last time is selected.
  dlg:add_label(lang.lbl_resolution, 1, row, 1, 1)
  ui.resolution = dlg:add_dropdown(2, row, 1, 1, click_preset_changed)
  for i, res in ipairs(RESOLUTIONS) do
    ui.resolution:add_value(res .. "p", i)
  end
  ui.resolution:set_value(index_of(RESOLUTIONS,
    app.pref_resolution or DEFAULT_RESOLUTION))

  dlg:add_label(lang.lbl_quality, 3, row, 1, 1)
  ui.quality = dlg:add_dropdown(4, row, 1, 1, click_preset_changed)
  local QUALITY_LABELS = {
    high = lang.q_high, veryhigh = lang.q_veryhigh,
    medium = lang.q_medium, low = lang.q_low,
  }
  for i, key in ipairs(QUALITY_KEYS) do
    ui.quality:add_value(QUALITY_LABELS[key], i)
  end
  ui.quality:set_value(index_of(QUALITY_KEYS,
    app.pref_quality or DEFAULT_QUALITY))
  row = row + 1

  -- Free-form bitrate, like JellyDinosaur: the presets above are a
  -- starting point, this is the value actually asked of the server.
  dlg:add_label(lang.lbl_bitrate, 1, row, 1, 1)
  -- the estimate follows what is being typed, not just the Enter key
  ui.bitrate = dlg:add_text_input(
    bps_to_mbps(app.pref_bitrate or preset_of_selection().bitrate),
    2, row, 1, 1, click_bitrate_changed, click_bitrate_typed)
  dlg:add_label(lang.lbl_audio_bitrate, 3, row, 1, 1)
  ui.audio_bitrate = dlg:add_dropdown(4, row, 1, 1, click_bitrate_changed)
  for i, rate in ipairs(AUDIO_BITRATES) do
    ui.audio_bitrate:add_value(math.floor(rate / 1000) .. " kb/s", i)
  end
  ui.audio_bitrate:set_value(index_of(AUDIO_BITRATES,
    app.pref_audio_bitrate or DEFAULT_AUDIO_BITRATE))
  row = row + 1

  -- The estimate follows the settings above, so it belongs to this block
  dlg:add_label(lang.lbl_estimated, 1, row, 1, 1)
  ui.estimate = dlg:add_label("", 2, row, 3, 1)
  row = row + 1
  dlg:add_button(lang.btn_play_hls, click_play_hls, 1, row, 2, 1)
  dlg:add_button(lang.btn_copy_hls, click_copy_hls, 3, row, 2, 1)
  row = row + 1

  dlg:add_button(lang.btn_back, click_playback_back, 1, row, 1, 1)
  row = row + 1
  ui.link = dlg:add_text_input("", 1, row, 4, 1)
  row = row + 1
  ui.message = dlg:add_label("", 1, row, 4, 1)
  place_artwork(row)

  update_estimate()
  dlg:show()
  show_live_warning()
end

-- A tuner that would not open is worth saying out loud: the URLs below
-- fall back to the channel's own id, which only some tuners answer to,
-- and the alternative is a play button that does nothing for a minute.
-- Said on the view the failure lands on, and only once.
function show_live_warning()
  if app.live_warning then
    set_message(lang.msg_live_open_fail .. app.live_warning)
    app.live_warning = nil
  end
end

function click_playback_back()
  if is_live(app.media) then
    show_live()
  elseif app.media_series then
    show_episodes()
  else
    show_library()
  end
end

-- Told to the server so it can name the session, and stop the transcode
-- that belongs to it.
local function play_session()
  return "powervlc" .. os.time() .. math.random(999999)
end

-- Direct play: the original file as it sits on the server (Static),
-- VLC handles the tracks itself.
--
-- A channel is served the same way whenever the tuner hands over a
-- transport stream: Static passes it through untouched, so ALL of it
-- arrives -- Arte's four audio tracks (French, German, original, audio
-- description) and its teletext subtitles, which VLC then switches
-- between on its own. Measured on the multicast tuner: 4 audio + 1
-- subtitle through Static, against 1 audio and no subtitle through
-- anything else.
--
-- "Anything else" is the fallback, and it exists because a tuner whose
-- source is itself a playlist (Container "hls") cannot be passed
-- through: Static then relays the tuner's own m3u8, whose segment names
-- are relative to the tuner and answer 404 under the server's address
-- (measured). There, asking for a TS with both codecs copied is the only
-- thing VLC can open -- and Jellyfin's remux carries a single audio
-- track and drops the subtitles, because ffmpeg is told to map one of
-- each. Nothing to be done about it from this side.
local function direct_play_url()
  if is_live(app.media) then
    local passthrough = app.live_container ~= nil
                    and app.live_container ~= ""
                    and app.live_container ~= "hls"
    return app.server .. "/Videos/" .. app.media.Id .. "/stream.ts?"
        .. "ApiKey=" .. esc(app.token)
        .. (passthrough and "&Static=true"
                        or "&Container=ts&VideoCodec=copy&AudioCodec=copy")
        .. live_source_params()
        .. "&deviceId=" .. DEVICE_ID
        .. "&playSessionId=" .. play_session()
  end
  return app.server .. "/Videos/" .. app.media.Id .. "/stream?"
      .. "Static=true"
      .. "&mediaSourceId=" .. app.media.Id
      .. "&deviceId=" .. DEVICE_ID
      .. "&ApiKey=" .. esc(app.token)
end

-- Transcoded HLS: main.m3u8 (the media playlist) rather than
-- master.m3u8, exactly like JellyDinosaur — the master's CODECS
-- attribute misleads some players and there is only one quality
-- anyway; VLC accepts a media playlist as-is.
-- A channel goes through live.m3u8 instead, the live-TV media playlist:
-- main.m3u8 is the one for a file, and asked of a channel the server
-- answers 500 (measured). Neither the master playlist nor an opened live
-- stream is needed -- the server opens the tuner on this very request.
local function hls_url()
  local res = selected_resolution()
  local preset = preset_of_selection()
  local bitrate, complaint = selected_bitrate()
  if complaint then
    set_message(complaint)
  end
  local live = is_live(app.media)
  local url = app.server .. "/Videos/" .. app.media.Id
      .. (live and "/live.m3u8?" or "/main.m3u8?")
      .. "ApiKey=" .. esc(app.token)
      .. "&VideoCodec=h264"
      .. "&AudioCodec=aac"
      .. "&maxHeight=" .. res
      .. "&maxWidth=" .. RESOLUTION_MAX_WIDTH[res]
      .. "&profile=" .. preset.profile
      .. "&level=" .. preset.level
      .. "&videoBitRate=" .. bitrate
      .. "&maxAudioChannels=2"
      .. "&audioBitRate=" .. selected_audio_bitrate()
      .. "&AudioSampleRate=" .. string.format("%d", AUDIO_SAMPLE_RATE)
      .. "&enableAudioVbrEncoding=false"
      .. "&maxVideoBitDepth=8"
      .. "&maxRefFrames=" .. preset.refs
      .. "&maxFramerate=30"
  -- Tracks are only named on a file; on a channel there is nothing to
  -- number yet, and an index the server cannot match is worse than none.
  if not live then
    local a, s = selected_streams()
    url = url .. "&subtitleMethod=Encode"
              .. "&audioStreamIndex=" .. a
              .. "&subtitleStreamIndex=" .. s
  end
  return url
      .. "&deviceId=" .. DEVICE_ID
      .. "&playSessionId=" .. play_session()
      .. (live and live_source_params()
              or ("&mediaSourceId=" .. app.media.Id))
      .. "&transcodeReasons=" .. esc(TRANSCODE_REASON)
end

-- JellyDinosaur's estimated-size helper: (video + audio bitrate) over
-- the whole duration. A target, not a promise -- the encoder is free to
-- spend less on an easy scene.
local function estimated_size(bitrate)
  if type(app.runtime_ticks) ~= "number" or app.runtime_ticks <= 0 then
    return nil
  end
  local seconds = app.runtime_ticks / 10000000
  return format_bytes((bitrate + selected_audio_bitrate()) * seconds / 8)
end

-- Called whenever a transcoding setting changes, so what is shown always
-- matches what the buttons would ask for.
function update_estimate()
  if not ui.estimate then
    return
  end
  local preset = preset_of_selection()
  local bitrate = select(1, selected_bitrate())
  local size = estimated_size(bitrate)
  ui.estimate:set_text((size and ("~ " .. size .. " — ") or "")
    .. selected_resolution() .. "p, " .. bps_to_mbps(bitrate) .. " "
    .. lang.unit_bitrate .. ", " .. preset.profile .. " " .. preset.level)
end

-- Resolution or quality changed: the preset is a starting point, so it
-- refills the bitrate field, then the estimate follows.
function click_preset_changed()
  ui.bitrate:set_text(bps_to_mbps(preset_of_selection().bitrate))
  update_estimate()
  remember_prefs()
  set_message("")
end

-- The bitrate field was validated (or the audio bitrate picked).
function click_bitrate_changed()
  local _, complaint = selected_bitrate()
  update_estimate()
  remember_prefs()
  set_message(complaint or "")
end

-- Still typing: refresh the estimate, but leave the field alone. Writing
-- a corrected value back mid-word would fight the user for the caret.
function click_bitrate_typed()
  local preset = preset_of_selection()
  local bps = mbps_to_bps(ui.bitrate:get_text())
  if not bps or bps <= 0 then
    return
  end
  local ceiling = level_max_bitrate(preset)
  if ceiling and bps > ceiling then
    bps = ceiling
  end
  local size = estimated_size(bps)
  ui.estimate:set_text((size and ("~ " .. size .. " — ") or "")
    .. selected_resolution() .. "p, " .. bps_to_mbps(bps) .. " "
    .. lang.unit_bitrate .. ", " .. preset.profile .. " " .. preset.level)
end

local function play(url)
  vlc.playlist.add({{ path = url, title = playback_title() }})
end

local function copy(url, size)
  ui.link:set_text(url)
  local msg
  if copy_to_clipboard(url) then
    msg = size and string.format(lang.msg_copied_size, size)
               or lang.msg_copied
  else
    msg = lang.msg_copy_fallback
  end
  set_message(msg)
end

function click_play_hls()
  local url = hls_url()   -- reads and, if need be, corrects the bitrate
  update_estimate()
  play(url)
  set_message(lang.msg_playing)
end

function click_copy_hls()
  local url = hls_url()
  update_estimate()
  copy(url, estimated_size(select(1, selected_bitrate())))
end

function click_play_direct()
  play(direct_play_url())
  set_message(lang.msg_playing)
end

function click_copy_direct()
  copy(direct_play_url(), nil)
end
