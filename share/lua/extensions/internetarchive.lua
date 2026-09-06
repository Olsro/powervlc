--[[
 internetarchive.lua : Internet Archive discovery for PowerVLC

 Browse the public Movies and Audio collections, inspect the files contained
 in an item, then play or download the selected representation.
--]]

local json, download_module, downloader = nil, nil, nil
local folder_picker_module, folder_picker = nil, nil
local API_SEARCH = "https://archive.org/advancedsearch.php"
local API_METADATA = "https://archive.org/metadata/"
local PAGE_SIZE = 30
local DIALOG_WIDTH, DIALOG_HEIGHT = 960, 560
local POLL_MS = 300
local lang = {}

local app = {
  mode = 1, sort = 1, query = "", page = 1, total = 0,
  results = {}, item = nil, files = {}, download_dir = nil,
}
local dlg = nil
local ui = {}

local MODES = {
  { mediatype = "movies", label = "mode_movies" },
  { mediatype = "audio", label = "mode_audio" },
}
local SORTS = {
  { field = "downloads desc", label = "sort_popular" },
  { field = "addeddate desc", label = "sort_recent" },
  { field = "titleSorter asc", label = "sort_title" },
}
local VIDEO_EXTENSIONS = {
  mp4=true, m4v=true, webm=true, ogv=true, mkv=true, mov=true,
  avi=true, mpg=true, mpeg=true, ts=true,
}
local AUDIO_EXTENSIONS = {
  mp3=true, ogg=true, oga=true, flac=true, m4a=true, wav=true,
  opus=true, aac=true, aiff=true, m3u=true,
}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("internetarchive") })
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function first(value)
  return type(value) == "table" and value[1] or value
end

local function cell(value)
  local text = tostring(first(value) or "?"):gsub("[\t\r\n\031]", " ")
  return (text:gsub("%s%s+", " "))
end

local function encode(value)
  if vlc.strings and vlc.strings.encode_uri_component then
    local encoded = vlc.strings.encode_uri_component(tostring(value or ""))
    return encoded
  end
  local encoded = tostring(value or ""):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
  return encoded
end

local function encode_path(path)
  local parts = {}
  for part in tostring(path or ""):gmatch("[^/]+") do
    table.insert(parts, encode(part))
  end
  return table.concat(parts, "/")
end

local function format_count(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  local groups = {}
  while #text > 3 do
    table.insert(groups, 1, text:sub(-3)); text = text:sub(1, -4)
  end
  table.insert(groups, 1, text)
  return table.concat(groups, " ")
end

local function format_size(value)
  local size = tonumber(value) or 0
  if size >= 1073741824 then return string.format("%.1f Gio", size / 1073741824) end
  if size >= 1048576 then return string.format("%.1f Mio", size / 1048576) end
  if size >= 1024 then return string.format("%.0f Kio", size / 1024) end
  return size > 0 and (size .. " o") or "?"
end

local function format_date(value)
  local text = tostring(first(value) or "")
  return text:match("^(%d%d%d%d%-%d%d%-%d%d)") or (text ~= "" and text or "?")
end

local function close_dlg()
  if dlg then dlg:hide() end
  dlg, ui = nil, {}
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
  if not ok or not stream then return nil, tostring(err or stream or "stream error") end
  local chunks = {}
  while true do
    if vlc.keep_alive then pcall(vlc.keep_alive) end
    local chunk = stream:read(65536)
    if not chunk or chunk == "" then break end
    table.insert(chunks, chunk)
  end
  local body = table.concat(chunks)
  return body ~= "" and body or nil, body == "" and "empty response" or nil
end

local function get_json(url)
  local body, err = stream_body(url)
  if not body then return nil, err end
  local object, _, decode_error = json.decode(body, 1, nil)
  if type(object) ~= "table" then return nil, tostring(decode_error or "invalid JSON") end
  return object
end

local function settings_path()
  local directory = vlc.config and vlc.config.userdatadir
                    and vlc.config.userdatadir()
  return directory and directory ~= "" and (directory .. "/internetarchive.json") or nil
end

local function load_settings()
  local path = settings_path()
  local file = path and io.open(path, "r")
  if not file then return end
  local object = json.decode(file:read("*a") or "")
  file:close()
  if type(object) ~= "table" then return end
  app.mode = math.max(1, math.min(#MODES, tonumber(object.mode) or app.mode))
  app.sort = math.max(1, math.min(#SORTS, tonumber(object.sort) or app.sort))
  if type(object.download_dir) == "string" then app.download_dir = object.download_dir end
end

local function save_settings()
  local path = settings_path()
  local file = path and io.open(path, "w")
  if not file then return end
  file:write(json.encode({ mode=app.mode, sort=app.sort,
                           download_dir=app.download_dir }, { indent=true }))
  file:close()
end

local function selected_row()
  if not ui.results then return nil end
  for id in pairs(ui.results:get_selection()) do return app.results[id] end
  return nil
end

local function search_query(query)
  local mode = MODES[app.mode] or MODES[1]
  -- The /details/movies and /details/audio landing pages aggregate many
  -- subcollections. mediatype selects that complete catalogue; adding the
  -- root collection would incorrectly keep only direct deposits.
  local clauses = { "mediatype:" .. mode.mediatype }
  query = trim(query)
  if query ~= "" then
    local quoted = query:gsub("\\", "\\\\"):gsub('"', '\\"')
    table.insert(clauses, '(title:"' .. quoted .. '" OR creator:"'
      .. quoted .. '" OR description:"' .. quoted .. '")')
  end
  return table.concat(clauses, " AND ")
end

local function search_url(query)
  local fields = { "identifier", "title", "creator", "date", "addeddate",
                   "downloads", "description", "mediatype" }
  local params = { "q=" .. encode(search_query(query)), "output=json",
                   "rows=" .. PAGE_SIZE, "page=" .. app.page,
                   "sort%5B%5D=" .. encode((SORTS[app.sort] or SORTS[1]).field) }
  for _, field in ipairs(fields) do
    table.insert(params, "fl%5B%5D=" .. encode(field))
  end
  return API_SEARCH .. "?" .. table.concat(params, "&")
end

local function fill_results(documents)
  app.results = {}
  ui.results:clear()
  for _, document in ipairs(documents or {}) do
    if document.identifier then
      local row = {
        identifier=document.identifier,
        title=first(document.title) or document.identifier,
        creator=first(document.creator) or "?",
        date=first(document.date) or first(document.addeddate),
        downloads=tonumber(document.downloads) or 0,
        mediatype=document.mediatype,
      }
      table.insert(app.results, row)
      ui.results:add_value(cell(row.title) .. "\t" .. cell(row.creator) .. "\t"
        .. format_date(row.date) .. "\t" .. format_count(row.downloads),
        #app.results)
    end
  end
  if #app.results == 0 then set_message(lang.msg_no_results); return end
  local from = (app.page - 1) * PAGE_SIZE + 1
  set_message(string.format(lang.msg_result_range, from,
    from + #app.results - 1, app.total))
end

local function run_search(query, reset)
  if reset then app.page = 1 end
  app.mode = ui.mode:get_value()
  app.sort = ui.sort:get_value()
  app.query = query or ""
  set_message(app.query ~= "" and lang.msg_searching or lang.msg_discovering)
  local object, err = get_json(search_url(app.query))
  if not object then set_message(lang.msg_search_fail .. tostring(err)); return false end
  local response = object.response or {}
  app.total = tonumber(response.numFound) or #(response.docs or {})
  fill_results(response.docs or {})
  save_settings()
  return true
end

function internetarchive_filter_changed()
  if not ui.mode or not ui.sort or not ui.results then return end
  if ui.mode:get_value() == app.mode and ui.sort:get_value() == app.sort then return end
  run_search(app.query, true)
end

function internetarchive_search()
  local query = trim(ui.query:get_text())
  if query == "" then set_message(lang.msg_enter_query); return end
  run_search(query, true)
end

function internetarchive_discover()
  ui.query:set_text("")
  run_search("", true)
end

function internetarchive_previous()
  if app.page <= 1 then return end
  app.page = app.page - 1; run_search(app.query, false)
end

function internetarchive_next()
  if app.page * PAGE_SIZE >= app.total then return end
  app.page = app.page + 1; run_search(app.query, false)
end

local function is_media_file(file)
  if type(file) ~= "table" or not file.name then return false end
  local name = tostring(file.name)
  local ext = name:match("%.([%w%d]+)$")
  ext = ext and ext:lower() or ""
  local allowed = app.mode == 1 and VIDEO_EXTENSIONS or AUDIO_EXTENSIONS
  if not allowed[ext] then return false end
  local format = tostring(file.format or ""):lower()
  return not format:find("metadata", 1, true)
     and not name:find("_thumb", 1, true)
     and not name:find("_spectrogram", 1, true)
end

local function collect_files(object, identifier)
  local files = {}
  for _, file in ipairs(object.files or {}) do
    if is_media_file(file) then
      local name = tostring(file.name)
      table.insert(files, {
        name=name, format=file.format or name:match("%.([^%.]+)$") or "?",
        size=tonumber(file.size) or 0, source=file.source,
        title=file.title or file.track or name,
        url="https://archive.org/download/" .. encode(identifier) .. "/"
            .. encode_path(name),
      })
    end
  end
  table.sort(files, function(a, b)
    if (a.source == "original") ~= (b.source == "original") then
      return a.source == "original"
    end
    if a.size ~= b.size then return a.size > b.size end
    return a.name < b.name
  end)
  return files
end

local function chosen_file()
  if #app.files == 0 then set_message(lang.msg_no_files); return nil end
  return app.files[ui.file:get_value()] or app.files[1]
end

local function play_current()
  local file = chosen_file()
  if not file then return end
  local metadata = app.item.metadata or {}
  set_message(lang.msg_playing)
  vlc.playlist.add({{
    path=file.url, name=first(metadata.title) or file.title,
    title=first(metadata.title) or file.title,
    artist=first(metadata.creator) or "Internet Archive",
    arturl="https://archive.org/services/img/" .. encode(metadata.identifier),
  }})
end

function internetarchive_open(autoplay)
  local result = selected_row()
  if not result then set_message(lang.msg_select); return end
  set_message(lang.msg_loading)
  local object, err = get_json(API_METADATA .. encode(result.identifier))
  if not object then set_message(lang.msg_metadata_fail .. tostring(err)); return end
  app.item = object
  app.files = collect_files(object, result.identifier)
  internetarchive_show_item()
  if autoplay and #app.files > 0 then play_current() end
end

function internetarchive_play_selection() internetarchive_open(true) end
function internetarchive_play() play_current() end

local function arm_timer()
  if vlc.timer and ((downloader and downloader:busy())
                    or (folder_picker and folder_picker:busy())) then
    vlc.timer(POLL_MS, "internetarchive_tick")
  end
end

function internetarchive_tick()
  if downloader then downloader:poll() end
  if folder_picker then folder_picker:poll() end
  arm_timer()
end

function internetarchive_choose_folder()
  if downloader:busy() or folder_picker:busy() then
    set_message(lang.msg_busy); return
  end
  local started = folder_picker:open(lang.folder_prompt,
    ui.download_dir and ui.download_dir:get_text() or app.download_dir)
  if started then set_message(lang.msg_folder_opening); arm_timer() end
end

function internetarchive_download()
  if downloader:busy() then downloader:cancel(); set_message(lang.msg_cancelling); return end
  local file = chosen_file()
  if not file then return end
  local directory = trim(ui.download_dir:get_text())
  if directory == "" then set_message(lang.msg_choose_folder); return end
  app.download_dir = directory; save_settings()
  local title = first((app.item or {}).metadata.title) or file.title
  local extension = download_module.extension(file.url,
    file.name:match("%.([^%.]+)$") or "bin")
  local path = download_module.unique_path(directory,
    title .. " [" .. tostring((app.item or {}).metadata.identifier or "archive")
      .. "]." .. extension)
  local started, err = downloader:start({{ url=file.url, path=path, label=file.name }})
  if started then
    if ui.download then ui.download:set_text(lang.btn_cancel) end
    arm_timer()
  else
    set_message(lang.msg_download_fail .. tostring(err))
  end
end

function internetarchive_open_page()
  local identifier = app.item and app.item.metadata and app.item.metadata.identifier
  local url = identifier and ("https://archive.org/details/" .. encode(identifier)) or nil
  if url and vlc.browser and vlc.browser.open and vlc.browser.open(url) then
    set_message(lang.msg_page_opened)
  elseif url then set_message(url) end
end

function internetarchive_show_item()
  close_dlg()
  local metadata = app.item.metadata or {}
  dlg = vlc.dialog(lang.title_item)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(cell(first(metadata.title) or metadata.identifier), 1, 1, 5, 1)
  dlg:add_label(string.format(lang.item_details,
    cell(first(metadata.creator) or "?"), format_date(metadata.date),
    cell(first(metadata.licenseurl) or first(metadata.rights) or "?")), 1, 2, 5, 1)
  dlg:add_label(lang.lbl_file, 1, 3, 1, 1)
  ui.file = dlg:add_dropdown(2, 3, 4, 1)
  for id, file in ipairs(app.files) do
    ui.file:add_value(cell(file.title) .. " — " .. cell(file.format)
      .. " — " .. format_size(file.size), id)
  end
  local row = 4
  dlg:add_label(lang.lbl_download_dir, 1, row, 1, 1)
  ui.download_dir = dlg:add_text_input(app.download_dir or "", 2, row, 3, 1)
  dlg:add_button(lang.btn_choose_folder, internetarchive_choose_folder, 5, row, 1, 1)
  row = row + 1
  dlg:add_button(lang.btn_play, internetarchive_play, 1, row, 1, 1)
  ui.download = dlg:add_button(downloader:busy() and lang.btn_cancel
                                                or lang.btn_download,
                               internetarchive_download, 2, row, 1, 1)
  dlg:add_button(lang.btn_open_page, internetarchive_open_page, 3, row, 1, 1)
  dlg:add_button(lang.btn_back, internetarchive_show_browser, 4, row, 1, 1)
  ui.message = dlg:add_label(#app.files == 0 and lang.msg_no_files or "",
                             1, row + 1, 5, 1)
  dlg:show()
end

function internetarchive_show_browser()
  close_dlg()
  dlg = vlc.dialog(lang.title_browser)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  ui.mode = dlg:add_dropdown(1, 1, 1, 1, internetarchive_filter_changed)
  for id, mode in ipairs(MODES) do ui.mode:add_value(lang[mode.label], id) end
  ui.mode:set_value(app.mode)
  ui.query = dlg:add_text_input(app.query, 2, 1, 2, 1, internetarchive_search)
  dlg:add_button(lang.btn_search, internetarchive_search, 4, 1, 1, 1)
  dlg:add_button(lang.btn_discover, internetarchive_discover, 5, 1, 1, 1)
  ui.sort = dlg:add_dropdown(1, 2, 1, 1, internetarchive_filter_changed)
  for id, sort in ipairs(SORTS) do ui.sort:add_value(lang[sort.label], id) end
  ui.sort:set_value(app.sort)
  dlg:add_button(lang.btn_previous, internetarchive_previous, 3, 2, 1, 1)
  dlg:add_button(lang.btn_next, internetarchive_next, 4, 2, 1, 1)
  ui.results = dlg:add_list(1, 3, 5, 1, internetarchive_open)
  ui.results:set_text(lang.col_title .. "\t" .. lang.col_creator .. "\t"
                    .. lang.col_date .. "\t" .. lang.col_downloads)
  dlg:add_button(lang.btn_open, internetarchive_open, 1, 4, 1, 1)
  dlg:add_button(lang.btn_play, internetarchive_play_selection, 2, 4, 1, 1)
  ui.message = dlg:add_label("", 1, 5, 5, 1)
  dlg:show()
  -- Returning from an item must restore the exact listing that led to it.
  -- app.query, app.page and app.total already describe that view; re-render
  -- the cached rows without issuing another network request.
  if #app.results > 0 then
    local cached_results = app.results
    fill_results(cached_results)
  end
end

function descriptor()
  return {
    title="Internet Archive", version="1.0", author="PowerVLC",
    url="https://archive.org/", shortdesc="Internet Archive",
    description="Discover, play and download movies and audio from Internet Archive.",
    capabilities={},
  }
end

function activate()
  load_lang()
  json = require("dkjson")
  download_module = require("pvlc_download")
  folder_picker_module = require("pvlc_folder_picker")
  load_settings()
  app.download_dir = app.download_dir or download_module.default_directory()
  downloader = download_module.new("internetarchive", {
    file=function(entry, index, total)
      set_message(string.format(lang.msg_downloading, index, total, entry.label))
    end,
    done=function(ok, value)
      if ui.download then ui.download:set_text(lang.btn_download) end
      if ok then
        set_message(string.format(lang.msg_downloaded, value[1].path))
      elseif value == "cancelled" then set_message(lang.msg_cancelled)
      else set_message(lang.msg_download_fail .. tostring(value)) end
    end,
  })
  folder_picker = folder_picker_module.new("internetarchive", {
    done=function(path, err)
      if path then
        app.download_dir = path
        if ui.download_dir then ui.download_dir:set_text(path) end
        save_settings(); set_message(string.format(lang.msg_folder_selected, path))
      elseif err == "cancelled" then set_message(lang.msg_folder_cancelled)
      else set_message(lang.msg_folder_unavailable) end
    end,
  })
  internetarchive_show_browser()
  internetarchive_discover()
end

function deactivate()
  if downloader and downloader:busy() then downloader:cancel() end
  if folder_picker then folder_picker:close() end
  close_dlg()
end
function close() vlc.deactivate() end
function meta_changed() end

if POWERVLC_INTERNETARCHIVE_TEST then
  internetarchive_test = {
    search_query=search_query, collect_files=collect_files,
    encode_path=encode_path,
  }
end
