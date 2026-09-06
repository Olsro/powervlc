--[[
 subsonic.lua : Subsonic / Navidrome browser extension for PowerVLC

 Browse a Subsonic-compatible music server (Navidrome, Airsonic,
 Gonic...) the way a music player does: by album, by album artist, by
 genre, by playlist or by song, with a per-view search box, a
 favorites filter, star/unstar from the right-click menu, gapless
 playback, server-side transcoding, and downloads -- either dragged
 straight out to the Finder or saved to the Downloads folder, with a
 live progress bar.

 Sign-in is username/password; the password goes to the system
 keystore when it can, in the clear (with a warning) when it cannot,
 exactly like the Jellyfin extension.

 The wire format is the Subsonic REST API in XML: the C-backed
 vlc.xml reader digests a seven-thousand-album listing in a moment
 where a pure-Lua JSON decoder would take ages on the machines this
 fork exists for.

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
-- how much a download moves per timer tick; big enough for speed,
-- small enough that the progress bar visibly lives
local DL_CHUNKS_PER_TICK = 16

local CLIENT_NAME = "PowerVLC"
local API_VERSION = "1.16.1"

-- one page of getAlbumList2 / getSongsByGenre; the API ceiling
local PAGE = 500
-- server-side song search: how many results are worth listing
local SEARCH_SONGS = 500

            --[[ Translations ]]--

-- One file per language under share/lua/i18n/subsonic/, and only the one in
-- use is ever read: eighteen catalogues parsed at every activation, to keep
-- one, is not free on the machines this fork exists for. English sits
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
  setmetatable(lang, { __index = require("pvlc_i18n").load("subsonic") })
end

            --[[ Transcoding choices ]]--

-- Formats every Subsonic server of this decade can produce; "raw" asks
-- for the file as-is (Navidrome honors it, others fall back to their
-- default transcoding, which is the sensible behavior either way).
local FORMATS = { "raw", "mp3", "opus", "aac" }
local BITRATES = { 128, 192, 256, 320 }
local DEFAULT_FORMAT = "raw"
local DEFAULT_BITRATE = 192

            --[[ State ]]--

local app = {
  server = nil,        -- normalized base URL of the connected server
  username = nil,
  auth = nil,          -- ready-made auth query-string fragment
  last_server = "https://",
  last_user = "",
  last_pass = "",
  remember = false,

  -- Album artists first: one request and a thousand-odd rows, where the
  -- album list is a dozen requests and several thousand. On the slow
  -- machines this fork exists for, that is the difference between
  -- opening the browser and waiting on it.
  view = "artists",    -- current root view key
  load_root = false,   -- only fetch a root listing once asked to
  cache = {},          -- view key -> the listing once fetched
  albums = nil,        -- caches, loaded once per connection
  artists = nil,
  genres = nil,
  playlists = nil,
  search_songs = {},   -- last server-side song search results
  search_query = "",

  stack = {},          -- drill-down levels above the root view
  rows = {},           -- list row id -> { kind, obj } currently displayed
  menu_actions = {},   -- context-menu entry index -> action key

  pref_format = nil,
  pref_bitrate = nil,
  show_transcode = false,

  -- what the account is allowed to do, and what the server can do,
  -- both asked once at sign-in
  rights = {},
  has_offset = false,  -- OpenSubsonic transcodeOffset extension
}

-- The track being listened to, and whether the server has been told.
-- Subsonic's convention: announce at the start, count it as played once
-- half of it has gone by (four minutes is enough for a long one).
local now_playing = {
  id = nil,
  deadline = nil,   -- seconds of playback after which it counts
  submitted = false,
}

-- download engine state; survives view changes
local dl = {
  active = false,
  files = {},          -- { song, path, size }
  idx = 0,             -- current file number (1-based once started)
  stream = nil,
  fh = nil,
  got = 0,             -- bytes of the current file
  total = 0,           -- bytes expected over the whole batch
  total_got = 0,
  files_ok = 0,
  files_failed = 0,
  base = nil,          -- folder shown in the final message
  cancelled = false,
}

local dlg = nil
local ui = {}

            --[[ VLC entry points ]]--

function descriptor()
  return {
    title = "Subsonic (Navidrome)",
    version = "1.0",
    author = "PowerVLC",
    url = "https://www.navidrome.org/",
    shortdesc = "Subsonic",
    description = "Browse a Subsonic or Navidrome music server by "
               .. "album, artist, genre or playlist; stream (with "
               .. "optional server-side transcoding) or download the "
               .. "files, favorites included.",
    -- input-listener: what is playing has to be known to report it back
    -- to the server, which is what feeds its own "recently played" and
    -- "most played" listings (and Last.fm, when the server has one).
    capabilities = { "input-listener" }
  }
end

function activate()
  load_lang()
  vlc.msg.dbg("[Subsonic] Welcome")
  json = require("dkjson")
  math.randomseed(os.time())
  load_settings()
  show_connect()
end

function deactivate()
  vlc.msg.dbg("[Subsonic] Bye")
  dl.cancelled = true
  dl_close_current()
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

            --[[ Small helpers ]]--

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- Long work has to say it is still there. The core watches the extension
-- thread and, after ten seconds without a sign of life, offers to kill
-- it -- and kills it outright when it cannot even show that question,
-- which is what made a listing of a couple of thousand albums die on
-- its own once in a while. Every page of a paged fetch says so.
local function still_alive()
  if vlc.keep_alive then
    pcall(vlc.keep_alive)
  end
end

local function set_message(text)
  if ui.message then
    ui.message:set_text(text or "")
    -- push the update NOW: a message set right before a blocking network
    -- call would otherwise only show once the call ends
    if dlg then
      dlg:update()
    end
  end
end

local function esc(value)
  return vlc.strings.encode_uri_component(tostring(value))
end

-- one table cell: tabs and the sort-key separator are structure
local function cell(s)
  return (string.gsub(tostring(s or ""), "[\t\r\n\031]", " "))
end

-- "display\031key": the interface sorts the column on the key
local function sortable(display, key)
  if key == nil then
    return cell(display)
  end
  return cell(display) .. "\031" .. tostring(key)
end

local function format_duration(seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds < 0 then
    return ""
  end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function format_bytes(bytes)
  bytes = tonumber(bytes)
  if not bytes or bytes < 0 then
    return "?"
  end
  if bytes >= 1073741824 then
    return string.format("%.2f", bytes / 1073741824) .. " GiB"
  end
  if bytes >= 1048576 then
    return string.format("%.1f", bytes / 1048576) .. " MiB"
  end
  return math.floor(bytes / 1024) .. " KiB"
end

-- Searching "detective" must find "Détective": accents folded on both
-- sides. string.lower only knows ASCII, so upper-case forms are listed
-- too -- each is two bytes in UTF-8, matched as a whole.
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

-- A string the Finder (or any file system) accepts as a name. Length is
-- capped without ever cutting inside a UTF-8 sequence.
local function sanitize_filename(s)
  s = tostring(s or "")
  s = string.gsub(s, "[/\\:%*%?\"<>|%c]", "_")
  s = trim(s)
  s = string.gsub(s, "^%.+", "_")
  if s == "" then
    s = "_"
  end
  if #s > 120 then
    -- Judged on the first byte DROPPED, not on the last one kept: a
    -- continuation byte there is what says the cut falls inside a
    -- character. Walking back from the last byte kept instead throws away
    -- a whole character when the cut happened to land cleanly -- and, on
    -- a lead byte, leaves it dangling with its continuation gone, which
    -- is not text any more.
    local cut = 120
    while cut > 0 do
      local b = string.byte(s, cut + 1)
      if not b or b < 128 or b >= 192 then
        break
      end
      cut = cut - 1
    end
    -- the cut may have exposed a space, and a name may not end on one
    s = trim(string.sub(s, 1, cut))
  end
  return s
end

-- vlc.io.mkdir creates one level at a time
local function mkdir_p(path)
  if not (vlc.io and vlc.io.mkdir) then
    return false
  end
  local built = ""
  if string.sub(path, 1, 1) == "/" then
    built = "/"
  end
  for part in string.gmatch(path, "[^/]+") do
    built = built .. part
    vlc.io.mkdir(built, "0755")
    built = built .. "/"
  end
  return true
end

local function hex_encode(s)
  return (string.gsub(s, ".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

function close_dlg()
  if dlg ~= nil then
    dlg:hide()
    -- now rather than at the whim of the garbage collector: the
    -- finalizer blocks on the interface, possibly in the middle of
    -- building the next dialog
    dlg:delete()
  end
  dlg = nil
  ui = {}
end

            --[[ HTTP + Subsonic API ]]--

-- HTTP(S) GET through VLC's stream layer: raw body or nil, error.
local function get_body(url)
  vlc.msg.dbg("[Subsonic] GET " .. url)
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

-- The authentication fragment sent on every request. Token
-- authentication (md5(password .. salt)) keeps the password itself off
-- the wire; the hex-password form is the documented fallback for the
-- rare build without vlc.strings.md5.
local function make_auth(username, password)
  local base = "u=" .. esc(username)
            .. "&v=" .. API_VERSION .. "&c=" .. CLIENT_NAME
  if vlc.strings.md5 then
    local salt = string.format("%08x%08x", math.random(0, 0x7fffffff),
                               math.random(0, 0x7fffffff))
    return base .. "&t=" .. vlc.strings.md5(password .. salt)
                .. "&s=" .. salt
  end
  return base .. "&p=enc:" .. hex_encode(password)
end

--[[
 Parse a Subsonic XML answer. wanted is a set of element names; every
 element with one of those names, wherever it sits, becomes a table of
 its attributes in the result, in document order. A text child (the
 genre name lives there) lands in .value.

 Returns the collection table, or nil and an error message (transport
 or the server's own <error>).
--]]
local function parse_subsonic(body, wanted)
  -- Locals keep xml and stream alive for the whole parse: the C reader
  -- holds no Lua reference, and the GC freeing them mid-parse is a
  -- segfault, not an error.
  local xml = vlc.xml()
  local stream = vlc.memory_stream(body)
  local reader = xml and stream and xml:create_reader(stream)
  if not reader then
    return nil, "cannot parse the answer"
  end

  local out = {}
  for name in pairs(wanted) do
    out[name] = {}
  end
  local status, errmsg = nil, nil
  local pending = nil

  local nodetype, nodename = reader:next_node()
  while nodetype > 0 do
    if nodetype == 1 then
      if nodename == "subsonic-response" or nodename == "error"
         or wanted[nodename] then
        local attrs = {}
        local attr, value = reader:next_attr()
        while attr ~= nil do
          attrs[attr] = value
          attr, value = reader:next_attr()
        end
        if nodename == "subsonic-response" then
          status = attrs.status
        elseif nodename == "error" then
          errmsg = tostring(attrs.message or "?")
        else
          table.insert(out[nodename], attrs)
          pending = attrs
        end
      end
    elseif nodetype == 3 then
      if pending then
        pending.value = nodename
      end
    elseif nodetype == 2 then
      pending = nil
    end
    nodetype, nodename = reader:next_node()
  end

  if status ~= "ok" then
    return nil, errmsg or "invalid answer"
  end
  return out
end

-- GET a REST endpoint, auth included, parsed. params is an ordered list
-- of "name=value" strings, already URI-encoded.
local function api(endpoint, params, wanted)
  local url = app.server .. "/rest/" .. endpoint .. ".view?" .. app.auth
  for _, p in ipairs(params or {}) do
    url = url .. "&" .. p
  end
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  return parse_subsonic(body, wanted or {})
end

local function cover_url(cover_id, size)
  return app.server .. "/rest/getCoverArt.view?" .. app.auth
      .. "&id=" .. esc(cover_id) .. "&size=" .. size
end

-- "mm:ss" or plain seconds -> seconds, 0 for anything else
local function parse_offset(text)
  text = trim(text or "")
  if text == "" then
    return 0
  end
  local m, s = string.match(text, "^(%d+):(%d%d)$")
  if m then
    return tonumber(m) * 60 + tonumber(s)
  end
  return tonumber(text) or 0
end

-- The URL a song is played from, transcoding choices included.
-- offset is honoured only where the server said it would be.
local function stream_url(song, offset)
  local url = app.server .. "/rest/stream.view?" .. app.auth
           .. "&id=" .. esc(song.id)
  local format = app.pref_format or DEFAULT_FORMAT
  if format == "raw" then
    return url .. "&format=raw"
  end
  url = url .. "&format=" .. format
      .. "&maxBitRate=" .. (app.pref_bitrate or DEFAULT_BITRATE)
  if app.has_offset and offset and offset > 0 then
    url = url .. "&timeOffset=" .. offset
  end
  return url
end

-- Downloads always fetch the original file
local function download_url(song)
  return app.server .. "/rest/download.view?" .. app.auth
      .. "&id=" .. esc(song.id)
end

            --[[ Telling the server what is being listened to ]]--

-- The song id of a stream URL of ours, or nil for anything else the
-- user happens to be playing.
local function playing_song_id(uri)
  if not app.server or not uri then
    return nil
  end
  if string.sub(uri, 1, #app.server) ~= app.server then
    return nil
  end
  if not string.find(uri, "/rest/stream%.view") then
    return nil
  end
  return string.match(uri, "[?&]id=([^&]+)")
end

-- Fire and forget: a listening report must never hold up playback, and
-- a server that refuses one is not worth an error message.
local function tell_server(song_id, submission)
  if not song_id or app.rights.scrobble == false then
    return
  end
  pcall(api, "scrobble",
        { "id=" .. esc(song_id),
          "submission=" .. (submission and "true" or "false") }, {})
end

-- VLC moved to another item: announce it, and work out when it should
-- count as played.
function input_changed()
  local ok, item = pcall(vlc.input.item)
  local uri = nil
  if ok and item then
    uri = item:uri()
  end
  local id = playing_song_id(uri)
  if id == now_playing.id then
    return
  end

  now_playing.id = id
  now_playing.submitted = false
  now_playing.deadline = nil
  if not id then
    return
  end

  local seconds = nil
  if ok and item then
    local dur = item:duration()
    if type(dur) == "number" and dur > 0 then
      seconds = dur
    end
  end
  -- half the track, and four minutes is plenty for a long one
  if seconds then
    now_playing.deadline = math.floor(seconds / 2)
    if now_playing.deadline > 240 then
      now_playing.deadline = 240
    end
  else
    now_playing.deadline = 30
  end

  tell_server(id, false)
  arm_tick()
end

            --[[ Saved connection (same scheme as the Jellyfin one) ]]--

local KEYSTORE_LABEL = "PowerVLC — Subsonic"

local function settings_path()
  local dir = vlc.config.userdatadir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/subsonic.json"
end

local function keystore_service(server)
  return "subsonic-powervlc://" .. string.gsub(server or "", "^%w+://", "")
end

local function have_keystore()
  return vlc.keystore ~= nil and vlc.keystore.find ~= nil
end

local function load_secret(server, user)
  if not have_keystore() then
    return nil
  end
  return vlc.keystore.find(keystore_service(server), user or "user")
end

local function save_secret(server, user, secret)
  if not have_keystore() then
    return false
  end
  if not vlc.keystore.store(keystore_service(server), user or "user",
                            secret, KEYSTORE_LABEL) then
    return false
  end
  -- Prove it can be read back before trusting it: macOS lets an
  -- application without a stable signing identity write to the
  -- Keychain, then refuses to let it read what it wrote.
  if load_secret(server, user) ~= secret then
    vlc.keystore.remove(keystore_service(server), user or "user")
    return false
  end
  return true
end

local function forget_secret(server, user)
  if have_keystore() then
    vlc.keystore.remove(keystore_service(server), user or "user")
  end
end

local function load_prefs(obj)
  local p = obj.prefs
  if type(p) ~= "table" then
    return
  end
  for _, f in ipairs(FORMATS) do
    if p.format == f then
      app.pref_format = f
    end
  end
  for _, r in ipairs(BITRATES) do
    if p.bitrate == r then
      app.pref_bitrate = r
    end
  end
  if type(p.view) == "string" then
    app.view = p.view
  end
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

  if type(obj.password) == "string" and obj.password ~= "" then
    -- an earlier clear-text save (or a broken keystore): keep using it
    app.last_pass = obj.password
    app.keystore_broken = obj.keystore_broken and true or false
  elseif app.remember then
    app.last_pass = load_secret(app.last_server, app.last_user) or ""
    if app.last_pass == "" and obj.keystore then
      -- The keystore took the password but will not give it back; give
      -- up on it for good rather than lose it again (see Jellyfin).
      app.secret_denied = true
      app.keystore_broken = true
      forget_secret(app.last_server, app.last_user)
    end
  end
  if obj.keystore_broken then
    app.keystore_broken = true
  end
end

local function prefs_table()
  return {
    format = app.pref_format,
    bitrate = app.pref_bitrate,
    view = app.view,
    show_transcode = app.show_transcode,
  }
end

-- Prefs changed: rewrite only the prefs part of the file
function save_prefs()
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
  obj.prefs = prefs_table()
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
    forget_secret(app.server, app.username)
    local f = io.open(path, "w")
    if f then
      f:write(json.encode({ prefs = prefs_table() }, { indent = true }))
      f:close()
    end
    return
  end

  local stored = not app.keystore_broken
             and save_secret(app.server, app.username, app.last_pass)
  -- the clear-text fallback is a choice the user gets to see: the
  -- warning shows on the very screen the connection lands on
  app.secret_plain = not stored
  local f = io.open(path, "w")
  if not f then
    return
  end
  f:write(json.encode({
    server = app.server,
    username = app.username,
    password = (not stored) and app.last_pass or nil,
    keystore = stored or nil,
    keystore_broken = app.keystore_broken or nil,
    prefs = prefs_table(),
    remember = true,
  }, { indent = true }))
  f:close()
end

            --[[ View 1: connection ]]--

-- Wide enough for the widest listing (album, artist, year, a figure and
-- the star) without the columns having to fight each other; the window
-- is clamped to the screen, so a small one still gets what it can.
local DIALOG_WIDTH = 900
local DIALOG_HEIGHT = 480
local ARTWORK_SIZE = 260

function show_connect()
  close_dlg()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(DIALOG_WIDTH, 0)

  dlg:add_label(lang.sec_server, 1, 1, 3, 1)
  dlg:add_label(lang.lbl_server, 1, 2, 1, 1)
  ui.server = dlg:add_text_input(app.last_server, 2, 2, 2, 1, click_connect)
  dlg:add_label(lang.hint_server, 1, 3, 3, 1)

  dlg:add_label(lang.sec_account, 1, 4, 3, 1)
  dlg:add_label(lang.lbl_username, 1, 5, 1, 1)
  ui.username = dlg:add_text_input(app.last_user, 2, 5, 2, 1, click_connect)
  dlg:add_label(lang.lbl_password, 1, 6, 1, 1)
  ui.password = dlg:add_password(app.last_pass, 2, 6, 2, 1, click_connect)

  ui.remember = dlg:add_check_box(lang.chk_remember, app.remember, 1, 7, 3, 1)
  dlg:add_button(lang.btn_forget, click_forget, 1, 8, 3, 1)
  dlg:add_button(lang.btn_connect, click_connect, 1, 9, 3, 1)
  ui.message = dlg:add_label("", 1, 10, 3, 1)
  dlg:show()
  if app.secret_denied then
    set_message(lang.msg_keystore_denied)
    app.secret_denied = false
  end
end

function click_forget()
  app.remember = false
  forget_secret(normalize_server_url(ui.server:get_text()) or app.last_server,
                trim(ui.username:get_text()))
  forget_secret(app.server, app.username)
  app.last_server = "https://"
  app.last_user = ""
  app.last_pass = ""
  local path = settings_path()
  if path then
    os.remove(path)
  end
  ui.server:set_text(app.last_server)
  ui.username:set_text("")
  ui.password:set_text("")
  ui.remember:set_checked(false)
  set_message(lang.msg_forgotten)
end

function normalize_server_url(url)
  url = trim(url)
  if url == "" or url == "http://" or url == "https://" then
    return nil
  end
  if not string.match(url, "^https?://") then
    -- A bare address: a server reached by name from the outside is
    -- served over TLS, one named by address and port on a home network
    -- almost never is. Whichever way this guesses, a failed connection
    -- tries the other scheme before giving up.
    if string.match(url, "^%d+%.%d+%.%d+%.%d+") or string.match(url, ":%d+") then
      url = "http://" .. url
    else
      url = "https://" .. url
    end
  end
  -- a pasted web-app URL carries /app/#/... -- the API base is above it
  url = string.gsub(url, "/app/?#?.*$", "")
  return (string.gsub(url, "/+$", ""))
end

local function scheme_swapped(url)
  if string.match(url, "^https://") then
    return (string.gsub(url, "^https://", "http://"))
  end
  return (string.gsub(url, "^http://", "https://"))
end

-- ping.view validates address and credentials in one go (error 40 is a
-- wrong password). Returns true, or nil and a message.
local function try_ping(server, auth)
  local body, err = get_body(server .. "/rest/ping.view?" .. auth)
  if not body then
    return nil, lang.msg_ping_fail .. tostring(err)
  end
  local out, aerr = parse_subsonic(body, {})
  if not out then
    if aerr and string.find(string.lower(aerr), "password")
       or aerr and string.find(aerr, "mot de passe") then
      return nil, lang.msg_bad_credentials
    end
    return nil, lang.msg_login_fail .. tostring(aerr)
  end
  return true
end

--[[
 The base URL that actually answers, or nil and a message. Two things
 are forgiven here rather than asked of the user: the scheme (a home
 server is plain http, one on a domain is not, and both are typed
 without thinking), and the base path -- Navidrome is commonly mounted
 under one, and its front page names it in a redirect.
--]]
function resolve_server(server, auth)
  local first_err = nil
  for _, base in ipairs({ server, scheme_swapped(server) }) do
    local ok, err = try_ping(base, auth)
    if ok then
      return base
    end
    -- the server is there and answering: no point trying elsewhere
    if err == lang.msg_bad_credentials then
      return nil, err
    end
    first_err = first_err or err

    -- Where the front page says it is mounted. Two forms, because what
    -- comes back depends on whether redirects were followed: the
    -- application itself states its base in its embedded settings
    -- (baseURL":"/nd"), while the bare redirect that leads to it names
    -- the same path in its one link.
    local page = get_body(base .. "/")
    local prefix = page and (string.match(page, "baseURL[\"\\:]*/([%w%-%._~]+)")
                          or string.match(page, "href=\"/([^\"/]+)/app/\""))
    if prefix then
      local candidate = base .. "/" .. prefix
      local ok2, err2 = try_ping(candidate, auth)
      if ok2 then
        return candidate
      end
      if err2 == lang.msg_bad_credentials then
        return nil, err2
      end
    end
  end
  return nil, first_err
end

function click_connect()
  local server = normalize_server_url(ui.server:get_text())
  if not server then
    set_message(lang.msg_enter_server)
    return
  end
  local user = trim(ui.username:get_text())
  local pass = ui.password:get_text()
  if user == "" or pass == "" then
    set_message(lang.msg_enter_account)
    return
  end
  app.remember = ui.remember:get_checked()

  local auth = make_auth(user, pass)
  set_message(lang.msg_pinging)
  local found, err = resolve_server(server, auth)
  if not found then
    set_message(err)
    return
  end
  if found ~= server then
    -- the address that answered is not quite the one typed: show it,
    -- it is the one that gets remembered
    server = found
    ui.server:set_text(server)
    set_message(string.format(lang.msg_found_base, server))
  end

  app.server = server
  app.username = user
  app.last_server = server
  app.last_user = user
  app.last_pass = pass
  app.auth = make_auth(user, pass)

  -- Two questions asked once, so the rest of the session stops guessing:
  -- what this account may do, and what this server can do. An account
  -- without the download right gets no download button rather than a
  -- button that fails.
  app.rights = {}
  local who = api("getUser", { "username=" .. esc(user) }, { user = true })
  if who and who.user[1] then
    local u = who.user[1]
    app.rights.download = u.downloadRole ~= "false"
    app.rights.scrobble = u.scrobblingEnabled ~= "false"
  else
    app.rights.download = true
    app.rights.scrobble = true
  end
  app.has_offset = false
  local exts = api("getOpenSubsonicExtensions", {},
                   { openSubsonicExtensions = true })
  for _, e in ipairs(exts and exts.openSubsonicExtensions or {}) do
    if e.name == "transcodeOffset" then
      app.has_offset = true
    end
  end

  -- fresh connection, fresh caches, and nothing fetched until asked
  app.cache = {}
  app.search_songs, app.search_query = {}, ""
  app.stack = {}
  app.load_root = false

  save_settings()
  show_browser()
end

            --[[ Library loading (lazy, cached per connection) ]]--

local function load_albums()
  if app.cache.albums then
    return app.cache.albums
  end
  local albums = {}
  local offset = 0
  while true do
    still_alive()
    set_message(string.format(lang.msg_loading_albums, #albums))
    local out, err = api("getAlbumList2",
      { "type=alphabeticalByName", "size=" .. PAGE, "offset=" .. offset },
      { album = true })
    if not out then
      set_message(lang.msg_api_fail .. tostring(err))
      return nil
    end
    for _, a in ipairs(out.album) do
      table.insert(albums, a)
    end
    if #out.album < PAGE or #albums > 200000 then
      break
    end
    offset = offset + PAGE
  end
  app.cache.albums = albums
  return albums
end

--[[
 The album listings the server itself picks and orders: a random draw,
 the latest additions, what was played lately, what is played most.
 One request each, deliberately bounded -- these are meant to be a
 glance at the library, not another way to page through all of it, and
 the whole point is that they cost nothing to open on a slow machine.
--]]
local ALBUM_VIEWS = {
  random   = "random",
  newest   = "newest",
  recent   = "recent",
  frequent = "frequent",
}
local ALBUM_VIEW_SIZE = 100

local function load_album_view(view)
  if app.cache[view] then
    return app.cache[view]
  end
  set_message(string.format(lang.msg_loading_albums, 0))
  local out, err = api("getAlbumList2",
    { "type=" .. ALBUM_VIEWS[view], "size=" .. ALBUM_VIEW_SIZE },
    { album = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  app.cache[view] = out.album
  return out.album
end

-- A hundred songs drawn at random, straight into the queue: one
-- request, no listing to walk, nothing to page through. On a slow
-- machine it is the quickest way from "I want music" to music.
local function load_shuffle()
  if app.cache.shuffle then
    return app.cache.shuffle
  end
  set_message(string.format(lang.msg_loading_songs, 0, ALBUM_VIEW_SIZE))
  local out, err = api("getRandomSongs", { "size=" .. ALBUM_VIEW_SIZE },
                       { song = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  app.cache.shuffle = out.song
  return out.song
end

-- Decades are worked out here rather than asked for: the server has no
-- endpoint for them, and a list of ten entries costs nothing to build.
-- Picking one asks for its albums, and only then.
local function load_decades()
  if app.cache.decades then
    return app.cache.decades
  end
  local now = tonumber(os.date("%Y")) or 2020
  local newest = math.floor(now / 10) * 10
  local list = {}
  local d = newest
  while d >= 1950 do
    table.insert(list, { name = string.format(lang.decade_fmt, d),
                         from = d, to = d + 9 })
    d = d - 10
  end
  app.cache.decades = list
  return list
end

-- The stations the server keeps for its users. Nothing here goes
-- through the library: a station is played from its own URL, so no
-- transcoding, no listening report, and nothing to download.
local function load_radios()
  if app.cache.radios then
    return app.cache.radios
  end
  set_message(lang.msg_loading_radios)
  local out, err = api("getInternetRadioStations", {},
                       { internetRadioStation = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  app.cache.radios = out.internetRadioStation
  return app.cache.radios
end

local function load_artists()
  if app.cache.artists then
    return app.cache.artists
  end
  set_message(lang.msg_loading_artists)
  local out, err = api("getArtists", {}, { artist = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  app.cache.artists = out.artist
  return app.cache.artists
end

local function load_genres()
  if app.cache.genres then
    return app.cache.genres
  end
  set_message(lang.msg_loading_genres)
  local out, err = api("getGenres", {}, { genre = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  -- the name is the text content; sort by it, the server does not
  local genres = {}
  for _, g in ipairs(out.genre) do
    g.name = trim(g.value or "")
    if g.name ~= "" then
      table.insert(genres, g)
    end
  end
  table.sort(genres, function(a, b)
    return fold_accents(a.name) < fold_accents(b.name)
  end)
  app.cache.genres = genres
  return genres
end

local function load_playlists()
  if app.cache.playlists then
    return app.cache.playlists
  end
  set_message(lang.msg_loading_playlists)
  local out, err = api("getPlaylists", {}, { playlist = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return nil
  end
  app.cache.playlists = out.playlist
  return app.cache.playlists
end

-- Songs of one album, in track order (the server's order)
local function album_songs(album_id)
  local out, err = api("getAlbum", { "id=" .. esc(album_id) },
                       { album = true, song = true })
  if not out then
    return nil, err
  end
  return out.song, out.album[1]
end

local function playlist_songs(playlist_id)
  local out, err = api("getPlaylist", { "id=" .. esc(playlist_id) },
                       { playlist = true, entry = true })
  if not out then
    return nil, err
  end
  return out.entry
end

local function artist_albums(artist_id)
  local out, err = api("getArtist", { "id=" .. esc(artist_id) },
                       { artist = true, album = true })
  if not out then
    return nil, err
  end
  return out.album
end

-- A genre listens better in one run than album by album
local function genre_songs(genre_name)
  local out, err = api("getSongsByGenre",
                       { "genre=" .. esc(genre_name),
                         "count=" .. SEARCH_SONGS }, { song = true })
  if not out then
    return nil, err
  end
  return out.song
end

local function decade_albums(from, to)
  local albums = {}
  local offset = 0
  while true do
    still_alive()
    set_message(string.format(lang.msg_loading_albums, #albums))
    local out, err = api("getAlbumList2",
      { "type=byYear", "fromYear=" .. from, "toYear=" .. to,
        "size=" .. PAGE, "offset=" .. offset }, { album = true })
    if not out then
      return nil, err
    end
    for _, a in ipairs(out.album) do
      table.insert(albums, a)
    end
    if #out.album < PAGE or #albums > 200000 then
      break
    end
    offset = offset + PAGE
  end
  return albums
end

local function genre_albums(genre_name)
  local albums = {}
  local offset = 0
  while true do
    still_alive()
    set_message(string.format(lang.msg_loading_albums, #albums))
    local out, err = api("getAlbumList2",
      { "type=byGenre", "genre=" .. esc(genre_name),
        "size=" .. PAGE, "offset=" .. offset },
      { album = true })
    if not out then
      return nil, err
    end
    for _, a in ipairs(out.album) do
      table.insert(albums, a)
    end
    if #out.album < PAGE or #albums > 200000 then
      break
    end
    offset = offset + PAGE
  end
  return albums
end

            --[[ View 2: the browser ]]--

local VIEWS = { "artists", "albums", "random", "shuffle", "newest",
                "recent", "frequent", "decades", "genres", "playlists",
                "radios", "songs" }
local VIEW_LABELS = nil  -- filled from lang at build time

-- What kind of rows a view shows
local VIEW_MODE = {
  artists = "artists", albums = "albums",
  random = "albums", shuffle = "songs",
  newest = "albums", recent = "albums", frequent = "albums",
  decades = "decades",
  genres = "genres", playlists = "playlists", radios = "radios",
  songs = "songs",
}

--[[
 Which column a view opens sorted on, case by case rather than by a
 blanket rule:
   - plain listings of names sort by name, ascending;
   - the listings the server picked BY a figure (added when, played
     when, played how often) sort by that figure, descending -- the
     same order the server sent, but now shown in a column the reader
     can see and click, instead of an order taken on trust;
   - a random draw is ordered by nothing at all. Sorting it would only
     undo the draw, so it is left exactly as it came.
--]]
local VIEW_SORT = {
  artists   = { 1, true },
  albums    = { 1, true },
  genres    = { 1, true },
  playlists = { 1, true },
  radios    = { 1, true },
  newest    = { 4, false },
  recent    = { 4, false },
  frequent  = { 4, false },
  -- random and songs: no order of ours
}

local function current_level()
  return app.stack[#app.stack]
end

-- The root listing of the current view if it has already been fetched.
-- The song view has none: it lists what the last search returned.
function root_cache()
  if app.view == "songs" then
    return app.search_songs or {}
  end
  return app.cache[app.view]
end

function load_root()
  if app.view == "albums" then
    return load_albums()
  elseif ALBUM_VIEWS[app.view] then
    return load_album_view(app.view)
  elseif app.view == "shuffle" then
    return load_shuffle()
  elseif app.view == "decades" then
    return load_decades()
  elseif app.view == "radios" then
    return load_radios()
  elseif app.view == "artists" then
    return load_artists()
  elseif app.view == "genres" then
    return load_genres()
  elseif app.view == "playlists" then
    return load_playlists()
  end
  return app.search_songs or {}
end

-- What the list is showing: "albums", "artists", "genres",
-- "playlists" or "songs", plus the backing array.
local function current_content()
  local level = current_level()
  if level then
    return level.mode, level.items
  end
  return VIEW_MODE[app.view] or "songs", root_cache() or {}
end

local function song_filename(song)
  local track = tonumber(song.track)
  local name = song.title or "?"
  if track then
    name = string.format("%02d - %s", track, name)
  end
  local suffix = song.suffix or "audio"
  return sanitize_filename(name .. "." .. suffix)
end

local function album_label(album)
  return tostring(album.name or "?")
end

-- "2026-07-05T18:56:58.8Z" -> "2026-07-05" and a number that orders the
-- same way, so the column sorts by the instant and reads as a date.
local function iso_date(stamp)
  local y, m, d, hh, mm, ss = string.match(tostring(stamp or ""),
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then
    return "", 0
  end
  return y .. "-" .. m .. "-" .. d,
         tonumber(y .. m .. d .. hh .. mm .. ss) or 0
end

-- The fourth column of an album row depends on the listing: what makes
-- "recently added" or "most played" a listing worth having is exactly
-- the figure it was ordered by, so that figure is what is shown -- and
-- being shown, it can be sorted on like any other column.
local ALBUM_EXTRA = {
  newest   = { field = "created",   label = "col_added"  },
  recent   = { field = "played",    label = "col_played" },
  frequent = { field = "playCount", label = "col_plays"  },
}

-- Row builders: each returns the tab-separated cells and the drag name
local function album_row(album)
  local year = album.year or ""
  local fourth
  local extra = ALBUM_EXTRA[app.album_extra or ""]
  if extra == nil then
    local count = tonumber(album.songCount) or 0
    fourth = sortable(count, count)
  elseif extra.field == "playCount" then
    local plays = tonumber(album.playCount) or 0
    fourth = sortable(plays, plays)
  else
    fourth = sortable(iso_date(album[extra.field]))
  end
  return cell(album_label(album))
      .. "\t" .. cell(album.artist or "")
      .. "\t" .. sortable(year, tonumber(year) or 0)
      .. "\t" .. fourth
      .. "\t" .. sortable(album.starred and "★" or "",
                          album.starred and 1 or 0),
      sanitize_filename(album_label(album))
end

local function artist_row(artist)
  local count = tonumber(artist.albumCount) or 0
  return cell(artist.name or "?")
      .. "\t" .. sortable(count, count)
      .. "\t" .. sortable(artist.starred and "★" or "",
                          artist.starred and 1 or 0),
      sanitize_filename(artist.name or "?")
end

local function genre_row(genre)
  return cell(genre.name)
      .. "\t" .. sortable(genre.albumCount or "0",
                          tonumber(genre.albumCount) or 0)
      .. "\t" .. sortable(genre.songCount or "0",
                          tonumber(genre.songCount) or 0),
      nil
end

local function decade_row(dec)
  return sortable(dec.name, dec.from), nil
end

local function radio_row(st)
  return cell(st.name or "?") .. "\t" .. cell(st.streamUrl or ""), nil
end

local function playlist_row(pl)
  local count = tonumber(pl.songCount) or 0
  return cell(pl.name or "?")
      .. "\t" .. sortable(count, count)
      .. "\t" .. sortable(format_duration(pl.duration),
                          tonumber(pl.duration) or 0),
      sanitize_filename(pl.name or "?")
end

-- Inside an album every row would repeat the album named in the title
-- above, for a column's worth of width: it is left out there.
local function song_row(song)
  local track = tonumber(song.track)
  local row = sortable(track or "", track or 0)
           .. "\t" .. cell(song.title or "?")
           .. "\t" .. cell(song.artist or "")
  if not app.hide_album_column then
    row = row .. "\t" .. cell(song.album or "")
  end
  return row
      .. "\t" .. sortable(format_duration(song.duration),
                          tonumber(song.duration) or 0)
      .. "\t" .. sortable(song.starred and "★" or "",
                          song.starred and 1 or 0),
      song_filename(song)
end

local MODE_HEADERS = nil  -- filled from lang at build time

local function build_labels()
  VIEW_LABELS = {
    albums = lang.view_albums,
    artists = lang.view_artists,
    random = lang.view_random,
    shuffle = lang.view_shuffle,
    decades = lang.view_decades,
    radios = lang.view_radios,
    newest = lang.view_newest,
    recent = lang.view_recent,
    frequent = lang.view_frequent,
    genres = lang.view_genres,
    playlists = lang.view_playlists,
    songs = lang.view_songs,
  }
  local fourth = lang.col_songs
  local extra = ALBUM_EXTRA[app.album_extra or ""]
  if extra then
    fourth = lang[extra.label]
  end
  MODE_HEADERS = {
    albums = lang.col_album .. "\t" .. lang.col_artist .. "\t"
          .. lang.col_year .. "\t" .. fourth .. "\t" .. lang.col_star,
    artists = lang.col_artist .. "\t" .. lang.col_albums .. "\t"
           .. lang.col_star,
    genres = lang.col_genre .. "\t" .. lang.col_albums .. "\t"
          .. lang.col_songs,
    decades = lang.col_decade,
    radios = lang.col_station .. "\t" .. lang.col_stream,
    playlists = lang.col_playlist .. "\t" .. lang.col_songs .. "\t"
             .. lang.col_duration,
    songs_in_album = lang.col_track .. "\t" .. lang.col_title .. "\t"
                  .. lang.col_artist .. "\t"
                  .. lang.col_duration .. "\t" .. lang.col_star,
    songs = lang.col_track .. "\t" .. lang.col_title .. "\t"
         .. lang.col_artist .. "\t" .. lang.col_album .. "\t"
         .. lang.col_duration .. "\t" .. lang.col_star,
  }
end

--[[
 What the search box matches an item against, folded once and kept on
 the item itself: the alternative is running every name of the listing
 through a byte-wise gsub again on each character typed, for a list
 whose contents did not change.
--]]
local function search_key(mode, obj)
  local key = obj.powervlc_key
  if key == nil then
    local hay
    if mode == "albums" then
      hay = (obj.name or "") .. " " .. (obj.artist or "")
    elseif mode == "songs" then
      hay = (obj.title or "") .. " " .. (obj.artist or "") .. " "
         .. (obj.album or "")
    else
      hay = obj.name or ""
    end
    key = fold_accents(hay)
    obj.powervlc_key = key
  end
  return key
end

-- Does this row pass the search box and the favorites filter?
local function row_passes(mode, obj, query, starred_only)
  -- there is no such thing as a favorite genre, decade or station
  if starred_only and mode ~= "genres" and mode ~= "playlists"
     and mode ~= "decades" and mode ~= "radios" and not obj.starred then
    return false
  end
  if query == "" then
    return true
  end
  return string.find(search_key(mode, obj), query, 1, true) ~= nil
end

-- (Re)fill the list from the current content, filters applied
function fill_list()
  if not ui.items then
    return
  end
  local mode, items = current_content()
  local query = fold_accents(trim(ui.search and ui.search:get_text() or ""))
  local starred_only = ui.starred and ui.starred:get_checked() or false

  -- the song view searches server-side: its box is not a local filter
  if mode == "songs" and not current_level() then
    query = ""
  end

  app.rows = {}
  ui.items:clear()
  local builders = {
    albums = album_row, artists = artist_row, genres = genre_row,
    playlists = playlist_row, songs = song_row, decades = decade_row,
    radios = radio_row,
  }
  local build = builders[mode]
  local shown = 0
  for _, obj in ipairs(items) do
    if row_passes(mode, obj, query, starred_only) then
      shown = shown + 1
      -- a listing of a few thousand rows takes a while to build: say so
      -- to the watchdog rather than be taken for a hung script
      if shown % 500 == 0 then
        still_alive()
      end
      app.rows[shown] = { kind = mode, obj = obj }
      local text, dragname = build(obj)
      ui.items:add_value(text, shown, dragname)
    end
  end

  if mode == "songs" and not current_level() and #items == 0 then
    set_message(app.search_query == "" and lang.msg_search_hint
                                        or lang.msg_no_content)
  else
    set_message(string.format(
      mode == "songs" and lang.msg_count_songs or lang.msg_count,
      shown, #items))
  end
end

-- The context menu offered on the current list; actions resolved by key
local function menu_for_mode(mode)
  local labels, actions
  if mode == "radios" then
    -- a station cannot be downloaded, starred or opened: it is played
    labels, actions = { lang.menu_play, lang.menu_enqueue },
                      { "play", "enqueue" }
  elseif mode == "decades" then
    labels, actions = { lang.menu_open }, { "open" }
  elseif mode == "genres" then
    labels = { lang.menu_open, lang.menu_open_songs }
    actions = { "open", "open_songs" }
  elseif mode == "playlists" then
    labels = { lang.menu_open, lang.menu_play, lang.menu_enqueue,
               lang.menu_download }
    actions = { "open", "play", "enqueue", "download" }
  elseif mode == "songs" then
    labels = { lang.menu_play, lang.menu_enqueue, lang.menu_download,
               lang.menu_star, lang.menu_unstar }
    actions = { "play", "enqueue", "download", "star", "unstar" }
  else  -- albums, artists
    labels = { lang.menu_open, lang.menu_play, lang.menu_enqueue,
               lang.menu_download, lang.menu_star, lang.menu_unstar }
    actions = { "open", "play", "enqueue", "download", "star", "unstar" }
  end

  -- An account without the download right is offered no download: a
  -- refusal from the server is a worse answer than not asking.
  if app.rights.download == false then
    local l, a = {}, {}
    for i, action in ipairs(actions) do
      if action ~= "download" then
        table.insert(l, labels[i])
        table.insert(a, action)
      end
    end
    labels, actions = l, a
  end
  return labels, actions
end

-- Rebuild the whole browser dialog for the current view / drill level
function show_browser()
  -- which figure the album rows carry, settled before the headers are
  -- built and before any row is made
  app.album_extra = nil
  if not current_level() and ALBUM_EXTRA[app.view] then
    app.album_extra = app.view
  end
  build_labels()
  close_dlg()
  dlg = vlc.dialog(lang.title_browse)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)

  local level = current_level()
  local mode = select(1, current_content())
  local row = 1

  -- read by song_row, so it must be settled before the list is filled
  app.hide_album_column = false
  if mode == "songs" and level and level.in_album then
    app.hide_album_column = true
  end

  -- top bar
  if level then
    dlg:add_button(lang.btn_back, click_back, 1, row, 1, 1)
  else
    dlg:add_button(lang.btn_connection, show_connect, 1, row, 1, 1)
  end
  ui.view = dlg:add_dropdown(2, row, 1, 1, click_view_changed)
  for i, key in ipairs(VIEWS) do
    ui.view:add_value(VIEW_LABELS[key], i)
  end
  for i, key in ipairs(VIEWS) do
    if key == app.view then
      ui.view:set_value(i)
    end
  end
  -- The filter belongs to the listing on screen, like the search box:
  -- opening an album because it is a favorite and finding it empty --
  -- none of its tracks being starred one by one -- reads as a bug.
  -- spelled out rather than "a and b or c": the value wanted here is
  -- often false, and that idiom falls through to the other branch
  local starred_now
  if level then
    starred_now = level.starred or false
  else
    starred_now = app.starred_only or false
  end
  ui.starred = dlg:add_check_box(lang.chk_starred, starred_now,
                                 3, row, 1, 1, click_starred_toggled)
  dlg:add_button(lang.btn_refresh, click_refresh, 4, row, 1, 1)
  row = row + 1

  -- the level's own title (album name, artist, genre...)
  if level and level.title then
    dlg:add_label("<b>" .. cell(level.title) .. "</b>", 1, row, 4, 1)
    row = row + 1
  end

  -- search
  dlg:add_label(lang.lbl_search, 1, row, 1, 1)
  ui.search = dlg:add_text_input(level and (level.query or "")
                                 or app.search_query or "",
                                 2, row, 3, 1,
                                 click_search_validate, click_search_changed)
  row = row + 1

  -- the list itself; the cover (when there is one) takes column 5
  local list_rows = 1
  ui.items = dlg:add_list(1, row, (level and level.art) and 4 or 5, list_rows,
                          click_open_row, nil)
  ui.items:set_text(MODE_HEADERS[app.hide_album_column and "songs_in_album"
                                 or mode])
  -- Name listings open in the order the platform sorts names in, which
  -- is the order a click on that header gives: the two agree because
  -- the interface does both. Everything whose order carries meaning --
  -- an album's tracks, a playlist, the server's own "recently added" --
  -- is left exactly as it came.
  local sort_col, sort_asc
  if level then
    sort_col, sort_asc = level.sort_col, level.sort_asc
  elseif VIEW_SORT[app.view] then
    sort_col, sort_asc = VIEW_SORT[app.view][1], VIEW_SORT[app.view][2]
  end
  if sort_col then
    ui.items:set_sort(sort_col, sort_asc)
  end
  local labels, actions = menu_for_mode(mode)
  app.menu_actions = actions
  ui.items:set_menu(labels, click_menu)
  ui.items:set_drag(on_drop)
  if level and level.art then
    -- centred on the list it sits beside, rather than hanging from its
    -- top edge: it belongs to the whole album, not to its first track
    -- the bounds are stated, so the layout knows the size the picture is
    -- meant to take even if the file that arrived is bigger
    dlg:add_image(level.art, 5, row, 1, list_rows,
                  ARTWORK_SIZE, ARTWORK_SIZE):set_centered(true)
  end
  row = row + list_rows

  -- action buttons
  dlg:add_button(lang.btn_play, click_play, 1, row, 1, 1)
  dlg:add_button(lang.btn_enqueue, click_enqueue, 2, row, 1, 1)
  -- no download button for an account the server would refuse
  if app.rights.download ~= false then
    dlg:add_button(lang.btn_download, click_download, 3, row, 1, 1)
  end
  ui.transcode_toggle = dlg:add_button(
    (app.show_transcode and "\226\150\188 " or "\226\150\182 ")
      .. lang.sec_transcode,
    click_toggle_transcode, 4, row, 2, 1)
  row = row + 1

  if app.show_transcode then
    dlg:add_label(lang.lbl_format, 1, row, 1, 1)
    ui.format = dlg:add_dropdown(2, row, 1, 1, click_transcode_changed)
    ui.format:add_value(lang.fmt_raw, 1)
    for i = 2, #FORMATS do
      ui.format:add_value(string.upper(FORMATS[i]), i)
    end
    for i, f in ipairs(FORMATS) do
      if f == (app.pref_format or DEFAULT_FORMAT) then
        ui.format:set_value(i)
      end
    end
    dlg:add_label(lang.lbl_maxrate, 3, row, 1, 1)
    ui.bitrate = dlg:add_dropdown(4, row, 1, 1, click_transcode_changed)
    for i, r in ipairs(BITRATES) do
      ui.bitrate:add_value(r .. " kb/s", i)
    end
    for i, r in ipairs(BITRATES) do
      if r == (app.pref_bitrate or DEFAULT_BITRATE) then
        ui.bitrate:set_value(i)
      end
    end
    row = row + 1
    -- Only where it would work: the server has to support the offset
    -- (an OpenSubsonic extension it announces), and it only means
    -- something for a stream the server is encoding as it goes.
    if app.has_offset and (app.pref_format or DEFAULT_FORMAT) ~= "raw" then
      dlg:add_label(lang.lbl_start_at, 1, row, 1, 1)
      ui.offset = dlg:add_text_input(app.start_at or "", 2, row, 1, 1)
      dlg:add_label(lang.hint_start_at, 3, row, 3, 1)
      row = row + 1
    end
    dlg:add_label(lang.hint_transcode, 1, row, 5, 1)
    row = row + 1
  end

  ui.message = dlg:add_label("", 1, row, 5, 1)
  row = row + 1
  ui.dlmsg = dlg:add_label("", 1, row, 4, 1)
  if dl.active then
    ui.dlcancel = dlg:add_button(lang.btn_dl_cancel, click_dl_cancel,
                                 5, row, 1, 1)
  end

  -- shown before the data loads: the loading messages then have a
  -- window to appear in
  dlg:show()

  -- Nothing is fetched on arrival: signing in should not commit the
  -- user to whichever view happens to be selected, and on a slow
  -- machine that first listing is a long wait to sit through before
  -- being allowed to change one's mind. Picking a view (or Refresh)
  -- is what asks for it; once fetched, it stays cached.
  local loaded = true
  if not level and root_cache() == nil then
    if app.load_root then
      loaded = load_root() ~= nil
    else
      loaded = false
      set_message(lang.msg_pick_view)
    end
  end
  if loaded then
    fill_list()
  end
  -- said once, on the screen the connection lands on
  if app.secret_plain then
    set_message(string.format(lang.msg_secret_plain, settings_path() or "?"))
    app.secret_plain = false
  end
end

            --[[ Browser callbacks ]]--

function click_view_changed()
  local id = ui.view and ui.view:get_value()
  local key = VIEWS[id]
  if not key or (key == app.view and #app.stack == 0) then
    return
  end
  app.view = key
  app.stack = {}
  -- a new view starts unfiltered: carrying the previous view's search
  -- over silently empties the list
  app.search_query = ""
  app.search_songs = {}
  -- picking a view is the request to fetch it
  app.load_root = true
  save_prefs()
  show_browser()
end

function click_starred_toggled()
  local checked = ui.starred and ui.starred:get_checked() or false
  local level = current_level()
  if level then
    level.starred = checked
  else
    app.starred_only = checked
  end
  -- the song search view has no local list to filter without a query:
  -- checked there, it shows the starred songs instead
  if not level and app.view == "songs" and app.search_query == "" then
    if checked then
      local out = api("getStarred2", {}, { song = true })
      app.search_songs = out and out.song or {}
    else
      app.search_songs = {}
    end
  end
  fill_list()
end

function click_refresh()
  local level = current_level()
  if level then
    -- re-open the level from its source
    if level.reload then
      level.reload(level)
    end
  else
    -- drop what was cached for this view: refreshing is also how the
    -- random draw is asked for again
    app.cache[app.view] = nil
    -- refreshing a root listing is the request to fetch it
    app.load_root = true
  end
  show_browser()
end

function click_back()
  table.remove(app.stack)
  show_browser()
end

function click_search_changed()
  local level = current_level()
  if level then
    level.query = ui.search and ui.search:get_text() or ""
    fill_list()
    return
  end
  if app.view ~= "songs" then
    app.search_query = ui.search and ui.search:get_text() or ""
    fill_list()
    return
  end
  -- server-side song search, as you type (the interface debounces)
  local query = trim(ui.search and ui.search:get_text() or "")
  if query == app.search_query then
    return
  end
  app.search_query = query
  if #query < 2 then
    app.search_songs = {}
    fill_list()
    return
  end
  set_message(lang.msg_searching)
  local out, err = api("search3",
    { "query=" .. esc(query), "songCount=" .. SEARCH_SONGS,
      "albumCount=0", "artistCount=0" },
    { song = true })
  if not out then
    set_message(lang.msg_api_fail .. tostring(err))
    return
  end
  app.search_songs = out.song
  fill_list()
end

function click_search_validate()
  click_search_changed()
end

            --[[ Selection plumbing ]]--

-- The selected rows, in display order
local function selected_rows()
  if not ui.items then
    return {}
  end
  local sel = ui.items:get_selection()
  local rows = {}
  for i, row in ipairs(app.rows) do
    if sel[i] then
      table.insert(rows, row)
    end
  end
  return rows
end

-- Selection, or -- inside a drill level -- everything: "Play" on an
-- opened album with nothing picked means the album.
local function selected_or_all()
  local rows = selected_rows()
  -- a drawn-at-random listing is meant to be played whole, like the
  -- contents of something one has opened
  if #rows == 0 and (current_level() or app.view == "shuffle") then
    for _, row in ipairs(app.rows) do
      table.insert(rows, row)
    end
  end
  return rows
end

--[[
 Turn a mix of selected rows into a flat song list, fetching whatever
 the server has to be asked for. Also builds the per-song download
 subfolder when for_download is set (albums land in a folder of their
 name, artists in artist/album, playlists in a folder of theirs).
 Returns a list of { song = ..., subdir = nil | "a" | "a/b" }.
--]]
local function resolve_songs(rows, for_download)
  local out = {}
  local function add(song, subdir)
    table.insert(out, { song = song, subdir = subdir })
  end
  local total = #rows
  for i, row in ipairs(rows) do
    still_alive()
    set_message(string.format(lang.msg_loading_songs, i, total))
    if row.kind == "songs" then
      add(row.obj, nil)
    elseif row.kind == "albums" then
      local songs = album_songs(row.obj.id)
      local subdir = for_download and sanitize_filename(album_label(row.obj))
                     or nil
      for _, s in ipairs(songs or {}) do
        add(s, subdir)
      end
    elseif row.kind == "artists" then
      local albums = artist_albums(row.obj.id) or {}
      for _, al in ipairs(albums) do
        local songs = album_songs(al.id)
        local subdir = for_download
          and (sanitize_filename(row.obj.name or "?") .. "/"
               .. sanitize_filename(album_label(al)))
          or nil
        for _, s in ipairs(songs or {}) do
          add(s, subdir)
        end
      end
    elseif row.kind == "playlists" then
      local songs = playlist_songs(row.obj.id) or {}
      local subdir = for_download and sanitize_filename(row.obj.name or "?")
                     or nil
      for _, s in ipairs(songs) do
        add(s, subdir)
      end
    end
    -- genres are not resolved wholesale: open them instead
  end
  return out
end

            --[[ Opening, playing, queueing ]]--

local function fetch_album_art(album)
  local cover = album.coverArt
  local dir = vlc.config.userdatadir()
  if not cover or not dir or dir == "" then
    return nil
  end
  local path = dir .. "/subsonic-art-" .. sanitize_filename(album.id)
            .. "-" .. ARTWORK_SIZE .. ".jpg"
  local cached = io.open(path, "rb")
  if cached then
    local size = cached:seek("end")
    cached:close()
    if size and size > 128 then
      return path
    end
  end
  set_message(lang.msg_loading_art)
  local body = get_body(cover_url(cover, ARTWORK_SIZE))
  if not body or #body < 128 then
    return nil
  end
  -- What comes back is whatever the server had: the size asked for is
  -- a wish, not a promise (some covers arrive untouched at 1024 square,
  -- and in WebP, which the older machines cannot display at all). The
  -- core decodes it and writes a JPEG of the size actually wanted --
  -- otherwise the picture dictates the layout and the window ends up
  -- taller than the screen.
  local raw = path .. ".part"
  local f = io.open(raw, "wb")
  if not f then
    return nil
  end
  f:write(body)
  f:close()

  local scaled = false
  if vlc.misc and vlc.misc.image_scale then
    local ok, width = pcall(vlc.misc.image_scale, raw, path,
                            ARTWORK_SIZE, ARTWORK_SIZE)
    if ok and width then
      local check = io.open(path, "rb")
      if check then
        local written = check:seek("end")
        check:close()
        scaled = written ~= nil and written > 128
      end
    end
  end
  if scaled then
    os.remove(raw)
  else
    -- no image support to lean on: keep what the server sent
    os.remove(path)
    os.rename(raw, path)
  end

  if app.art_path and app.art_path ~= path then
    os.remove(app.art_path)
  end
  app.art_path = path
  return path
end

local function push_album_level(album)
  set_message(lang.msg_loading_album)
  local songs, full = album_songs(album.id)
  if not songs then
    set_message(lang.msg_no_content)
    return
  end
  local shown = full or album
  table.insert(app.stack, {
    mode = "songs",
    items = songs,
    in_album = true,
    title = album_label(shown) .. " — " .. (shown.artist or "")
         .. ((shown.year and shown.year ~= "") and (" (" .. shown.year .. ")")
             or ""),
    art = fetch_album_art(shown),
    reload = function(level)
      level.items = album_songs(album.id) or level.items
    end,
  })
  show_browser()
end

local function push_artist_level(artist)
  local albums = artist_albums(artist.id)
  if not albums then
    set_message(lang.msg_no_content)
    return
  end
  table.insert(app.stack, {
    mode = "albums",
    items = albums,
    title = artist.name or "?",
    -- a discography reads newest first, not alphabetically (column 3 is
    -- the year, and it carries a numeric sort key)
    sort_col = 3,
    sort_asc = false,
    reload = function(level)
      level.items = artist_albums(artist.id) or level.items
    end,
  })
  show_browser()
end

local function push_genre_level(genre)
  local albums = genre_albums(genre.name)
  if not albums then
    set_message(lang.msg_no_content)
    return
  end
  table.insert(app.stack, {
    mode = "albums",
    items = albums,
    title = genre.name,
    sort_col = 1,
    sort_asc = true,
    reload = function(level)
      level.items = genre_albums(genre.name) or level.items
    end,
  })
  show_browser()
end

function push_genre_songs(genre)
  set_message(lang.msg_loading_album)
  local songs = genre_songs(genre.name)
  if not songs or #songs == 0 then
    set_message(lang.msg_no_content)
    return
  end
  table.insert(app.stack, {
    mode = "songs",
    items = songs,
    title = genre.name,
    reload = function(level)
      level.items = genre_songs(genre.name) or level.items
    end,
  })
  show_browser()
end

local function push_decade_level(dec)
  local albums, err = decade_albums(dec.from, dec.to)
  if not albums then
    set_message(lang.msg_api_fail .. tostring(err or "?"))
    return
  end
  if #albums == 0 then
    set_message(lang.msg_no_content)
    return
  end
  table.insert(app.stack, {
    mode = "albums",
    items = albums,
    title = dec.name,
    sort_col = 3,
    sort_asc = true,
    reload = function(level)
      level.items = decade_albums(dec.from, dec.to) or level.items
    end,
  })
  show_browser()
end

local function push_playlist_level(pl)
  local songs = playlist_songs(pl.id)
  if not songs then
    set_message(lang.msg_no_content)
    return
  end
  table.insert(app.stack, {
    mode = "songs",
    items = songs,
    title = pl.name or "?",
    reload = function(level)
      level.items = playlist_songs(pl.id) or level.items
    end,
  })
  show_browser()
end

local function open_row(row)
  if row.kind == "albums" then
    push_album_level(row.obj)
  elseif row.kind == "artists" then
    push_artist_level(row.obj)
  elseif row.kind == "genres" then
    push_genre_level(row.obj)
  elseif row.kind == "decades" then
    push_decade_level(row.obj)
  elseif row.kind == "playlists" then
    push_playlist_level(row.obj)
  elseif row.kind == "songs" then
    play_songs({ { song = row.obj } })
  elseif row.kind == "radios" then
    play_rows({ row }, false)
  end
end

-- Double-click (or the Open menu entry)
function click_open_row()
  local rows = selected_rows()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  open_row(rows[1])
end

local function song_playlist_item(song, offset)
  local item = {
    path = stream_url(song, offset),
    name = song.title or "?",
    title = song.title or "?",
    artist = song.artist,
    album = song.album,
    duration = tonumber(song.duration),
  }
  if song.coverArt then
    item.arturl = cover_url(song.coverArt, 600)
  end
  return item
end

-- One playlist call for the whole batch: consecutive items are what
-- the gapless machinery joins seamlessly.
function play_songs(entries)
  local items = {}
  -- Starting elsewhere than at the beginning only makes sense for one
  -- track; on a batch it would be an odd thing to do to every song.
  local offset = 0
  if #entries == 1 and ui.offset then
    offset = parse_offset(ui.offset:get_text())
    app.start_at = ui.offset:get_text()
  end
  for _, e in ipairs(entries) do
    table.insert(items, song_playlist_item(e.song, offset))
  end
  if #items == 0 then
    set_message(lang.msg_no_content)
    return
  end
  set_message(string.format(lang.msg_playing, #items))
  vlc.playlist.add(items)
end

local function enqueue_songs(entries)
  local items = {}
  for _, e in ipairs(entries) do
    table.insert(items, song_playlist_item(e.song))
  end
  if #items == 0 then
    set_message(lang.msg_no_content)
    return
  end
  set_message(string.format(lang.msg_queued, #items))
  vlc.playlist.enqueue(items)
end

-- A station is played from its own URL: nothing to resolve, nothing to
-- transcode, and it is not a library track, so nothing to report either.
local function play_radios(rows, queue)
  local items = {}
  for _, row in ipairs(rows) do
    local url = row.obj.streamUrl
    if url and url ~= "" then
      table.insert(items, { path = url,
                            name = row.obj.name or url,
                            title = row.obj.name or url })
    end
  end
  if #items == 0 then
    set_message(lang.msg_no_content)
    return
  end
  if queue then
    set_message(string.format(lang.msg_queued, #items))
    vlc.playlist.enqueue(items)
  else
    set_message(string.format(lang.msg_playing, #items))
    vlc.playlist.add(items)
  end
end

-- The one door to playback, so that every way in -- button, menu,
-- double-click -- treats stations and library tracks alike.
function play_rows(rows, queue)
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  if rows[1].kind == "radios" then
    play_radios(rows, queue)
    return
  end
  local entries = resolve_songs(rows, false)
  if queue then
    enqueue_songs(entries)
  else
    play_songs(entries)
  end
end

function click_play()
  play_rows(selected_or_all(), false)
end

function click_enqueue()
  play_rows(selected_or_all(), true)
end

            --[[ Favorites ]]--

-- The id parameter star/unstar wants depends on what is starred
local function star_param(row)
  if row.kind == "albums" then
    return "albumId=" .. esc(row.obj.id)
  elseif row.kind == "artists" then
    return "artistId=" .. esc(row.obj.id)
  end
  return "id=" .. esc(row.obj.id)
end

local function set_starred(rows, starred)
  local endpoint = starred and "star" or "unstar"
  for _, row in ipairs(rows) do
    local out, err = api(endpoint, { star_param(row) }, {})
    if not out then
      set_message(lang.msg_star_fail .. tostring(err))
      return
    end
    -- mirror the server: the attribute is a date when set, absent when not
    row.obj.starred = starred and "now" or nil
  end
  fill_list()
  set_message(starred and lang.msg_starred or lang.msg_unstarred)
end

            --[[ Context menu ]]--

function click_menu(entry)
  local action = app.menu_actions[entry]
  if not action then
    return
  end
  local rows = selected_rows()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  if action == "open" then
    open_row(rows[1])
  elseif action == "open_songs" then
    push_genre_songs(rows[1].obj)
  elseif action == "play" then
    play_rows(rows, false)
  elseif action == "enqueue" then
    play_rows(rows, true)
  elseif action == "download" then
    download_rows(rows, nil)
  elseif action == "star" then
    set_starred(rows, true)
  elseif action == "unstar" then
    set_starred(rows, false)
  end
end

            --[[ Transcoding section ]]--

function click_toggle_transcode()
  app.show_transcode = not app.show_transcode
  save_prefs()
  show_browser()
end

function click_transcode_changed()
  local id = ui.format and ui.format:get_value()
  if id and FORMATS[id] then
    app.pref_format = FORMATS[id]
  end
  id = ui.bitrate and ui.bitrate:get_value()
  if id and BITRATES[id] then
    app.pref_bitrate = BITRATES[id]
  end
  save_prefs()
end

            --[[ Downloads ]]--

-- 24 cells of a bar the width every interface font gets roughly right
local function progress_bar(got, total)
  local width = 24
  local filled = 0
  if total > 0 then
    filled = math.floor(got * width / total)
  end
  if filled > width then
    filled = width
  end
  return string.rep("\226\150\136", filled)
      .. string.rep("\226\150\145", width - filled)
end

function dl_close_current()
  if dl.fh then
    dl.fh:close()
    dl.fh = nil
  end
  dl.stream = nil
end

-- Cut a string to a length, never inside a UTF-8 sequence
local function ellipsize(s, max)
  s = tostring(s or "")
  if #s <= max then
    return s
  end
  -- Judged on the first byte DROPPED, exactly as in sanitize_filename
  -- above and for the same two reasons: a clean cut must not cost a whole
  -- character, and a cut landing on a lead byte must take that byte with
  -- it rather than leave it standing without its continuation.
  local cut = max
  while cut > 0 do
    local b = string.byte(s, cut + 1)
    if not b or b < 128 or b >= 192 then
      break
    end
    cut = cut - 1
  end
  return string.sub(s, 1, cut) .. "…"
end

local function dl_update_label()
  if not ui.dlmsg then
    return
  end
  local cur = dl.files[dl.idx]
  -- Bounded: this line is rewritten several times a second, and a
  -- window that grows to fit a long title never shrinks back.
  local name = cur and cur.song and ellipsize(cur.song.title or "?", 48) or ""
  local done = dl.total_got + dl.got
  local percent = 0
  if dl.total > 0 then
    percent = math.floor(done * 100 / dl.total)
  end
  ui.dlmsg:set_text(string.format(lang.dl_progress,
    progress_bar(done, dl.total), percent, cell(name),
    dl.idx, #dl.files, format_bytes(done), format_bytes(dl.total)))
  if dlg then
    dlg:update()
  end
end

local function dl_finish(cancelled)
  dl_close_current()
  dl.active = false
  local msg
  if cancelled then
    msg = lang.dl_cancelled
  elseif dl.files_failed > 0 then
    msg = string.format(lang.dl_done_errors, dl.files_ok, dl.files_failed,
                        dl.base or "?")
  else
    msg = string.format(lang.dl_done, dl.files_ok, dl.base or "?")
  end
  if ui.dlmsg then
    ui.dlmsg:set_text(msg)
  end
  if ui.dlcancel then
    pcall(function() dlg:del_widget(ui.dlcancel) end)
    ui.dlcancel = nil
  end
  if dlg then
    dlg:update()
  end
end

function click_dl_cancel()
  dl.cancelled = true
end

-- Has the current track been listened to long enough to count?
local function check_scrobble()
  if not now_playing.id or now_playing.submitted
     or not now_playing.deadline then
    return
  end
  local ok, input = pcall(vlc.object.input)
  if not ok or not input then
    return
  end
  local got, elapsed = pcall(vlc.var.get, input, "time")
  if not got or type(elapsed) ~= "number" then
    return
  end
  if elapsed / 1000000 >= now_playing.deadline then
    now_playing.submitted = true
    tell_server(now_playing.id, true)
  end
end

-- One pending callback exists per extension, so one tick does both
-- jobs: a download moves in bounded slices (clicks queue up behind a
-- slice, not behind the whole file), and playback is watched for the
-- moment it counts as played. It only re-arms while there is something
-- to do, so an idle extension costs nothing.
function arm_tick()
  if dl.active then
    vlc.timer(15, "subsonic_tick")
  elseif now_playing.id and not now_playing.submitted then
    vlc.timer(2000, "subsonic_tick")
  end
end

local function dl_step()
  if dl.cancelled then
    dl_finish(true)
    return
  end

  if not dl.stream then
    -- next file
    dl.idx = dl.idx + 1
    if dl.idx > #dl.files then
      dl_finish(false)
      return
    end
    local cur = dl.files[dl.idx]
    dl.got = 0
    local ok, stream = pcall(vlc.stream, download_url(cur.song))
    local fh = nil
    if ok and stream then
      fh = io.open(cur.path, "wb")
    end
    if not fh then
      dl.files_failed = dl.files_failed + 1
      vlc.msg.err("[Subsonic] cannot download to " .. tostring(cur.path))
      return
    end
    dl.stream = stream
    dl.fh = fh
  end

  local finished = false
  for _ = 1, DL_CHUNKS_PER_TICK do
    local chunk = dl.stream:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      finished = true
      break
    end
    dl.fh:write(chunk)
    dl.got = dl.got + #chunk
  end

  if finished then
    dl.fh:close()
    dl.fh = nil
    dl.stream = nil
    dl.files_ok = dl.files_ok + 1
    -- keep the totals honest even when the size announced was off
    dl.total = dl.total - (dl.files[dl.idx].size or 0) + dl.got
    dl.total_got = dl.total_got + dl.got
    dl.got = 0
  end

  dl_update_label()
end

function subsonic_tick()
  check_scrobble()
  if dl.active then
    dl_step()
  end
  arm_tick()
end

-- Queue a download of the given entries below base_dir. Entries whose
-- subdir is set land in that (created) folder.
local function start_download(entries, base_dir)
  if dl.active then
    set_message(lang.dl_busy)
    return
  end
  dl.files = {}
  dl.idx = 0
  dl.got = 0
  dl.total = 0
  dl.total_got = 0
  dl.files_ok = 0
  dl.files_failed = 0
  dl.cancelled = false
  dl.base = base_dir

  for _, e in ipairs(entries) do
    local dir = base_dir
    if e.subdir then
      dir = dir .. "/" .. e.subdir
    end
    mkdir_p(dir)
    local size = tonumber(e.song.size) or 0
    table.insert(dl.files, {
      song = e.song,
      path = dir .. "/" .. song_filename(e.song),
      size = size,
    })
    dl.total = dl.total + size
  end
  if #dl.files == 0 then
    set_message(lang.msg_no_content)
    return
  end

  dl.active = true
  -- The view places the Cancel button itself, next to the progress
  -- line, so rebuilding is how it gets one. Dropping it into a row of
  -- its own instead made the grid as tall as the row number asked for:
  -- the window shot down the screen the moment a download began.
  if dlg and not ui.dlcancel then
    show_browser()
  end
  dl_update_label()
  arm_tick()
end

-- Download the given rows; dest nil = the user's Downloads folder
function download_rows(rows, dest)
  for _, row in ipairs(rows) do
    if row.kind == "genres" then
      set_message(lang.msg_no_genre_download)
      return
    end
  end
  if not dest then
    local home = vlc.config.homedir() or "."
    dest = home .. "/Downloads"
    mkdir_p(dest)
  end
  set_message(lang.dl_preparing)
  local entries = resolve_songs(rows, true)
  start_download(entries, dest)
end

function click_download()
  local rows = selected_or_all()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  download_rows(rows, nil)
end

-- Rows dragged out to the Finder: the drop folder arrives here. The
-- promised names are exactly the drag names the rows were added with,
-- which is what download_rows creates.
function on_drop(dest_dir)
  if not dest_dir or dest_dir == "" then
    return
  end
  local rows = selected_rows()
  if #rows == 0 then
    return
  end
  download_rows(rows, dest_dir)
end
