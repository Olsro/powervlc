--[[
 yt-dlp.lua : graphical yt-dlp companion for PowerVLC

 Search videos, YouTube channels and playlists, inspect any URL supported by
 yt-dlp, select audio/subtitle languages, play streams and download them.
 Every invocation is asynchronous and its exact command remains visible.

 Copyright (C) 2026 the PowerVLC team

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
--]]

local EXT_NAME = "yt-dlp"
local RESULT_LIMIT = 20
local COLLECTION_LIMIT = 100
local POLL_MS = 250
local COMBINE_GIVEUP_POLLS = 20
local DIALOG_WIDTH = 820
local DIALOG_HEIGHT = 430
local folder_picker = nil

-- These are yt-dlp's public SearchInfoExtractor prefixes. A pasted URL does
-- not use this menu: every URL still goes to yt-dlp's complete extractor set.
local SERVICES = {
  { label = "YouTube",       prefix = "ytsearch" },
  { label = "SoundCloud",    prefix = "scsearch" },
  { label = "Bilibili",      prefix = "bilisearch" },
  { label = "Google Videos", prefix = "gvsearch" },
  { label = "Niconico",      prefix = "nicosearch" },
  { label = "Yahoo Video",   prefix = "yvsearch" },
  { label = "Rokfin",        prefix = "rkfnsearch" },
  { label = "PRX Stories",   prefix = "prxstories" },
}

local SEARCH_MODES = { "videos", "channels", "playlists" }

-- YouTube's metadata language is independent from PowerVLC's interface.
-- "auto" follows that interface; the other values are passed verbatim to
-- yt-dlp's documented youtube:lang extractor argument.
local SEARCH_LANGUAGES = {
  { code = "auto", key = "language_auto" },
  { code = "fr", label = "Français" },
  { code = "en", label = "English" },
  { code = "de", label = "Deutsch" },
  { code = "es", label = "Español" },
  { code = "it", label = "Italiano" },
  { code = "pt", label = "Português" },
  { code = "nl", label = "Nederlands" },
  { code = "pl", label = "Polski" },
  { code = "cs", label = "Čeština" },
  { code = "sv", label = "Svenska" },
  { code = "tr", label = "Türkçe" },
  { code = "ru", label = "Русский" },
  { code = "uk", label = "Українська" },
  { code = "ja", label = "日本語" },
  { code = "ko", label = "한국어" },
  { code = "zh-CN", label = "简体中文" },
  { code = "zh-TW", label = "繁體中文" },
}

local YOUTUBE_JOBS = {
  metadata = true,
  collection = true,
  search = true,
  play = true,
  download = true,
}

-- The controls are deliberately independent: an old computer can combine
-- H.264, 240p and 30 fps, while newer machines can opt into VP9 or AV1 at any
-- resolution. "auto" does not constrain the codec and follows yt-dlp's own
-- ranking.
local QUALITY_PRESETS = {
  { key = "best" },
  { key = "2160", height = 2160 },
  { key = "1440", height = 1440 },
  { key = "1080", height = 1080 },
  { key = "720", height = 720 },
  { key = "480", height = 480 },
  { key = "360", height = 360 },
  { key = "240", height = 240 },
  { key = "144", height = 144 },
  { key = "audio", audio_only = true },
}

local VIDEO_CODECS = {
  { key = "auto" },
  { key = "h264", prefix = "avc" },
  { key = "vp9", prefix = "vp9", audio_ext = "webm" },
  { key = "av1", prefix = "av01" },
}

local FPS_LIMITS = {
  { key = "auto" },
  { key = "30", maximum = 30 },
  { key = "24", maximum = 24 },
}

local STREAM_MODES = {
  { key = "adaptive" },
  { key = "single" },
}

-- --print emits one compact JSON object instead of --dump-json's full format
-- inventory (hundreds of kilobytes for one YouTube video).
local INFO_TEMPLATE = "%(.{id,title,webpage_url,original_url,uploader,channel,"
  .. "duration,view_count,upload_date,description,thumbnail,extractor,"
  .. "live_status,language})j"
local SEARCH_TEMPLATE = "%(.{id,title,webpage_url,url,uploader,channel,"
  .. "duration,view_count,upload_date,description,thumbnail,extractor,"
  .. "live_status,_type,"
  .. "channel_id,channel_url,uploader_url,playlist_count})j"
local AUDIO_TEMPLATE = "POWERVLC_AUDIO="
  .. "%(formats.:.{format_id,format_note,language,language_preference,"
  .. "audio_channels,abr,acodec,ext,vcodec})j"
local SUBTITLE_TEMPLATE = "POWERVLC_SUBS=%(subtitles)j"

local json = nil
local lang = {}
local dlg = nil
local ui = {}

local app = {
  binary = nil,
  custom_binary = nil,
  version = nil,
  download_dir = nil,
  service = 1,
  search_mode = 1,
  language = "auto",
  quality = 1,
  codec = 1,
  fps = 1,
  stream_mode = 1,
  query = "",
  results = {},
  result_kind = "video",
  view_title = nil,
  content = nil,
  audio_tracks = {},
  captions = {},
  combine = nil,
  last_command = "",
  output_path = nil,
  job = nil,
  current_view = "setup",
}

-- PowerVLC's internal Matroska muxer joins downloaded picture and sound.
-- Keep the VLM object alive for the whole job: its garbage collector stops
-- the broadcast.
local cb = {
  active = false,
  vlm = nil,
  out = nil,
  size = 0,
  total = 0,
  quiet = 0,
  percent = 0,
}
local combine_poll
local combine_stop

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("ytdlp") })
end

local function trim(value)
  return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

local function cell(value)
  return (string.gsub(tostring(value or ""), "[\t\r\n\031]", " "))
end

local function language_index(code)
  for i, entry in ipairs(SEARCH_LANGUAGES) do
    if entry.code == code then return i end
  end
  return nil
end

local function setting_index(entries, key)
  for i, entry in ipairs(entries) do
    if entry.key == key then return i end
  end
  return nil
end

local function ui_language()
  if vlc.config and vlc.config.language then
    local ok, value = pcall(vlc.config.language)
    if ok and type(value) == "string" and value ~= "" then
      return string.lower(value)
    end
  end
  for _, name in ipairs({ "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" }) do
    local value = os and os.getenv and os.getenv(name) or nil
    if value and value ~= "" then return string.lower(value) end
  end
  return "en"
end

local function effective_language()
  if app.language and app.language ~= "auto" then return app.language end
  local code = string.match(ui_language(), "^(%a%a)") or "en"
  return language_index(code) and code or "en"
end

local function language_label(code)
  for _, entry in ipairs(SEARCH_LANGUAGES) do
    if entry.code == code then return entry.label or lang[entry.key] or code end
  end
  return code or "?"
end

local function close_dlg()
  if dlg then
    dlg:hide()
    dlg:delete()
  end
  dlg = nil
  ui = {}
end

local function set_message(message)
  if ui.message then
    local text = tostring(message or "")
    if ui.message_text ~= text then
      ui.message_text = text
      ui.message:set_text(text)
      if dlg then dlg:update() end
    end
  end
end

local function settings_path()
  local dir = vlc.config and vlc.config.userdatadir
              and vlc.config.userdatadir()
  return dir and dir ~= "" and (dir .. "/yt-dlp.json") or nil
end

local function load_settings()
  local path = settings_path()
  if not (path and json) then return end
  local file = io.open(path, "r")
  if not file then return end
  local body = file:read("*a")
  file:close()
  local value = json.decode(body or "")
  if type(value) ~= "table" then return end
  if type(value.binary) == "string" and value.binary ~= "" then
    app.custom_binary = value.binary
  end
  if type(value.download_dir) == "string" and value.download_dir ~= "" then
    app.download_dir = value.download_dir
  end
  if SERVICES[tonumber(value.service) or 0] then
    app.service = tonumber(value.service)
  end
  if SEARCH_MODES[tonumber(value.search_mode) or 0] then
    app.search_mode = tonumber(value.search_mode)
  end
  if type(value.language) == "string" and language_index(value.language) then
    app.language = value.language
  end
  app.quality = setting_index(QUALITY_PRESETS, value.quality) or app.quality
  app.codec = setting_index(VIDEO_CODECS, value.codec) or app.codec
  app.fps = setting_index(FPS_LIMITS, value.fps) or app.fps
  app.stream_mode = setting_index(STREAM_MODES, value.stream_mode)
                    or app.stream_mode

  -- Migrate the unpublished extension's original five-value quality setting.
  -- Keep accepting it so locally created configuration files do not break.
  if not value.quality then
    local legacy = tonumber(value.format)
    local migrated = ({ [1] = "best", [2] = "1080", [3] = "720",
                        [4] = "720", [5] = "audio" })[legacy]
    app.quality = setting_index(QUALITY_PRESETS, migrated) or app.quality
    if legacy == 4 then
      app.stream_mode = setting_index(STREAM_MODES, "single")
    end
  end
end

local function save_settings()
  local path = settings_path()
  if not (path and json) then return end
  local file = io.open(path, "w")
  if not file then
    vlc.msg.warn("[yt-dlp] cannot write " .. path)
    return
  end
  file:write(json.encode({
    binary = app.custom_binary,
    download_dir = app.download_dir,
    service = app.service,
    search_mode = app.search_mode,
    language = app.language,
    quality = QUALITY_PRESETS[app.quality].key,
    codec = VIDEO_CODECS[app.codec].key,
    fps = FPS_LIMITS[app.fps].key,
    stream_mode = STREAM_MODES[app.stream_mode].key,
  }, { indent = true }))
  file:close()
end

local function is_windows()
  return package and package.config
     and string.sub(package.config, 1, 1) == "\\"
end

local function binary_candidates(preferred)
  local values, seen = {}, {}
  local function add(value)
    value = trim(value)
    if value ~= "" and not seen[value] then
      seen[value] = true
      table.insert(values, value)
    end
  end

  add(preferred)
  if is_windows() then
    add("yt-dlp.exe")
    add("yt-dlp")
    return values
  end

  -- Applications opened from Finder do not inherit the PATH configured by
  -- the user's interactive shell. Probe the standard package-manager paths
  -- explicitly before consulting the (often minimal) application PATH.
  add("yt-dlp")
  add("/opt/homebrew/bin/yt-dlp")
  add("/usr/local/bin/yt-dlp")
  add("/opt/local/bin/yt-dlp")

  local home = vlc.config and vlc.config.homedir
               and vlc.config.homedir() or ""
  if home ~= "" then
    add(home .. "/.local/bin/yt-dlp")
    add(home .. "/bin/yt-dlp")
  end

  local path = os and os.getenv and os.getenv("PATH") or ""
  for directory in string.gmatch(path .. ":", "([^:]+):") do
    add(directory .. "/yt-dlp")
  end
  return values
end

local function posix_quote(value)
  local text = tostring(value or "")
  if text ~= "" and not string.find(text, "[^%w_@%%+=:,./%-]") then
    return text
  end
  return "'" .. string.gsub(text, "'", "'\\''") .. "'"
end

-- The same escaping algorithm used by CreateProcess's argv serializer. This
-- string is only for display/copy; the process API receives the original list.
local function windows_quote(value)
  local text = tostring(value or "")
  if text ~= "" and not string.find(text, '[%s\t"]') then return text end
  local out, slashes = { '"' }, 0
  for i = 1, #text do
    local char = string.sub(text, i, i)
    if char == "\\" then
      slashes = slashes + 1
    elseif char == '"' then
      table.insert(out, string.rep("\\", slashes * 2 + 1))
      table.insert(out, char)
      slashes = 0
    else
      if slashes > 0 then table.insert(out, string.rep("\\", slashes)) end
      table.insert(out, char)
      slashes = 0
    end
  end
  if slashes > 0 then table.insert(out, string.rep("\\", slashes * 2)) end
  table.insert(out, '"')
  return table.concat(out)
end

local function command_text(argv)
  local quote = is_windows() and windows_quote or posix_quote
  local words = {}
  for i, value in ipairs(argv) do words[i] = quote(value) end
  return table.concat(words, " ")
end

local function refresh_command()
  if ui.command then ui.command:set_text(app.last_command or "") end
end

function click_copy_command()
  refresh_command()
  if app.last_command == "" then
    set_message(lang.msg_no_command)
    return
  end
  if vlc.clipboard and vlc.clipboard.set
     and vlc.clipboard.set(app.last_command) then
    set_message(lang.msg_command_copied)
  else
    set_message(lang.msg_copy_fallback)
  end
end

local function add_command_row(row, width)
  dlg:add_label(lang.lbl_command, 1, row, 1, 1)
  ui.command = dlg:add_text_input(app.last_command or "", 2, row,
                                  width - 3, 1)
  dlg:add_button(lang.btn_copy_command, click_copy_command,
                 width - 1, row, 1, 1)
  dlg:add_button(lang.btn_cancel, click_cancel_job, width, row, 1, 1)
end

local function output_tail(text)
  local cleaned = string.gsub(tostring(text or ""), "\r", "")
  cleaned = trim(cleaned)
  if #cleaned > 420 then cleaned = string.sub(cleaned, -420) end
  return cleaned
end

local function last_line(text)
  local answer = ""
  for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
    if trim(line) ~= "" then answer = trim(line) end
  end
  return answer
end

local function read_job_output(job)
  local file = io.open(app.output_path, "rb")
  if not file then return "" end
  file:seek("set", job.offset or 0)
  local chunk = file:read("*a") or ""
  job.offset = file:seek() or (job.offset or 0) + #chunk
  file:close()
  if chunk ~= "" then
    job.buffer = (job.buffer or "") .. chunk
    -- A long download should not grow the Lua heap for hours. Search and
    -- metadata outputs are tiny; 1 MiB still leaves ample diagnostic tail.
    if #job.buffer > 1024 * 1024 then
      job.buffer = string.sub(job.buffer, -512 * 1024)
    end
  end
  return chunk
end

local function arm_timer()
  if (app.job or cb.active or (folder_picker and folder_picker:busy()))
     and vlc.timer then
    vlc.timer(POLL_MS, "ytdlp_tick")
  end
end

local function start_job(kind, arguments, done, binary)
  if app.job then
    set_message(lang.msg_busy)
    return false
  end
  if not (vlc.process and vlc.process.start) then
    set_message(lang.msg_no_process_api)
    return false
  end

  local executable = binary or app.binary
  if not executable or executable == "" then
    set_message(lang.msg_binary_missing)
    return false
  end
  local argv = { executable }
  if YOUTUBE_JOBS[kind] then
    table.insert(argv, "--extractor-args")
    table.insert(argv, "youtube:lang=" .. effective_language())
  end
  for _, value in ipairs(arguments or {}) do table.insert(argv, tostring(value)) end
  app.last_command = command_text(argv)
  refresh_command()
  set_message(lang.msg_starting)

  local handle, err = vlc.process.start(argv, app.output_path)
  if not handle then
    set_message(string.format(lang.msg_start_failed, tostring(err or "?")))
    return false, err
  end
  app.job = {
    kind = kind,
    handle = handle,
    done = done,
    buffer = "",
    offset = 0,
    argv = argv,
  }
  arm_timer()
  return true
end

function click_cancel_job()
  if not app.job then
    if cb.active and combine_stop then
      combine_stop()
      set_message(lang.msg_combine_cancelled)
      return
    end
    set_message(lang.msg_nothing_to_cancel)
    return
  end
  if app.job.handle:cancel() then
    set_message(lang.msg_cancelling)
    arm_timer()
  end
end

function ytdlp_tick()
  local job = app.job
  if job then
    local chunk = read_job_output(job)
    if job.kind == "download" and chunk ~= "" then
      local line = last_line(job.buffer)
      if line ~= "" then set_message(line) end
    end

    local running, code = job.handle:status()
    if not running then
      read_job_output(job)
      app.job = nil
      local callback = job.done
      if callback then
        local ok, err = pcall(callback, code or -1, job.buffer or "", job)
        if not ok then
          vlc.msg.warn("[yt-dlp] asynchronous callback failed: " .. tostring(err))
          set_message(string.format(lang.msg_internal_error, tostring(err)))
        end
      end
    end
  end
  if folder_picker then folder_picker:poll() end
  if cb.active and combine_poll then combine_poll() end
  arm_timer()
end

local function parse_json_lines(body)
  local rows = {}
  for line in string.gmatch(tostring(body or "") .. "\n", "([^\n]+)\n") do
    if string.sub(trim(line), 1, 1) == "{" then
      local value = json.decode(line)
      if type(value) == "table" then table.insert(rows, value) end
    end
  end
  return rows
end

local function tagged_json(body, tag)
  for line in string.gmatch(tostring(body or "") .. "\n", "([^\r\n]*)\r?\n") do
    if string.sub(line, 1, #tag) == tag then
      local value = json.decode(string.sub(line, #tag + 1))
      if type(value) == "table" then return value end
    end
  end
  return {}
end

local function tagged_json_all(body, tag)
  local values = {}
  for line in string.gmatch(tostring(body or "") .. "\n", "([^\r\n]*)\r?\n") do
    if string.sub(line, 1, #tag) == tag then
      local value = json.decode(string.sub(line, #tag + 1))
      if type(value) == "table" then table.insert(values, value) end
    end
  end
  return values
end

local function audio_tracks_from_formats(formats)
  local by_language = {}
  for _, format in ipairs(formats or {}) do
    local code = trim(format.language)
    local acodec = trim(format.acodec)
    if code ~= "" and acodec ~= "" and acodec ~= "none"
       and trim(format.vcodec) == "none" then
      local previous = by_language[code]
      local rate = tonumber(format.abr) or 0
      if not previous or rate > previous.rate then
        local note = string.lower(tostring(format.format_note or ""))
        by_language[code] = {
          code = code,
          label = language_label(code),
          original = (tonumber(format.language_preference) or -1) > 0
                  or string.find(note, "original", 1, true) ~= nil,
          rate = rate,
        }
      end
    end
  end
  local tracks = {}
  for _, track in pairs(by_language) do table.insert(tracks, track) end
  local preferred = effective_language()
  table.sort(tracks, function(a, b)
    if (a.code == preferred) ~= (b.code == preferred) then
      return a.code == preferred
    end
    if a.original ~= b.original then return a.original end
    return a.label < b.label
  end)
  return tracks
end

local function choose_caption(code, variants, automatic)
  if code == "live_chat" or type(variants) ~= "table" then return nil end
  local chosen = nil
  for _, variant in ipairs(variants) do
    if variant.url and (not chosen or variant.ext == "vtt"
       or (variant.ext == "srt" and chosen.ext ~= "vtt")) then
      chosen = variant
    end
  end
  if not chosen then return nil end
  return {
    code = code,
    label = chosen.name or language_label(code),
    url = chosen.url,
    automatic = automatic == true,
  }
end

local function captions_from_metadata(subtitles, automatic_variants)
  local captions, seen = {}, {}
  for code, variants in pairs(subtitles or {}) do
    local caption = choose_caption(code, variants, false)
    if caption then
      seen[code] = true
      table.insert(captions, caption)
    end
  end
  local preferred = effective_language()
  if not seen[preferred] then
    local caption = choose_caption(preferred, automatic_variants, true)
    if caption then table.insert(captions, caption) end
  end
  table.sort(captions, function(a, b)
    if (a.code == preferred) ~= (b.code == preferred) then
      return a.code == preferred
    end
    if a.automatic ~= b.automatic then return not a.automatic end
    return a.label < b.label
  end)
  return captions
end

local function looks_like_url(value)
  return string.match(trim(value), "^[%a][%w+%.%-]*://") ~= nil
end

local function encode_uri_component(value)
  return (string.gsub(tostring(value or ""), "[^%w%-_%.~]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function youtube_url_kind(url)
  local value = string.lower(tostring(url or ""))
  if string.find(value, "youtube.com/watch", 1, true)
     or string.find(value, "youtu.be/", 1, true)
     or string.find(value, "/shorts/", 1, true) then
    return "video"
  end
  if string.find(value, "youtube.com/playlist", 1, true)
     and string.find(value, "list=", 1, true) then
    return "playlist"
  end
  if string.find(value, "youtube.com/channel/", 1, true)
     or string.find(value, "youtube.com/@", 1, true)
     or string.find(value, "youtube.com/c/", 1, true)
     or string.find(value, "youtube.com/user/", 1, true) then
    return "channel"
  end
  return "video"
end

local function youtube_search_url(query, kind)
  local filter = kind == "channel" and "EgIQAg%3D%3D" or "EgIQAw%3D%3D"
  return "https://www.youtube.com/results?search_query="
      .. encode_uri_component(query) .. "&sp=" .. filter
end

local function duration_text(seconds)
  local total = math.floor(tonumber(seconds) or 0)
  if total <= 0 then return "" end
  local hours = math.floor(total / 3600)
  local minutes = math.floor((total % 3600) / 60)
  local secs = total % 60
  if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
  return string.format("%d:%02d", minutes, secs)
end

local function count_text(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  local groups = {}
  while #text > 3 do
    table.insert(groups, 1, string.sub(text, -3))
    text = string.sub(text, 1, -4)
  end
  table.insert(groups, 1, text)
  return table.concat(groups, " ")
end

local function date_text(value)
  local date = tostring(value or "")
  local year, month, day = string.match(date, "^(%d%d%d%d)(%d%d)(%d%d)$")
  return year and (day .. "/" .. month .. "/" .. year) or date
end

local function content_url(content)
  return content and (content.webpage_url or content.original_url or content.url)
end

local function media_channel_url(media)
  if type(media) ~= "table" then return nil end
  if media._kind == "channel" then return content_url(media) end
  for _, value in ipairs({ media.channel_url, media.uploader_url }) do
    if looks_like_url(value) then return value end
  end
  local id = trim(media.channel_id)
  if id ~= "" and string.match(id, "^[%w_%-]+$") then
    return "https://www.youtube.com/channel/" .. id
  end
  return nil
end

local function wrap_text(value, width, max_lines)
  local text = string.gsub(tostring(value or ""), "%s+", " ")
  text = trim(text)
  local lines, line = {}, ""
  for word in string.gmatch(text, "%S+") do
    if #line > 0 and #line + #word + 1 > width then
      table.insert(lines, line)
      line = word
      if #lines >= max_lines then break end
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if #lines < max_lines and line ~= "" then table.insert(lines, line) end
  local result = table.concat(lines, "\n")
  if #text > #string.gsub(result, "\n", " ") then result = result .. "…" end
  return result
end

local function selected_result()
  if not ui.results then return nil end
  for id in pairs(ui.results:get_selection()) do return app.results[id] end
  return nil
end

local function selected_setting(widget, entries, current)
  local value = widget and widget:get_value() or current
  value = tonumber(value) or 1
  if not entries[value] then value = 1 end
  return value, entries[value]
end

local function selected_playback_settings()
  local quality, quality_entry = selected_setting(
    ui.quality, QUALITY_PRESETS, app.quality)
  local codec, codec_entry = selected_setting(
    ui.codec, VIDEO_CODECS, app.codec)
  local fps, fps_entry = selected_setting(
    ui.fps, FPS_LIMITS, app.fps)
  local stream_mode, stream_mode_entry = selected_setting(
    ui.stream_mode, STREAM_MODES, app.stream_mode)
  app.quality, app.codec, app.fps, app.stream_mode =
    quality, codec, fps, stream_mode
  return quality_entry, codec_entry, fps_entry, stream_mode_entry
end

local function selected_audio_track()
  if #app.audio_tracks == 0 or not ui.audio_track then return nil end
  local index = ui.audio_track:get_value()
  return app.audio_tracks[tonumber(index) or 1] or app.audio_tracks[1]
end

local function selected_caption()
  if not ui.caption then return nil end
  local value = ui.caption:get_value()
  local index = tonumber(value) or 1
  return index > 1 and app.captions[index - 1] or nil
end

local function filter(name, operator, value)
  return "[" .. name .. operator .. tostring(value) .. "]"
end

local function format_components(quality, codec, fps, audio)
  local language = audio and string.match(audio.code or "", "^[%w%-]+$")
  local audio_filter = language and filter("language", "=", language) or ""
  local audio_selector = "ba" .. audio_filter
  if quality.audio_only then return nil, audio_selector, nil end

  local video_filter = ""
  if quality.height then
    video_filter = video_filter .. filter("height", "<=", quality.height)
  end
  if codec.prefix then
    video_filter = video_filter .. filter("vcodec", "^=", codec.prefix)
  end
  if fps.maximum then
    video_filter = video_filter .. filter("fps", "<=", fps.maximum)
  end

  if codec.audio_ext then
    audio_selector = "(ba" .. audio_filter
      .. filter("ext", "=", codec.audio_ext) .. "/" .. audio_selector .. ")"
  end
  local video_selector = "bv" .. video_filter
  local combined = "b" .. filter("vcodec", "!=", "none")
    .. filter("acodec", "!=", "none") .. video_filter .. audio_filter
  return video_selector, audio_selector, combined
end

local function format_selector(quality, codec, fps, stream_mode, audio)
  local video, audio_selector, combined =
    format_components(quality, codec, fps, audio)
  if not video then return audio_selector end
  local adaptive = video .. "+" .. audio_selector
  if stream_mode.key == "single" then return combined .. "/" .. adaptive end
  return adaptive .. "/" .. combined
end

local function selected_format_selector()
  local quality, codec, fps, stream_mode = selected_playback_settings()
  return format_selector(quality, codec, fps, stream_mode,
                         selected_audio_track())
end

local function selected_download_selector()
  local quality, codec, fps, stream_mode = selected_playback_settings()
  local video, audio, combined = format_components(
    quality, codec, fps, selected_audio_track())
  if not video then return audio, false end
  if stream_mode.key == "single" then return combined, false end
  -- A comma tells yt-dlp to save each selected format independently. The
  -- extension then offers PowerVLC's own lossless Matroska muxer, exactly as
  -- the Invidious extension does, with no external ffmpeg dependency.
  return video .. "," .. audio, true
end

local function setting_labels(prefix, entries)
  local labels = {}
  for i, entry in ipairs(entries) do
    labels[i] = lang[prefix .. entry.key]
  end
  return labels
end

local fill_results
local show_search
local show_content
local browse_collection

local function apply_localized_metadata(content, localized)
  if type(localized) ~= "table" then return content end
  for _, key in ipairs({ "title", "description" }) do
    if type(localized[key]) == "string" and trim(localized[key]) ~= "" then
      content[key] = localized[key]
    end
  end
  return content
end

local function metadata_done(code, body, source_url, localized)
  local rows = parse_json_lines(body)
  if code ~= 0 or #rows == 0 then
    set_message(string.format(lang.msg_command_failed, code,
                              output_tail(body)))
    return
  end

  if #rows == 1 then
    app.content = apply_localized_metadata(rows[1], localized)
    app.audio_tracks = audio_tracks_from_formats(
      tagged_json(body, "POWERVLC_AUDIO="))
    app.captions = captions_from_metadata(
      tagged_json(body, "POWERVLC_SUBS="),
      tagged_json(body, "POWERVLC_AUTOSUBS="))
    if not content_url(app.content) then app.content.webpage_url = source_url end
    show_content()
  else
    app.results = rows
    fill_results(rows)
    set_message(string.format(lang.msg_results, #rows))
  end
end

local function open_url(url, localized)
  set_message(lang.msg_loading_content)
  start_job("metadata", {
    "--no-warnings", "--skip-download", "--no-playlist",
    "--no-flat-playlist",
    "--print", INFO_TEMPLATE,
    "--print", AUDIO_TEMPLATE,
    "--print", SUBTITLE_TEMPLATE,
    "--print", "POWERVLC_AUTOSUBS=%(automatic_captions."
                 .. effective_language() .. ")j",
    url,
  }, function(code, body) metadata_done(code, body, url, localized) end)
end

function click_open_result()
  local result = selected_result()
  if not result then
    set_message(lang.msg_select_result)
    return
  end
  if result._kind == "channel" or result._kind == "playlist" then
    browse_collection(result)
    return
  end
  local url = content_url(result)
  if not url then
    set_message(lang.msg_result_no_url)
    return
  end
  open_url(url, result)
end

function click_open_selected_channel()
  local result = selected_result()
  if not result then
    set_message(lang.msg_select_result)
    return
  end
  local url = media_channel_url(result)
  if not url then
    set_message(lang.msg_channel_unavailable)
    return
  end
  browse_collection({
    _kind = "channel",
    title = result.channel or result.uploader or result.title or url,
    webpage_url = url,
  })
end

fill_results = function(rows, kind, view_title)
  kind = kind or "video"
  app.results = {}
  app.result_kind = kind
  app.view_title = view_title
  if not ui.results then return end
  ui.results:clear()
  ui.results:set_text(lang.col_title .. "\t" .. lang.col_author .. "\t"
    .. (kind == "playlist" and lang.col_videos or lang.col_duration))
  for _, entry in ipairs(rows or {}) do
    local url = content_url(entry)
    if type(entry.title) == "string" and entry.title ~= "" and url then
      local id = #app.results + 1
      entry._kind = kind
      app.results[id] = entry
      ui.results:add_value(cell(entry.title) .. "\t"
        .. cell(entry.uploader or entry.channel or "") .. "\t"
        .. (kind == "playlist" and tostring(entry.playlist_count or "")
                                  or duration_text(entry.duration)), id)
    end
  end
end


browse_collection = function(result)
  local url = content_url(result)
  if not url then
    set_message(lang.msg_result_no_url)
    return
  end
  if result._kind == "channel"
     and string.find(string.lower(url), "youtube.com/", 1, true)
     and not string.match(url, "/(videos|shorts|streams)/?$") then
    url = string.gsub(url, "[?#].*$", "")
    url = string.gsub(url, "/+$", "") .. "/videos"
  end
  set_message(result._kind == "playlist" and lang.msg_playlist_loading
                                              or lang.msg_channel_loading)
  start_job("collection", {
    "--no-warnings", "--flat-playlist", "--playlist-end",
    tostring(COLLECTION_LIMIT), "--print", SEARCH_TEMPLATE, url,
  }, function(code, body)
    local rows = parse_json_lines(body)
    if code ~= 0 then
      set_message(string.format(lang.msg_command_failed, code,
                                output_tail(body)))
      return
    end
    fill_results(rows, "video", result.title)
    if #app.results == 0 then
      set_message(lang.msg_no_results)
    else
      set_message(string.format(lang.msg_collection_results,
                                result.title or "?", #app.results))
    end
  end)
end

function click_search()
  if app.job then
    set_message(lang.msg_busy)
    return
  end
  local query = trim(ui.query and ui.query:get_text() or app.query)
  if query == "" then
    set_message(lang.msg_enter_query)
    return
  end
  app.query = query
  local service = ui.service and ui.service:get_value() or app.service
  service = tonumber(service) or 1
  if not SERVICES[service] then service = 1 end
  app.service = service
  local mode = ui.mode and ui.mode:get_value() or app.search_mode
  mode = tonumber(mode) or 1
  if not SEARCH_MODES[mode] then mode = 1 end
  app.search_mode = mode
  save_settings()

  if looks_like_url(query) then
    local kind = youtube_url_kind(query)
    if kind == "channel" or kind == "playlist" then
      browse_collection({ _kind = kind, title = query, webpage_url = query })
    else
      open_url(query)
    end
    return
  end

  local kind = SEARCH_MODES[mode]
  local target
  if kind == "channels" or kind == "playlists" then
    -- Those two filtered search pages are YouTube-specific. Keep the service
    -- selector honest even if another service was selected for video search.
    app.service = 1
    if ui.service then ui.service:set_value(1) end
    local singular = kind == "channels" and "channel" or "playlist"
    target = youtube_search_url(query, singular)
    kind = singular
    set_message(string.format(lang.msg_searching, "YouTube"))
  else
    kind = "video"
    target = SERVICES[service].prefix .. RESULT_LIMIT .. ":" .. query
    set_message(string.format(lang.msg_searching, SERVICES[service].label))
  end
  app.view_title = nil
  start_job("search", {
    "--no-warnings", "--flat-playlist", "--playlist-end",
    tostring(RESULT_LIMIT), "--print", SEARCH_TEMPLATE, target,
  }, function(code, body)
    local rows = parse_json_lines(body)
    if code ~= 0 then
      set_message(string.format(lang.msg_command_failed, code,
                                output_tail(body)))
      return
    end
    fill_results(rows, kind)
    if #app.results == 0 then
      set_message(lang.msg_no_results)
    else
      set_message(string.format(lang.msg_results, #app.results))
    end
  end)
end

local function playback_done(code, body)
  if code ~= 0 then
    set_message(string.format(lang.msg_command_failed, code,
                              output_tail(body)))
    return
  end
  local urls = {}
  for line in string.gmatch(tostring(body or "") .. "\n", "([^\r\n]+)\r?\n") do
    line = trim(line)
    if looks_like_url(line) then table.insert(urls, line) end
  end
  if #urls == 0 then
    set_message(lang.msg_no_stream)
    return
  end
  local options = {}
  for i = 2, #urls do table.insert(options, ":input-slave=" .. urls[i]) end
  local caption = selected_caption()
  if caption and caption.url then
    table.insert(options, ":sub-file=" .. caption.url)
  end
  local content = app.content or {}
  vlc.playlist.add({{
    path = urls[1],
    title = content.title or content_url(content),
    artist = content.uploader or content.channel,
    arturl = content.thumbnail,
    url = content_url(content),
    options = options,
  }})
  set_message(lang.msg_playing)
end

function click_play()
  local url = content_url(app.content)
  if not url then
    set_message(lang.msg_result_no_url)
    return
  end
  local selector = selected_format_selector()
  save_settings()
  set_message(lang.msg_resolving_stream)
  start_job("play", {
    "--no-warnings", "--no-playlist", "--get-url",
    "--format", selector, url,
  }, playback_done)
end

function click_copy_url()
  local url = content_url(app.content)
  if not url then return end
  if vlc.clipboard and vlc.clipboard.set and vlc.clipboard.set(url) then
    set_message(lang.msg_url_copied)
  else
    set_message(lang.msg_url_copy_fallback .. url)
  end
end

-- Losslessly mux the two downloaded streams with PowerVLC's own VLM and
-- Matroska stream output. This is the same mechanism used by Invidious.
local function chain_quote(value)
  return "'" .. string.gsub(tostring(value or ""), "[\\'\"]", "\\%0") .. "'"
end

local function vlm_quote(value)
  return '"' .. string.gsub(tostring(value or ""), '[\\"]', '\\%0') .. '"'
end

local function file_size(path)
  local file = path and io.open(path, "rb")
  if not file then return 0 end
  local size = file:seek("end") or 0
  file:close()
  return size
end

local function file_exists(path)
  local file = path and io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function vlm_has_instance(node)
  if type(node) ~= "table" then return false end
  if node.name == "instance" then return true end
  for _, child in ipairs(node.children or {}) do
    if vlm_has_instance(child) then return true end
  end
  return false
end

local COMBINE_NAME = "powervlc_ytdlp_combine"

combine_stop = function()
  if cb.vlm then
    pcall(cb.vlm.execute_command, cb.vlm,
          "control " .. COMBINE_NAME .. " stop")
    pcall(cb.vlm.execute_command, cb.vlm, "del " .. COMBINE_NAME)
  end
  cb.vlm = nil
  cb.active = false
end

local function combine_start(record)
  if not (vlc.vlm and vlc.strings and vlc.strings.make_uri) then return false end
  local ok, vlm = pcall(vlc.vlm)
  if not ok or not vlm then return false end
  local video = vlc.strings.make_uri(record.video)
  local audio = vlc.strings.make_uri(record.audio)
  if not (video and audio) then return false end

  os.remove(record.out)
  local commands = {
    "del " .. COMBINE_NAME,
    "new " .. COMBINE_NAME .. " broadcast enabled",
    "setup " .. COMBINE_NAME .. " input " .. vlm_quote(video),
    "setup " .. COMBINE_NAME .. " option "
      .. vlm_quote("input-slave=" .. audio),
    "setup " .. COMBINE_NAME .. " option sout-all",
    "setup " .. COMBINE_NAME .. " option no-sout-display",
    "setup " .. COMBINE_NAME .. " output " .. vlm_quote(
      "#std{access=file,mux=avformat{mux=matroska},dst="
      .. chain_quote(record.out) .. "}"),
    "control " .. COMBINE_NAME .. " play",
  }
  for index, command in ipairs(commands) do
    local called, _, code = pcall(vlm.execute_command, vlm, command)
    if index > 1 and (not called or code ~= 0) then
      pcall(vlm.execute_command, vlm, "del " .. COMBINE_NAME)
      return false
    end
  end
  cb.vlm = vlm
  cb.active = true
  cb.out = record.out
  cb.size = 0
  cb.quiet = 0
  cb.percent = 0
  cb.total = file_size(record.video) + file_size(record.audio)
  return true
end

combine_poll = function()
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
    local output = cb.out
    combine_stop()
    set_message(string.format(lang.msg_combine_ok, output))
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

function click_combine()
  local record = app.combine
  if cb.active then
    set_message(string.format(lang.msg_combine_running, cb.percent))
    return
  end
  if not (record and file_exists(record.video)
          and file_exists(record.audio)) then
    set_message(lang.msg_combine_gone)
    return
  end
  if not vlc.timer or not combine_start(record) then
    set_message(lang.msg_combine_unsupported)
    return
  end
  set_message(string.format(lang.msg_combine_running, 0))
  arm_timer()
end

local function merged_output_path(file)
  local path = tostring(file.filepath or "")
  local suffix = "." .. tostring(file.format_id or "")
               .. "." .. tostring(file.ext or "")
  local base = path
  if suffix ~= ".." and string.sub(path, -#suffix) == suffix then
    base = string.sub(path, 1, #path - #suffix)
  else
    base = string.gsub(path, "%.[^./\\]+$", "")
  end
  return base .. ".mkv"
end

local function download_done(code, body)
  if ui.download then ui.download:set_text(lang.btn_download) end
  if code == 0 then
    local video, audio, saved
    for _, file in ipairs(tagged_json_all(body, "POWERVLC_FILE=")) do
      if type(file.filepath) == "string" and file.filepath ~= "" then
        saved = file.filepath
        if file.vcodec and file.vcodec ~= "none"
           and (not file.acodec or file.acodec == "none") then
          video = file
        elseif file.acodec and file.acodec ~= "none"
               and (not file.vcodec or file.vcodec == "none") then
          audio = file
        end
      end
    end
    if video and audio then
      app.combine = {
        video = video.filepath,
        audio = audio.filepath,
        out = merged_output_path(video),
        id = app.content and (app.content.id or content_url(app.content)),
      }
      local message = string.format(lang.msg_download_pair,
                                    video.filepath, audio.filepath)
      if app.current_view == "content" and show_content then show_content() end
      set_message(message)
    else
      set_message(saved and string.format(lang.msg_download_saved, saved)
                         or lang.msg_download_done)
    end
  elseif code == 130 or code == 143 then
    set_message(lang.msg_cancelled)
  else
    set_message(string.format(lang.msg_command_failed, code,
                              output_tail(body)))
  end
end

function click_download()
  if app.job then
    if app.job.kind == "download" then click_cancel_job()
    else set_message(lang.msg_busy) end
    return
  end
  local url = content_url(app.content)
  if not url then return end
  local directory = trim(ui.download_dir and ui.download_dir:get_text()
                         or app.download_dir)
  if directory == "" then
    set_message(lang.msg_download_dir_missing)
    return
  end
  app.download_dir = directory
  local selector = selected_download_selector()
  save_settings()

  local arguments = {
    "--no-playlist", "--newline", "--no-colors",
    "--progress-delta", "1", "--progress-template",
    "download:[download] %(progress._percent_str)s | %(progress._speed_str)s | ETA %(progress._eta_str)s",
    "--print", "after_move:POWERVLC_FILE="
      .. "%(.{filepath,vcodec,acodec,format_id,ext})j",
    "--print", "after_move:" .. lang.cli_finished .. " %(filepath)s",
    "--format", selector, "--paths", directory,
    "--output", "%(title).160B [%(id)s].%(format_id)s.%(ext)s",
  }
  local caption = selected_caption()
  if caption then
    table.insert(arguments, "--write-subs")
    if caption.automatic then table.insert(arguments, "--write-auto-subs") end
    table.insert(arguments, "--sub-langs")
    table.insert(arguments, caption.code)
  end
  table.insert(arguments, url)
  local started = start_job("download", arguments, download_done)
  if started and ui.download then
    ui.download:set_text(lang.btn_cancel_download)
    set_message(lang.msg_downloading)
  end
end

function click_choose_download_dir()
  if app.job or (folder_picker and folder_picker:busy()) then
    set_message(lang.msg_busy)
    return
  end
  app.download_dir = trim(ui.download_dir and ui.download_dir:get_text()
                          or app.download_dir)
  local started = folder_picker:open(lang.folder_picker_prompt,
                                     app.download_dir)
  if started then
    set_message(lang.msg_folder_picker_opening)
    arm_timer()
  else
    set_message(lang.msg_folder_picker_unavailable)
  end
end

show_content = function()
  close_dlg()
  app.current_view = "content"
  local content = app.content or {}
  dlg = vlc.dialog(lang.title_content)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(content.title or lang.unknown_title, 1, 1, 6, 1)
  local details = {}
  local author = content.uploader or content.channel
  if author and author ~= "" then table.insert(details, author) end
  if content.extractor then table.insert(details, content.extractor) end
  if tonumber(content.duration) then
    table.insert(details, duration_text(content.duration))
  end
  if tonumber(content.view_count) then
    table.insert(details, count_text(content.view_count) .. " " .. lang.views)
  end
  if content.upload_date then table.insert(details, date_text(content.upload_date)) end
  dlg:add_label(table.concat(details, " — "), 1, 2, 6, 1)
  local description = wrap_text(content.description, 92, 3)
  if description ~= "" then dlg:add_label(description, 1, 3, 6, 1) end

  local row = 4
  dlg:add_label(lang.lbl_quality, 1, row, 1, 1)
  ui.quality = dlg:add_dropdown(2, row, 2, 1)
  for i, label in ipairs(setting_labels("quality_", QUALITY_PRESETS)) do
    ui.quality:add_value(label, i)
  end
  ui.quality:set_value(app.quality)
  dlg:add_label(lang.lbl_codec, 4, row, 1, 1)
  ui.codec = dlg:add_dropdown(5, row, 2, 1)
  for i, label in ipairs(setting_labels("codec_", VIDEO_CODECS)) do
    ui.codec:add_value(label, i)
  end
  ui.codec:set_value(app.codec)
  row = row + 1

  dlg:add_label(lang.lbl_fps, 1, row, 1, 1)
  ui.fps = dlg:add_dropdown(2, row, 2, 1)
  for i, label in ipairs(setting_labels("fps_", FPS_LIMITS)) do
    ui.fps:add_value(label, i)
  end
  ui.fps:set_value(app.fps)
  dlg:add_label(lang.lbl_stream_mode, 4, row, 1, 1)
  ui.stream_mode = dlg:add_dropdown(5, row, 2, 1)
  for i, label in ipairs(setting_labels("stream_", STREAM_MODES)) do
    ui.stream_mode:add_value(label, i)
  end
  ui.stream_mode:set_value(app.stream_mode)
  row = row + 1

  if #app.audio_tracks > 1 then
    dlg:add_label(lang.lbl_audio_track, 1, row, 1, 1)
    ui.audio_track = dlg:add_dropdown(2, row, 5, 1)
    for i, track in ipairs(app.audio_tracks) do
      local label = track.label
      if track.original then label = label .. " (" .. lang.audio_original .. ")" end
      ui.audio_track:add_value(label, i)
    end
    ui.audio_track:set_value(1)
    row = row + 1
  end

  if #app.captions > 0 then
    dlg:add_label(lang.lbl_subtitles, 1, row, 1, 1)
    ui.caption = dlg:add_dropdown(2, row, 5, 1)
    ui.caption:add_value(lang.subtitles_none, 1)
    for i, caption in ipairs(app.captions) do
      local label = caption.label
      if caption.automatic then
        label = label .. " (" .. lang.subtitles_automatic .. ")"
      end
      ui.caption:add_value(label, i + 1)
    end
    ui.caption:set_value(1)
    row = row + 1
  end

  dlg:add_label(lang.lbl_download_dir, 1, row, 1, 1)
  ui.download_dir = dlg:add_text_input(app.download_dir or "", 2, row, 4, 1)
  dlg:add_button(lang.btn_choose_folder, click_choose_download_dir,
                 6, row, 1, 1)
  row = row + 1
  dlg:add_button(lang.btn_play, click_play, 1, row, 1, 1)
  ui.download = dlg:add_button(app.job and app.job.kind == "download"
                               and lang.btn_cancel_download or lang.btn_download,
                               click_download, 2, row, 1, 1)
  dlg:add_button(lang.btn_copy_url, click_copy_url, 3, row, 2, 1)
  dlg:add_button(lang.btn_back, show_search, 5, row, 2, 1)
  row = row + 1
  local content_id = content.id or content_url(content)
  if app.combine and app.combine.id == content_id
     and file_exists(app.combine.video) and file_exists(app.combine.audio) then
    dlg:add_button(lang.btn_combine, click_combine, 1, row, 3, 1)
    row = row + 1
  end
  ui.message = dlg:add_label(app.job and lang.msg_running
                                     or lang.msg_content_ready, 1, row, 6, 1)
  add_command_row(row + 1, 6)
  dlg:show()
end

function click_settings()
  show_setup(app.binary and lang.msg_binary_ready
                        or lang.msg_binary_prompt)
end

show_search = function()
  close_dlg()
  app.current_view = "search"
  dlg = vlc.dialog(lang.title_search)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  ui.mode = dlg:add_dropdown(1, 1, 1, 1)
  ui.mode:add_value(lang.mode_videos, 1)
  ui.mode:add_value(lang.mode_channels, 2)
  ui.mode:add_value(lang.mode_playlists, 3)
  ui.mode:set_value(app.search_mode)
  ui.service = dlg:add_dropdown(2, 1, 1, 1)
  for i, service in ipairs(SERVICES) do ui.service:add_value(service.label, i) end
  ui.service:set_value(app.service)
  ui.query = dlg:add_text_input(app.query or "", 3, 1, 3, 1, click_search)
  dlg:add_button(lang.btn_search, click_search, 6, 1, 1, 1)
  ui.results = dlg:add_list(1, 2, 6, 1, click_open_result)
  ui.results:set_text(lang.col_title .. "\t" .. lang.col_author
                      .. "\t" .. lang.col_duration)
  if #app.results > 0 then
    local previous = app.results
    fill_results(previous, app.result_kind, app.view_title)
  end
  dlg:add_button(lang.btn_open, click_open_result, 1, 3, 2, 1)
  dlg:add_button(lang.btn_open_channel, click_open_selected_channel,
                 3, 3, 2, 1)
  dlg:add_button(lang.btn_settings, click_settings, 5, 3, 2, 1)
  local search_message = app.view_title
      and string.format(lang.msg_collection_results,
                        app.view_title, #app.results)
      or lang.msg_search_hint
  ui.message = dlg:add_label(app.job and lang.msg_running
                                     or search_message, 1, 4, 6, 1)
  add_command_row(5, 6)
  dlg:show()
end

local function probe_binary(candidate, remember, on_failure)
  if app.job then
    set_message(lang.msg_busy)
    return
  end
  set_message(string.format(lang.msg_testing_binary, candidate))
  local started = start_job("probe", { "--version" }, function(code, body)
    local version = trim(last_line(body))
    if code ~= 0 or version == "" then
      app.binary = nil
      local detail = output_tail(body)
      if on_failure then
        on_failure(candidate, detail)
      else
        set_message(string.format(lang.msg_binary_failed, candidate, detail))
      end
      return
    end
    app.binary = candidate
    app.version = version
    if remember then
      app.custom_binary = candidate == "yt-dlp" and nil or candidate
      save_settings()
    end
    show_search()
    set_message(string.format(lang.msg_found_version, version))
  end, candidate)
  if not started then
    app.binary = nil
    if on_failure then on_failure(candidate, "not found") end
  end
end

local function probe_binary_candidates(candidates, remember, index,
                                       failed_candidate, failed_detail)
  index = index or 1
  local candidate = candidates[index]
  if not candidate then
    app.binary = nil
    set_message(string.format(lang.msg_binary_failed,
      failed_candidate or "yt-dlp", failed_detail or "not found"))
    return
  end
  probe_binary(candidate, remember, function(name, detail)
    probe_binary_candidates(candidates, remember, index + 1, name, detail)
  end)
end

local function capture_setup_preferences()
  local value = ui.language and ui.language:get_value() or 1
  local index = tonumber(value) or 1
  local entry = SEARCH_LANGUAGES[index] or SEARCH_LANGUAGES[1]
  app.language = entry.code
end

function click_test_binary()
  capture_setup_preferences()
  local candidate = trim(ui.binary and ui.binary:get_text() or "")
  -- Copying a path from a shell commonly includes one harmless quote pair.
  local quoted = string.match(candidate, "^['\"](.-)['\"]$")
  if quoted then candidate = quoted end
  if candidate == "" then
    set_message(lang.msg_enter_binary)
    return
  end
  probe_binary(candidate, true)
end

function click_use_path()
  capture_setup_preferences()
  probe_binary_candidates(binary_candidates(), true)
end

function click_back_from_setup()
  capture_setup_preferences()
  save_settings()
  if app.binary then show_search() else set_message(lang.msg_binary_prompt) end
end

function show_setup(message)
  close_dlg()
  app.current_view = "setup"
  dlg = vlc.dialog(lang.title_setup)
  dlg:set_size(680, 0)
  dlg:add_label(lang.lbl_binary_help, 1, 1, 4, 1)
  dlg:add_label(lang.lbl_binary, 1, 2, 1, 1)
  ui.binary = dlg:add_text_input(app.custom_binary or app.binary or "", 2, 2, 3, 1)
  dlg:add_label(lang.lbl_search_language, 1, 3, 1, 1)
  ui.language = dlg:add_dropdown(2, 3, 3, 1)
  for i, entry in ipairs(SEARCH_LANGUAGES) do
    ui.language:add_value(entry.label or lang[entry.key] or entry.code, i)
  end
  ui.language:set_value(language_index(app.language) or 1)
  dlg:add_button(lang.btn_test_save, click_test_binary, 1, 4, 2, 1)
  dlg:add_button(lang.btn_use_path, click_use_path, 3, 4, 1, 1)
  if app.binary then dlg:add_button(lang.btn_back, click_back_from_setup, 4, 4, 1, 1) end
  ui.message = dlg:add_label(message or lang.msg_binary_prompt, 1, 5, 4, 1)
  add_command_row(6, 4)
  dlg:show()
end

function descriptor()
  return {
    title = EXT_NAME,
    version = "1.0",
    author = "PowerVLC",
    url = "https://github.com/yt-dlp/yt-dlp",
    shortdesc = EXT_NAME,
    description = "Search, inspect, play and download content through "
               .. "yt-dlp with every background command kept visible.",
    capabilities = {},
  }
end

function activate()
  load_lang()
  json = require("dkjson")
  folder_picker = require("pvlc_folder_picker").new("yt-dlp", {
    done=function(path, reason)
      if path then
        app.download_dir = path
        if ui.download_dir then ui.download_dir:set_text(path) end
        save_settings()
        set_message(string.format(lang.msg_folder_selected, path))
      elseif reason == "cancelled" then
        set_message(lang.msg_folder_picker_cancelled)
      else
        set_message(lang.msg_folder_picker_unavailable)
      end
    end,
  }, { platform = POWERVLC_YTDLP_PLATFORM })
  load_settings()
  local home = vlc.config and vlc.config.homedir and vlc.config.homedir() or "."
  if not app.download_dir or app.download_dir == "" then app.download_dir = home end
  local cache = vlc.config and vlc.config.cachedir and vlc.config.cachedir() or home
  local stamp = vlc.misc and vlc.misc.mdate and vlc.misc.mdate() or os.time()
  app.output_path = cache .. "/powervlc-ytdlp-" .. tostring(stamp) .. ".out"
  vlc.msg.dbg("[yt-dlp] Welcome")
  show_setup(lang.msg_looking_for_binary)
  if not (vlc.process and vlc.process.start) then
    set_message(lang.msg_no_process_api)
    return
  end
  probe_binary_candidates(binary_candidates(app.custom_binary), false)
end

function deactivate()
  vlc.msg.dbg("[yt-dlp] Bye")
  if vlc.timer then vlc.timer(0) end
  if cb.active and combine_stop then combine_stop() end
  if app.job and app.job.handle then
    app.job.handle:cancel()
    if app.job.handle.close then app.job.handle:close() end
  end
  app.job = nil
  if folder_picker then folder_picker:close() end
  if app.output_path then os.remove(app.output_path) end
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

if POWERVLC_YTDLP_TEST then
  ytdlp_test = {
    looks_like_url = looks_like_url,
    command_text = command_text,
    parse_json_lines = parse_json_lines,
    binary_candidates = binary_candidates,
    youtube_url_kind = youtube_url_kind,
    youtube_search_url = youtube_search_url,
    media_channel_url = media_channel_url,
    audio_tracks_from_formats = audio_tracks_from_formats,
    format_selector = format_selector,
    apply_localized_metadata = apply_localized_metadata,
  }
end
