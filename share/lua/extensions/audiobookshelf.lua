--[[
 audiobookshelf.lua : Audiobookshelf browser extension for PowerVLC

 Browse Audiobookshelf book and podcast libraries by item, series,
 author, collection or playlist; search the server, resume listening,
 and keep Audiobookshelf progress in sync while VLC plays the original
 audio files.

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
local PAGE = 500
local DIALOG_WIDTH = 920
local DIALOG_HEIGHT = 520

-- Keep this table empty until activate(): the extension scanner loads this
-- file in a deliberately bare Lua state in order to call descriptor().
local lang = {}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("audiobookshelf") })
end

local app = {
  server = nil,
  token = nil,
  username = nil,
  user = nil,
  rights = {},
  device_id = nil,

  last_server = "https://",
  last_user = "",
  last_token = "",
  remember = false,
  keystore_broken = false,
  secret_denied = false,
  secret_plain = false,

  libraries = {},
  library_map = {},
  library_id = nil,
  view = "items",
  cache = {},
  stack = {},
  rows = {},
  search_query = "",
  menu_actions = {},
  view_keys = {},
}

-- One Audiobookshelf playback session at a time. Starting a second session
-- on the same device closes the first one server-side, so queued items use
-- authenticated file URLs while the item started with Play gets progress
-- synchronization and resume support.
local playback = {
  session_id = nil,
  library_item_id = nil,
  episode_id = nil,
  duration = 0,
  tracks = {},
  track = nil,
  last_elapsed = nil,
  last_absolute = nil,
  last_tick = nil,
  sync_armed = false,
  seen_input = false,
}

local dlg = nil
local ui = {}

function descriptor()
  return {
    title = "Audiobookshelf",
    version = "1.0",
    author = "PowerVLC",
    url = "https://www.audiobookshelf.org/",
    shortdesc = "Audiobookshelf",
    description = "Browse Audiobookshelf audiobook and podcast libraries, "
               .. "search, resume playback and synchronize listening progress.",
    capabilities = { "input-listener" }
  }
end

function activate()
  load_lang()
  json = require("dkjson")
  init_headers()
  math.randomseed(os.time())
  vlc.msg.dbg("[Audiobookshelf] Welcome")
  load_settings()
  if not app.device_id then
    app.device_id = string.format("PowerVLC-%08x-%08x",
      os.time() % 0x7fffffff, math.random(0, 0x7fffffff))
  end
  show_connect()
end

function deactivate()
  close_playback_session()
  close_dlg()
  vlc.msg.dbg("[Audiobookshelf] Bye")
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

local function still_alive()
  if vlc.keep_alive then
    pcall(vlc.keep_alive)
  end
end

local function esc(value)
  return vlc.strings.encode_uri_component(tostring(value))
end

local function cell(s)
  return (string.gsub(tostring(s or ""), "[\t\r\n\031]", " "))
end

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

local function format_date(value)
  if type(value) == "number" then
    return os.date("%Y-%m-%d", math.floor(value / 1000))
  end
  if type(value) == "string" then
    return string.sub(value, 1, 16)
  end
  return ""
end

local function join_names(values)
  if type(values) ~= "table" then
    return ""
  end
  local names = {}
  for _, value in ipairs(values) do
    if type(value) == "table" then
      value = value.name
    end
    if value and value ~= "" then
      table.insert(names, value)
    end
  end
  return table.concat(names, ", ")
end

local function metadata(item)
  if type(item) ~= "table" then
    return {}
  end
  if type(item.media) == "table" and type(item.media.metadata) == "table" then
    return item.media.metadata
  end
  return item.metadata or {}
end

local function item_title(item)
  local md = metadata(item)
  return md.title or item.title or item.name or "?"
end

local function item_author(item)
  local md = metadata(item)
  return md.authorName or md.authorNameLF or join_names(md.authors)
end

local function item_series(item)
  local md = metadata(item)
  if type(md.seriesName) == "string" then
    return md.seriesName
  end
  if type(md.series) == "table" then
    if md.series.name then
      return md.series.name
    end
    local values = {}
    for _, series in ipairs(md.series) do
      local name = series.name or ""
      if series.sequence and series.sequence ~= "" then
        name = name .. " #" .. series.sequence
      end
      table.insert(values, name)
    end
    return table.concat(values, ", ")
  end
  return ""
end

local function item_duration(item)
  if type(item.media) == "table" then
    return tonumber(item.media.duration) or 0
  end
  return tonumber(item.duration) or 0
end

local function progress_of(item)
  return item.userMediaProgress or item.mediaProgress or item.progress
end

local function progress_text(item)
  local progress = progress_of(item)
  if type(progress) ~= "table" then
    return ""
  end
  if progress.isFinished then
    return lang.progress_finished
  end
  local ratio = tonumber(progress.progress)
  if not ratio then
    local duration = item_duration(item)
    if duration > 0 then
      ratio = (tonumber(progress.currentTime) or 0) / duration
    end
  end
  if not ratio or ratio <= 0 then
    return ""
  end
  return string.format("%d %%", math.floor(math.min(1, ratio) * 100 + 0.5))
end

local function fold(s)
  s = s or ""
  if vlc.strings and vlc.strings.fold then
    local ok, value = pcall(vlc.strings.fold, s)
    if ok and value then
      return value
    end
  end
  return string.lower(s)
end

local function set_message(text)
  if ui.message then
    ui.message:set_text(text or "")
    if dlg then
      dlg:update()
    end
  end
end

function close_dlg()
  if dlg then
    dlg:hide()
    dlg:delete()
  end
  dlg = nil
  ui = {}
end

            --[[ HTTP and API ]]--

local function get_body(url)
  local ok, stream, err = pcall(vlc.stream, url)
  if not ok or not stream then
    return nil, tostring(err or stream or "stream error")
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
  if body == "" then
    return nil, "empty response"
  end
  return body
end

local function decode_json(body)
  local obj, _, err = json.decode(body or "")
  if obj == nil then
    return nil, tostring(err or "invalid JSON")
  end
  return obj
end

local function authenticated_url(path, params)
  local url = app.server .. path
  local sep = string.find(url, "?", 1, true) and "&" or "?"
  url = url .. sep .. "token=" .. esc(app.token)
  for _, param in ipairs(params or {}) do
    url = url .. "&" .. param
  end
  return url
end

local function api_get(path, params)
  local body, err = get_body(authenticated_url(path, params))
  if not body then
    return nil, err
  end
  return decode_json(body)
end

local function api_post(path, payload)
  if not (vlc.http and vlc.http.post) then
    return nil, lang.msg_no_http
  end
  local status, body = vlc.http.post(authenticated_url(path),
    json.encode(payload or {}), "application/json")
  if not status then
    return nil, tostring(body)
  end
  if status < 200 or status >= 300 then
    return nil, "HTTP " .. tostring(status)
  end
  if not body or body == "" or body == "OK" then
    return true
  end
  return decode_json(body)
end

local function normalize_server_url(url)
  url = trim(url)
  if url == "" or url == "http://" or url == "https://" then
    return nil
  end
  if not string.match(url, "^https?://") then
    if string.match(url, "^%d+%.%d+%.%d+%.%d+") or string.match(url, ":%d+") then
      url = "http://" .. url
    else
      url = "https://" .. url
    end
  end
  url = string.gsub(url, "/login/?#?.*$", "")
  url = string.gsub(url, "/app/?#?.*$", "")
  url = string.gsub(url, "/+$", "")
  return url
end

local function server_status(server)
  local body, err = get_body(server .. "/status")
  if not body then
    return nil, err
  end
  local obj, jerr = decode_json(body)
  if type(obj) ~= "table" or obj.app ~= "audiobookshelf" then
    return nil, jerr or lang.msg_not_abs
  end
  return obj
end

local function resolve_server(server)
  local status, err = server_status(server)
  if status then
    return server, status
  end
  return nil, err
end

local function login_password(server, username, password)
  if not (vlc.http and vlc.http.post) then
    return nil, lang.msg_no_http
  end
  local status, body = vlc.http.post(server .. "/login",
    json.encode({ username = username, password = password }),
    "application/json")
  if not status then
    return nil, lang.msg_login_fail .. tostring(body)
  end
  if status == 401 then
    return nil, lang.msg_bad_credentials
  end
  if status < 200 or status >= 300 then
    return nil, lang.msg_login_fail .. "HTTP " .. tostring(status)
  end
  local obj, err = decode_json(body)
  local user = obj and obj.user
  local token = user and (user.token or user.accessToken)
  if type(token) ~= "string" or token == "" then
    return nil, lang.msg_login_fail .. tostring(err or "token?")
  end
  return token, user
end

            --[[ Saved connection ]]--

local KEYSTORE_USER = "token"
local KEYSTORE_LABEL = "PowerVLC — Audiobookshelf"

local function settings_path()
  local dir = vlc.config.userdatadir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/audiobookshelf.json"
end

local function keystore_service(server, username)
  return "audiobookshelf-powervlc://"
      .. string.gsub(server or "", "^%w+://", "")
      .. "/" .. (username or "user")
end

local function have_keystore()
  return vlc.keystore and vlc.keystore.find and vlc.keystore.store
end

local function load_secret(server, username)
  if not have_keystore() then
    return nil
  end
  return vlc.keystore.find(keystore_service(server, username), KEYSTORE_USER)
end

local function forget_secret(server, username)
  if have_keystore() then
    vlc.keystore.remove(keystore_service(server, username), KEYSTORE_USER)
  end
end

local function save_secret(server, username, token)
  if not have_keystore() then
    return false
  end
  local service = keystore_service(server, username)
  if not vlc.keystore.store(service, KEYSTORE_USER, token, KEYSTORE_LABEL) then
    return false
  end
  if load_secret(server, username) ~= token then
    vlc.keystore.remove(service, KEYSTORE_USER)
    return false
  end
  return true
end

function load_settings()
  local path = settings_path()
  if not path then
    return
  end
  local file = io.open(path, "r")
  if not file then
    return
  end
  local obj = json.decode(file:read("*a") or "")
  file:close()
  if type(obj) ~= "table" then
    return
  end
  if type(obj.server) == "string" and obj.server ~= "" then
    app.last_server = obj.server
  end
  if type(obj.username) == "string" then
    app.last_user = obj.username
  end
  if type(obj.view) == "string" then
    app.view = obj.view
  end
  if type(obj.libraryId) == "string" then
    app.library_id = obj.libraryId
  end
  if type(obj.deviceId) == "string" and obj.deviceId ~= "" then
    app.device_id = obj.deviceId
  end
  app.remember = obj.remember and true or false
  app.keystore_broken = obj.keystore_broken and true or false

  if type(obj.token) == "string" and obj.token ~= "" then
    app.last_token = obj.token
  elseif app.remember then
    app.last_token = load_secret(app.last_server, app.last_user) or ""
    if app.last_token == "" and obj.keystore then
      app.secret_denied = true
      app.keystore_broken = true
      forget_secret(app.last_server, app.last_user)
    end
  end
end

local function save_settings()
  local path = settings_path()
  if not path then
    return
  end
  if not app.remember then
    forget_secret(app.server or app.last_server, app.username or app.last_user)
    local file = io.open(path, "w")
    if file then
      file:write(json.encode({ view = app.view, libraryId = app.library_id,
                               deviceId = app.device_id },
                             { indent = true }))
      file:close()
    end
    return
  end
  local stored = not app.keystore_broken
             and save_secret(app.server, app.username, app.token)
  app.secret_plain = not stored
  local file = io.open(path, "w")
  if not file then
    return
  end
  file:write(json.encode({
    server = app.server,
    username = app.username,
    token = (not stored) and app.token or nil,
    keystore = stored or nil,
    keystore_broken = app.keystore_broken or nil,
    view = app.view,
    libraryId = app.library_id,
    deviceId = app.device_id,
    remember = true,
  }, { indent = true }))
  file:close()
end

local function save_preferences()
  if not app.server or not app.token then
    return
  end
  save_settings()
end

            --[[ Connection view ]]--

function show_connect()
  close_dlg()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(720, 0)

  dlg:add_label(lang.sec_server, 1, 1, 3, 1)
  dlg:add_label(lang.lbl_server, 1, 2, 1, 1)
  ui.server = dlg:add_text_input(app.last_server, 2, 2, 2, 1, click_connect)
  dlg:add_label(lang.hint_server, 1, 3, 3, 1)

  dlg:add_label(lang.sec_account, 1, 4, 3, 1)
  dlg:add_label(lang.lbl_username, 1, 5, 1, 1)
  ui.username = dlg:add_text_input(app.last_user, 2, 5, 2, 1, click_connect)
  dlg:add_label(lang.lbl_password, 1, 6, 1, 1)
  ui.password = dlg:add_password("", 2, 6, 2, 1, click_connect)
  dlg:add_label(lang.hint_saved, 1, 7, 3, 1)

  ui.remember = dlg:add_check_box(lang.chk_remember, app.remember, 1, 8, 3, 1)
  dlg:add_button(lang.btn_forget, click_forget, 1, 9, 3, 1)
  dlg:add_button(lang.btn_connect, click_connect, 1, 10, 3, 1)
  ui.message = dlg:add_label("", 1, 11, 3, 1)
  dlg:show()

  if app.secret_denied then
    set_message(lang.msg_keystore_denied)
    app.secret_denied = false
  end
end

function click_forget()
  local server = normalize_server_url(ui.server:get_text()) or app.last_server
  local username = trim(ui.username:get_text())
  forget_secret(server, username)
  forget_secret(app.server, app.username)
  local path = settings_path()
  if path then
    os.remove(path)
  end
  app.last_server = "https://"
  app.last_user = ""
  app.last_token = ""
  app.remember = false
  ui.server:set_text(app.last_server)
  ui.username:set_text("")
  ui.password:set_text("")
  ui.remember:set_checked(false)
  set_message(lang.msg_forgotten)
end

local function establish_connection(server, token, user, username)
  app.server = server
  app.token = token
  app.user = user
  -- Keep the sign-in name as the keystore key. A proxy-backed demo may
  -- return a short-lived internal username that differs from what the user
  -- typed; using it here would make the remembered token impossible to find.
  app.username = username or (user and user.username)
  app.rights = (user and user.permissions) or {}
  app.last_server = server
  app.last_user = username or app.username or ""
  app.last_token = token
  app.cache = {}
  app.stack = {}
  app.search_query = ""

  set_message(lang.msg_loading_libraries)
  local response, err = api_get("/api/libraries")
  if not response or type(response.libraries) ~= "table" then
    app.token = nil
    set_message(lang.msg_api_fail .. tostring(err or "libraries?"))
    return
  end
  app.libraries = response.libraries
  app.library_map = {}
  local found = false
  for i, library in ipairs(app.libraries) do
    app.library_map[i] = library
    if library.id == app.library_id then
      found = true
    end
  end
  if not found then
    app.library_id = response.userDefaultLibraryId
                     or (app.libraries[1] and app.libraries[1].id)
  end
  if not app.library_id then
    set_message(lang.msg_no_libraries)
    return
  end
  app.remember = ui.remember and ui.remember:get_checked() or app.remember
  save_settings()
  show_browser()
end

function click_connect()
  local server = normalize_server_url(ui.server:get_text())
  if not server then
    set_message(lang.msg_enter_server)
    return
  end
  local username = trim(ui.username:get_text())
  local password = ui.password:get_text()
  if username == "" then
    set_message(lang.msg_enter_account)
    return
  end
  set_message(lang.msg_contacting)
  local found, status_or_err = resolve_server(server)
  if not found then
    set_message(lang.msg_server_fail .. tostring(status_or_err or "?"))
    return
  end
  server = found

  local token = nil
  local user = nil
  if password == "" and app.last_token ~= ""
     and server == app.last_server and username == app.last_user then
    app.server = server
    app.token = app.last_token
    user = api_get("/api/me")
    if type(user) == "table" then
      token = app.last_token
    end
  end
  if not token then
    if password == "" then
      set_message(lang.msg_enter_password)
      return
    end
    token, user = login_password(server, username, password)
    if not token then
      set_message(user)
      return
    end
  end
  establish_connection(server, token, user, username)
end

            --[[ Library API loaders ]]--

local function current_library()
  for _, library in ipairs(app.libraries) do
    if library.id == app.library_id then
      return library
    end
  end
  return app.libraries[1]
end

local function cache_key(view)
  return tostring(app.library_id) .. ":" .. tostring(view)
end

local function paged_results(path, params)
  local all = {}
  local page = 0
  local total = nil
  repeat
    local p = {}
    for _, value in ipairs(params or {}) do
      table.insert(p, value)
    end
    table.insert(p, "limit=" .. PAGE)
    table.insert(p, "page=" .. page)
    local response, err = api_get(path, p)
    if not response then
      return nil, err
    end
    local results = response.results or {}
    for _, value in ipairs(results) do
      table.insert(all, value)
    end
    total = tonumber(response.total) or #all
    page = page + 1
    still_alive()
  until #all >= total or total == 0
  return all
end

local function load_items()
  return paged_results("/api/libraries/" .. esc(app.library_id) .. "/items",
    { "include=progress", "sort=media.metadata.title", "desc=0", "minified=1" })
end

local function load_series()
  return paged_results("/api/libraries/" .. esc(app.library_id) .. "/series",
    { "include=progress", "sort=name", "desc=0", "minified=1" })
end

local function load_authors()
  local response, err = api_get("/api/libraries/" .. esc(app.library_id)
                              .. "/authors")
  if not response then
    return nil, err
  end
  return response.authors or response.results or {}
end

local function load_collections()
  return paged_results("/api/libraries/" .. esc(app.library_id)
                     .. "/collections", { "include=progress", "minified=1" })
end

local function load_playlists()
  return paged_results("/api/libraries/" .. esc(app.library_id)
                     .. "/playlists")
end

local function load_continue()
  local response, err = api_get("/api/me/items-in-progress")
  if not response then
    return nil, err
  end
  local items = {}
  for _, item in ipairs(response.libraryItems or {}) do
    if item.libraryId == app.library_id then
      table.insert(items, item)
    end
  end
  return items
end

local LOADERS = {
  items = load_items,
  series = load_series,
  authors = load_authors,
  collections = load_collections,
  playlists = load_playlists,
  continue = load_continue,
}

local function load_root(force)
  local key = cache_key(app.view)
  if not force and app.cache[key] then
    return app.cache[key]
  end
  if app.view == "search" then
    app.cache[key] = app.cache[key] or {}
    return app.cache[key]
  end
  local loader = LOADERS[app.view]
  if not loader then
    return {}
  end
  set_message(lang.msg_loading)
  local values, err = loader()
  if not values then
    set_message(lang.msg_api_fail .. tostring(err or "?"))
    return nil
  end
  app.cache[key] = values
  return values
end

local function current_level()
  return app.stack[#app.stack]
end

local function current_content()
  local level = current_level()
  if level then
    return level.mode, level.items
  end
  local mode = app.view
  if mode == "continue" or mode == "search" then
    mode = "items"
  end
  return mode, app.cache[cache_key(app.view)] or {}
end

            --[[ Row rendering ]]--

local HEADERS = {}

function init_headers()
  HEADERS = {
    items = table.concat({ lang.col_title, lang.col_author, lang.col_series,
                           lang.col_duration, lang.col_progress }, "\t"),
    series = table.concat({ lang.col_series, lang.col_books }, "\t"),
    authors = table.concat({ lang.col_author, lang.col_books }, "\t"),
    collections = table.concat({ lang.col_collection, lang.col_books }, "\t"),
    playlists = table.concat({ lang.col_playlist, lang.col_items }, "\t"),
    tracks = table.concat({ lang.col_number, lang.col_title,
                            lang.col_duration, lang.col_codec }, "\t"),
    episodes = table.concat({ lang.col_date, lang.col_title,
                              lang.col_duration, lang.col_progress }, "\t"),
  }
end

local function item_row(item)
  return table.concat({ cell(item_title(item)), cell(item_author(item)),
    cell(item_series(item)), sortable(format_duration(item_duration(item)),
    item_duration(item)), cell(progress_text(item)) }, "\t")
end

local function group_count(group)
  local values = group.books or group.items or group.libraryItems
  if type(values) == "table" then
    return #values
  end
  return tonumber(group.numBooks or group.numItems) or 0
end

local function group_row(group, field)
  return cell(group[field] or group.name or "?") .. "\t"
      .. sortable(group_count(group), group_count(group))
end

local function track_title(track)
  local tags = track.metaTags
            or (track.metadata and track.metadata.metaTags)
            or {}
  return tags.tagTitle or track.title
      or (track.metadata and track.metadata.filename) or "?"
end

local function track_row(track)
  return table.concat({ sortable(track.index or "", tonumber(track.index) or 0),
    cell(track_title(track)), sortable(format_duration(track.duration),
    tonumber(track.duration) or 0), cell(track.codec or track.mimeType or "") }, "\t")
end

local function episode_row(episode)
  return table.concat({ cell(format_date(episode.pubDate or episode.publishedAt)),
    cell(episode.title or "?"), sortable(format_duration(episode.duration),
    tonumber(episode.duration) or 0), cell(progress_text(episode)) }, "\t")
end

local function row_text(mode, obj)
  if mode == "items" then
    return item_row(obj)
  elseif mode == "series" then
    return group_row(obj, "name")
  elseif mode == "authors" then
    return group_row(obj, "name")
  elseif mode == "collections" then
    return group_row(obj, "name")
  elseif mode == "playlists" then
    return group_row(obj, "name")
  elseif mode == "tracks" then
    return track_row(obj.track or obj)
  elseif mode == "episodes" then
    return episode_row(obj.episode or obj)
  end
  return cell(obj.name or obj.title or "?")
end

local function row_search_text(mode, obj)
  if mode == "items" then
    return item_title(obj) .. " " .. item_author(obj) .. " " .. item_series(obj)
  elseif mode == "tracks" then
    return track_title(obj.track or obj)
  elseif mode == "episodes" then
    local episode = obj.episode or obj
    return episode.title or ""
  end
  return obj.name or obj.title or ""
end

function fill_list()
  if not ui.items then
    return
  end
  local mode, values = current_content()
  local query = fold(trim(ui.search and ui.search:get_text() or ""))
  if app.view == "search" and not current_level() then
    query = ""
  end
  app.rows = {}
  ui.items:clear()
  local shown = 0
  for _, value in ipairs(values or {}) do
    if query == "" or string.find(fold(row_search_text(mode, value)), query,
                                  1, true) then
      shown = shown + 1
      app.rows[shown] = { kind = mode, obj = value }
      ui.items:add_value(row_text(mode, value), shown)
      if shown % 500 == 0 then
        still_alive()
      end
    end
  end
  if shown == 0 then
    set_message((app.view == "search" and app.search_query == "")
                and lang.msg_search_hint or lang.msg_no_content)
  else
    set_message(string.format(lang.msg_count, shown, #values))
  end
end

local function selected_rows()
  if not ui.items then
    return {}
  end
  local selection = ui.items:get_selection()
  local rows = {}
  for i, row in ipairs(app.rows) do
    if selection[i] then
      table.insert(rows, row)
    end
  end
  return rows
end

local function selected_or_first()
  local rows = selected_rows()
  if #rows == 0 and current_level()
     and (current_level().mode == "tracks" or current_level().mode == "episodes") then
    for _, row in ipairs(app.rows) do
      table.insert(rows, row)
    end
  end
  return rows
end

            --[[ Browser view ]]--

local VIEW_KEYS = { "items", "continue", "series", "authors",
                    "collections", "playlists", "search" }
local PODCAST_VIEW_KEYS = { "items", "continue", "playlists", "search" }

local function available_view_keys()
  local library = current_library()
  if library and library.mediaType == "podcast" then
    return PODCAST_VIEW_KEYS
  end
  return VIEW_KEYS
end

local function view_label(key)
  return lang["view_" .. key] or key
end

local function menu_for_mode(mode)
  if mode == "tracks" or mode == "episodes" then
    return { lang.menu_play, lang.menu_enqueue }, { "play", "enqueue" }
  end
  if mode == "items" then
    return { lang.menu_open, lang.menu_play, lang.menu_enqueue },
           { "open", "play", "enqueue" }
  end
  return { lang.menu_open }, { "open" }
end

function show_browser()
  close_dlg()
  dlg = vlc.dialog(lang.title_browse)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)

  local row = 1
  dlg:add_button(current_level() and lang.btn_back or lang.btn_connection,
                 current_level() and click_back or show_connect,
                 1, row, 1, 1)
  ui.library = dlg:add_dropdown(2, row, 2, 1, click_library_changed)
  local selected_library = 1
  for i, library in ipairs(app.libraries) do
    ui.library:add_value(library.name or "?", i)
    if library.id == app.library_id then
      selected_library = i
    end
  end
  ui.library:set_value(selected_library)

  ui.view = dlg:add_dropdown(4, row, 1, 1, click_view_changed)
  app.view_keys = available_view_keys()
  local selected_view = 1
  local view_available = false
  for _, key in ipairs(app.view_keys) do
    if key == app.view then
      view_available = true
    end
  end
  if not view_available then
    app.view = "items"
  end
  for i, key in ipairs(app.view_keys) do
    ui.view:add_value(view_label(key), i)
    if key == app.view then
      selected_view = i
    end
  end
  ui.view:set_value(selected_view)
  dlg:add_button(lang.btn_refresh, click_refresh, 5, row, 1, 1)
  row = row + 1

  local level = current_level()
  if level and level.title then
    dlg:add_label("<b>" .. cell(level.title) .. "</b>", 1, row, 5, 1)
    row = row + 1
  end

  dlg:add_label(lang.lbl_search, 1, row, 1, 1)
  ui.search = dlg:add_text_input(level and (level.query or "")
                                 or app.search_query,
                                 2, row, 3, 1,
                                 click_search_validate, click_search_changed)
  if app.view == "search" and not level then
    dlg:add_button(lang.btn_search, click_search_validate, 5, row, 1, 1)
  end
  row = row + 1

  local mode = current_content()
  ui.items = dlg:add_list(1, row, 5, 1, click_open_row, nil)
  ui.items:set_text(HEADERS[mode] or lang.col_title)
  local labels, actions = menu_for_mode(mode)
  app.menu_actions = actions
  ui.items:set_menu(labels, click_menu)
  row = row + 1

  dlg:add_button(lang.btn_open, click_open, 1, row, 1, 1)
  dlg:add_button(lang.btn_play, click_play, 2, row, 1, 1)
  dlg:add_button(lang.btn_enqueue, click_enqueue, 3, row, 1, 1)
  ui.message = dlg:add_label("", 1, row + 1, 5, 1)
  dlg:show()

  local values = load_root(false)
  if values then
    fill_list()
  end
  if app.secret_plain then
    set_message(string.format(lang.msg_secret_plain, settings_path() or "?"))
    app.secret_plain = false
  end
end

function click_library_changed()
  local index = ui.library and ui.library:get_value()
  local library = index and app.library_map[index]
  if not library or library.id == app.library_id then
    return
  end
  app.library_id = library.id
  app.stack = {}
  app.search_query = ""
  save_preferences()
  show_browser()
end

function click_view_changed()
  local index = ui.view and ui.view:get_value()
  local view = index and app.view_keys[index]
  if not view or (view == app.view and #app.stack == 0) then
    return
  end
  app.view = view
  app.stack = {}
  app.search_query = ""
  save_preferences()
  show_browser()
end

function click_refresh()
  if current_level() and current_level().reload then
    current_level().reload(current_level())
  else
    app.cache[cache_key(app.view)] = nil
    load_root(true)
  end
  show_browser()
end

function click_back()
  table.remove(app.stack)
  show_browser()
end

function click_search_changed()
  local value = ui.search and ui.search:get_text() or ""
  local level = current_level()
  if level then
    level.query = value
  else
    app.search_query = value
  end
  if app.view ~= "search" or level then
    fill_list()
  end
end

local function append_search_item(values, seen, candidate)
  local item = candidate and (candidate.libraryItem or candidate.item
                               or candidate)
  if not (item and item.id) then
    return
  end
  local id = tostring(item.id)
  if seen[id] then
    return
  end
  seen[id] = true
  table.insert(values, item)
end

local function append_search_items(values, seen, candidates)
  for _, candidate in ipairs(candidates or {}) do
    append_search_item(values, seen, candidate)
  end
end

-- Audiobookshelf separates search matches by what matched. A query for an
-- author's name can therefore leave `book` empty while returning the author
-- in `authors`; turn every useful match back into playable library items.
local function search_result_items(response, expand_author)
  local values = {}
  local seen = {}
  local first_error = nil

  for _, key in ipairs({ "book", "podcast", "books", "podcasts",
                         "results", "libraryItems" }) do
    append_search_items(values, seen, response[key])
  end

  for _, series in ipairs(response.series or {}) do
    append_search_items(values, seen,
      series.books or series.items or series.libraryItems)
  end

  for _, author in ipairs(response.authors or {}) do
    local items = author.libraryItems or author.items or author.books
    if not items and expand_author and author.id then
      local err = nil
      items, err = expand_author(author)
      first_error = first_error or err
    end
    append_search_items(values, seen, items)
  end

  return values, first_error
end

function click_search_validate()
  click_search_changed()
  if app.view ~= "search" or current_level() then
    return
  end
  local query = trim(app.search_query)
  if #query < 2 then
    set_message(lang.msg_search_hint)
    return
  end
  set_message(lang.msg_searching)
  local response, err = api_get("/api/libraries/" .. esc(app.library_id)
                              .. "/search",
    { "q=" .. esc(query), "limit=100" })
  if not response then
    set_message(lang.msg_api_fail .. tostring(err or "?"))
    return
  end
  local values, expansion_error = search_result_items(response,
    function(author)
      local expanded, author_error = api_get("/api/authors/" .. esc(author.id),
                                              { "include=items" })
      still_alive()
      if not expanded then
        return nil, author_error
      end
      return expanded.libraryItems or expanded.items or expanded.books or {}
    end)
  if #values == 0 and expansion_error then
    set_message(lang.msg_api_fail .. tostring(expansion_error))
    return
  end
  app.cache[cache_key("search")] = values
  fill_list()
end

            --[[ Drill-down ]]--

local function push_level(mode, values, title, parent, reload)
  table.insert(app.stack, {
    mode = mode,
    items = values or {},
    title = title,
    parent = parent,
    reload = reload,
    query = "",
  })
  show_browser()
end

local function expanded_item(item)
  if item._expanded then
    return item._expanded
  end
  local expanded, err = api_get("/api/items/" .. esc(item.id),
    { "expanded=1", "include=progress" })
  if not expanded then
    set_message(lang.msg_api_fail .. tostring(err or "?"))
    return nil
  end
  item._expanded = expanded
  return expanded
end

local function track_entries(item, expanded)
  local entries = {}
  for _, track in ipairs((expanded.media and
                          (expanded.media.tracks or expanded.media.audioTracks))
                         or {}) do
    table.insert(entries, { track = track, parent = item })
  end
  return entries
end

local function episode_entries(item, expanded)
  local entries = {}
  for _, episode in ipairs((expanded.media and expanded.media.episodes) or {}) do
    table.insert(entries, { episode = episode, parent = item })
  end
  return entries
end

local function open_item(item)
  set_message(lang.msg_opening)
  local expanded = expanded_item(item)
  if not expanded then
    return
  end
  if expanded.mediaType == "podcast" then
    local entries = episode_entries(item, expanded)
    push_level("episodes", entries, item_title(expanded), item,
      function(level)
        item._expanded = nil
        local fresh = expanded_item(item)
        level.items = fresh and episode_entries(item, fresh) or level.items
      end)
  else
    local entries = track_entries(item, expanded)
    push_level("tracks", entries, item_title(expanded), item,
      function(level)
        item._expanded = nil
        local fresh = expanded_item(item)
        level.items = fresh and track_entries(item, fresh) or level.items
      end)
  end
end

local function open_author(author)
  set_message(lang.msg_opening)
  local response, err = api_get("/api/authors/" .. esc(author.id),
                                { "include=items" })
  if not response then
    set_message(lang.msg_api_fail .. tostring(err or "?"))
    return
  end
  push_level("items", response.libraryItems or {}, author.name or "?", author,
    function(level)
      local fresh = api_get("/api/authors/" .. esc(author.id),
                            { "include=items" })
      level.items = fresh and fresh.libraryItems or level.items
    end)
end

local function playlist_items(playlist)
  local response, err = api_get("/api/playlists/" .. esc(playlist.id))
  if not response then
    return nil, err
  end
  local values = {}
  local source = response.items or response.playlistMediaItems or {}
  for _, entry in ipairs(source) do
    local item = entry.libraryItem or entry
    if item and item.id then
      -- Keep the episode selection for podcast playlist entries.
      item._playlist_episode_id = entry.episodeId
        or (entry.mediaItem and entry.mediaItem.episodeId)
      table.insert(values, item)
    end
  end
  return values
end

local function open_group(row)
  local group = row.obj
  if row.kind == "authors" then
    open_author(group)
    return
  end
  if row.kind == "playlists" then
    local values, err = playlist_items(group)
    if not values then
      set_message(lang.msg_api_fail .. tostring(err or "?"))
      return
    end
    push_level("items", values, group.name or "?", group,
      function(level)
        level.items = playlist_items(group) or level.items
      end)
    return
  end
  local values = group.books or group.items or group.libraryItems or {}
  push_level("items", values, group.name or "?", group, nil)
end

local function open_row(row)
  if row.kind == "items" then
    open_item(row.obj)
  elseif row.kind == "tracks" or row.kind == "episodes" then
    play_rows({ row }, false)
  else
    open_group(row)
  end
end

function click_open_row()
  local rows = selected_rows()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  open_row(rows[1])
end

function click_open()
  click_open_row()
end

            --[[ Playback and progress ]]--

local SUPPORTED_MIME_TYPES = {
  "audio/aac", "audio/flac", "audio/mp4", "audio/mpeg", "audio/ogg",
  "audio/opus", "audio/wav", "audio/webm", "audio/x-aiff", "audio/x-m4a",
  "audio/x-matroska", "audio/x-wav",
}

local function product_version()
  if vlc.misc and vlc.misc.product_version then
    local ok, value = pcall(vlc.misc.product_version)
    if ok and value and value ~= "" then
      return value
    end
  end
  return "?"
end

local function playback_payload()
  return {
    deviceInfo = {
      clientName = "PowerVLC",
      clientVersion = product_version(),
      deviceId = app.device_id or "PowerVLC",
      deviceName = "PowerVLC",
    },
    supportedMimeTypes = SUPPORTED_MIME_TYPES,
    mediaPlayer = "vlc",
    forceDirectPlay = true,
    forceTranscode = false,
  }
end

local function session_path(session_id, suffix)
  return "/api/session/" .. esc(session_id) .. suffix
end

local function current_input_elapsed()
  local ok, input = pcall(vlc.object.input)
  if not ok or not input then
    return nil
  end
  local got, value = pcall(vlc.var.get, input, "time")
  if not got or type(value) ~= "number" then
    return nil
  end
  return value / 1000000
end

local function absolute_playback_time()
  local elapsed = current_input_elapsed()
  if not elapsed or not playback.track then
    return playback.last_absolute, elapsed
  end
  return (tonumber(playback.track.startOffset) or 0) + elapsed, elapsed
end

local function sync_playback(force)
  if not playback.session_id then
    return
  end
  local absolute, elapsed = absolute_playback_time()
  if not absolute then
    return
  end
  local now = os.time()
  local listened = 0
  if playback.last_tick and playback.last_elapsed and elapsed
     and elapsed > playback.last_elapsed + 0.2 then
    listened = math.max(0, math.min(now - playback.last_tick, 30))
  end
  if force or listened > 0 then
    pcall(api_post, session_path(playback.session_id, "/sync"), {
      currentTime = absolute,
      timeListened = listened,
      duration = playback.duration,
    })
  end
  playback.last_absolute = absolute
  playback.last_elapsed = elapsed
  playback.last_tick = now
end

function close_playback_session()
  if not playback.session_id then
    return
  end
  local absolute, elapsed = absolute_playback_time()
  local listened = 0
  if playback.last_tick and playback.last_elapsed and elapsed
     and elapsed > playback.last_elapsed + 0.2 then
    listened = math.max(0, math.min(os.time() - playback.last_tick, 30))
  end
  pcall(api_post, session_path(playback.session_id, "/close"), {
    currentTime = absolute or playback.last_absolute or 0,
    timeListened = listened,
    duration = playback.duration,
  })
  playback.session_id = nil
  playback.library_item_id = nil
  playback.episode_id = nil
  playback.duration = 0
  playback.tracks = {}
  playback.track = nil
  playback.last_elapsed = nil
  playback.last_absolute = nil
  playback.last_tick = nil
  playback.sync_armed = false
  playback.seen_input = false
end

local function arm_sync()
  if playback.session_id and not playback.sync_armed then
    playback.sync_armed = true
    vlc.timer(10000, "audiobookshelf_tick")
  end
end

function audiobookshelf_tick()
  playback.sync_armed = false
  if playback.session_id then
    sync_playback(false)
    arm_sync()
  end
end

local function session_track_uri(session_id, track_index)
  return app.server .. "/public/session/" .. esc(session_id)
      .. "/track/" .. esc(track_index)
end

local function raw_track_uri(track)
  local path = track.contentUrl
  if not path or path == "" then
    return nil
  end
  return authenticated_url(path)
end

local function cover_url(item)
  if item and item.id and item.media and item.media.coverPath then
    return authenticated_url("/api/items/" .. esc(item.id) .. "/cover")
  end
  return nil
end

local function playlist_item(track, uri, title, author, series, start_at,
                             arturl)
  local item = {
    path = uri,
    name = track_title(track),
    title = track_title(track),
    artist = author,
    album = title,
    duration = tonumber(track.duration),
    arturl = arturl,
  }
  if start_at and start_at > 0 then
    item.options = { ":start-time=" .. tostring(start_at) }
  end
  return item
end

-- vlc.playlist.add() starts every item it receives. Passing a whole book to
-- it therefore leaves the last chapter playing. Start only the first item,
-- then enqueue the remaining chapters so they follow it without taking over.
local function play_playlist_items(values)
  if #values == 0 then
    return 0
  end
  vlc.playlist.add({ values[1] })
  if #values > 1 then
    local following = {}
    for i = 2, #values do
      table.insert(following, values[i])
    end
    vlc.playlist.enqueue(following)
  end
  return #values
end

local function session_track_bounds(tracks, selected_index, start_time)
  local first, last = 1, #tracks
  if selected_index ~= nil then
    for i, track in ipairs(tracks) do
      if tonumber(track.index) == tonumber(selected_index) then
        first, last = i, i
        start_time = tonumber(track.startOffset) or 0
        break
      end
    end
  else
    for i, track in ipairs(tracks) do
      local from = tonumber(track.startOffset) or 0
      local until_ = from + (tonumber(track.duration) or 0)
      if start_time >= from and start_time < until_ then
        first = i
        break
      end
    end
  end
  return first, last, start_time
end

local function start_session(item, episode_id, selected_index)
  close_playback_session()
  local path = "/api/items/" .. esc(item.id) .. "/play"
  if episode_id then
    path = path .. "/" .. esc(episode_id)
  end
  set_message(lang.msg_starting)
  local session, err = api_post(path, playback_payload())
  if not session or type(session) ~= "table" or not session.id then
    set_message(lang.msg_api_fail .. tostring(err or "session?"))
    return nil
  end
  local tracks = session.audioTracks or {}
  if #tracks == 0 then
    api_post(session_path(session.id, "/close"), {})
    set_message(lang.msg_no_audio)
    return nil
  end

  playback.session_id = session.id
  playback.library_item_id = item.id
  playback.episode_id = episode_id
  playback.duration = tonumber(session.duration) or item_duration(item)
  playback.tracks = tracks
  playback.last_absolute = tonumber(session.currentTime) or 0
  playback.last_tick = os.time()
  playback.seen_input = false

  local start_time = tonumber(session.currentTime) or 0
  local first, last
  first, last, start_time = session_track_bounds(tracks, selected_index,
                                                  start_time)

  local title = session.displayTitle or item_title(item)
  local author = session.displayAuthor or item_author(item)
  local arturl = cover_url(item)
  local values = {}
  for i = first, last do
    local track = tracks[i]
    local offset = 0
    if i == first then
      offset = math.max(0, start_time - (tonumber(track.startOffset) or 0))
    end
    table.insert(values, playlist_item(track,
      session_track_uri(session.id, track.index), title, author,
      item_series(item), offset, arturl))
  end
  playback.track = tracks[first]
  playback.last_elapsed = nil
  set_message(string.format(lang.msg_playing, #values))
  play_playlist_items(values)
  arm_sync()
  return true
end

local function queued_playlist_items(item, episode_id, selected_index)
  local expanded = expanded_item(item)
  if not expanded then
    return {}
  end
  local tracks = {}
  if episode_id then
    for _, episode in ipairs((expanded.media and expanded.media.episodes) or {}) do
      if episode.id == episode_id and episode.audioTrack then
        table.insert(tracks, episode.audioTrack)
      end
    end
  else
    tracks = (expanded.media and
              (expanded.media.tracks or expanded.media.audioTracks)) or {}
  end
  local values = {}
  local arturl = cover_url(expanded)
  for _, track in ipairs(tracks) do
    if not selected_index or tonumber(track.index) == tonumber(selected_index) then
      local uri = raw_track_uri(track)
      if uri then
        table.insert(values, playlist_item(track, uri, item_title(expanded),
          item_author(expanded), item_series(expanded), nil, arturl))
      end
    end
  end
  return values
end

function play_rows(rows, queue)
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  if rows[1].kind ~= "items" and rows[1].kind ~= "tracks"
     and rows[1].kind ~= "episodes" then
    open_row(rows[1])
    return
  end
  if queue then
    local values = {}
    for _, queued_row in ipairs(rows) do
      local queued_item = nil
      local queued_episode = nil
      local queued_track = nil
      if queued_row.kind == "items" then
        queued_item = queued_row.obj
        queued_episode = queued_item._playlist_episode_id
      elseif queued_row.kind == "tracks" then
        queued_item = queued_row.obj.parent
        queued_track = (queued_row.obj.track or {}).index
      elseif queued_row.kind == "episodes" then
        queued_item = queued_row.obj.parent
        queued_episode = (queued_row.obj.episode or {}).id
      end
      if queued_item then
        for _, value in ipairs(queued_playlist_items(queued_item,
          queued_episode, queued_track)) do
          table.insert(values, value)
        end
      end
    end
    if #values == 0 then
      set_message(lang.msg_no_audio)
      return
    end
    set_message(string.format(lang.msg_queued, #values))
    vlc.playlist.enqueue(values)
    return
  end

  local row = rows[1]
  local item = nil
  local episode_id = nil
  local track_index = nil
  if row.kind == "items" then
    item = row.obj
    episode_id = item._playlist_episode_id
  elseif row.kind == "tracks" then
    item = row.obj.parent
    track_index = (row.obj.track or {}).index
  elseif row.kind == "episodes" then
    item = row.obj.parent
    episode_id = (row.obj.episode or {}).id
  else
    open_row(row)
    return
  end
  start_session(item, episode_id, track_index)
end

function click_play()
  play_rows(selected_or_first(), false)
end

function click_enqueue()
  play_rows(selected_or_first(), true)
end

function click_menu(entry)
  local action = app.menu_actions[entry]
  local rows = selected_rows()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  if action == "open" then
    open_row(rows[1])
  elseif action == "play" then
    play_rows(rows, false)
  elseif action == "enqueue" then
    play_rows(rows, true)
  end
end

-- Track changes within our public session URLs. Moving to another item of
-- the same book keeps the server session open; moving elsewhere closes it.
function input_changed()
  if not playback.session_id then
    return
  end
  local ok, item = pcall(vlc.input.item)
  local uri = ok and item and item:uri() or nil
  local marker = "/public/session/" .. playback.session_id .. "/track/"
  if not uri or not string.find(uri, marker, 1, true) then
    -- playlist.add() can briefly report the input it is replacing before
    -- it reports the first new track. Do not close the freshly-created
    -- session until one of its own tracks has actually been observed.
    if playback.seen_input then
      close_playback_session()
    end
    return
  end
  local index = tonumber(string.match(uri, "/track/(%d+)"))
  for _, track in ipairs(playback.tracks) do
    if tonumber(track.index) == index then
      if playback.seen_input and playback.track
         and tonumber(playback.track.index) ~= index then
        local next_time = tonumber(track.startOffset) or playback.last_absolute or 0
        pcall(api_post, session_path(playback.session_id, "/sync"), {
          currentTime = next_time,
          timeListened = playback.last_tick
                         and math.max(0, math.min(os.time() - playback.last_tick, 30))
                         or 0,
          duration = playback.duration,
        })
      end
      playback.track = track
      playback.last_absolute = tonumber(track.startOffset) or 0
      playback.last_elapsed = nil
      playback.last_tick = os.time()
      playback.seen_input = true
      break
    end
  end
  arm_sync()
end

if POWERVLC_AUDIOBOOKSHELF_TEST then
  audiobookshelf_test = {
    session_track_bounds = session_track_bounds,
    search_result_items = search_result_items,
    play_playlist_items = play_playlist_items,
  }
end
