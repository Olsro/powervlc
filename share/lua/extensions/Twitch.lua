--[[
 Twitch.lua : simple Twitch browser extension for PowerVLC

 Search Twitch channels, discover live streams by category and play a
 selected result. A complete Twitch channel or video URL entered in the
 search field is resolved and played immediately.

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

local EXT_NAME = "Twitch"
local GQL_URL = "https://gql.twitch.tv/gql"
-- Public client used by Twitch's web player. No user credentials or OAuth
-- token are needed for the anonymous search and playback queries below.
local CLIENT_ID = "ue6666qo983tsx6so1t0vnawi233wa"
local RESULT_LIMIT = 30

local json = nil
local lang = {}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("twitch") })
end

local CHANNEL_SEARCH_QUERY = [[
query PowerVLCChannelSearch($query: String!, $limit: Int!) {
  searchUsers(userQuery: $query, first: $limit) {
    edges {
      node {
        id
        login
        displayName
        stream {
          id
          title
          viewersCount
          game { id name displayName }
        }
      }
    }
  }
}
]]

local CATEGORY_SEARCH_QUERY = [[
query PowerVLCCategorySearch($query: String!) {
  searchFor(userQuery: $query, platform: "web") {
    games {
      edges {
        item {
          ... on Game { id name displayName }
        }
      }
    }
  }
}
]]

local GAME_STREAMS_QUERY = [[
query PowerVLCGameStreams($name: String!, $limit: Int!) {
  game(name: $name) {
    id
    name
    displayName
    streams(first: $limit) {
      edges {
        node {
          id
          title
          viewersCount
          broadcaster { login displayName }
          game { id name displayName }
        }
      }
    }
  }
}
]]

local LIVE_PLAYBACK_QUERY = [[
query PowerVLCLivePlayback($login: String!) {
  user(login: $login) {
    displayName
    stream { id title viewersCount game { name displayName } }
  }
  streamPlaybackAccessToken(
    channelName: $login,
    params: { platform: "web", playerBackend: "mediaplayer", playerType: "site" }
  ) { value signature }
}
]]

local VIDEO_PLAYBACK_QUERY = [[
query PowerVLCVideoPlayback($id: ID!) {
  video(id: $id) { id title owner { login displayName } }
  videoPlaybackAccessToken(
    id: $id,
    params: { platform: "web", playerBackend: "mediaplayer", playerType: "site" }
  ) { value signature }
}
]]

local app = {
  query = "",
  mode = 1,             -- 1 = channels, 2 = streams by category
  rows = {},            -- list row id -> normalized channel
  categories = {},      -- dropdown id -> { id, name }
  category = nil,
}

local dlg = nil
local ui = {}

local function trim(value)
  return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

local function cell(value)
  return (string.gsub(tostring(value or ""), "[\t\r\n\031]", " "))
end

-- A hidden numeric sort key follows the unit separator. PowerVLC's list
-- widget displays the first part but sorts the second one numerically.
local function sortable(display, key)
  return cell(display) .. "\031" .. tostring(tonumber(key) or 0)
end

local function format_count(value)
  local digits = tostring(math.floor(tonumber(value) or 0))
  local sign = ""
  if string.sub(digits, 1, 1) == "-" then
    sign = "-"
    digits = string.sub(digits, 2)
  end
  local groups = {}
  while #digits > 3 do
    table.insert(groups, 1, string.sub(digits, -3))
    digits = string.sub(digits, 1, -4)
  end
  table.insert(groups, 1, digits)
  return sign .. table.concat(groups, " ")
end

local function set_message(message)
  if ui.message then
    ui.message:set_text(message or "")
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

local function gql(query, variables)
  if not (vlc.http and vlc.http.post) then
    return nil, lang.msg_no_http
  end

  local payload = json.encode({ query = query, variables = variables or {} })
  local status, body = vlc.http.post(
    GQL_URL, payload, "text/plain;charset=UTF-8", nil,
    { ["Client-ID"] = CLIENT_ID })
  if not status then
    return nil, tostring(body or lang.msg_bad_answer)
  end
  if status ~= 200 then
    return nil, "HTTP " .. tostring(status)
  end

  local answer, _, decode_error = json.decode(body or "")
  if type(answer) ~= "table" then
    return nil, tostring(decode_error or lang.msg_bad_answer)
  end
  if type(answer.errors) == "table" and answer.errors[1] then
    return nil, tostring(answer.errors[1].message or lang.msg_bad_answer)
  end
  if type(answer.data) ~= "table" then
    return nil, lang.msg_bad_answer
  end
  return answer.data
end

local TWITCH_HOSTS = {
  ["twitch.tv"] = true,
  ["www.twitch.tv"] = true,
  ["m.twitch.tv"] = true,
  ["go.twitch.tv"] = true,
}

local RESERVED_PATHS = {
  activate = true, creatorcamp = true, directory = true, downloads = true,
  drops = true, friends = true, inventory = true, jobs = true, login = true,
  messages = true, p = true, prime = true, products = true, search = true,
  settings = true, signup = true, store = true, subscriptions = true,
  team = true, turbo = true, videos = true, wallet = true,
}

-- Returns { kind = "channel", login = ... } or { kind = "video", id = ... }
-- only for a complete Twitch URL (scheme and host included).
local function parse_twitch_url(value)
  local url = trim(value)
  local _, host, path = string.match(url,
    "^(https?)://([^/%?#]+)([^%?#]*)")
  if not host then
    return nil
  end
  host = string.lower(host)
  if not TWITCH_HOSTS[host] then
    if string.match(host, "%.twitch%.tv$") then
      return false, "unsupported"
    end
    return nil
  end

  local video_id = string.match(path or "", "^/videos/(%d+)/?$")
  if video_id then
    return { kind = "video", id = video_id }
  end

  local login = string.match(path or "", "^/([%w_]+)")
  if not login or RESERVED_PATHS[string.lower(login)] then
    return false, "unsupported"
  end
  return { kind = "channel", login = string.lower(login) }
end

local function graph_name(game)
  if type(game) ~= "table" then
    return ""
  end
  return game.displayName or game.name or ""
end

local function channel_from_search(item)
  if type(item) ~= "table" or type(item.login) ~= "string" then
    return nil
  end
  local stream = item.stream
  return {
    login = item.login,
    display_name = item.displayName or item.login,
    live = type(stream) == "table",
    title = type(stream) == "table" and stream.title or nil,
    viewers = type(stream) == "table" and tonumber(stream.viewersCount) or 0,
    category = type(stream) == "table" and graph_name(stream.game) or "",
  }
end

local function channel_from_stream(stream)
  if type(stream) ~= "table" or type(stream.broadcaster) ~= "table"
      or type(stream.broadcaster.login) ~= "string" then
    return nil
  end
  return {
    login = stream.broadcaster.login,
    display_name = stream.broadcaster.displayName or stream.broadcaster.login,
    live = true,
    title = stream.title,
    viewers = tonumber(stream.viewersCount) or 0,
    category = graph_name(stream.game),
  }
end

local function fill_results(entries, category_name)
  app.rows = {}
  ui.results:clear()

  local shown = 0
  for _, entry in ipairs(entries or {}) do
    if entry then
      shown = shown + 1
      app.rows[shown] = entry
      ui.results:add_value(table.concat({
        cell(entry.display_name),
        cell(entry.category ~= "" and entry.category or lang.offline),
        sortable(format_count(entry.viewers), entry.viewers),
        cell(entry.title or lang.offline),
      }, "\t"), shown)
    end
  end
  ui.results:set_sort(3, false)

  if shown == 0 then
    set_message(lang.msg_no_results)
  elseif category_name then
    set_message(string.format(lang.msg_category_results, shown, category_name))
  else
    set_message(string.format(lang.msg_results, shown))
  end
end

local function search_channels(term)
  local data, err = gql(CHANNEL_SEARCH_QUERY, {
    query = term,
    limit = RESULT_LIMIT,
  })
  if not data then
    return nil, err
  end
  local found = data.searchUsers
  if type(found) ~= "table" then
    return nil, lang.msg_bad_answer
  end
  local entries = {}
  local edges = found.edges or {}
  for _, edge in ipairs(edges or {}) do
    local entry = channel_from_search(type(edge) == "table" and edge.node)
    if entry then
      table.insert(entries, entry)
    end
  end
  return entries
end

local function fill_categories(categories, preferred_name)
  app.categories = categories
  ui.category:clear()
  if #categories == 0 then
    ui.category:add_value(lang.category_none, 1)
    ui.category:set_value(1)
    return nil
  end

  local selected = 1
  local wanted = string.lower(preferred_name or "")
  for id, category in ipairs(categories) do
    ui.category:add_value(cell(category.name), id)
    if string.lower(category.name) == wanted then
      selected = id
    end
  end
  ui.category:set_value(selected)
  app.category = categories[selected]
  return app.category
end

local function find_categories(term)
  local data, err = gql(CATEGORY_SEARCH_QUERY, { query = term })
  if not data then
    return nil, err
  end
  local found = data.searchFor
  if type(found) ~= "table" then
    return nil, lang.msg_bad_answer
  end
  local categories = {}
  local edges = type(found.games) == "table" and found.games.edges or {}
  for _, edge in ipairs(edges or {}) do
    local game = type(edge) == "table" and edge.item
    if type(game) == "table" and game.id and (game.displayName or game.name) then
      table.insert(categories, {
        id = tostring(game.id),
        name = game.displayName or game.name,
      })
    end
  end
  return categories
end

local function streams_for_category(category)
  local data, err = gql(GAME_STREAMS_QUERY, {
    name = category.name,
    limit = RESULT_LIMIT,
  })
  if not data then
    return nil, err
  end
  if type(data.game) ~= "table" then
    return nil, lang.msg_no_categories
  end

  local entries = {}
  local streams = data.game.streams
  local edges = type(streams) == "table" and streams.edges or {}
  for _, edge in ipairs(edges or {}) do
    local entry = channel_from_stream(type(edge) == "table" and edge.node)
    if entry then
      table.insert(entries, entry)
    end
  end
  return entries, nil, data.game.displayName or data.game.name or category.name
end

local function esc(value)
  if vlc.strings and vlc.strings.encode_uri_component then
    return vlc.strings.encode_uri_component(tostring(value or ""))
  end
  return (string.gsub(tostring(value or ""), "[^%w%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function usher_url(kind, id, token)
  local path = kind == "video" and ("vod/" .. id)
                                  or ("api/channel/hls/" .. id)
  local params = {
    "allow_source=true",
    "allow_audio_only=true",
    "allow_spectre=true",
    "p=" .. tostring(math.random(1000000, 9999999)),
    "platform=web",
    "player=twitchweb",
    "supported_codecs=h264",
    "playlist_include_framerate=true",
    "sig=" .. esc(token.signature),
    "token=" .. esc(token.value),
  }
  return "https://usher.ttvnw.net/" .. path .. ".m3u8?"
         .. table.concat(params, "&")
end

local function valid_token(token)
  return type(token) == "table"
     and type(token.value) == "string" and token.value ~= ""
     and type(token.signature) == "string" and token.signature ~= ""
end

local function play_channel(login, known_name)
  set_message(string.format(lang.msg_opening, known_name or login))
  local data, err = gql(LIVE_PLAYBACK_QUERY, { login = login })
  if not data then
    return nil, err
  end
  if type(data.user) ~= "table" then
    return nil, lang.msg_not_found
  end
  local display_name = data.user.displayName or known_name or login
  if type(data.user.stream) ~= "table" then
    return nil, string.format(lang.msg_offline, display_name)
  end
  if not valid_token(data.streamPlaybackAccessToken) then
    return nil, lang.msg_bad_answer
  end

  local stream = data.user.stream
  set_message(lang.msg_playing)
  vlc.playlist.add({{
    path = usher_url("channel", login, data.streamPlaybackAccessToken),
    name = display_name,
    title = stream.title or display_name,
    artist = display_name,
    genre = graph_name(stream.game),
    url = "https://www.twitch.tv/" .. login,
  }})
  return true
end

local function play_video(id)
  set_message(string.format(lang.msg_opening_video, id))
  local data, err = gql(VIDEO_PLAYBACK_QUERY, { id = id })
  if not data then
    return nil, err
  end
  if type(data.video) ~= "table" then
    return nil, lang.msg_not_found
  end
  if not valid_token(data.videoPlaybackAccessToken) then
    return nil, lang.msg_bad_answer
  end

  local owner = data.video.owner or {}
  local display_name = owner.displayName or owner.login
  set_message(lang.msg_playing)
  vlc.playlist.add({{
    path = usher_url("video", id, data.videoPlaybackAccessToken),
    name = data.video.title or ("Twitch " .. id),
    title = data.video.title or ("Twitch " .. id),
    artist = display_name,
    url = "https://www.twitch.tv/videos/" .. id,
  }})
  return true
end

local function play_target(target, known_name)
  local ok, err
  if target.kind == "video" then
    ok, err = play_video(target.id)
  else
    ok, err = play_channel(target.login, known_name)
  end
  if not ok then
    set_message(lang.msg_play_failed .. tostring(err or lang.msg_bad_answer))
  end
  return ok
end

local function selected_row()
  if not ui.results then
    return nil
  end
  for id in pairs(ui.results:get_selection()) do
    return app.rows[id]
  end
  return nil
end

function click_play()
  local entry = selected_row()
  if not entry then
    set_message(lang.msg_select)
    return
  end
  if not entry.live then
    set_message(string.format(lang.msg_offline, entry.display_name))
    return
  end
  play_target({ kind = "channel", login = entry.login }, entry.display_name)
end

function click_category_changed()
  local id = ui.category and ui.category:get_value()
  local category = app.categories[tonumber(id) or 0]
  if not category then
    return
  end
  app.category = category
  set_message(lang.msg_searching)
  local entries, err, name = streams_for_category(category)
  if not entries then
    set_message(lang.msg_search_failed .. tostring(err))
    return
  end
  fill_results(entries, name)
end

local function show_category_controls()
  if ui.category or not dlg then
    return
  end

  ui.category_label = dlg:add_label(lang.lbl_category, 3, 2, 1, 1)
  ui.category = dlg:add_dropdown(4, 2, 2, 1, click_category_changed)

  if #app.categories == 0 then
    ui.category:add_value(lang.category_none, 1)
    ui.category:set_value(1)
  else
    local selected = 1
    for id, category in ipairs(app.categories) do
      ui.category:add_value(cell(category.name), id)
      if app.category and category.id == app.category.id then
        selected = id
      end
    end
    ui.category:set_value(selected)
  end
  dlg:update()
end

local function hide_category_controls()
  if not ui.category or not dlg then
    return
  end
  dlg:del_widget(ui.category)
  dlg:del_widget(ui.category_label)
  ui.category = nil
  ui.category_label = nil
  dlg:update()
end

function click_mode_changed()
  local mode = ui.mode and ui.mode:get_value()
  app.mode = (mode == 2) and 2 or 1
  if app.mode == 2 then
    show_category_controls()
  else
    hide_category_controls()
  end
end

function click_search()
  app.query = trim(ui.query:get_text())
  if app.query == "" then
    set_message(lang.msg_enter_query)
    return
  end

  local target, url_error = parse_twitch_url(app.query)
  if target then
    play_target(target)
    return
  elseif target == false or url_error then
    set_message(lang.msg_bad_url)
    return
  end

  click_mode_changed()
  set_message(lang.msg_searching)
  if app.mode == 1 then
    local entries, err = search_channels(app.query)
    if not entries then
      set_message(lang.msg_search_failed .. tostring(err))
      return
    end
    fill_results(entries)
    return
  end

  local categories, err = find_categories(app.query)
  if not categories then
    set_message(lang.msg_search_failed .. tostring(err))
    return
  end
  if #categories == 0 then
    fill_categories({}, app.query)
    fill_results({})
    set_message(lang.msg_no_categories)
    return
  end
  local category = fill_categories(categories, app.query)
  app.category = category
  local entries, stream_error, name = streams_for_category(category)
  if not entries then
    set_message(lang.msg_search_failed .. tostring(stream_error))
    return
  end
  fill_results(entries, name)
end

local function show_main()
  close_dlg()
  dlg = vlc.dialog(lang.title or EXT_NAME)
  dlg:set_size(780, 500)

  dlg:add_label(lang.lbl_query, 1, 1, 1, 1)
  ui.query = dlg:add_text_input(app.query, 2, 1, 3, 1, click_search)
  dlg:add_button(lang.btn_search, click_search, 5, 1, 1, 1)

  dlg:add_label(lang.lbl_mode, 1, 2, 1, 1)
  ui.mode = dlg:add_dropdown(2, 2, 1, 1, click_mode_changed)
  ui.mode:add_value(lang.mode_channels, 1)
  ui.mode:add_value(lang.mode_categories, 2)
  ui.mode:set_value(app.mode)

  if app.mode == 2 then
    show_category_controls()
  end

  ui.results = dlg:add_list(1, 3, 5, 1, click_play)
  ui.results:set_text(table.concat({
    lang.col_channel, lang.col_category, lang.col_viewers, lang.col_title,
  }, "\t"))
  ui.results:set_sort(3, false)

  dlg:add_button(lang.btn_play, click_play, 1, 4, 2, 1)
  ui.message = dlg:add_label(lang.msg_enter_query, 1, 5, 5, 1)
  dlg:show()
end

function descriptor()
  return {
    title = EXT_NAME,
    version = "1.0",
    author = "PowerVLC",
    url = "https://www.twitch.tv/",
    shortdesc = EXT_NAME,
    description = "Search Twitch channels, discover live streams by "
               .. "category and play complete Twitch URLs directly.",
    capabilities = {},
  }
end

function activate()
  load_lang()
  json = require("dkjson")
  vlc.msg.dbg("[Twitch] Welcome")
  show_main()
end

function deactivate()
  vlc.msg.dbg("[Twitch] Bye")
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

-- Pure helpers exposed only to the standalone test harness. The scanner and
-- the real extension never create this table.
if POWERVLC_TWITCH_TEST then
  twitch_test = {
    parse_twitch_url = parse_twitch_url,
    channel_from_search = channel_from_search,
    channel_from_stream = channel_from_stream,
    usher_url = usher_url,
  }
end
