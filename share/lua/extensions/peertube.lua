--[[
 peertube.lua : PeerTube discovery extension for PowerVLC

 Browse public PeerTube instances, discover or search federated content,
 open channels and playlists, then play a video at the chosen quality.

 Copyright (C) 2026 the PowerVLC team

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
--]]

local json, download_module, downloader = nil, nil, nil
local folder_picker_module, folder_picker = nil, nil

local DIRECTORY_URL = "https://instances.joinpeertube.org/api/v1/instances"
local SEPIASEARCH_URL = "https://sepiasearch.org"
local READ_CHUNK = 65536
local PAGE_SIZE = 30
local DIALOG_WIDTH, DIALOG_HEIGHT = 960, 560
local DOWNLOAD_POLL_MS = 300
local COMBINE_POLL_MS = 500
local COMBINE_GIVEUP_POLLS = 20

-- Kept empty at scan time: PowerVLC's extension scanner has no usable
-- require(), io or os library. The catalogue is loaded only in activate().
local lang = {}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("peertube") })
end

local app = {
  instance = nil,
  instance_name = nil,
  last_instance = "https://peertube.cpy.re",
  config = nil,
  directory = {},
  directory_topic = 1,
  directory_nsfw = 2,
  directory_language = 1,
  results = {},
  view_items = nil,
  view_kind = nil,
  view_title = nil,
  query = "",
  kind = 1,
  scope = 1,
  sort = 1,
  offset = 0,
  total = 0,
  collection = nil,
  video = nil,
  formats = {},
  audio_tracks = {},
  captions = {},
  download_dir = nil,
  -- The last separately downloaded picture and sound.  Keeping their
  -- paths lets the video view offer the same lossless remux as Invidious.
  combine = nil,
}

local dlg = nil
local ui = {}
local combine_stop
local arm_download_timer

-- Combining is performed by PowerVLC's own VLM/avformat output.  The VLM
-- object must stay referenced for the lifetime of the job: collecting it
-- would stop the broadcast before the Matroska file is complete.
local cb = {
  active = false,
  vlm = nil,
  out = nil,
  quiet = 0,
  size = 0,
  total = 0,
  percent = 0,
}

-- PeerTube's public instance form uses the IDs from /videos/categories.
-- A dropdown is used here because the plain VLC dialog API has no compact
-- group of multi-select checkboxes.
local DIRECTORY_TOPICS = {
  { nil, "topic_any" }, { 1, "topic_music" }, { 2, "topic_films" },
  { 3, "topic_vehicles" }, { 4, "topic_art" }, { 5, "topic_sports" },
  { 6, "topic_travels" }, { 7, "topic_gaming" }, { 8, "topic_people" },
  { 9, "topic_comedy" }, { 10, "topic_entertainment" },
  { 11, "topic_news" }, { 12, "topic_howto" },
  { 13, "topic_education" }, { 14, "topic_activism" },
  { 15, "topic_science" }, { 16, "topic_animals" },
  { 17, "topic_kids" }, { 18, "topic_food" },
}

local DIRECTORY_LANGUAGES = {
  { nil, "language_any" }, { "fr", "language_fr" },
  { "en", "language_en" }, { "de", "language_de" },
  { "es", "language_es" }, { "it", "language_it" },
  { "pt", "language_pt" }, { "nl", "language_nl" },
  { "pl", "language_pl" }, { "ru", "language_ru" },
  { "ja", "language_ja" }, { "zh", "language_zh" },
}

local function trim(value)
  return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

local function file_exists(path)
  local file = path and io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function cell(value)
  value = tostring(value or "?")
  value = string.gsub(value, "[\t\r\n\031]", " ")
  return string.gsub(value, "%s%s+", " ")
end

local function sortable(display, key)
  if key == nil then return cell(display) end
  return cell(display) .. "\031" .. tostring(key)
end

local function format_count(value)
  local digits = tostring(math.floor(tonumber(value) or 0))
  local groups = {}
  while #digits > 3 do
    table.insert(groups, 1, string.sub(digits, -3))
    digits = string.sub(digits, 1, -4)
  end
  table.insert(groups, 1, digits)
  return table.concat(groups, " ")
end

local function format_duration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, secs)
  end
  return string.format("%d:%02d", minutes, secs)
end

local function format_date(value)
  local date = tostring(value or "")
  return string.match(date, "^(%d%d%d%d%-%d%d%-%d%d)") or "?"
end

local function encode(value)
  if vlc.strings and vlc.strings.encode_uri_component then
    return vlc.strings.encode_uri_component(tostring(value or ""))
  end
  return (string.gsub(tostring(value or ""), "[^%w%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function normalize_instance(value)
  local url = trim(value)
  if url == "" or url == "https://" or url == "http://" then return nil end
  if not string.match(url, "^https?://") then url = "https://" .. url end
  local origin = string.match(url, "^(https?://[^/%?#]+)")
  return origin and string.gsub(origin, "/+$", "") or nil
end

local function origin_of(url)
  return type(url) == "string" and string.match(url, "^(https?://[^/%?#]+)")
                                    or nil
end

local function absolute_url(base, value)
  if type(value) ~= "string" or value == "" then return nil end
  if string.match(value, "^https?://") then return value end
  if string.sub(value, 1, 1) ~= "/" then value = "/" .. value end
  return base .. value
end

local function close_dlg()
  if dlg then dlg:hide() end
  dlg = nil
  ui = {}
  collectgarbage()
end

local function set_message(message)
  if ui.message then
    ui.message:set_text(message or "")
    if dlg then dlg:update() end
  end
end

local function stream_body(url)
  local ok, stream, err = pcall(vlc.stream, url)
  if not ok or not stream then
    return nil, tostring(err or stream or "stream error")
  end
  local chunks = {}
  while true do
    if vlc.keep_alive then pcall(vlc.keep_alive) end
    local chunk = stream:read(READ_CHUNK)
    if not chunk or #chunk == 0 then break end
    table.insert(chunks, chunk)
  end
  local body = table.concat(chunks)
  if body == "" then return nil, "empty response" end
  return body
end

local function get_json(url)
  local body, err = stream_body(url)
  if not body then return nil, err end
  local object, _, decode_err = json.decode(body, 1, nil)
  if type(object) ~= "table" then
    return nil, tostring(decode_err or "invalid JSON response")
  end
  if object.error and not object.data then
    return nil, tostring(object.error)
  end
  return object
end

local function settings_path()
  local dir = vlc.config and vlc.config.userdatadir
              and vlc.config.userdatadir()
  return dir and dir ~= "" and (dir .. "/peertube.json") or nil
end

local function load_settings()
  local path = settings_path()
  if not path then return end
  local file = io.open(path, "r")
  if not file then return end
  local object = json.decode(file:read("*a") or "")
  file:close()
  if type(object) == "table" then
    app.last_instance = normalize_instance(object.instance) or app.last_instance
    app.scope = tonumber(object.scope) or app.scope
    app.directory_topic = tonumber(object.directory_topic) or app.directory_topic
    local directory_nsfw = tonumber(object.directory_nsfw)
    if directory_nsfw and tonumber(object.directory_nsfw_version) ~= 2 then
      -- Migrate the former hide / blur / any / display choices to the new
      -- hide / no-preference / sensitive-only model.
      if directory_nsfw == 3 then directory_nsfw = 2 end
      if directory_nsfw == 4 then directory_nsfw = 3 end
    end
    if directory_nsfw and directory_nsfw >= 1 and directory_nsfw <= 3 then
      app.directory_nsfw = directory_nsfw
    end
    if type(object.download_dir) == "string" and object.download_dir ~= "" then
      app.download_dir = object.download_dir
    end
    app.directory_language = tonumber(object.directory_language)
                          or app.directory_language
  end
end

local function save_settings()
  local path = settings_path()
  if not path then return end
  local file = io.open(path, "w")
  if not file then return end
  file:write(json.encode({ instance = app.instance or app.last_instance,
    scope = app.scope,
    directory_topic = app.directory_topic,
    directory_nsfw = app.directory_nsfw,
    directory_nsfw_version = 2,
    directory_language = app.directory_language,
    download_dir = app.download_dir },
                         { indent = true }))
  file:close()
end

local function selected_row(list, rows)
  if not list then return nil end
  for id in pairs(list:get_selection()) do return rows[id] end
  return nil
end

local function target_from_url(value)
  local base, path = string.match(trim(value), "^(https?://[^/%?#]+)(/[^?#]*)")
  if not base then return nil end

  local id = string.match(path, "^/w/p/([%w_%-]+)")
          or string.match(path, "^/videos/watch/playlist/([%w_%-]+)")
          or string.match(path, "^/video%-playlists/watch/([%w_%-]+)")
          or string.match(path, "^/api/v1/video%-playlists/([%w_%-]+)")
  if id then return { kind = "playlist", id = id, base = base, title = value } end

  id = string.match(path, "^/videos/watch/([%w_%-]+)")
    or string.match(path, "^/videos/embed/([%w_%-]+)")
    or string.match(path, "^/w/([%w_%-]+)")
    or string.match(path, "^/api/v1/videos/([%w_%-]+)")
  if id then return { kind = "video", id = id, base = base, title = value } end

  id = string.match(path, "^/c/([^/]+)")
    or string.match(path, "^/video%-channels/([^/]+)")
    or string.match(path, "^/api/v1/video%-channels/([^/]+)")
  if id then return { kind = "channel", id = id, base = base, title = value } end
  return nil
end

function descriptor()
  return {
    title = "PeerTube",
    version = "1.0",
    author = "PowerVLC",
    url = "https://joinpeertube.org/",
    shortdesc = "PeerTube",
    description = "Discover videos, channels and playlists across PeerTube "
               .. "instances and play their streams in PowerVLC.",
    capabilities = {}
  }
end

function activate()
  load_lang()
  json = require("dkjson")
  download_module = require("pvlc_download")
  folder_picker_module = require("pvlc_folder_picker")
  load_settings()
  app.download_dir = app.download_dir or download_module.default_directory()
  downloader = download_module.new("peertube", {
    file=function(entry, index, total)
      set_message(string.format(lang.msg_downloading, index, total, entry.label))
    end,
    done=function(ok, value)
      if ui.download then ui.download:set_text(lang.btn_download) end
      if ok then
        local video_entry, audio_entry = nil, nil
        for _, entry in ipairs(value or {}) do
          if entry.kind == "video" then video_entry = entry end
          if entry.kind == "audio" then audio_entry = entry end
        end
        if video_entry and audio_entry then
          app.combine = {
            video = video_entry.path,
            audio = audio_entry.path,
            out = video_entry.combine_out,
            id = video_entry.video_id,
          }
          -- The view predates the completed download. Rebuild it so the new
          -- Combine button appears immediately, but never pull somebody back
          -- from a listing they opened while the download was running.
          if ui.quality and app.video
             and tostring(app.video.uuid) == tostring(app.combine.id) then
            peertube_show_video()
          end
        end
        set_message(string.format(lang.msg_download_complete, #value,
                                  value[1] and value[1].path or ""))
      elseif value == "cancelled" then set_message(lang.msg_download_cancelled)
      else set_message(lang.msg_download_fail .. tostring(value)) end
    end,
  })
  folder_picker = folder_picker_module.new("peertube", {
    done=function(path, err)
      if path then
        app.download_dir = path
        if ui.download_dir then ui.download_dir:set_text(path) end
        save_settings()
        set_message(string.format(lang.msg_folder_selected, path))
      elseif err == "cancelled" then set_message(lang.msg_folder_cancelled)
      else set_message(lang.msg_folder_unavailable) end
    end,
  })
  vlc.msg.dbg("[PeerTube] Welcome")
  peertube_show_connect()
end

function deactivate()
  vlc.msg.dbg("[PeerTube] Bye")
  if downloader and downloader:busy() then downloader:cancel() end
  if folder_picker then folder_picker:close() end
  if combine_stop then combine_stop() end
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

-- Connection and public directory -----------------------------------------

function peertube_show_connect()
  close_dlg()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  dlg:add_label(lang.lbl_instance, 1, 1, 1, 1)
  ui.instance = dlg:add_text_input(app.last_instance or "", 2, 1, 3, 1,
                                   peertube_click_connect)
  dlg:add_button(lang.btn_connect, peertube_click_connect, 5, 1, 1, 1)
  dlg:add_button(lang.btn_list_instances, peertube_click_list_instances,
                 1, 2, 2, 1)
  ui.directory_topic = dlg:add_dropdown(3, 2, 1, 1,
                                        peertube_directory_filter_changed)
  for id, topic in ipairs(DIRECTORY_TOPICS) do
    ui.directory_topic:add_value(lang[topic[2]], id)
  end
  ui.directory_topic:set_value(app.directory_topic)
  ui.directory_nsfw = dlg:add_dropdown(4, 2, 1, 1,
                                       peertube_directory_filter_changed)
  ui.directory_nsfw:add_value(lang.nsfw_hide, 1)
  ui.directory_nsfw:add_value(lang.nsfw_any, 2)
  ui.directory_nsfw:add_value(lang.nsfw_only, 3)
  ui.directory_nsfw:set_value(app.directory_nsfw)
  ui.directory_language = dlg:add_dropdown(5, 2, 1, 1,
                                           peertube_directory_filter_changed)
  for id, language in ipairs(DIRECTORY_LANGUAGES) do
    ui.directory_language:add_value(lang[language[2]], id)
  end
  ui.directory_language:set_value(app.directory_language)
  ui.instances = dlg:add_list(1, 3, 5, 1, peertube_click_instance_activated)
  ui.instances:set_text(lang.col_instance .. "\t" .. lang.col_country
                      .. "\t" .. lang.col_videos .. "\t" .. lang.col_users
                      .. "\t" .. lang.col_version)
  dlg:add_button(lang.btn_use_selection, peertube_click_use_instance,
                 1, 4, 2, 1)
  dlg:add_button(lang.btn_sepiasearch, peertube_open_sepiasearch,
                 3, 4, 1, 1)
  ui.message = dlg:add_label("", 4, 4, 2, 1)
  dlg:show()
end

function peertube_click_list_instances()
  set_message(lang.msg_fetching_instances)
  app.directory_topic = ui.directory_topic:get_value()
  app.directory_nsfw = ui.directory_nsfw:get_value()
  app.directory_language = ui.directory_language:get_value()
  local params = {
    "start=0", "count=100", "healthy=true", "customizations=3",
    "sort=-customizations", "randomSortSeed=" .. tostring(os.time()),
  }
  local topic = DIRECTORY_TOPICS[app.directory_topic]
  if topic and topic[1] then
    table.insert(params, "categoriesOr%5B%5D=" .. encode(topic[1]))
  end
  local language = DIRECTORY_LANGUAGES[app.directory_language]
  if language and language[1] then
    table.insert(params, "languagesOr%5B%5D=" .. encode(language[1]))
  end
  if app.directory_nsfw == 1 then
    table.insert(params, "nsfwPolicy%5B%5D=do_not_list")
  elseif app.directory_nsfw == 3 then
    table.insert(params, "nsfwPolicy%5B%5D=display")
  end
  save_settings()
  local object, err = get_json(DIRECTORY_URL .. "?" .. table.concat(params, "&"))
  if not object then
    set_message(lang.msg_directory_fail .. tostring(err))
    return
  end
  app.directory = {}
  ui.instances:clear()
  for _, item in ipairs(object.data or {}) do
    if item.host then
      local row = {
        url = "https://" .. item.host,
        name = trim(item.name) ~= "" and item.name or item.host,
      }
      table.insert(app.directory, row)
      local id = #app.directory
      ui.instances:add_value(cell(row.name .. " — " .. item.host) .. "\t"
        .. cell(item.country or "?") .. "\t"
        .. sortable(format_count(item.totalLocalVideos), item.totalLocalVideos)
        .. "\t" .. sortable(format_count(item.totalUsers), item.totalUsers)
        .. "\t" .. cell(item.version or "?"), id)
    end
  end
  if #app.directory == 0 then
    set_message(lang.msg_no_instances)
  else
    set_message(string.format(lang.msg_instances_count, #app.directory))
  end
end

function peertube_directory_filter_changed()
  -- The three set_value() calls used to restore the dialog can notify before
  -- the instance list exists. They are initialization, not user changes.
  if not ui.directory_topic or not ui.directory_nsfw
     or not ui.directory_language or not ui.instances then return end
  if ui.directory_topic:get_value() == app.directory_topic
     and ui.directory_nsfw:get_value() == app.directory_nsfw
     and ui.directory_language:get_value() == app.directory_language then
    return
  end
  peertube_click_list_instances()
end

function peertube_click_use_instance()
  local item = selected_row(ui.instances, app.directory)
  if not item then set_message(lang.msg_select_instance); return end
  ui.instance:set_text(item.url)
  peertube_click_connect()
end

function peertube_click_instance_activated()
  peertube_click_use_instance()
end

-- SepiaSearch results carry their origin URLs, so an instance connection is
-- unnecessary: video details and streams will be fetched from that origin.
function peertube_open_sepiasearch()
  app.instance = app.instance or app.last_instance
  app.instance_name = "SepiaSearch"
  app.scope = 3
  app.offset, app.total = 0, 0
  app.collection = nil
  app.view_items, app.view_kind, app.view_title = nil, nil, nil
  save_settings()
  peertube_show_browser()
  peertube_discover(true)
end

function peertube_click_connect()
  local base = normalize_instance(ui.instance:get_text())
  if not base then set_message(lang.msg_enter_instance); return end
  set_message(lang.msg_connecting)
  local config, err = get_json(base .. "/api/v1/config")
  if not config then
    set_message(lang.msg_connect_fail .. tostring(err))
    return
  end
  app.instance = base
  app.last_instance = base
  app.config = config
  app.instance_name = config.instance and config.instance.name or base
  app.offset, app.total = 0, 0
  app.collection = nil
  app.view_items, app.view_kind, app.view_title = nil, nil, nil
  save_settings()
  peertube_show_browser()
  peertube_discover(true)
end

-- Search, discovery and content lists -------------------------------------

local VIDEO_SORTS = { "-publishedAt", "-trending", "-views", "-likes", "-publishedAt" }

local function selected_kind()
  local value = ui.kind and ui.kind:get_value() or app.kind
  return value == 2 and "channel" or value == 3 and "playlist" or "video"
end

local function query_url(kind, query)
  local scope = ui.scope and ui.scope:get_value() or app.scope
  local path
  if (query and query ~= "") or scope == 3 then
    path = kind == "channel" and "/api/v1/search/video-channels"
        or kind == "playlist" and "/api/v1/search/video-playlists"
        or "/api/v1/search/videos"
  else
    path = kind == "channel" and "/api/v1/video-channels"
        or kind == "playlist" and "/api/v1/video-playlists"
        or "/api/v1/videos"
  end

  local params = { "start=" .. app.offset, "count=" .. PAGE_SIZE }
  if query and query ~= "" then table.insert(params, "search=" .. encode(query)) end

  if kind == "video" then
    local sort_index = ui.sort and ui.sort:get_value() or app.sort
    table.insert(params, "sort=" .. encode(VIDEO_SORTS[sort_index] or "-publishedAt"))
    table.insert(params, "nsfw=false")
    if sort_index == 5 then table.insert(params, "isLive=true") end
  else
    table.insert(params, "sort=-createdAt")
  end

  if scope == 2 then
    if kind == "video" then
      table.insert(params, "isLocal=true")
    elseif query and query ~= "" then
      local host = string.match(app.instance or "", "^https?://([^/]+)")
      if host then table.insert(params, "host=" .. encode(host)) end
    end
  end
  local base = scope == 3 and SEPIASEARCH_URL or app.instance
  return base .. path .. "?" .. table.concat(params, "&")
end

local function result_base(item)
  return origin_of(item.url)
      or (item.channel and origin_of(item.channel.url))
      or (item.videoChannel and origin_of(item.videoChannel.url))
      or app.instance
end

local function normalize_result(item, kind)
  if kind == "channel" then
    return {
      kind = kind,
      id = item.name or item.id,
      title = item.displayName or item.name or "?",
      author = item.ownerAccount and item.ownerAccount.displayName or "",
      host = item.host or (item.ownerAccount and item.ownerAccount.host) or "",
      videos = item.videosCount or item.totalVideos or 0,
      date = item.createdAt,
      base = result_base(item),
      raw = item,
    }
  elseif kind == "playlist" then
    local channel = item.videoChannel or {}
    return {
      kind = kind,
      id = item.uuid or item.shortUUID or item.id,
      title = item.displayName or "?",
      author = channel.displayName
            or (item.ownerAccount and item.ownerAccount.displayName) or "?",
      host = channel.host or (item.ownerAccount and item.ownerAccount.host) or "",
      videos = item.videoLength or item.videosLength or 0,
      date = item.createdAt,
      base = result_base(item),
      raw = item,
    }
  end
  local channel = item.channel or {}
  return {
    kind = "video",
    id = item.uuid or item.shortUUID or item.id,
    title = item.name or "?",
    author = channel.displayName
          or (item.account and item.account.displayName) or "?",
    channel_id = channel.name,
    channel_url = channel.url,
    host = channel.host or (item.account and item.account.host) or "",
    duration = item.duration or 0,
    views = item.views or 0,
    date = item.publishedAt or item.createdAt,
    live = item.isLive == true,
    thumbnail = (item.thumbnails and item.thumbnails[1]
                 and item.thumbnails[1].fileUrl)
             or absolute_url(app.instance, item.thumbnailPath),
    base = result_base(item),
    raw = item,
  }
end

local function fill_results(items, kind, title)
  app.results = {}
  app.view_items, app.view_kind, app.view_title = items, kind, title
  ui.results:clear()
  if kind == "channel" then
    ui.results:set_text(lang.col_channel .. "\t" .. lang.col_owner
                      .. "\t" .. lang.col_host .. "\t" .. lang.col_date)
  elseif kind == "playlist" then
    ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                      .. "\t" .. lang.col_videos .. "\t" .. lang.col_host)
  else
    ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                      .. "\t" .. lang.col_date .. "\t" .. lang.col_duration
                      .. "\t" .. lang.col_views .. "\t" .. lang.col_host)
  end
  for _, raw in ipairs(items or {}) do
    -- Playlist entries wrap the actual video in a `video` property.
    local item = kind == "video" and raw.video or raw
    if type(item) == "table" then
      local result = normalize_result(item, kind)
      table.insert(app.results, result)
      local id, line = #app.results, ""
      if kind == "channel" then
        line = cell(result.title) .. "\t" .. cell(result.author) .. "\t"
            .. cell(result.host) .. "\t" .. cell(format_date(result.date))
      elseif kind == "playlist" then
        line = cell(result.title) .. "\t" .. cell(result.author) .. "\t"
            .. sortable(format_count(result.videos), result.videos) .. "\t"
            .. cell(result.host)
      else
        local title_text = result.live and ("● " .. result.title) or result.title
        line = cell(title_text) .. "\t" .. cell(result.author) .. "\t"
            .. cell(format_date(result.date)) .. "\t"
            .. sortable(format_duration(result.duration), result.duration) .. "\t"
            .. sortable(format_count(result.views), result.views) .. "\t"
            .. cell(result.host)
      end
      ui.results:add_value(line, id)
    end
  end
  local prefix = title and title ~= "" and (title .. " — ") or ""
  if #app.results == 0 then
    set_message(prefix .. lang.msg_no_results)
  else
    local from = app.offset + 1
    local to = app.offset + #app.results
    set_message(prefix .. string.format(lang.msg_result_range, from, to,
                                        app.total or to))
  end
end

function peertube_show_browser()
  close_dlg()
  dlg = vlc.dialog("PeerTube — " .. tostring(app.instance_name or app.instance))
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  ui.kind = dlg:add_dropdown(1, 1, 1, 1, peertube_listing_filter_changed)
  ui.kind:add_value(lang.kind_videos, 1)
  ui.kind:add_value(lang.kind_channels, 2)
  ui.kind:add_value(lang.kind_playlists, 3)
  ui.kind:set_value(app.kind)
  ui.query = dlg:add_text_input(app.query or "", 2, 1, 2, 1,
                                peertube_search)
  dlg:add_button(lang.btn_search, peertube_search, 4, 1, 1, 1)
  dlg:add_button(lang.btn_discover, peertube_discover, 5, 1, 1, 1)

  ui.scope = dlg:add_dropdown(1, 2, 1, 1, peertube_listing_filter_changed)
  ui.scope:add_value(lang.scope_federated, 1)
  ui.scope:add_value(lang.scope_local, 2)
  ui.scope:add_value(lang.scope_global, 3)
  ui.scope:set_value(app.scope)
  ui.sort = dlg:add_dropdown(2, 2, 1, 1, peertube_listing_filter_changed)
  ui.sort:add_value(lang.sort_latest, 1)
  ui.sort:add_value(lang.sort_trending, 2)
  ui.sort:add_value(lang.sort_views, 3)
  ui.sort:add_value(lang.sort_likes, 4)
  ui.sort:add_value(lang.sort_live, 5)
  ui.sort:set_value(app.sort)
  dlg:add_button(lang.btn_previous, peertube_previous_page, 3, 2, 1, 1)
  dlg:add_button(lang.btn_next, peertube_next_page, 4, 2, 1, 1)
  dlg:add_button(lang.btn_change_instance, peertube_show_connect, 5, 2, 1, 1)

  ui.results = dlg:add_list(1, 3, 5, 1, peertube_open_selection)
  dlg:add_button(lang.btn_open, peertube_open_selection, 1, 4, 1, 1)
  dlg:add_button(lang.btn_play, peertube_play_selection, 2, 4, 1, 1)
  dlg:add_button(lang.btn_open_channel, peertube_open_channel, 3, 4, 1, 1)
  ui.message = dlg:add_label("", 1, 5, 5, 1)
  if app.view_items then
    fill_results(app.view_items, app.view_kind, app.view_title)
  else
    ui.results:set_text(lang.col_title)
  end
  dlg:show()
end

local function load_listing(query, reset)
  if reset then app.offset = 0 end
  app.collection = nil
  app.kind = ui.kind:get_value()
  app.scope = ui.scope:get_value()
  app.sort = ui.sort:get_value()
  app.query = query or ""
  local kind = selected_kind()
  set_message(query and query ~= "" and lang.msg_searching or lang.msg_discovering)
  local object, err = get_json(query_url(kind, query))
  if not object then
    set_message(lang.msg_query_fail .. tostring(err))
    return false
  end
  app.total = tonumber(object.total) or #(object.data or {})
  fill_results(object.data or {}, kind, nil)
  save_settings()
  return true
end

function peertube_listing_filter_changed()
  -- set_value() may notify while the dialog is still being assembled. Wait
  -- until every listing filter exists, and ignore values already in effect.
  if not ui.kind or not ui.scope or not ui.sort or not ui.results then return end
  local kind = ui.kind:get_value()
  local scope = ui.scope:get_value()
  local sort = ui.sort:get_value()
  if kind == app.kind and scope == app.scope and sort == app.sort then return end

  -- A filter change applies to the listing currently on screen: keep its
  -- search term, leave a channel/playlist collection if necessary, and start
  -- again on the first page without requiring another button click.
  load_listing(app.query or "", true)
end

function peertube_search()
  local query = trim(ui.query:get_text())
  if query == "" then set_message(lang.msg_enter_query); return end
  local target = target_from_url(query)
  if target then
    app.query = query
    if target.kind == "video" then peertube_open_video(target)
    else peertube_open_result(target) end
    return
  end
  load_listing(query, true)
end

function peertube_discover(initial)
  if not ui.kind then return end
  ui.query:set_text("")
  load_listing("", initial == true or initial == nil)
end

local function reload_page()
  if app.collection then
    peertube_open_result(app.collection, true)
  else
    load_listing(app.query, false)
  end
end

function peertube_previous_page()
  if app.offset <= 0 then return end
  app.offset = math.max(0, app.offset - PAGE_SIZE)
  reload_page()
end

function peertube_next_page()
  if app.offset + PAGE_SIZE >= app.total then return end
  app.offset = app.offset + PAGE_SIZE
  reload_page()
end

local function current_result()
  local result = selected_row(ui.results, app.results)
  if not result then set_message(lang.msg_select_result) end
  return result
end

function peertube_open_selection()
  local result = current_result()
  if result then peertube_open_result(result) end
end

function peertube_play_selection()
  local result = current_result()
  if not result then return end
  if result.kind ~= "video" then
    peertube_open_result(result)
    return
  end
  peertube_open_video(result, true)
end

function peertube_open_channel()
  local result = current_result()
  if not result then return end
  if result.kind == "channel" then peertube_open_result(result); return end
  if not result.channel_id then set_message(lang.msg_no_channel); return end
  peertube_open_result({
    kind = "channel",
    id = result.channel_id,
    title = result.author,
    base = origin_of(result.channel_url) or result.base,
  })
end

function peertube_open_result(result, keep_offset)
  if result.kind == "video" then peertube_open_video(result); return end
  if not keep_offset then app.offset = 0 end
  set_message(result.kind == "channel" and lang.msg_loading_channel
                                           or lang.msg_loading_playlist)
  local path
  if result.kind == "channel" then
    path = "/api/v1/video-channels/" .. encode(result.id)
        .. "/videos?start=" .. app.offset .. "&count=" .. PAGE_SIZE
        .. "&sort=-publishedAt&nsfw=false"
  else
    path = "/api/v1/video-playlists/" .. encode(result.id)
        .. "/videos?start=" .. app.offset .. "&count=" .. PAGE_SIZE
  end
  local object, err = get_json((result.base or app.instance) .. path)
  if not object then set_message(lang.msg_query_fail .. tostring(err)); return end
  app.collection = result
  app.total = tonumber(object.total) or #(object.data or {})
  fill_results(object.data or {}, "video", result.title)
end

-- Video details and playback ----------------------------------------------

local function add_format(formats, seen, entry)
  local label_key = "label:" .. string.lower(trim(entry.label))
  if not entry.url or seen[entry.url] or seen[label_key] then return end
  seen[entry.url] = true
  seen[label_key] = true
  table.insert(formats, entry)
end

local function collect_formats(video)
  local formats, audio_tracks, seen, seen_audio, seen_audio_labels = {}, {}, {}, {}, {}
  local function add_audio(file)
    local url = file and (file.fileUrl or file.playlistUrl)
    if not url or seen_audio[url] then return end
    local resolution = file.resolution or {}
    local bitrate = tonumber(file.bitrate) or tonumber(file.metadata
                    and file.metadata.bitrate) or 0
    local language_label = file.language
                           and (file.language.label or file.language.id)
    local label = language_label
               or ((tonumber(resolution.id) == 0 or file.hasVideo == false)
                   and lang.format_audio)
               or resolution.label or lang.format_audio
    if bitrate > 0 then label = label .. " — " .. math.floor(bitrate / 1000) .. " kb/s" end
    -- PeerTube may advertise the same audio representation once as a direct
    -- file and once per streaming playlist. Their URLs differ, but presenting
    -- several indistinguishable "Audio only" choices is not useful. Keep the
    -- first direct representation for each visible technical identity.
    local label_key = string.lower(trim(label))
    if seen_audio_labels[label_key] then return end
    seen_audio[url] = true
    seen_audio_labels[label_key] = true
    table.insert(audio_tracks, { label=label, url=url, bitrate=bitrate })
  end
  for _, playlist in ipairs(video.streamingPlaylists or {}) do
    add_format(formats, seen, {
      label = lang.quality_auto_hls,
      url = playlist.playlistUrl,
      rank = 100000,
      adaptive = true,
      has_audio = true,
    })
  end
  for _, file in ipairs(video.files or {}) do
    local resolution = file.resolution or {}
    local rank = tonumber(resolution.id) or tonumber(file.height) or 0
    local audio = file.hasAudio ~= false
    local picture = file.hasVideo ~= false and rank > 0
    local suffix = picture and (audio and lang.format_av or lang.format_video)
                            or lang.format_audio
    if picture then
      add_format(formats, seen, {
        label = tostring(resolution.label or (rank .. "p")) .. " — " .. suffix,
        url = file.fileUrl, rank = rank, has_audio = audio,
      })
    else
      add_audio(file)
    end
  end
  for _, playlist in ipairs(video.streamingPlaylists or {}) do
    for _, file in ipairs(playlist.files or {}) do
      local resolution = file.resolution or {}
      if tonumber(resolution.id) == 0 or file.hasVideo == false then
        add_audio(file)
      end
    end
    for _, file in ipairs(playlist.files or {}) do
      local resolution = file.resolution or {}
      local rank = tonumber(resolution.id) or tonumber(file.height) or 0
      if rank > 0 then
        add_format(formats, seen, {
          label = tostring(resolution.label or (rank .. "p")) .. " — "
               .. (file.hasAudio == false and lang.format_separate
                                             or lang.format_av),
          url = file.fileUrl or file.playlistUrl,
          rank = rank,
          has_audio = file.hasAudio ~= false,
        })
      end
    end
  end
  table.sort(formats, function(a, b) return (a.rank or 0) > (b.rank or 0) end)
  table.sort(audio_tracks, function(a, b) return a.bitrate > b.bitrate end)
  return formats, audio_tracks
end

local function collect_captions(video, base)
  local list = video.captions
  if type(list) ~= "table" or (#list == 0 and not list.data) then
    local object = get_json(base .. "/api/v1/videos/" .. encode(video.uuid)
                         .. "/captions")
    list = object and (object.data or object) or {}
  else
    list = list.data or list
  end
  local captions = {}
  for _, caption in ipairs(list or {}) do
    local language = caption.language or {}
    local url = caption.fileUrl or absolute_url(base, caption.captionPath or caption.path)
    if url then
      table.insert(captions, {
        label = language.label or language.id or caption.languageId or "?",
        url = url,
      })
    end
  end
  return captions
end

function peertube_open_video(result, autoplay)
  local base = result.base or app.instance
  if ui.message then set_message(lang.msg_loading_video) end
  local video, err = get_json(base .. "/api/v1/videos/" .. encode(result.id))
  if not video then
    set_message(lang.msg_video_fail .. tostring(err))
    return
  end
  video._base = base
  video._thumbnail = result.thumbnail
  app.video = video
  app.formats, app.audio_tracks = collect_formats(video)
  app.captions = collect_captions(video, base)
  peertube_show_video()
  if autoplay and #app.formats > 0 then peertube_click_play() end
end

function peertube_show_video()
  close_dlg()
  local video = app.video
  dlg = vlc.dialog(lang.title_video)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(cell(video.name), 1, 1, 5, 1)
  local channel = video.channel or {}
  local details = string.format(lang.video_details,
    cell(channel.displayName or (video.account and video.account.displayName) or "?"),
    format_date(video.publishedAt or video.createdAt),
    format_duration(video.duration), format_count(video.views))
  dlg:add_label(details, 1, 2, 5, 1)
  dlg:add_label(lang.lbl_quality, 1, 3, 1, 1)
  ui.quality = dlg:add_dropdown(2, 3, 4, 1)
  for id, format in ipairs(app.formats) do
    ui.quality:add_value(format.label, id)
  end
  local row = 4
  if #app.audio_tracks > 0 then
    dlg:add_label(lang.lbl_audio, 1, row, 1, 1)
    ui.audio = dlg:add_dropdown(2, row, 4, 1)
    ui.audio:add_value(lang.audio_auto, 1)
    for id, audio in ipairs(app.audio_tracks) do
      ui.audio:add_value(audio.label, id + 1)
    end
    row = row + 1
  end
  if #app.captions > 0 then
    dlg:add_label(lang.lbl_subtitles, 1, row, 1, 1)
    ui.caption = dlg:add_dropdown(2, row, 4, 1)
    ui.caption:add_value(lang.subtitles_none, 1)
    for id, caption in ipairs(app.captions) do
      ui.caption:add_value(caption.label, id + 1)
    end
    row = row + 1
  end
  dlg:add_label(lang.lbl_download_dir, 1, row, 1, 1)
  ui.download_dir = dlg:add_text_input(app.download_dir or "", 2, row, 3, 1)
  dlg:add_button(lang.btn_choose_folder, peertube_choose_download_folder,
                 5, row, 1, 1)
  row = row + 1
  dlg:add_button(lang.btn_play, peertube_click_play, 1, row, 1, 1)
  dlg:add_button(lang.btn_copy_stream, peertube_copy_stream, 2, row, 1, 1)
  dlg:add_button(lang.btn_open_page, peertube_open_page, 3, row, 1, 1)
  if video.downloadEnabled ~= false then
    ui.download = dlg:add_button(downloader and downloader:busy()
                                 and lang.btn_cancel_download or lang.btn_download,
                                 peertube_click_download, 4, row, 1, 1)
  else
    dlg:add_label(lang.download_disabled, 4, row, 1, 1)
  end
  dlg:add_button(lang.btn_back, peertube_show_browser, 5, row, 1, 1)
  if app.combine and tostring(app.combine.id) == tostring(video.uuid)
                 and file_exists(app.combine.video)
                 and file_exists(app.combine.audio) then
    row = row + 1
    dlg:add_button(lang.btn_combine, peertube_click_combine, 3, row, 2, 1)
  end
  ui.link = dlg:add_text_input("", 1, row + 1, 5, 1)
  ui.message = dlg:add_label(#app.formats == 0 and lang.msg_no_formats or "",
                             1, row + 2, 5, 1)
  dlg:show()
end

local function chosen_format()
  if #app.formats == 0 then set_message(lang.msg_no_formats); return nil end
  return app.formats[ui.quality:get_value()] or app.formats[1]
end

local function chosen_audio(format)
  if #app.audio_tracks == 0 then return nil end
  local value = ui.audio and ui.audio:get_value() or 1
  if value > 1 then return app.audio_tracks[value - 1], true end
  if format and format.has_audio == false then return app.audio_tracks[1], false end
  return nil, false
end

local function chosen_caption()
  if ui.caption and ui.caption:get_value() > 1 then
    return app.captions[ui.caption:get_value() - 1]
  end
  return nil
end

function peertube_click_play()
  local format = chosen_format()
  if not format then return end
  local options = {}
  local audio = chosen_audio(format)
  if audio then table.insert(options, ":input-slave=" .. audio.url) end
  local caption = chosen_caption()
  if caption then table.insert(options, ":sub-file=" .. caption.url) end
  local channel = app.video.channel or {}
  vlc.playlist.add({{
    path = format.url,
    name = app.video.name,
    title = app.video.name,
    artist = channel.displayName
          or (app.video.account and app.video.account.displayName) or "PeerTube",
    arturl = app.video._thumbnail,
    options = options,
  }})
  set_message(lang.msg_playing)
end

-- Losslessly put a separately downloaded video and audio stream into one
-- Matroska file. This is the same in-process VLM/avformat path as Invidious:
-- no external ffmpeg executable, terminal or re-encoding is involved.
local function chain_quote(value)
  return "'" .. string.gsub(tostring(value or ""), "[\\'\"]", "\\%0") .. "'"
end

local function vlm_quote(value)
  return '"' .. string.gsub(tostring(value or ""), '[\\"]', '\\%0') .. '"'
end

local function vlm_has_instance(node)
  if type(node) ~= "table" then return false end
  if node.name == "instance" then return true end
  for _, child in ipairs(node.children or {}) do
    if vlm_has_instance(child) then return true end
  end
  return false
end

local function file_size(path)
  local file = path and io.open(path, "rb")
  if not file then return 0 end
  local size = file:seek("end") or 0
  file:close()
  return size
end

local COMBINE_NAME = "powervlc_peertube_combine"

combine_stop = function()
  if cb.vlm then
    pcall(cb.vlm.execute_command, cb.vlm,
          "control " .. COMBINE_NAME .. " stop")
    pcall(cb.vlm.execute_command, cb.vlm, "del " .. COMBINE_NAME)
  end
  cb.vlm = nil
  cb.active = false
end

local function combine_start(pair)
  if not (vlc.vlm and vlc.strings and vlc.strings.make_uri) then return false end
  local ok, manager = pcall(vlc.vlm)
  if not ok or not manager then return false end
  local video_uri = vlc.strings.make_uri(pair.video)
  local audio_uri = vlc.strings.make_uri(pair.audio)
  if not (video_uri and audio_uri) then return false end
  os.remove(pair.out)
  local commands = {
    "del " .. COMBINE_NAME,
    "new " .. COMBINE_NAME .. " broadcast enabled",
    "setup " .. COMBINE_NAME .. " input " .. vlm_quote(video_uri),
    "setup " .. COMBINE_NAME .. " option "
      .. vlm_quote("input-slave=" .. audio_uri),
    "setup " .. COMBINE_NAME .. " option sout-all",
    "setup " .. COMBINE_NAME .. " option no-sout-display",
    "setup " .. COMBINE_NAME .. " output " .. vlm_quote(
      "#std{access=file,mux=avformat{mux=matroska},dst="
      .. chain_quote(pair.out) .. "}"),
    "control " .. COMBINE_NAME .. " play",
  }
  for index, command in ipairs(commands) do
    local called, _, code = pcall(manager.execute_command, manager, command)
    -- Removing an absent previous job is the expected first-run result.
    if index > 1 and (not called or code ~= 0) then
      vlc.msg.err("[PeerTube] VLM refused: " .. command)
      pcall(manager.execute_command, manager, "del " .. COMBINE_NAME)
      return false
    end
  end
  cb.vlm = manager
  cb.active = true
  cb.out = pair.out
  cb.quiet = 0
  cb.size = 0
  cb.percent = 0
  cb.total = file_size(pair.video) + file_size(pair.audio)
  return true
end

local function combine_poll()
  if not cb.vlm then cb.active = false; return end
  local ok, state = pcall(cb.vlm.execute_command, cb.vlm,
                          "show " .. COMBINE_NAME)
  local size = file_size(cb.out)
  if ok and vlm_has_instance(state) then
    cb.quiet = 0
    cb.size = size
    if cb.total > 0 then
      cb.percent = math.min(99, math.max(cb.percent,
        math.floor(size * 100 / cb.total)))
    end
    set_message(string.format(lang.msg_combine_running, cb.percent))
    return
  end
  if size > 0 and size == cb.size then
    combine_stop()
    set_message(string.format(lang.msg_combine_ok, cb.out))
    return
  end
  cb.size = size
  cb.quiet = cb.quiet + 1
  if cb.quiet < COMBINE_GIVEUP_POLLS then return end
  local output = cb.out
  combine_stop()
  os.remove(output)
  set_message(lang.msg_combine_failed)
end

function peertube_click_combine()
  local pair = app.combine
  if cb.active then
    set_message(string.format(lang.msg_combine_running, cb.percent))
    return
  end
  if not (pair and file_exists(pair.video) and file_exists(pair.audio)) then
    set_message(lang.msg_combine_gone)
    return
  end
  if not vlc.timer or not combine_start(pair) then
    set_message(lang.msg_combine_unsupported)
    return
  end
  set_message(string.format(lang.msg_combine_running, 0))
  arm_download_timer()
end

arm_download_timer = function()
  if not vlc.timer then return end
  if (downloader and downloader:busy())
     or (folder_picker and folder_picker:busy()) then
    vlc.timer(DOWNLOAD_POLL_MS, "peertube_download_tick")
  elseif cb.active then
    vlc.timer(COMBINE_POLL_MS, "peertube_download_tick")
  end
end

function peertube_download_tick()
  if downloader then downloader:poll() end
  if folder_picker then folder_picker:poll() end
  if cb.active then combine_poll() end
  arm_download_timer()
end

function peertube_choose_download_folder()
  if downloader:busy() or folder_picker:busy() then
    set_message(lang.msg_download_busy); return
  end
  local started = folder_picker:open(lang.folder_picker_prompt,
    ui.download_dir and ui.download_dir:get_text() or app.download_dir)
  if started then set_message(lang.msg_folder_picker_opening); arm_download_timer() end
end

function peertube_click_download()
  if app.video.downloadEnabled == false then
    set_message(lang.msg_download_disabled)
    return
  end
  if downloader:busy() then
    downloader:cancel(); set_message(lang.msg_download_cancelling); return
  end
  local format = chosen_format()
  if not format then return end
  if format.adaptive then set_message(lang.msg_download_hls); return end
  local directory = trim(ui.download_dir and ui.download_dir:get_text()
                         or app.download_dir)
  if directory == "" then set_message(lang.msg_download_dir_missing); return end
  app.download_dir = directory
  save_settings()

  local base_name = download_module.sanitize(app.video.name) .. " ["
                  .. tostring(app.video.uuid or "peertube") .. "]"
  local tag = tostring(format.label or "video"):match("(%d+p)") or "video"
  local entries = {{
    url=format.url,
    path=download_module.unique_path(directory, base_name .. " — " .. tag
      .. "." .. download_module.extension(format.url, "mp4")),
    label=format.label,
    kind="video",
    video_id=app.video.uuid,
    combine_out=download_module.unique_path(directory,
      base_name .. " — combined.mkv"),
  }}
  local audio, explicit_audio = chosen_audio(format)
  if audio and (format.has_audio == false or explicit_audio) then
    table.insert(entries, {
      url=audio.url,
      path=download_module.unique_path(directory, base_name .. " — audio — "
        .. download_module.sanitize(audio.label) .. "."
        .. download_module.extension(audio.url, "m4a")),
      label=audio.label,
      kind="audio",
    })
  end
  local caption = chosen_caption()
  if caption then
    table.insert(entries, {
      url=caption.url,
      path=download_module.unique_path(directory, base_name .. " — subtitles — "
        .. download_module.sanitize(caption.label) .. "."
        .. download_module.extension(caption.url, "vtt")),
      label=caption.label,
      kind="caption",
    })
  end
  local started, err = downloader:start(entries)
  if started then
    if ui.download then ui.download:set_text(lang.btn_cancel_download) end
    arm_download_timer()
  else
    set_message(lang.msg_download_fail .. tostring(err))
  end
end

function peertube_copy_stream()
  local format = chosen_format()
  if not format then return end
  ui.link:set_text(format.url)
  if vlc.clipboard and vlc.clipboard.set and vlc.clipboard.set(format.url) then
    set_message(lang.msg_copied)
  else
    set_message(lang.msg_copy_fallback)
  end
end

function peertube_open_page()
  local url = app.video.url
         or (app.video._base .. "/w/" .. tostring(app.video.uuid))
  if vlc.browser and vlc.browser.open and vlc.browser.open(url) then
    set_message(lang.msg_page_opened)
  else
    ui.link:set_text(url)
    set_message(lang.msg_page_fallback)
  end
end

if POWERVLC_PEERTUBE_TEST then
  peertube_test = {
    normalize_instance = normalize_instance,
    target_from_url = target_from_url,
    collect_formats = collect_formats,
    normalize_result = normalize_result,
    combine_stop = combine_stop,
  }
end
