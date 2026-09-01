--[[
 soulseek.lua : lightweight, download-only Soulseek client for PowerVLC

 Implements the documented Soulseek protocol directly over vlc.net.  It does
 not expose chat and never advertises or uploads local files.  Search replies,
 user profiles and share lists are accepted through the listening socket.
 File bytes are either written incrementally or relayed through a bounded
 loopback TCP buffer so VLC can start decoding before the download completes.

 Protocol reference: https://nicotine-plus.org/doc/SLSKPROTOCOL.html

 Copyright (C) 2026 the PowerVLC team
 License: GPL-2.0-or-later
--]]

local lang = {}
local json = nil

local SERVER_HOST = "server.slsknet.org"
local SERVER_PORT = 2242
-- Jaguar's resolver occasionally rejects the CNAME-backed service although
-- the same host is reachable over IPv4.  Keep the current service address as
-- a last-resort fallback; the hostname remains authoritative and is tried
-- first on every connection.
local SERVER_IPV4_FALLBACK = "208.76.170.59"
local DEFAULT_LISTEN_PORT = 2234
local CLIENT_MAJOR = 177       -- protocol-reserved experimental range
local CLIENT_MINOR = 77        -- PowerVLC project identifier within that range

local TICK_IDLE = 400
local TICK_SEARCH = 80
local TICK_TRANSFER = 25
local SEARCH_SECONDS = 12
local MAX_FRAME = 16 * 1024 * 1024
local MAX_SEARCH_COMPRESSED = 2 * 1024 * 1024
local MAX_SHARES_COMPRESSED = 8 * 1024 * 1024
local MAX_SEARCH_FILES = 3000
local MAX_SEARCH_USERS = 300
local MAX_FOLDER_COMPRESSED = 2 * 1024 * 1024
local MAX_FOLDER_FILES = 4000
local MAX_FOLDER_DIRS = 2000
local MAX_SHARE_FILES = 15000
local MAX_SHARE_DIRS = 8000
local INFLATE_SEARCH_MAX = 16 * 1024 * 1024
local INFLATE_FOLDER_MAX = 16 * 1024 * 1024
local INFLATE_SHARES_MAX = 32 * 1024 * 1024
local COPY_CHUNK = 32768
local COPY_BURST = 4
local STREAM_INITIAL_BUFFER = 1024 * 1024
local PEER_CONNECT_TIMEOUT = 600
local STREAM_PORT_FIRST = 62770
local STREAM_PORT_LAST = 62829
-- Keep the final value clear of native scrollbars in older dialog providers.
-- Trailing spaces are invisible, but are included in the column measurement.
local LIST_TRAILING_PAD = "      "
local MAX_INDIRECT_QUEUE = 16

local dlg = nil
local ui = {}
local folder_picker = nil

local app = {
  username = nil,
  password = nil,
  listen_port = DEFAULT_LISTEN_PORT,
  upnp_enabled = true,
  upnp_mapping = nil,
  download_dir = nil,
  cache_dir = nil,
  stream_caches = {},
  last_cache_cleanup = 0,
  remember = false,
  server = nil,
  listener = nil,
  connections = {},
  peers = {},
  pending_users = {},
  pending_tokens = {},
  indirect_queue = {},
  indirect_seen = {},
  token = 1000,
  connected = false,
  stopping = false,
  last_ping = 0,

  search_token = nil,
  search_deadline = nil,
  search_query = "",
  results = {},
  result_order = {},
  result_files = 0,

  users = {},
  view = "search",
  view_user = nil,
  view_path = "",
  view_root = "",
  view_limited = false,
  user_filter = "",
  active_user_list = "folder",
  match_rows = {},
  matches_rendered_version = nil,
  rows = {},
  transfer_rows = {},
  transfer_history = {},
  transfers_return = nil,
  transfer = nil,
  transfer_queue = {},
  folder_batch = nil,
  folder_request = nil,
}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("soulseek") })
end

function descriptor()
  return {
    title = "Soulseek",
    version = "1.0",
    author = "PowerVLC",
    url = "https://nicotine-plus.org/doc/SLSKPROTOCOL.html",
    shortdesc = "Soulseek",
    description = "Search Soulseek, inspect users and their shared files, "
               .. "then download or stream them directly. Download-only: "
               .. "no chat and no uploads.",
    capabilities = {}
  }
end

local function trim(value)
  return (string.gsub(value or "", "^%s*(.-)%s*$", "%1"))
end

local rendered_message = nil

local function set_message(text)
  text = text or ""
  if ui.message and text ~= rendered_message then
    ui.message:set_text(text)
    rendered_message = text
  end
end

local function close_dialog()
  if dlg then
    dlg:delete()
    dlg = nil
  end
  ui = {}
  rendered_message = nil
end

local function close_fd(fd)
  if fd and fd >= 0 then pcall(vlc.net.close, fd) end
end

local function p8(n)
  return string.char(n % 256)
end

local function p16(n)
  n = math.floor(n or 0)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function p32(n)
  n = math.floor(n or 0)
  return string.char(n % 256, math.floor(n / 256) % 256,
                     math.floor(n / 65536) % 256,
                     math.floor(n / 16777216) % 256)
end

local function p64(n)
  n = math.floor(n or 0)
  local low = n % 4294967296
  local high = math.floor(n / 4294967296)
  return p32(low) .. p32(high)
end

local function pstr(value)
  value = tostring(value or "")
  return p32(#value) .. value
end

local function reader(data)
  return { data = data or "", pos = 1, len = #(data or ""), bad = false }
end

local function remaining(r)
  return r.len - r.pos + 1
end

local function take(r, amount)
  if amount < 0 or amount > remaining(r) then
    r.bad = true
    return nil
  end
  local value = string.sub(r.data, r.pos, r.pos + amount - 1)
  r.pos = r.pos + amount
  return value
end

local function u8(r)
  local a = string.byte(r.data, r.pos)
  if not a then r.bad = true return nil end
  r.pos = r.pos + 1
  return a
end

local function u16(r)
  local a, b = string.byte(r.data, r.pos, r.pos + 1)
  if not b then r.bad = true return nil end
  r.pos = r.pos + 2
  return a + b * 256
end

local function u32(r)
  local a, b, c, d = string.byte(r.data, r.pos, r.pos + 3)
  if not d then r.bad = true return nil end
  r.pos = r.pos + 4
  return a + b * 256 + c * 65536 + d * 16777216
end

local function u64(r)
  local low = u32(r)
  local high = u32(r)
  if not high then return nil end
  return low + high * 4294967296
end

local function ustr(r, max_len)
  local amount = u32(r)
  if not amount then return nil end
  if amount > (max_len or MAX_FRAME) then
    r.bad = true
    return nil
  end
  return take(r, amount)
end

local function ip_from_reader(r)
  local a, b, c, d = string.byte(r.data, r.pos, r.pos + 3)
  if not d then r.bad = true return nil end
  r.pos = r.pos + 4
  return string.format("%d.%d.%d.%d", d, c, b, a)
end

local function server_frame(code, payload)
  payload = payload or ""
  return p32(#payload + 4) .. p32(code) .. payload
end

local function peer_frame(code, payload)
  payload = payload or ""
  return p32(#payload + 4) .. p32(code) .. payload
end

local function init_frame(code, payload)
  payload = payload or ""
  return p32(#payload + 1) .. p8(code) .. payload
end

local function send_all(fd, data)
  local pos = 1
  while pos <= #data do
    local sent = vlc.net.send(fd, string.sub(data, pos))
    if not sent or sent <= 0 then return false end
    pos = pos + sent
  end
  return true
end

local function next_token()
  app.token = app.token + 1
  if app.token >= 4294967000 then app.token = 1000 end
  return app.token
end

local function format_size(value)
  value = tonumber(value) or 0
  if value >= 1073741824 then return string.format("%.2f GiB", value / 1073741824) end
  if value >= 1048576 then return string.format("%.1f MiB", value / 1048576) end
  if value >= 1024 then return string.format("%.0f KiB", value / 1024) end
  return string.format("%d B", value)
end

local function sortable_number(label, value)
  return (label or "") .. string.char(31)
       .. string.format("%.0f", tonumber(value) or 0)
end

local function sortable_size(value)
  return sortable_number(format_size(value), value)
end

local function sortable_speed(value)
  return sortable_number(format_size(value) .. "/s", value)
end

local function format_duration(seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds <= 0 then return "" end
  seconds = math.floor(seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function basename(path)
  path = string.gsub(path or "", "/", "\\")
  return string.match(path, "([^\\]+)$") or path
end

local function dirname(path)
  path = string.gsub(path or "", "/", "\\")
  return string.match(path, "^(.*)\\[^\\]*$") or ""
end

local function html_escape(value)
  value = value or ""
  value = string.gsub(value, "&", "&amp;")
  value = string.gsub(value, "<", "&lt;")
  value = string.gsub(value, ">", "&gt;")
  value = string.gsub(value, '"', "&quot;")
  return string.gsub(value, "'", "&#39;")
end

local function profile_html(description)
  description = trim(description)
  if description == "" then description = "—" end
  description = string.gsub(description, "\r\n?", "\n")
  description = string.gsub(html_escape(description), "\n", "<br>")
  return '<div style="margin:0; padding:4px; overflow-wrap:anywhere">'
      .. description .. "</div>"
end

local function quality_text(file)
  local bits = {}
  if file.bitrate then bits[#bits + 1] = tostring(file.bitrate) .. " kb/s" end
  if file.sample_rate then bits[#bits + 1] = tostring(file.sample_rate) .. " Hz" end
  if file.bit_depth then bits[#bits + 1] = tostring(file.bit_depth) .. " bit" end
  return table.concat(bits, " · ")
end

local function quality_sort_value(file)
  if not file then return 0 end
  if file.sample_rate and file.bit_depth then
    -- Channel count is not part of Soulseek's file attributes. Their product
    -- is still a useful ordering proxy for lossless PCM quality and keeps it
    -- above ordinary lossy bitrates.
    return file.sample_rate * file.bit_depth
  end
  if file.bitrate then return file.bitrate * 1000 end
  if file.sample_rate then return file.sample_rate end
  return tonumber(file.bit_depth) or 0
end

local function sortable_quality(file)
  return sortable_number(quality_text(file), quality_sort_value(file))
end

local function parse_file(r, full_path)
  if u8(r) == nil then return nil end
  local path = ustr(r, 8192)
  local size = u64(r)
  local extension = ustr(r, 64)
  local count = u32(r)
  if not path or not size or not extension or not count or count > 32 then
    r.bad = true
    return nil
  end
  local file = { path = path, name = basename(path), size = size,
                 extension = extension }
  for _ = 1, count do
    local code, value = u32(r), u32(r)
    if not value then return nil end
    if code == 0 then file.bitrate = value
    elseif code == 1 then file.duration = value
    elseif code == 2 then file.vbr = value ~= 0
    elseif code == 4 then file.sample_rate = value
    elseif code == 5 then file.bit_depth = value end
  end
  if not full_path then file.name = path end
  return file
end

local function inflate(data, limit)
  if not vlc.strings or not vlc.strings.inflate then
    return nil, lang.needs_zlib
  end
  local ok, body, err = pcall(vlc.strings.inflate, data, limit)
  if not ok then return nil, body end
  return body, err
end

local function parse_search_response(compressed, expected_token)
  local body, err = inflate(compressed, INFLATE_SEARCH_MAX)
  if not body then return nil, err end
  local r = reader(body)
  local username = ustr(r, 64)
  local token = u32(r)
  local count = u32(r)
  if not username or not token or not count or count > 10000 then
    return nil, "invalid search response"
  end
  if token ~= expected_token then return false end
  local files = {}
  for _ = 1, count do
    local file = parse_file(r, true)
    if not file then return nil, "invalid file result" end
    if #files < MAX_SEARCH_FILES then files[#files + 1] = file end
  end
  local slots = u8(r)
  local speed = u32(r)
  local queue = u32(r)
  if slots == nil or not speed or not queue then
    return nil, "truncated search response"
  end
  if remaining(r) >= 4 then u32(r) end -- official clients send zero
  -- Private search matches follow the public results. Parse and discard them
  -- so the frame stays validated, but never expose files that cannot be
  -- downloaded without negotiating access through chat.
  if remaining(r) >= 4 then
    local private_count = u32(r)
    if not private_count or private_count > 10000 then
      return nil, "invalid private search results"
    end
    for _ = 1, private_count do
      if not parse_file(r, true) then
        return nil, "invalid private search result"
      end
    end
  end
  return { username = username, files = files, slots = slots ~= 0,
           speed = speed, queue = queue }
end

local function parse_share_dirs(r, result, counters, is_private)
  local dir_count = u32(r)
  if not dir_count or dir_count > 100000 then return false end
  for _ = 1, dir_count do
    local path = ustr(r, 8192)
    local file_count = u32(r)
    if not path or not file_count or file_count > 100000 then return false end
    if is_private then counters.private_dirs = counters.private_dirs + 1
    else counters.dirs = counters.dirs + 1 end
    local entry = nil
    if not is_private and counters.dirs <= MAX_SHARE_DIRS then
      entry = { path = string.gsub(path, "/", "\\"), files = {} }
      result[#result + 1] = entry
    end
    for _ = 1, file_count do
      local file = parse_file(r, false)
      if not file then return false end
      if is_private then counters.private_files = counters.private_files + 1
      else counters.files = counters.files + 1 end
      if not is_private and entry and counters.files <= MAX_SHARE_FILES then
        file.path = entry.path .. "\\" .. file.name
        entry.files[#entry.files + 1] = file
      end
    end
  end
  return true
end

local function parse_share_response(compressed)
  local body, err = inflate(compressed, INFLATE_SHARES_MAX)
  if not body then return nil, err end
  local r, dirs = reader(body), {}
  local counters = { dirs = 0, files = 0, private_dirs = 0, private_files = 0 }
  if not parse_share_dirs(r, dirs, counters, false) then
    return nil, "invalid share list"
  end
  if remaining(r) >= 4 then u32(r) end
  if remaining(r) >= 4 and not parse_share_dirs(r, dirs, counters, true) then
    return nil, "invalid private share list"
  end
  counters.truncated = counters.files > MAX_SHARE_FILES
                    or counters.dirs > MAX_SHARE_DIRS
  return dirs, counters
end

local function parse_folder_response(compressed, expected_token, expected_folder)
  local body, err = inflate(compressed, INFLATE_FOLDER_MAX)
  if not body then return nil, err end
  local r = reader(body)
  local token = u32(r)
  local folder = ustr(r, 8192)
  local dir_count = u32(r)
  if not token or not folder or not dir_count or dir_count > 100000 then
    return nil, "invalid folder response"
  end
  folder = string.gsub(folder, "/", "\\")
  expected_folder = string.gsub(expected_folder or "", "/", "\\")
  if token ~= expected_token or folder ~= expected_folder then return false end

  local dirs = {}
  local counters = { dirs = 0, files = 0 }
  for _ = 1, dir_count do
    local path = ustr(r, 8192)
    local file_count = u32(r)
    if not path or not file_count or file_count > 100000 then
      return nil, "invalid folder response"
    end
    path = string.gsub(path, "/", "\\")
    if path == "" or path == "." then
      path = folder
    elseif path ~= folder
       and string.sub(path, 1, #folder + 1) ~= folder .. "\\" then
      -- FolderContentsResponse describes the requested tree, but peers are
      -- allowed to encode its children relative to the requested directory.
      -- Keeping "CD1" as a top-level share made it invisible while browsing
      -- "Album", and excluded it from recursive folder downloads.
      path = string.gsub(path, "^%.?\\+", "")
      path = folder == "" and path or folder .. "\\" .. path
    end
    counters.dirs = counters.dirs + 1
    local entry = nil
    if counters.dirs <= MAX_FOLDER_DIRS then
      entry = { path = path, files = {} }
      dirs[#dirs + 1] = entry
    end
    for _ = 1, file_count do
      local file = parse_file(r, false)
      if not file then return nil, "invalid folder response" end
      counters.files = counters.files + 1
      if entry and counters.files <= MAX_FOLDER_FILES then
        file.path = entry.path .. "\\" .. file.name
        entry.files[#entry.files + 1] = file
      end
    end
  end
  counters.truncated = counters.files > MAX_FOLDER_FILES
                    or counters.dirs > MAX_FOLDER_DIRS
  return dirs, counters
end

-- FolderContentsResponse and GetSharedFileList are complementary in
-- practice: some peers omit the files in the requested root from the full
-- share list, while others return only one level from FolderContents. Merge
-- every reply by path instead of letting whichever packet arrived last hide
-- data supplied by the other one.
local function merge_share_sources(...)
  local merged, by_path = {}, {}
  for source_index = 1, select("#", ...) do
    local source = select(source_index, ...)
    for _, dir in ipairs(source or {}) do
      local entry = by_path[dir.path]
      if not entry then
        entry = { path = dir.path, files = {}, private = dir.private }
        by_path[dir.path] = entry
        merged[#merged + 1] = entry
      end
      local seen = {}
      for _, file in ipairs(entry.files) do seen[file.path or file.name] = true end
      for _, file in ipairs(dir.files or {}) do
        local key = file.path or file.name
        if not seen[key] then
          entry.files[#entry.files + 1] = file
          seen[key] = true
        end
      end
    end
  end
  return merged
end

local function combined_user_shares(user)
  local sources = {}
  if user.shares then sources[#sources + 1] = user.shares end
  for _, dirs in pairs(user.folder_cache or {}) do
    sources[#sources + 1] = dirs
  end
  if #sources == 0 then return nil end
  return merge_share_sources(unpack(sources))
end

local function parse_user_info(payload)
  local r = reader(payload)
  local info = { description = ustr(r, 1024 * 1024) }
  local has_picture = u8(r)
  if not info.description or has_picture == nil then return nil end
  if has_picture ~= 0 then
    local amount = u32(r)
    if not amount or amount > 8 * 1024 * 1024 or not take(r, amount) then return nil end
    info.has_picture = true
  end
  info.uploads = u32(r)
  info.queue = u32(r)
  local slots = u8(r)
  if not info.uploads or not info.queue or slots == nil then return nil end
  info.slots = slots ~= 0
  if remaining(r) >= 4 then info.upload_allowed = u32(r) end
  return info
end

local function settings_path()
  local dir = vlc.config.userdatadir()
  if not dir or dir == "" then return nil end
  return dir .. "/soulseek.json"
end

local function keystore_service()
  return "soulseek-powervlc://" .. SERVER_HOST
end

local function have_keystore()
  return vlc.keystore and vlc.keystore.find and vlc.keystore.store
end

local function xml_unescape(value)
  if not value then return nil end
  value = string.gsub(value, "&amp;", "&")
  value = string.gsub(value, "&lt;", "<")
  value = string.gsub(value, "&gt;", ">")
  value = string.gsub(value, "&quot;", "\"")
  value = string.gsub(value, "&apos;", "'")
  return trim(value)
end

local function xml_text(block, name)
  return xml_unescape(string.match(block or "", "<" .. name ..
    "[^>]*>%s*(.-)%s*</" .. name .. ">"))
end

local function resolve_control_url(location, url_base, control)
  if string.match(control or "", "^https?://") then return control end
  local origin = string.match(location or "", "^(https?://[^/]+)")
  if not origin then return nil end
  if string.sub(control or "", 1, 1) == "/" then return origin .. control end
  local base = url_base and trim(url_base) or location
  if base == origin then base = base .. "/"
  elseif string.sub(base, -1) ~= "/" then
    base = string.match(base, "^(.*)/[^/]*$") or (base .. "/")
    if string.sub(base, -1) ~= "/" then base = base .. "/" end
  end
  return base .. (control or "")
end

local function soap_request(mapping, action, arguments)
  local fields = {}
  for _, item in ipairs(arguments or {}) do
    fields[#fields + 1] = "<" .. item[1] .. ">" .. tostring(item[2] or "")
                       .. "</" .. item[1] .. ">"
  end
  local body = '<?xml version="1.0"?>'
    .. '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    .. 's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    .. '<s:Body><u:' .. action .. ' xmlns:u="' .. mapping.service .. '">'
    .. table.concat(fields) .. '</u:' .. action .. '></s:Body></s:Envelope>'
  local ok, status, response = pcall(vlc.http.post, mapping.control, body,
    'text/xml; charset="utf-8"', nil,
    { SOAPAction = '"' .. mapping.service .. '#' .. action .. '"' })
  if not ok then return false, tostring(status) end
  if status == 200 then return true end
  local detail = xml_text(response, "errorDescription")
              or xml_text(response, "errorCode") or tostring(status)
  return false, detail
end

local function open_upnp_mapping(port)
  if not vlc.net.upnp_discover or not vlc.http or
     not vlc.http.get or not vlc.http.post then
    return nil, lang.upnp_unavailable
  end
  local ok, location, local_ip = pcall(vlc.net.upnp_discover, 1600)
  if not ok or not location then
    return nil, ok and (local_ip or lang.upnp_unavailable) or tostring(location)
  end
  local got, status, description = pcall(vlc.http.get, location)
  if not got or status ~= 200 or type(description) ~= "string" then
    return nil, lang.upnp_description_failed
  end
  local service, control
  for block in string.gmatch(description, "<service[^>]*>(.-)</service>") do
    local candidate = xml_text(block, "serviceType")
    if candidate and (string.find(candidate, ":WANIPConnection:", 1, true)
                   or string.find(candidate, ":WANPPPConnection:", 1, true)) then
      service, control = candidate, xml_text(block, "controlURL")
      break
    end
  end
  if not service or not control then return nil, lang.upnp_service_missing end
  local mapping = {
    port = port, service = service, local_ip = local_ip,
    control = resolve_control_url(location, xml_text(description, "URLBase"), control)
  }
  if not mapping.control then return nil, lang.upnp_service_missing end
  local added, err = soap_request(mapping, "AddPortMapping", {
    { "NewRemoteHost", "" }, { "NewExternalPort", port },
    { "NewProtocol", "TCP" }, { "NewInternalPort", port },
    { "NewInternalClient", local_ip }, { "NewEnabled", 1 },
    { "NewPortMappingDescription", "PowerVLC Soulseek" },
    { "NewLeaseDuration", 0 },
  })
  if not added then return nil, err end
  return mapping
end

local function close_upnp_mapping()
  local mapping = app.upnp_mapping
  app.upnp_mapping = nil
  if not mapping then return end
  pcall(soap_request, mapping, "DeletePortMapping", {
    { "NewRemoteHost", "" }, { "NewExternalPort", mapping.port },
    { "NewProtocol", "TCP" },
  })
end

local function load_settings()
  local path = settings_path()
  if not path then return end
  local file = io.open(path, "r")
  if not file then return end
  local obj = json.decode(file:read("*a") or "")
  file:close()
  if type(obj) ~= "table" then return end
  if type(obj.username) == "string" then app.username = obj.username end
  if type(obj.listen_port) == "number" and obj.listen_port > 0
     and obj.listen_port < 65536 then
    app.listen_port = math.floor(obj.listen_port)
  end
  if type(obj.upnp_enabled) == "boolean" then app.upnp_enabled = obj.upnp_enabled end
  if type(obj.download_dir) == "string" and trim(obj.download_dir) ~= "" then
    app.download_dir = trim(obj.download_dir)
  end
  app.remember = obj.remember and true or false
  if app.remember then
    local stored_password
    if have_keystore() then
      stored_password = vlc.keystore.find(keystore_service(),
                                          app.username or "user")
    end
    if type(stored_password) == "string" and stored_password ~= "" then
      app.password = stored_password
    elseif type(obj.password) == "string" then
      -- The Lua keystore API can exist even when XP has no usable keystore
      -- backend. save_settings() then deliberately falls back to the JSON
      -- value; load that fallback instead of treating the mere presence of
      -- the API as proof that the secret was stored there.
      app.password = obj.password
      app.secret_plain = true
    end
  end
end

local function save_settings()
  local path = settings_path()
  if not path then return end
  if not app.remember then
    if have_keystore() then
      vlc.keystore.remove(keystore_service(), app.username or "user")
    end
    local file = io.open(path, "w")
    if file then file:write(json.encode({ listen_port = app.listen_port,
                                         upnp_enabled = app.upnp_enabled,
                                         download_dir = app.download_dir })); file:close() end
    return
  end

  local stored = false
  if have_keystore() then
    stored = vlc.keystore.store(keystore_service(), app.username or "user",
                                app.password or "", "PowerVLC — Soulseek")
    if stored then
      stored = vlc.keystore.find(keystore_service(), app.username or "user")
               == app.password
    end
  end
  app.secret_plain = not stored
  local file = io.open(path, "w")
  if file then
    file:write(json.encode({ username = app.username,
                            password = stored and nil or app.password,
                            listen_port = app.listen_port,
                            upnp_enabled = app.upnp_enabled,
                            download_dir = app.download_dir,
                            remember = true }, { indent = true }))
    file:close()
  end
end

local function close_connection(conn)
  if not conn then return end
  local fd = conn.fd
  if app.peers[conn.user] == conn then app.peers[conn.user] = nil end
  app.connections[fd] = nil
  close_fd(fd)
  conn.fd = nil
end

local arm_tick
local remove_playlist_path

local function discard_transfer_requests(transfer)
  if not transfer then return end
  local pending = app.pending_users[transfer.user]
  if pending then
    local payload = pstr(transfer.path)
    for index = #pending.messages, 1, -1 do
      local message = pending.messages[index]
      if (message.code == 43 or message.code == 51)
         and message.payload == payload then
        table.remove(pending.messages, index)
      end
    end
    if #pending.messages == 0 then
      app.pending_users[transfer.user] = nil
      app.pending_tokens[pending.token] = nil
    end
  end
  for index = #app.indirect_queue, 1, -1 do
    local item = app.indirect_queue[index]
    if item.user == transfer.user and item.type == "F" then
      app.indirect_seen[item.key] = nil
      table.remove(app.indirect_queue, index)
    end
  end
end

local function cancel_transfer(silent)
  local transfer = app.transfer
  if not transfer then return end
  discard_transfer_requests(transfer)
  if transfer.mode == "stream" and transfer.playlist_added
     and remove_playlist_path then
    remove_playlist_path(transfer.proxy_uri)
  end
  local remove_partial = transfer.file ~= nil
  if transfer.source_fd then close_fd(transfer.source_fd) end
  if transfer.proxy_fd then close_fd(transfer.proxy_fd) end
  if transfer.file then pcall(function() transfer.file:close() end) end
  if transfer.proxy_listener then pcall(function() transfer.proxy_listener:close() end) end
  if transfer.serve_file then pcall(function() transfer.serve_file:close() end) end
  if transfer.destination and (remove_partial or (transfer.got and transfer.got > 0)) then
    if vlc.io and vlc.io.unlink then pcall(vlc.io.unlink, transfer.destination)
    else pcall(os.remove, transfer.destination) end
  end
  transfer.source_fd, transfer.proxy_fd, transfer.file = nil, nil, nil
  transfer.serve_file = nil
  transfer.proxy_listener = nil
  app.transfer = nil
  if not silent then set_message(lang.transfer_cancelled) end
  return transfer
end

local function disconnect()
  if vlc.timer then pcall(vlc.timer, 0) end
  close_upnp_mapping()
  cancel_transfer(true)
  app.transfer_queue = {}
  app.folder_batch = nil
  app.folder_request = nil
  for _, conn in pairs(app.connections) do close_fd(conn.fd) end
  app.connections = {}
  app.peers = {}
  app.pending_users = {}
  app.pending_tokens = {}
  app.indirect_queue = {}
  app.indirect_seen = {}
  if app.server then close_fd(app.server.fd) end
  if app.listener then pcall(function() app.listener:close() end) end
  app.server = nil
  app.listener = nil
  app.connected = false
  if not app.stopping and next(app.stream_caches) then arm_tick() end
end

local function read_login_reply(fd)
  local buffer = ""
  local deadline = os.time() + 20
  while os.time() <= deadline do
    local pollfds = { [fd] = vlc.net.POLLIN }
    local ok, ready = pcall(vlc.net.poll, pollfds, 1000)
    if not ok then return nil, ready end
    if ready > 0 then
      local chunk = vlc.net.recv(fd, 65536)
      if not chunk then return nil, "connection closed" end
      buffer = buffer .. chunk
      if #buffer >= 8 then
        local r = reader(buffer)
        local length, code = u32(r), u32(r)
        if length and length > MAX_FRAME then return nil, "oversized server message" end
        if length and #buffer >= length + 4 then
          local payload = string.sub(buffer, 9, length + 4)
          if code == 1 then
            return payload, nil, string.sub(buffer, length + 5)
          end
          buffer = string.sub(buffer, length + 5)
        end
      end
    end
    if vlc.keep_alive then pcall(vlc.keep_alive) end
  end
  return nil, "timeout"
end

local function parse_login(payload)
  local r = reader(payload)
  local success = u8(r)
  if success == nil then return nil, "invalid reply" end
  if success == 0 then
    local reason = ustr(r, 256) or "rejected"
    local detail = remaining(r) >= 4 and ustr(r, 1024) or nil
    return nil, detail and (reason .. " — " .. detail) or reason
  end
  local banner = ustr(r, 1024 * 1024)
  local own_ip = ip_from_reader(r)
  local hash = ustr(r, 64)
  local supporter = u8(r)
  if not banner or not own_ip or not hash or supporter == nil then
    return nil, "invalid reply"
  end
  return { banner = banner, ip = own_ip, supporter = supporter ~= 0 }
end

local function listen_on_requested_port(requested)
  for port = requested, math.min(requested + 9, 65535) do
    local ok, listener = pcall(vlc.net.listen_tcp, "0.0.0.0", port)
    if ok and listener then return listener, port end
  end
  return nil, requested
end

local function server_send(code, payload)
  return app.server and send_all(app.server.fd, server_frame(code, payload))
end

arm_tick = function()
  if not vlc.timer or app.stopping then return end
  if folder_picker and folder_picker:busy() then
    vlc.timer(100, "soulseek_tick")
    return
  end
  if not app.connected and not next(app.stream_caches) then return end
  local delay = TICK_IDLE
  if app.transfer then delay = TICK_TRANSFER
  elseif app.search_deadline then delay = TICK_SEARCH
  elseif next(app.stream_caches) then
    for _, cache in pairs(app.stream_caches) do
      if cache.proxy_fd then delay = TICK_TRANSFER; break end
    end
  end
  vlc.timer(delay, "soulseek_tick")
end

local function peer_send(conn, code, payload)
  if not conn or not conn.fd then return false end
  local ok = send_all(conn.fd, peer_frame(code, payload))
  if ok then conn.last_activity = os.time() end
  return ok
end

local function send_pending(conn)
  local pending = app.pending_users[conn.user]
  if not pending then return end
  app.pending_users[conn.user] = nil
  for _, message in ipairs(pending.messages) do
    if not peer_send(conn, message.code, message.payload) then
      close_connection(conn)
      return
    end
  end
end

local function attach_peer(fd, user, conn_type, buffer)
  local conn = { fd = fd, user = user, type = conn_type,
                 kind = conn_type == "F" and "file" or "peer",
                 buffer = buffer or "", last_activity = os.time() }
  app.connections[fd] = conn
  if conn_type == "P" then
    local old = app.peers[user]
    if old and old.fd ~= fd then close_connection(old) end
    app.peers[user] = conn
    send_pending(conn)
  end
  return conn
end

local function connect_direct(user, address, port, conn_type)
  if not address or address == "0.0.0.0" or not port or port <= 0 then
    return nil
  end
  local ok, fd = pcall(vlc.net.connect_tcp, address, port, PEER_CONNECT_TIMEOUT)
  if not ok or not fd or fd < 0 then return nil end
  local payload = pstr(app.username) .. pstr(conn_type) .. p32(0)
  if not send_all(fd, init_frame(1, payload)) then close_fd(fd); return nil end
  return attach_peer(fd, user, conn_type)
end

local function request_peer(user, code, payload)
  local existing = app.peers[user]
  if existing and existing.fd then return peer_send(existing, code, payload) end

  local pending = app.pending_users[user]
  if not pending then
    local token = next_token()
    pending = { user = user, token = token, messages = {}, type = "P",
                started = os.time() }
    app.pending_users[user] = pending
    app.pending_tokens[token] = pending
    server_send(18, p32(token) .. pstr(user) .. pstr("P"))
    server_send(3, pstr(user))
  end
  pending.messages[#pending.messages + 1] = { code = code, payload = payload or "" }
  return true
end

local function parse_init(conn)
  if #conn.buffer < 5 then return false end
  local r = reader(conn.buffer)
  local length = u32(r)
  if not length or length < 1 or length > 16384 then close_connection(conn); return false end
  if #conn.buffer < length + 4 then return false end
  local code = u8(r)
  local payload = take(r, length - 1)
  conn.buffer = string.sub(conn.buffer, length + 5)
  if code == 0 then
    local pr = reader(payload)
    local token = u32(pr)
    local pending = token and app.pending_tokens[token]
    if not pending then close_connection(conn); return false end
    app.pending_tokens[token] = nil
    app.connections[conn.fd] = nil
    attach_peer(conn.fd, pending.user, pending.type, conn.buffer)
    return true
  elseif code == 1 then
    local pr = reader(payload)
    local user = ustr(pr, 64)
    local conn_type = ustr(pr, 4)
    u32(pr) -- obsolete token
    if not user or (conn_type ~= "P" and conn_type ~= "F") then
      close_connection(conn)
      return false
    end
    app.connections[conn.fd] = nil
    attach_peer(conn.fd, user, conn_type, conn.buffer)
    return true
  end
  close_connection(conn)
  return false
end

local function user_state(name)
  local user = app.users[name]
  if not user then
    user = { username = name, shares = nil, shares_loading = false,
             folder_cache = {},
             info_loading = false, search_version = 0 }
    app.users[name] = user
  end
  return user
end

local function update_visible_user(user)
  if app.view == "user" and app.view_user == user.username
     and refresh_user_view then
    refresh_user_view()
  elseif app.view == "profile" and app.view_user == user.username
     and refresh_profile_view then
    refresh_profile_view()
  end
end

local function queue_indirect(user, conn_type, address, port, token)
  if #app.indirect_queue >= MAX_INDIRECT_QUEUE then return end
  local key = tostring(token) .. "@" .. address .. ":" .. tostring(port)
  if app.indirect_seen[key] then return end
  app.indirect_seen[key] = true
  app.indirect_queue[#app.indirect_queue + 1] = {
    user = user, type = conn_type, address = address, port = port,
    token = token, key = key, queued = os.time()
  }
end

local function handle_server_message(code, payload)
  local r = reader(payload)
  if code == 3 then
    local user = ustr(r, 64)
    local address = ip_from_reader(r)
    local port = u32(r)
    u32(r); u16(r) -- optional obfuscation fields are deliberately unused
    local pending = user and app.pending_users[user]
    if pending then
      if address == "0.0.0.0" or not port or port <= 0 then
        app.pending_tokens[pending.token] = nil
        app.pending_users[user] = nil
        local state = user_state(user)
        state.info_loading, state.shares_loading = false, false
        state.shares_error = string.format(lang.user_unreachable, user)
        update_visible_user(state)
      else
        local conn = connect_direct(user, address, port, pending.type)
        if conn then app.pending_tokens[pending.token] = nil end
      end
    end

  elseif code == 5 then
    local name = ustr(r, 64)
    local exists = u8(r)
    if name and exists ~= nil then
      local user = user_state(name)
      user.exists = exists ~= 0
      if user.exists then
        user.status = u32(r)
        user.speed = u32(r)
        user.uploads = u32(r)
        u32(r)
        user.file_count = u32(r)
        user.dir_count = u32(r)
        if remaining(r) >= 4 then user.country = ustr(r, 16) end
      end
      update_visible_user(user)
    end

  elseif code == 18 then
    local user = ustr(r, 64)
    local conn_type = ustr(r, 4)
    local address = ip_from_reader(r)
    local port = u32(r)
    local token = u32(r)
    u8(r); u32(r); u32(r) -- privileged and obfuscation fields
    if user and token and (conn_type == "P" or conn_type == "F")
       and address and port and port > 0 then
      queue_indirect(user, conn_type, address, port, token)
    end

  elseif code == 22 then
    -- Chat is intentionally absent.  Acknowledge silently so the server does
    -- not keep redelivering private messages on every login.
    local message_id = u32(r)
    if message_id then server_send(23, p32(message_id)) end

  elseif code == 36 then
    local name = ustr(r, 64)
    if name then
      local user = user_state(name)
      user.speed = u32(r)
      user.uploads = u32(r)
      u32(r)
      user.file_count = u32(r)
      user.dir_count = u32(r)
      update_visible_user(user)
    end

  elseif code == 41 then
    set_message(lang.relogged)
    disconnect()
  end
end

local function process_one_indirect()
  while #app.indirect_queue > 0 do
    local item = table.remove(app.indirect_queue, 1)
    app.indirect_seen[item.key] = nil
    local transfer = app.transfer
    local relevant = false
    if item.type == "F" then
      relevant = transfer and transfer.user == item.user
    else
      relevant = app.search_deadline ~= nil
              or app.pending_users[item.user] ~= nil
              or ((app.view == "user" or app.view == "profile")
                  and app.view_user == item.user)
              or (transfer and transfer.user == item.user)
    end
    if relevant and os.time() - item.queued <= 15 then
      local ok, fd = pcall(vlc.net.connect_tcp, item.address, item.port,
                           PEER_CONNECT_TIMEOUT)
      if ok and fd and fd >= 0 then
        if send_all(fd, init_frame(0, p32(item.token))) then
          attach_peer(fd, item.user, item.type)
        else
          close_fd(fd)
        end
      end
      return
    end
  end
end

local function parse_server_frames()
  local server = app.server
  while server and #server.buffer >= 8 do
    local r = reader(server.buffer)
    local length, code = u32(r), u32(r)
    if not length or length < 4 or length > MAX_FRAME then
      set_message(lang.disconnected)
      disconnect()
      return
    end
    if #server.buffer < length + 4 then return end
    local payload = string.sub(server.buffer, 9, length + 4)
    server.buffer = string.sub(server.buffer, length + 5)
    handle_server_message(code, payload)
    server = app.server
  end
end

local function add_search_result(result)
  -- Peers can answer with only locked/private matches.  Such an entry has no
  -- downloadable path and opening it would degrade into a costly root-folder
  -- request.  This client is download-only, so omit unusable empty results.
  if #result.files == 0 then return end
  local group = app.results[result.username]
  if not group then
    if #app.result_order >= MAX_SEARCH_USERS then return end
    group = { username = result.username, files = {}, seen = {},
              slots = result.slots, speed = result.speed, queue = result.queue }
    app.results[result.username] = group
    app.result_order[#app.result_order + 1] = result.username
  end
  group.slots, group.speed, group.queue = result.slots, result.speed, result.queue
  for _, file in ipairs(result.files) do
    if app.result_files >= MAX_SEARCH_FILES then break end
    if not group.seen[file.path] then
      group.seen[file.path] = true
      file.user = result.username
      group.files[#group.files + 1] = file
      app.result_files = app.result_files + 1
      local user = user_state(result.username)
      user.search_version = (user.search_version or 0) + 1
    end
  end
  local user = user_state(result.username)
  user.search_files = group.files
end

local function transfer_status()
  local transfer = app.transfer
  if not transfer then
    if app.view == "transfers" and refresh_transfers then refresh_transfers() end
    return
  end
  local suffix = ""
  if transfer.queue_place then
    suffix = string.format(lang.queue_place, transfer.queue_place)
  end
  if transfer.state == "queued" then
    set_message(string.format(lang.queued, transfer.user, suffix))
  elseif transfer.state == "ready" then
    set_message(lang.transfer_ready)
  elseif transfer.state == "streaming" or transfer.state == "downloading" then
    local status
    if transfer.state == "streaming" and not transfer.playlist_added then
      local size = tonumber(transfer.size) or 0
      local target = transfer.enqueue_only and size
                                            or math.min(size, STREAM_INITIAL_BUFFER)
      status = string.format(lang.stream_prebuffering, basename(transfer.path),
                             format_size(transfer.got), format_size(target))
    else
      local key = transfer.state == "streaming" and lang.streaming
                                                   or lang.downloading
      status = string.format(key, basename(transfer.path),
                             format_size(transfer.got), format_size(transfer.size))
    end
    if app.folder_batch and transfer.mode == "download" then
      status = string.format(lang.folder_progress, app.folder_batch.index,
                             app.folder_batch.total, status)
    end
    set_message(status)
  end
  if app.view == "transfers" and refresh_transfers then refresh_transfers() end
end

local finish_transfer, fail_transfer, start_next_queued_transfer

local function stream_start_ready(transfer)
  if not transfer or transfer.mode ~= "stream" then return false end
  local size, got = tonumber(transfer.size) or 0, tonumber(transfer.got) or 0
  -- Items explicitly added to the playback queue must be durable before VLC
  -- can reach them. Advertising a one-megabyte relay as a playlist item lets
  -- VLC loop a truncated file when the Soulseek peer disconnects afterwards.
  if transfer.enqueue_only then return size > 0 and got >= size end
  return size > 0 and got >= math.min(size, STREAM_INITIAL_BUFFER)
end

local function start_buffered_stream(transfer)
  if transfer.playlist_added or not stream_start_ready(transfer) then return false end
  transfer.playlist_added = true
  local item = {
    path = transfer.proxy_uri,
    name = transfer.title,
    title = transfer.title,
    artist = transfer.artist,
    album = transfer.album,
    duration = transfer.duration,
    meta = { ["Soulseek user"] = transfer.user,
             ["Soulseek path"] = transfer.path },
  }
  if transfer.enqueue_only and vlc.playlist.enqueue then
    vlc.playlist.enqueue({ item })
  else
    vlc.playlist.add({ item })
  end
  return true
end

local function handle_peer_message(conn, code, payload)
  if code == 9 then
    if #payload > MAX_SEARCH_COMPRESSED or not app.search_token then return true end
    local result = parse_search_response(payload, app.search_token)
    if result and result ~= false then
      add_search_result(result)
      if app.view == "search" and refresh_search_results then refresh_search_results() end
    end
    return true -- search connections are intentionally short-lived

  elseif code == 5 then
    local user = user_state(conn.user)
    user.shares_loading = false
    if #payload > MAX_SHARES_COMPRESSED then
      user.shares_error = lang.shares_too_large
      user.shares_warning = nil
    else
      local dirs, counters = parse_share_response(payload)
      if dirs then
        user.shares = dirs
        user.share_counts = counters
        user.shares_error = nil
        user.shares_warning = counters.truncated and lang.shares_truncated or nil
      else
        user.shares_error = lang.shares_too_large
        user.shares_warning = nil
      end
    end
    local pending = app.folder_request
    if pending and pending.user == user.username and not user.shares_loading then
      app.folder_request = nil
      local shares = combined_user_shares(user)
      if shares then
        begin_folder_download(user.username, pending.path, shares)
      else
        set_message(user.shares_error or user.folder_error
                    or lang.folder_too_large)
      end
    end
    update_visible_user(user)

  elseif code == 16 then
    local user = user_state(conn.user)
    user.info_loading = false
    user.info = parse_user_info(payload)
    update_visible_user(user)

  elseif code == 37 then
    local user = user_state(conn.user)
    if #payload > MAX_FOLDER_COMPRESSED or not user.folder_token then
      user.folder_loading = false
      user.folder_error = lang.folder_too_large
    else
      local dirs, counters = parse_folder_response(payload, user.folder_token,
                                                   user.folder_path)
      if dirs == false then return false end -- stale reply for an older folder
      user.folder_loading = false
      if dirs then
        user.folder_shares = dirs
        user.folder_cache = user.folder_cache or {}
        user.folder_cache[user.folder_path] = dirs
        user.folder_counts = counters
        user.folder_error = nil
        user.folder_warning = counters.truncated and lang.folder_truncated or nil
      else
        user.folder_error = lang.folder_too_large
        user.folder_warning = nil
      end
    end
    local pending = app.folder_request
    if pending and pending.user == user.username
       and pending.path == user.folder_path and not user.folder_loading
       and not user.shares_loading then
      app.folder_request = nil
      local shares = combined_user_shares(user)
      if shares then
        begin_folder_download(user.username, pending.path, shares)
      else
        set_message(user.shares_error or user.folder_error
                    or lang.folder_too_large)
      end
    end
    update_visible_user(user)

  elseif code == 40 then
    local r = reader(payload)
    local direction, token = u32(r), u32(r)
    local path = ustr(r, 8192)
    local size = direction == 1 and u64(r) or nil
    local transfer = app.transfer
    if direction == 1 and token and path and transfer
       and transfer.user == conn.user and transfer.path == path then
      if size and size > 0 then transfer.size = size end
      transfer.token = token
      transfer.state = "ready"
      peer_send(conn, 41, p32(token) .. p8(1))
      transfer_status()
    elseif token then
      peer_send(conn, 41, p32(token) .. p8(0) .. pstr("Cancelled"))
    end

  elseif code == 44 then
    local r = reader(payload)
    local path, place = ustr(r, 8192), u32(r)
    local transfer = app.transfer
    if transfer and path == transfer.path then
      transfer.queue_place = place
      transfer_status()
    end

  elseif code == 46 then
    local failed_path = ustr(reader(payload), 8192)
    local transfer = app.transfer
    if transfer and transfer.user == conn.user
       and failed_path == transfer.path then
      fail_transfer("remote upload failed")
    end

  elseif code == 50 then
    local r = reader(payload)
    local path, reason = ustr(r, 8192), ustr(r, 1024)
    local transfer = app.transfer
    if transfer and path == transfer.path then
      fail_transfer(reason or lang.unknown)
    end
  elseif code == 43 or code == 51 then
    -- This client is deliberately download-only.  Reject unsolicited upload
    -- attempts explicitly instead of leaving the requesting peer waiting.
    local r = reader(payload)
    local path = ustr(r, 8192)
    if path then peer_send(conn, 50, pstr(path) .. pstr("File not shared.")) end
  end
  return false
end

local function parse_peer_frames(conn)
  while conn.fd and #conn.buffer >= 8 do
    local r = reader(conn.buffer)
    local length, code = u32(r), u32(r)
    if not length or length < 4 or length > MAX_FRAME then
      close_connection(conn)
      return
    end
    if #conn.buffer < length + 4 then return end
    local payload = string.sub(conn.buffer, 9, length + 4)
    conn.buffer = string.sub(conn.buffer, length + 5)
    if handle_peer_message(conn, code, payload) then
      close_connection(conn)
      return
    end
  end
end

local function begin_file_connection(conn)
  if #conn.buffer < 4 then return end
  local r = reader(conn.buffer)
  local token = u32(r)
  local transfer = app.transfer
  if not transfer or transfer.user ~= conn.user or transfer.token ~= token then
    close_connection(conn)
    return
  end
  conn.buffer = string.sub(conn.buffer, 5)
  if not send_all(conn.fd, p64(0)) then
    close_connection(conn)
    fail_transfer("offset handshake")
    return
  end

  app.connections[conn.fd] = nil
  transfer.source_fd = conn.fd
  conn.fd = nil
  transfer.got = 0
  transfer.buffer = conn.buffer
  transfer.state = transfer.mode == "stream" and "streaming" or "downloading"

  transfer.file = vlc.io.open(transfer.destination, "wb")
  if not transfer.file then
    close_fd(transfer.source_fd)
    fail_transfer("cannot create file")
    return
  end
  if transfer.mode == "download" then
    if #transfer.buffer > 0 then
      transfer.buffer = string.sub(transfer.buffer, 1, transfer.size)
      transfer.file:write(transfer.buffer)
      transfer.got = #transfer.buffer
      transfer.buffer = ""
    end
  else
    transfer.buffer = string.sub(transfer.buffer, 1, transfer.size)
    transfer.got = #transfer.buffer
    if #transfer.buffer > 0 then
      transfer.file:write(transfer.buffer)
      transfer.file:flush()
    end
    transfer.buffer = ""
    start_buffered_stream(transfer)
  end
  if transfer.got >= transfer.size then
    close_fd(transfer.source_fd)
    transfer.source_fd = nil
    transfer.source_done = true
    finish_transfer()
  end
  transfer_status()
end

local function process_connection(conn)
  if not conn.fd then return end
  local chunk = vlc.net.recv(conn.fd, 65536)
  if not chunk then close_connection(conn); return end
  conn.last_activity = os.time()
  conn.buffer = conn.buffer .. chunk
  if #conn.buffer > MAX_FRAME + 8 then close_connection(conn); return end
  if conn.kind == "new" then
    local fd = conn.fd
    parse_init(conn)
    conn = app.connections[fd]
    if not conn then return end
  end
  if conn.kind == "peer" then parse_peer_frames(conn)
  elseif conn.kind == "file" then begin_file_connection(conn) end
end

local function has_flag(value, flag)
  value, flag = math.floor(value or 0), math.floor(flag or 0)
  -- POLLIN/POLLOUT are aliases for a *set* of bits on systems without a
  -- native poll(2), notably Jaguar (POLLIN = POLLRDNORM | POLLRDBAND).
  -- The select-based compatibility layer quite correctly returns only the
  -- ready member of that set.  Testing the composite number as if it were a
  -- single power of two therefore missed every socket event on 10.2.
  while value > 0 and flag > 0 do
    if value % 2 == 1 and flag % 2 == 1 then return true end
    value, flag = math.floor(value / 2), math.floor(flag / 2)
  end
  return false
end

local function add_listener_fds(listener, pollfds)
  if not listener then return end
  local fds = { listener:fds() }
  for _, fd in ipairs(fds) do pollfds[fd] = vlc.net.POLLIN end
end

local function listener_ready(listener, pollfds)
  if not listener then return false end
  local fds = { listener:fds() }
  for _, fd in ipairs(fds) do
    if has_flag(pollfds[fd], vlc.net.POLLIN) then return true end
  end
  return false
end

local function close_stream_client(stream)
  if stream.proxy_fd then close_fd(stream.proxy_fd) end
  if stream.serve_file then pcall(function() stream.serve_file:close() end) end
  stream.proxy_fd, stream.serve_file = nil, nil
  stream.serve_offset, stream.serve_buffer = 0, ""
end

local function destroy_stream_cache(uri, cache)
  close_stream_client(cache)
  if cache.proxy_listener then
    pcall(function() cache.proxy_listener:close() end)
    cache.proxy_listener = nil
  end
  if cache.destination then
    if vlc.io and vlc.io.unlink then pcall(vlc.io.unlink, cache.destination)
    else pcall(os.remove, cache.destination) end
  end
  app.stream_caches[uri] = nil
end

local function playlist_contains_path(node, wanted)
  if type(node) ~= "table" then return false end
  if node.path == wanted then return true end
  local children = node.children
  if type(children) == "table" then
    for _, child in pairs(children) do
      if playlist_contains_path(child, wanted) then return true end
    end
  else
    for _, child in pairs(node) do
      if type(child) == "table" and playlist_contains_path(child, wanted) then
        return true
      end
    end
  end
  return false
end

local function playlist_item_id(node, wanted)
  if type(node) ~= "table" then return nil end
  if node.path == wanted and node.id ~= nil then return node.id end
  for _, child in pairs(node.children or node) do
    if type(child) == "table" then
      local id = playlist_item_id(child, wanted)
      if id ~= nil then return id end
    end
  end
  return nil
end

remove_playlist_path = function(wanted)
  if not wanted or not (vlc.playlist and vlc.playlist.get
                         and vlc.playlist.delete) then return false end
  local ok, tree = pcall(vlc.playlist.get, nil, false)
  if not ok or type(tree) ~= "table" then return false end
  local id = playlist_item_id(tree, wanted)
  if id == nil then return false end
  return pcall(vlc.playlist.delete, id)
end

local function cleanup_stream_caches(force)
  local now = os.time()
  if not force and now - app.last_cache_cleanup < 3 then return end
  app.last_cache_cleanup = now
  local playlist = nil
  if not force and vlc.playlist and vlc.playlist.get then
    local ok, value = pcall(vlc.playlist.get, nil, false)
    if ok and type(value) == "table" then playlist = value end
  end
  for uri, cache in pairs(app.stream_caches) do
    local expired = force
    if playlist and now - (cache.created or now) >= 5 then
      expired = not playlist_contains_path(playlist, uri)
    end
    if expired then destroy_stream_cache(uri, cache) end
  end
end

local function accept_stream_client(stream)
  if stream.proxy_fd or not stream.proxy_listener then return end
  local fd = stream.proxy_listener:accept()
  if not fd or fd < 0 then return end
  local file = vlc.io.open(stream.destination, "rb")
  if not file then close_fd(fd); return end
  stream.proxy_fd, stream.serve_file = fd, file
  stream.serve_offset, stream.serve_buffer = 0, ""
end

local function serve_stream_client(stream)
  if not stream.proxy_fd or not stream.serve_file then return end
  for _ = 1, COPY_BURST do
    if stream.serve_buffer == "" and stream.serve_offset < (stream.got or 0) then
      stream.serve_file:seek("set", stream.serve_offset)
      stream.serve_buffer = stream.serve_file:read(
        math.min(COPY_CHUNK, (stream.got or 0) - stream.serve_offset)) or ""
    end
    if stream.serve_buffer == "" then break end
    local sent = vlc.net.send(stream.proxy_fd, stream.serve_buffer)
    -- The accepted loopback socket is non-blocking.  A full send buffer is a
    -- normal condition while VLC is decoding and must be retried on the next
    -- POLLOUT notification, otherwise a cached track stops almost at once.
    if not sent or sent <= 0 then return end
    stream.serve_offset = stream.serve_offset + sent
    stream.serve_buffer = string.sub(stream.serve_buffer, sent + 1)
  end
  if stream.complete and stream.serve_offset >= stream.size
     and stream.serve_buffer == "" then
    close_stream_client(stream)
  end
end

local function add_stream_cache_fds(pollfds)
  for _, cache in pairs(app.stream_caches) do
    if cache.proxy_listener and not cache.proxy_fd then
      add_listener_fds(cache.proxy_listener, pollfds)
    elseif cache.proxy_fd then
      if cache.serve_offset < cache.got or cache.serve_buffer ~= "" then
        pollfds[cache.proxy_fd] = vlc.net.POLLOUT
      else
        pollfds[cache.proxy_fd] = vlc.net.POLLIN
      end
    end
  end
end

local function process_stream_caches(pollfds)
  for _, cache in pairs(app.stream_caches) do
    if cache.proxy_listener and not cache.proxy_fd
       and listener_ready(cache.proxy_listener, pollfds) then
      accept_stream_client(cache)
    elseif cache.proxy_fd then
      local flags = pollfds[cache.proxy_fd]
      if has_flag(flags, vlc.net.POLLOUT) then
        serve_stream_client(cache)
      elseif has_flag(flags, vlc.net.POLLERR)
          or has_flag(flags, vlc.net.POLLHUP)
          or has_flag(flags, vlc.net.POLLNVAL) then
        close_stream_client(cache)
      elseif has_flag(flags, vlc.net.POLLIN) then
        local probe = vlc.net.recv(cache.proxy_fd, 1)
        if not probe then close_stream_client(cache) end
      end
    end
  end
  cleanup_stream_caches(false)
end

local function remember_completed_transfer(transfer)
  transfer.state = "complete"
  transfer.got = tonumber(transfer.size) or tonumber(transfer.got) or 0
  transfer.completed_at = os.time()
  app.transfer_history[#app.transfer_history + 1] = transfer
end

finish_transfer = function()
  local transfer = app.transfer
  if not transfer then return end
  if transfer.mode == "stream" then start_buffered_stream(transfer) end
  if transfer.source_fd then close_fd(transfer.source_fd) end
  if transfer.file then pcall(function() transfer.file:close() end) end
  local destination = transfer.destination
  local mode = transfer.mode
  remember_completed_transfer(transfer)
  app.transfer = nil
  if mode == "stream" then
    transfer.file, transfer.source_fd = nil, nil
    transfer.complete = true
    transfer.created = os.time()
    app.stream_caches[transfer.proxy_uri] = transfer
    set_message(lang.stream_cached)
  elseif mode == "download" and app.folder_batch then
    if transfer.proxy_fd then close_fd(transfer.proxy_fd) end
    if transfer.proxy_listener then pcall(function() transfer.proxy_listener:close() end) end
    app.folder_batch.completed = app.folder_batch.completed + 1
    start_next_folder_file()
  elseif mode == "download" and destination then
    if transfer.proxy_fd then close_fd(transfer.proxy_fd) end
    if transfer.proxy_listener then pcall(function() transfer.proxy_listener:close() end) end
    set_message(string.format(lang.saved, destination))
  else
    set_message(lang.complete)
  end
  if not app.folder_batch then start_next_queued_transfer() end
  if app.view == "transfers" then refresh_transfers() end
end

fail_transfer = function(reason)
  local batch = app.folder_batch
  local failed = cancel_transfer(true)
  if batch then
    batch.failed = batch.failed + 1
    start_next_folder_file()
  elseif failed and failed.mode == "stream" and failed.enqueue_only
     and (failed.retry_count or 0) < 2 and failed.file_info then
    table.insert(app.transfer_queue, 1, {
      file = failed.file_info, mode = "stream", enqueue_only = true,
      retry_count = (failed.retry_count or 0) + 1,
    })
    set_message(string.format(lang.transfer_failed, reason or lang.unknown))
    start_next_queued_transfer()
  else
    set_message(string.format(lang.transfer_failed, reason or lang.unknown))
    start_next_queued_transfer()
  end
  if app.view == "transfers" then refresh_transfers() end
end

local function read_transfer_source(transfer)
  for _ = 1, COPY_BURST do
    if not transfer.source_fd or transfer.got >= transfer.size then break end
    local probe = { [transfer.source_fd] = vlc.net.POLLIN }
    local ok, ready = pcall(vlc.net.poll, probe, 0)
    if not ok or ready <= 0 or not has_flag(probe[transfer.source_fd], vlc.net.POLLIN) then break end
    local amount = math.min(COPY_CHUNK, transfer.size - transfer.got)
    local chunk = vlc.net.recv(transfer.source_fd, amount)
    if not chunk then
      if transfer.got < transfer.size then fail_transfer("connection closed") end
      return
    end
    transfer.got = transfer.got + #chunk
    if transfer.mode == "download" then
      if not transfer.file:write(chunk) then fail_transfer("write error"); return end
    else
      if not transfer.file:write(chunk) then fail_transfer("cache write error"); return end
    end
  end
  if transfer.mode == "stream" and transfer.file then transfer.file:flush() end
  if transfer.mode == "stream" then start_buffered_stream(transfer) end

  if transfer.got >= transfer.size and transfer.source_fd then
    close_fd(transfer.source_fd)
    transfer.source_fd = nil
    transfer.source_done = true
    finish_transfer()
  end
end

local function write_proxy(transfer)
  serve_stream_client(transfer)
end

function soulseek_tick()
  if app.stopping then return end
  if folder_picker then folder_picker:poll() end
  if not app.connected then
    local cache_fds = {}
    add_stream_cache_fds(cache_fds)
    if next(cache_fds) then
      local ok = pcall(vlc.net.poll, cache_fds, 0)
      if ok then process_stream_caches(cache_fds) end
    else
      cleanup_stream_caches(false)
    end
    arm_tick()
    return
  end
  local pollfds = {}
  if app.server then pollfds[app.server.fd] = vlc.net.POLLIN end
  add_listener_fds(app.listener, pollfds)
  for fd in pairs(app.connections) do pollfds[fd] = vlc.net.POLLIN end
  add_stream_cache_fds(pollfds)

  local transfer = app.transfer
  if transfer then
    if transfer.proxy_listener and not transfer.proxy_fd then
      add_listener_fds(transfer.proxy_listener, pollfds)
    end
    if transfer.source_fd then
      pollfds[transfer.source_fd] = vlc.net.POLLIN
    end
    if transfer.proxy_fd and (transfer.serve_offset < transfer.got
                              or transfer.serve_buffer ~= "") then
      pollfds[transfer.proxy_fd] = vlc.net.POLLOUT
    elseif transfer.proxy_fd then
      pollfds[transfer.proxy_fd] = vlc.net.POLLIN
    end
  end

  local ok, ready = pcall(vlc.net.poll, pollfds, 0)
  if not ok then
    set_message(string.format(lang.network_failed, tostring(ready)))
    disconnect()
    return
  end

  if app.server and has_flag(pollfds[app.server.fd], vlc.net.POLLIN) then
    local chunk = vlc.net.recv(app.server.fd, 65536)
    if not chunk then
      set_message(lang.disconnected)
      disconnect()
      return
    end
    app.server.buffer = app.server.buffer .. chunk
    if #app.server.buffer > MAX_FRAME + 8 then
      set_message(lang.disconnected)
      disconnect()
      return
    end
    parse_server_frames()
  end

  if app.listener and listener_ready(app.listener, pollfds) then
    local fd = app.listener:accept()
    if fd and fd >= 0 then
      app.connections[fd] = { fd = fd, kind = "new", buffer = "" }
    end
  end

  process_stream_caches(pollfds)

  transfer = app.transfer
  if transfer and transfer.proxy_listener and not transfer.proxy_fd
     and listener_ready(transfer.proxy_listener, pollfds) then
    accept_stream_client(transfer)
  end

  local snapshot = {}
  for _, conn in pairs(app.connections) do snapshot[#snapshot + 1] = conn end
  for _, conn in ipairs(snapshot) do
    if conn.fd and has_flag(pollfds[conn.fd], vlc.net.POLLIN) then
      process_connection(conn)
    elseif conn.fd and (has_flag(pollfds[conn.fd], vlc.net.POLLERR)
                     or has_flag(pollfds[conn.fd], vlc.net.POLLHUP)
                     or has_flag(pollfds[conn.fd], vlc.net.POLLNVAL)) then
      close_connection(conn)
    end
  end

  transfer = app.transfer
  if transfer and transfer.source_fd
     and has_flag(pollfds[transfer.source_fd], vlc.net.POLLIN) then
    read_transfer_source(transfer)
  end
  transfer = app.transfer
  if transfer and transfer.source_fd
     and (has_flag(pollfds[transfer.source_fd], vlc.net.POLLERR)
       or has_flag(pollfds[transfer.source_fd], vlc.net.POLLHUP)
       or has_flag(pollfds[transfer.source_fd], vlc.net.POLLNVAL)) then
    if transfer.got >= transfer.size then
      close_fd(transfer.source_fd)
      transfer.source_fd, transfer.source_done = nil, true
      finish_transfer()
    else
      fail_transfer("file connection closed")
    end
  end
  transfer = app.transfer
  if transfer and transfer.proxy_fd then
    if has_flag(pollfds[transfer.proxy_fd], vlc.net.POLLOUT) then
      write_proxy(transfer)
    elseif has_flag(pollfds[transfer.proxy_fd], vlc.net.POLLIN) then
      local probe = vlc.net.recv(transfer.proxy_fd, 1)
      if not probe then close_stream_client(transfer) end
    elseif has_flag(pollfds[transfer.proxy_fd], vlc.net.POLLERR)
        or has_flag(pollfds[transfer.proxy_fd], vlc.net.POLLHUP)
        or has_flag(pollfds[transfer.proxy_fd], vlc.net.POLLNVAL) then
      close_stream_client(transfer)
    end
  end

  transfer = app.transfer
  if transfer and transfer.state and transfer.got
     and os.time() ~= transfer.last_progress then
    transfer.last_progress = os.time()
    transfer_status()
  end

  if app.search_deadline and os.time() >= app.search_deadline then
    app.search_deadline = nil
    if app.view == "search" and refresh_search_results then refresh_search_results() end
  end
  process_one_indirect()
  local now = os.time()
  for name, pending in pairs(app.pending_users) do
    if pending.started and now - pending.started >= 30 then
      app.pending_users[name] = nil
      app.pending_tokens[pending.token] = nil
      local state = user_state(name)
      state.info_loading, state.shares_loading = false, false
      state.shares_error = string.format(lang.user_unreachable, name)
      update_visible_user(state)
    end
  end
  local active_user = app.transfer and app.transfer.user or nil
  for _, conn in pairs(app.connections) do
    if conn.kind == "peer" and conn.user ~= active_user
       and conn.last_activity and now - conn.last_activity >= 45 then
      close_connection(conn)
    end
  end
  if os.time() - app.last_ping >= 60 then
    server_send(32, "")
    app.last_ping = os.time()
  end
  arm_tick()
end

local function selected_widget_row(widget, rows)
  if not widget then return nil end
  local selection = widget:get_selection()
  for id in pairs(selection or {}) do return rows[tonumber(id) or id] end
  return nil
end

local function selected_widget_rows(widget, rows)
  local selected, ids = {}, {}
  if not widget then return selected end
  for id in pairs(widget:get_selection() or {}) do
    ids[#ids + 1] = tonumber(id) or id
  end
  table.sort(ids, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(ids) do
    local row = rows[id]
    if row then selected[#selected + 1] = row end
  end
  return selected
end

local function selected_search_users(widget, rows)
  local selected = {}
  if not widget then return selected end
  for id in pairs(widget:get_selection() or {}) do
    local row = rows[tonumber(id) or id]
    if row and row.kind == "user" and row.username then
      selected[row.username] = true
    end
  end
  return selected
end

local function selected_row()
  if app.view == "user" and app.active_user_list == "matches" then
    return selected_widget_row(ui.matches, app.match_rows)
        or selected_widget_row(ui.list, app.rows)
  end
  return selected_widget_row(ui.list, app.rows)
      or selected_widget_row(ui.matches, app.match_rows)
end

local function selected_rows()
  local primary, fallback
  if app.view == "user" and app.active_user_list == "matches" then
    primary = selected_widget_rows(ui.matches, app.match_rows)
    fallback = selected_widget_rows(ui.list, app.rows)
  else
    primary = selected_widget_rows(ui.list, app.rows)
    fallback = selected_widget_rows(ui.matches, app.match_rows)
  end
  return #primary > 0 and primary or fallback
end

local function selected_match_row()
  return selected_widget_row(ui.matches, app.match_rows)
end

local function add_row(text, row)
  local id = #app.rows + 1
  app.rows[id] = row
  ui.list:add_value(text, id)
  return id
end

local function add_match_row(text, row)
  local id = #app.match_rows + 1
  app.match_rows[id] = row
  ui.matches:add_value(text, id)
end

local function status_name(status)
  if status == 0 then return lang.offline end
  if status == 1 then return lang.away end
  if status == 2 then return lang.online end
  return lang.unknown
end

local function user_summary(user)
  local slot = user.info and (user.info.slots and lang.slots_free or lang.slots_busy)
               or lang.unknown
  return string.format(lang.profile_summary,
    status_name(user.status), user.country or "--", slot,
    user.file_count or (user.share_counts and user.share_counts.files) or 0,
    user.dir_count or (user.share_counts and user.share_counts.dirs) or 0)
end

function refresh_search_results()
  if app.view ~= "search" or not ui.list then return end
  local selected_users = selected_search_users(ui.list, app.rows)
  ui.list:clear()
  app.rows = {}
  local selected_ids = {}
  for _, name in ipairs(app.result_order) do
    local group = app.results[name]
    -- FreeSans (our XP fallback) does not contain the filled/empty circle
    -- glyphs. Keep this status legible even before a system fallback exists.
    local availability = group.slots and "+" or "-"
    local text = ">\t" .. name .. "\t" .. tostring(#group.files)
              .. "\t" .. sortable_speed(group.speed) .. "\t"
              .. availability .. " " .. tostring(group.queue or 0)
              .. LIST_TRAILING_PAD
    local first = group.files[1]
    local id = add_row(text, { kind = "user", username = name,
                               path = first and dirname(first.path) or "" })
    if selected_users[name] then selected_ids[id] = true end
  end
  if next(selected_ids) and ui.list.set_selection then
    ui.list:set_selection(selected_ids)
  end
  if app.search_deadline then
    set_message(lang.searching)
  else
    set_message(string.format(lang.search_done, #app.result_order, app.result_files))
  end
end

local function show_search()
  app.view, app.view_user, app.view_path = "search", nil, ""
  app.view_root, app.view_limited = "", false
  app.user_filter = ""
  close_dialog()
  dlg = vlc.dialog(lang.title)
  dlg:set_size(900, 520)
  dlg:add_label(string.format(lang.connected, app.username, app.listen_port), 1, 1, 5, 1)
  dlg:add_label(lang.search, 1, 2, 1, 1)
  ui.query = dlg:add_text_input(app.search_query, 2, 2, 3, 1, click_search)
  dlg:add_button(lang.search_button, click_search, 5, 2, 1, 1)
  dlg:add_label(lang.user, 1, 3, 1, 1)
  ui.username = dlg:add_text_input("", 2, 3, 3, 1, click_open_user)
  dlg:add_button(lang.open_user, click_open_user, 5, 3, 1, 1)
  ui.list = dlg:add_list(1, 4, 5, 1, click_open_row)
  ui.list:set_text(">\t" .. lang.user .. "\t" .. lang.file
                   .. "\t" .. lang.quality .. "\tQueue"
                   .. LIST_TRAILING_PAD)
  dlg:add_button(lang.open_user, click_open_row, 1, 5, 2, 1)
  dlg:add_button(lang.transfers, click_show_transfers, 3, 5, 2, 1)
  ui.message = dlg:add_label("", 1, 6, 5, 1)
  dlg:add_label(lang.privacy, 1, 7, 5, 1)
  dlg:show()
  refresh_search_results()
end

local function immediate_children(shares, current)
  local folders, exact_files = {}, {}
  local seen = {}
  local prefix = current == "" and "" or (current .. "\\")
  for _, dir in ipairs(shares or {}) do
    if not dir.private and dir.path == current then
      for _, file in ipairs(dir.files) do
        if not file.private and not file.locked then
          exact_files[#exact_files + 1] = file
        end
      end
    elseif not dir.private and string.sub(dir.path, 1, #prefix) == prefix then
      local rest = string.sub(dir.path, #prefix + 1)
      local segment = string.match(rest, "^([^\\]+)")
      if segment and not seen[segment] then
        seen[segment] = true
        folders[#folders + 1] = { name = segment,
          path = prefix == "" and segment or (prefix .. segment) }
      end
    end
  end
  table.sort(folders, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  table.sort(exact_files, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return folders, exact_files
end

local function user_filter_key(item)
  if not item.filter_key then
    -- The list shows the current folder already, so matching its whole path
    -- produces irrelevant hits.  Filter strictly on the visible item name.
    item.filter_key = string.lower(item.name or basename(item.path or ""))
  end
  return item.filter_key
end

local function filter_user_items(items, query)
  if query == "" then return items end
  local filtered = {}
  for _, item in ipairs(items) do
    if string.find(user_filter_key(item), query, 1, true) then
      filtered[#filtered + 1] = item
    end
  end
  return filtered
end

local function refresh_search_matches(user)
  if not ui.matches
     or app.matches_rendered_version == (user.search_version or 0) then return end
  ui.matches:clear()
  app.match_rows = {}
  for _, file in ipairs(user.search_files or {}) do
    if not file.private and not file.locked then
      file.user = user.username
      add_match_row("♪\t" .. file.path .. "\t" .. sortable_size(file.size)
                    .. "\t" .. sortable_quality(file) .. "\t"
                    .. format_duration(file.duration),
                    { kind = "file", file = file })
    end
  end
  app.matches_rendered_version = user.search_version or 0
end

function refresh_user_view()
  if app.view ~= "user" or not ui.list then return end
  local user = user_state(app.view_user)
  if ui.profile then ui.profile:set_text(user_summary(user)) end
  if ui.description then
    ui.description:set_text(profile_html(user.info and user.info.description or ""))
  end
  if app.view_limited then
    ui.path:set_text(string.format(lang.folder_path, app.view_path))
  else
    ui.path:set_text(app.view_path == "" and lang.shares or app.view_path)
  end
  refresh_search_matches(user)
  ui.list:clear()
  app.rows = {}

  -- Exact-result browsing deliberately stays lightweight: render only the
  -- reply cached for the folder the user opened.  Loading and merging the
  -- peer's complete share list here made a simple CD1 view noticeably slow;
  -- the explicit "load all files" action remains available when wanted.
  local shares
  if app.view_limited then
    shares = user.folder_cache and user.folder_cache[app.view_path]
  else
    shares = user.shares
  end
  local folders, files = immediate_children(shares, app.view_path)
  local filter_query = string.lower(trim(app.user_filter or ""))
  folders = filter_user_items(folders, filter_query)
  files = filter_user_items(files, filter_query)
  for _, folder in ipairs(folders) do
    add_row(">\t" .. folder.name .. "\t\t\t",
            { kind = "folder", path = folder.path })
  end
  for _, file in ipairs(files) do
    file.user = user.username
    add_row("♪\t" .. file.name .. "\t" .. sortable_size(file.size)
            .. "\t" .. sortable_quality(file) .. "\t" .. format_duration(file.duration),
            { kind = "file", file = file })
  end

  if not shares and not app.view_limited then
    for _, file in ipairs(user.search_files or {}) do
      if filter_query == ""
         or string.find(user_filter_key(file), filter_query, 1, true) then
        add_row("♪\t" .. file.path .. "\t" .. sortable_size(file.size)
                .. "\t" .. sortable_quality(file) .. "\t" .. format_duration(file.duration),
                { kind = "file", file = file })
      end
    end
  end

  if app.view_limited and user.folder_error then set_message(user.folder_error)
  elseif app.view_limited and user.folder_warning then set_message(user.folder_warning)
  elseif not app.view_limited and user.shares_error then set_message(user.shares_error)
  elseif not app.view_limited and user.shares_warning then set_message(user.shares_warning)
  elseif (app.view_limited and user.folder_loading)
      or (not app.view_limited and (user.shares_loading or user.info_loading)) then
    set_message(app.view_limited and lang.loading_folder or lang.loading_user)
  elseif filter_query ~= "" and #app.rows == 0 then
    set_message(lang.no_filter_results)
  elseif app.transfer then transfer_status()
  else set_message("") end
end

local function show_user(name, initial_path, limited)
  initial_path = initial_path or ""
  app.view, app.view_user, app.view_path = "user", name, initial_path
  app.view_root, app.view_limited = initial_path, limited and true or false
  app.active_user_list = app.view_limited and "matches" or "folder"
  app.match_rows, app.matches_rendered_version = {}, nil
  local exact_count = 0
  if app.view_limited then
    for _, file in ipairs(user_state(name).search_files or {}) do
      if not file.private and not file.locked then exact_count = exact_count + 1 end
    end
  end
  -- A two-item search should not reserve the same tall pane as dozens of
  -- matches on a 768-pixel Jaguar display. Keep one compact grid row for a
  -- handful of exact hits and expand only when scrolling is actually useful.
  local match_span = exact_count <= 3 and 1 or 2
  close_dialog()
  dlg = vlc.dialog("Soulseek — " .. name)
  dlg:set_size(900, app.view_limited and (match_span == 1 and 610 or 660) or 620)
  dlg:add_button(lang.back_results, click_back_results, 1, 1, 1, 1)
  dlg:add_button(lang.refresh, click_refresh_user, 2, 1, 1, 1)
  dlg:add_button(lang.view_description, click_show_profile, 3, 1, 1, 1)
  if app.view_limited then
    dlg:add_button(lang.load_all_files, click_all_shares, 4, 1, 3, 1)
  end
  -- User browsing opens on files only.  The description has its own view and
  -- is never requested merely because this listing was opened.
  ui.path = dlg:add_label("", 1, 2, 6, 1)
  dlg:add_label(lang.download_location, 1, 3, 1, 1)
  ui.download_dir = dlg:add_text_input(app.download_dir or "", 2, 3, 4, 1)
  dlg:add_button(lang.choose_folder, click_choose_download_dir, 6, 3, 1, 1)
  local filter_row, list_row, list_span, actions_row, message_row
  if app.view_limited then
    dlg:add_label(lang.exact_search_matches, 1, 4, 6, 1)
    ui.matches = dlg:add_list(1, 5, 6, match_span, click_open_match,
                              click_select_matches)
    ui.matches:set_text(">\t" .. lang.file .. "\t" .. lang.size
                        .. "\t" .. lang.quality .. "\t" .. lang.duration)
    ui.matches:set_menu({ lang.open_folder }, click_open_match_folder)
    filter_row = 5 + match_span
    dlg:add_label(lang.folder_contents, 1, filter_row + 1, 6, 1)
    list_row, list_span = filter_row + 2, 4
    actions_row, message_row = list_row + list_span, list_row + list_span + 1
  else
    filter_row = 4
    dlg:add_label(lang.folder_contents, 1, 5, 6, 1)
    list_row, list_span, actions_row, message_row = 6, 5, 11, 12
  end
  dlg:add_label(lang.filter_files, 1, filter_row, 1, 1)
  -- The text-change callback is delayed by 300 ms in both native providers;
  -- Enter uses the validation callback to apply immediately.
  ui.filter = dlg:add_text_input(app.user_filter or "", 2, filter_row, 5, 1,
                                 click_filter_user, click_filter_user)
  ui.list = dlg:add_list(1, list_row, 6, list_span, click_open_row,
                         click_select_folder)
  ui.list:set_text(">\t" .. lang.file .. "\t" .. lang.size
                   .. "\t" .. lang.quality .. "\t" .. lang.duration)
  if not app.view_limited then
    dlg:add_button(lang.back_user, click_back, 1, actions_row, 1, 1)
  end
  dlg:add_button(lang.play, click_play, 2, actions_row, 1, 1)
  dlg:add_button(lang.enqueue, click_enqueue, 3, actions_row, 1, 1)
  dlg:add_button(lang.download, click_download, 4, actions_row, 1, 1)
  dlg:add_button(lang.download_folder, click_download_folder, 5, actions_row, 1, 1)
  dlg:add_button(lang.transfers, click_show_transfers, 6, actions_row, 1, 1)
  ui.message = dlg:add_label("", 1, message_row, 6, 1)
  dlg:show()
  refresh_user_view()
end

function refresh_transfers()
  if app.view ~= "transfers" or not ui.list then return end

  local selected_refs = {}
  for id in pairs(ui.list:get_selection() or {}) do
    local old = app.transfer_rows[tonumber(id) or id]
    if old and old.ref then selected_refs[old.ref] = true end
  end

  ui.list:clear()
  ui.list:set_text(lang.file .. "\t" .. lang.transfer_type .. "\t"
                   .. lang.transfer_state .. "\t" .. lang.progress)
  app.transfer_rows = {}
  local selected_ids = {}

  local function add_transfer_row(ref, kind, file, state, got, size, extra)
    local id = #app.transfer_rows + 1
    app.transfer_rows[id] = { kind = kind, ref = ref, extra = extra }
    local mode = ref.mode == "stream"
               and lang.transfer_stream or lang.transfer_download
    ui.list:add_value(basename(file.path or file.name or "") .. "\t" .. mode
                      .. "\t" .. state .. "\t"
                      .. format_size(got or 0) .. " / " .. format_size(size or 0), id)
    if selected_refs[ref] then selected_ids[id] = true end
  end

  if app.transfer then
    add_transfer_row(app.transfer, "active", app.transfer.file_info
                     or { path = app.transfer.path }, lang.transfer_active,
                     app.transfer.got, app.transfer.size)
  end
  for _, queued in ipairs(app.transfer_queue) do
    add_transfer_row(queued, "queued", queued.file, lang.transfer_waiting,
                     0, queued.file and queued.file.size or 0)
  end
  if app.folder_batch then
    for index = app.folder_batch.index + 1, #app.folder_batch.files do
      local file = app.folder_batch.files[index]
      add_transfer_row(file, "folder", file, lang.transfer_waiting,
                       0, file.size, index)
    end
  end
  for _, completed in ipairs(app.transfer_history) do
    add_transfer_row(completed, "complete", completed.file_info
                     or { path = completed.path }, lang.transfer_complete,
                     completed.size, completed.size)
  end

  if next(selected_ids) and ui.list.set_selection then
    ui.list:set_selection(selected_ids)
  end
  if #app.transfer_rows == 0 then set_message(lang.no_transfers) end
end

local function show_transfers()
  app.view = "transfers"
  close_dialog()
  dlg = vlc.dialog(lang.title_transfers)
  dlg:set_size(900, 520)
  ui.list = dlg:add_list(1, 1, 6, 6)
  dlg:add_button(lang.back, click_back_transfers, 1, 7, 2, 1)
  dlg:add_button(lang.cancel_selected, click_cancel_selected_transfers,
                 3, 7, 2, 1)
  dlg:add_button(lang.remove, click_remove_completed_transfers, 5, 7, 2, 1)
  ui.message = dlg:add_label("", 1, 8, 6, 1)
  dlg:show()
  refresh_transfers()
end

function click_show_transfers()
  if app.view ~= "transfers" then
    app.transfers_return = {
      view = app.view, user = app.view_user, path = app.view_path,
      root = app.view_root, limited = app.view_limited,
    }
  end
  show_transfers()
end

function click_back_transfers()
  local previous = app.transfers_return
  app.transfers_return = nil
  if previous and previous.view == "user" and previous.user then
    show_user(previous.user, previous.path, previous.limited)
    app.view_root = previous.root or app.view_root
  else
    show_search()
  end
end

function refresh_profile_view()
  if app.view ~= "profile" or not ui.description then return end
  local user = user_state(app.view_user)
  ui.profile:set_text(user_summary(user))
  ui.description:set_text(profile_html(user.info and user.info.description or ""))
  if user.info_loading then set_message(lang.loading_profile)
  elseif not user.info then set_message(lang.profile_unavailable)
  else set_message("") end
end

function show_profile(name)
  app.view, app.view_user = "profile", name
  close_dialog()
  dlg = vlc.dialog("Soulseek — " .. name .. " — " .. lang.profile)
  dlg:set_size(760, 360)
  dlg:add_button(lang.back_files, click_back_to_files, 1, 1, 1, 1)
  dlg:add_button(lang.refresh, click_refresh_profile, 2, 1, 1, 1)
  ui.profile = dlg:add_label("", 1, 2, 4, 1)
  ui.description = dlg:add_html("", 1, 3, 4, 2, 700, 220)
  ui.message = dlg:add_label("", 1, 5, 4, 1)
  dlg:show()
  refresh_profile_view()
end

local function request_user_files(name, force)
  local user = user_state(name)
  if not force and (user.shares or user.shares_loading) then return end
  if force then
    user.shares, user.shares_error, user.shares_warning = nil, nil, nil
  end
  user.shares_loading = true
  request_peer(name, 4, "")
end

function request_user_profile(name, force)
  local user = user_state(name)
  if force then user.info = nil end
  user.info_loading = true
  server_send(5, pstr(name))
  server_send(36, pstr(name))
  request_peer(name, 15, "")
end

local function request_user_folder(name, path, force)
  local user = user_state(name)
  user.folder_cache = user.folder_cache or {}
  if not force and user.folder_cache[path] then return end
  if force or user.folder_path ~= path then
    user.folder_error, user.folder_warning = nil, nil
    if force then user.folder_cache[path] = nil end
  end
  user.folder_path = path
  user.folder_token = next_token()
  user.folder_loading = true
  -- FolderContentsRequest alone is enough here.  Status, statistics, profile
  -- and the full share list belong to the explicit full-profile action.
  request_peer(name, 36, p32(user.folder_token) .. pstr(path))
end

function click_search()
  if not app.connected then return end
  local query = trim(ui.query and ui.query:get_text() or "")
  if query == "" then set_message(lang.search_hint); return end
  app.search_query = query
  app.search_token = next_token()
  app.search_deadline = os.time() + SEARCH_SECONDS
  app.results, app.result_order, app.result_files = {}, {}, 0
  server_send(26, p32(app.search_token) .. pstr(query))
  refresh_search_results()
  arm_tick()
end

function click_filter_user()
  if app.view ~= "user" or not ui.filter then return end
  local query = trim(ui.filter:get_text() or "")
  if query == app.user_filter then return end
  app.user_filter = query
  refresh_user_view()
end

function click_show_profile()
  if not app.view_user then return end
  local user = user_state(app.view_user)
  if not user.info then request_user_profile(app.view_user, false) end
  show_profile(app.view_user)
end

function click_refresh_profile()
  if not app.view_user then return end
  request_user_profile(app.view_user, true)
  refresh_profile_view()
end

function click_back_to_files()
  if not app.view_user then return end
  show_user(app.view_user, app.view_path, app.view_limited)
end

function click_open_user()
  local name = trim(ui.username and ui.username:get_text() or "")
  if name == "" then
    local row = selected_row()
    if row and row.kind == "user" then name = row.username end
  end
  if name == "" then set_message(lang.nothing_selected); return end
  app.user_filter = ""
  request_user_files(name, false)
  show_user(name, "", false)
end

function click_select_matches()
  if app.view == "user" then app.active_user_list = "matches" end
end

function click_select_folder()
  if app.view == "user" then app.active_user_list = "folder" end
end

function click_open_match()
  app.active_user_list = "matches"
  local row = selected_match_row()
  if not row or row.kind ~= "file" then
    set_message(lang.nothing_selected)
    return
  end
  click_play()
end

function click_open_match_folder(entry)
  if entry ~= 1 then return end
  app.active_user_list = "matches"
  local row = selected_match_row()
  if not row or row.kind ~= "file" or not row.file then
    set_message(lang.nothing_selected)
    return
  end

  local folder = dirname(row.file.path or "")
  app.user_filter = ""
  app.view_path, app.view_root, app.view_limited = folder, folder, true
  request_user_folder(app.view_user, folder, false)
  show_user(app.view_user, folder, true)
end

function click_open_row()
  if app.view == "user" then app.active_user_list = "folder" end
  local row = selected_row()
  if not row then set_message(lang.nothing_selected); return end
  if row.kind == "user" then
    app.user_filter = ""
    request_user_folder(row.username, row.path or "", false)
    show_user(row.username, row.path or "", true)
  elseif row.kind == "folder" then
    app.view_path = row.path
    request_user_folder(app.view_user, app.view_path, false)
    refresh_user_view()
  elseif row.kind == "file" then
    click_play()
  end
end

function click_back()
  if app.view ~= "user" then return end
  if app.view_path ~= app.view_root then
    app.view_path = dirname(app.view_path)
    if app.view_limited then
      request_user_folder(app.view_user, app.view_path, false)
    end
    refresh_user_view()
  else
    show_search()
  end
end

function click_back_results()
  if app.view == "user" then show_search() end
end

function click_refresh_user()
  if app.view_user then
    if app.view_limited then
      request_user_folder(app.view_user, app.view_path, true)
    else
      request_user_files(app.view_user, true)
    end
    refresh_user_view()
  end
end

function click_all_shares()
  if not app.view_user then return end
  app.view_limited, app.view_root, app.view_path = false, "", ""
  request_user_files(app.view_user, false)
  show_user(app.view_user, "", false)
end

local function download_directory()
  local home = vlc.config and vlc.config.homedir and vlc.config.homedir() or "."
  local entered = trim(ui.download_dir and ui.download_dir:get_text() or "")
  if entered ~= "" and entered ~= app.download_dir then
    app.download_dir = entered
    save_settings()
  end
  local base = trim(app.download_dir or "")
  if base == "" then base = home .. "/Downloads" end
  base = string.gsub(base, "\\", "/")
  if vlc.io and vlc.io.mkdir then pcall(vlc.io.mkdir, base, "0755") end
  return base
end

local function safe_filename(name)
  name = string.gsub(name or "download", "[%z\1-\31\\/:*?\"<>|]", "_")
  name = trim(name)
  if name == "" then name = "download" end
  return name
end

-- vlc.io.mkdir creates one level at a time.
local function mkdir_p(path)
  if not (vlc.io and vlc.io.mkdir) then return false end
  path = string.gsub(path or "", "\\", "/")
  local drive = string.match(path, "^([A-Za-z]:)/")
  local built = drive and (drive .. "/")
             or (string.sub(path, 1, 1) == "/" and "/" or "")
  if drive then path = string.sub(path, 4) end
  for part in string.gmatch(path, "[^/]+") do
    built = built .. part
    vlc.io.mkdir(built, "0755")
    built = built .. "/"
  end
  return true
end

local function purge_stale_stream_files()
  if not app.cache_dir or not (vlc.net and vlc.net.opendir) then return end
  mkdir_p(app.cache_dir)
  local ok, names = pcall(vlc.net.opendir, app.cache_dir)
  if not ok or type(names) ~= "table" then return end
  for _, name in ipairs(names) do
    if name ~= "." and name ~= ".." then
      pcall(os.remove, app.cache_dir .. "/" .. name)
    end
  end
end

local function collect_folder_files(shares, root, username)
  local files = {}
  local prefix = root == "" and "" or (root .. "\\")
  for _, dir in ipairs(shares or {}) do
    if not dir.private
       and (dir.path == root
            or (prefix ~= "" and string.sub(dir.path, 1, #prefix) == prefix)) then
      for _, file in ipairs(dir.files or {}) do
        if not file.private and not file.locked then
          file.user = username
          files[#files + 1] = file
        end
      end
    end
  end
  table.sort(files, function(a, b)
    return string.lower(a.path or "") < string.lower(b.path or "")
  end)
  return files
end

local function shares_cover_folder(shares, root)
  for _, dir in ipairs(shares or {}) do
    if dir.path == root then return true end
  end
  return false
end

local function unique_folder_destination(root)
  local base = download_directory()
  local name = safe_filename(basename(root))
  local candidate = base .. "/" .. name
  local index = 1
  while vlc.net.stat(candidate) do
    candidate = base .. "/" .. name .. " (" .. tostring(index) .. ")"
    index = index + 1
  end
  mkdir_p(candidate)
  return candidate
end

local function relative_folder_destination(batch, file)
  local path = string.gsub(file.path or "", "/", "\\")
  local prefix = batch.root == "" and "" or (batch.root .. "\\")
  local relative = prefix ~= "" and string.sub(path, 1, #prefix) == prefix
                   and string.sub(path, #prefix + 1) or basename(path)
  local parts = {}
  for part in string.gmatch(relative, "[^\\/]+") do
    parts[#parts + 1] = safe_filename(part)
  end
  return batch.destination .. "/" .. table.concat(parts, "/")
end

local function unique_destination(file)
  local dir = download_directory()
  local name = safe_filename(basename(file.path))
  local stem, ext = string.match(name, "^(.*)(%.[^%.]+)$")
  if not stem then stem, ext = name, "" end
  local candidate = dir .. "/" .. name
  local index = 1
  while vlc.net.stat(candidate) do
    candidate = dir .. "/" .. stem .. " (" .. tostring(index) .. ")" .. ext
    index = index + 1
  end
  return candidate
end

local function without_extension(name)
  local value = basename(name or "")
  return (string.match(value, "^(.*)%.[^%.]+$") or value)
end

local function infer_track_metadata(file)
  local path = string.gsub(file.path or "", "/", "\\")
  local album_path = dirname(path)
  local artist_path = dirname(album_path)
  return {
    title = without_extension(path),
    album = basename(album_path),
    artist = basename(artist_path),
  }
end

local function stream_cache_destination(file)
  local dir = app.cache_dir or download_directory()
  mkdir_p(dir)
  local stem = safe_filename(without_extension(file.path))
  local ext = string.match(basename(file.path or ""), "(%.[^%.]+)$") or ".cache"
  local candidate = dir .. "/" .. stem .. "-" .. tostring(next_token()) .. ext
  while vlc.net.stat(candidate) do
    candidate = dir .. "/" .. stem .. "-" .. tostring(next_token()) .. ext
  end
  return candidate
end

local function open_stream_listener()
  -- Port 0 is race-free and remains the preferred path. Mac OS X 10.2 can
  -- bind it, but its old getsockname path does not expose the selected port
  -- through the Lua listener userdata. Close that unusable listener and bind
  -- the first free loopback-only fallback port instead.
  local ok, listener = pcall(vlc.net.listen_tcp, "127.0.0.1", 0)
  if ok and listener then
    if listener.port then
      local got_port, port = pcall(function() return listener:port() end)
      port = got_port and tonumber(port) or nil
      if port and port > 0 then return listener, port end
    end
    pcall(function() listener:close() end)
  end
  for port = STREAM_PORT_FIRST, STREAM_PORT_LAST do
    local bound, fallback = pcall(vlc.net.listen_tcp, "127.0.0.1", port)
    if bound and fallback then return fallback, port end
  end
  return nil, nil
end

local function start_transfer(file, mode, destination, enqueue_only, retry_count)
  if app.transfer then set_message(lang.busy); return end
  if not file or not file.user or file.private or file.locked then
    set_message(lang.nothing_selected)
    return
  end
  local transfer = { user = file.user, path = file.path, size = file.size,
                     mode = mode, state = "queued", got = 0, buffer = "",
                     enqueue_only = enqueue_only and true or false,
                     retry_count = retry_count or 0, file_info = file }
  if mode == "download" then
    transfer.destination = destination or unique_destination(file)
  else
    local listener, port = open_stream_listener()
    if not listener or not port then set_message(lang.needs_core); return end
    local metadata = infer_track_metadata(file)
    transfer.proxy_listener, transfer.proxy_port = listener, port
    transfer.proxy_uri = "tcp://127.0.0.1:" .. tostring(port)
    transfer.destination = stream_cache_destination(file)
    transfer.title, transfer.album, transfer.artist = metadata.title,
      metadata.album, metadata.artist
    transfer.duration = file.duration
    transfer.serve_offset, transfer.serve_buffer = 0, ""
  end
  app.transfer = transfer
  request_peer(file.user, 43, pstr(file.path))
  request_peer(file.user, 51, pstr(file.path))
  transfer_status()
  arm_tick()
  return true
end

local function queue_transfer(file, mode, destination, enqueue_only)
  if not file or not file.user or file.private or file.locked then return false end
  app.transfer_queue[#app.transfer_queue + 1] = {
    file = file, mode = mode, destination = destination,
    enqueue_only = enqueue_only and true or false, retry_count = 0,
  }
  start_next_queued_transfer()
  if app.view == "transfers" then refresh_transfers() end
  arm_tick()
  return true
end

start_next_queued_transfer = function()
  if app.transfer or app.folder_batch or app.folder_request then return end
  while #app.transfer_queue > 0 do
    local queued = table.remove(app.transfer_queue, 1)
    if start_transfer(queued.file, queued.mode, queued.destination,
                      queued.enqueue_only, queued.retry_count) then
      return
    end
  end
end

function start_next_folder_file()
  local batch = app.folder_batch
  if not batch or app.transfer then return end
  batch.index = batch.index + 1
  if batch.index > batch.total then
    app.folder_batch = nil
    set_message(string.format(lang.folder_download_complete, batch.completed,
                              batch.failed, batch.destination))
    start_next_queued_transfer()
    return
  end

  local file = batch.files[batch.index]
  local destination = relative_folder_destination(batch, file)
  local parent = string.match(destination, "^(.*)/[^/]*$")
  if parent then mkdir_p(parent) end
  start_transfer(file, "download", destination)
end

function begin_folder_download(username, root, shares)
  if app.transfer or app.folder_batch then set_message(lang.busy); return end
  local files = collect_folder_files(shares, root, username)
  if #files == 0 then set_message(lang.folder_empty); return end
  app.folder_batch = {
    user = username, root = root, files = files, index = 0,
    total = #files, completed = 0, failed = 0,
    destination = unique_folder_destination(root),
  }
  start_next_folder_file()
end

function click_play()
  local rows, files = selected_rows(), {}
  for _, row in ipairs(rows) do
    if row.kind == "file" then files[#files + 1] = row.file end
  end
  if #files == 0 then set_message(lang.nothing_selected); return end
  for index, file in ipairs(files) do
    queue_transfer(file, "stream", nil, index > 1)
  end
  set_message(string.format(lang.files_queued, #files))
end

function click_download()
  local count = 0
  for _, row in ipairs(selected_rows()) do
    if row.kind == "file" and queue_transfer(row.file, "download") then
      count = count + 1
    end
  end
  if count == 0 then set_message(lang.nothing_selected); return end
  set_message(string.format(lang.downloads_queued, count))
end

function click_enqueue()
  local count = 0
  for _, row in ipairs(selected_rows()) do
    if row.kind == "file" and queue_transfer(row.file, "stream", nil, true) then
      count = count + 1
    end
  end
  if count == 0 then set_message(lang.nothing_selected); return end
  set_message(string.format(lang.files_queued, count))
end

function click_download_folder()
  if app.transfer or app.folder_batch or app.folder_request then
    set_message(lang.busy)
    return
  end
  local row = selected_row()
  if not row or (row.kind ~= "file" and row.kind ~= "folder") then
    set_message(lang.nothing_selected)
    return
  end

  local root = row.kind == "folder" and row.path or dirname(row.file.path)
  local user = user_state(app.view_user)
  if app.view_limited and user.shares_loading then
    app.folder_request = { user = user.username, path = root }
    set_message(lang.loading_folder_download)
    return
  end
  local shares = app.view_limited and combined_user_shares(user)
                                  or user.shares
  if shares_cover_folder(shares, root) then
    begin_folder_download(user.username, root, shares)
    return
  end

  -- The selected row can come from the instant search-result fallback while
  -- its FolderContentsResponse is still in flight.  Ask for that exact folder
  -- and start the batch as soon as the recursive response arrives.
  app.folder_request = { user = user.username, path = root }
  request_user_folder(user.username, root, true)
  set_message(lang.loading_folder_download)
end

function click_cancel_transfer()
  local had_work = app.transfer or app.folder_batch or app.folder_request
                   or #app.transfer_queue > 0
  app.transfer_queue = {}
  app.folder_batch = nil
  app.folder_request = nil
  cancel_transfer(true)
  if app.view == "user" then
    refresh_user_view()
  elseif app.view == "transfers" then
    refresh_transfers()
  end
  if had_work then set_message(lang.transfers_cancelled) end
end

function click_cancel_selected_transfers()
  if app.view ~= "transfers" or not ui.list then return end
  local selected = selected_widget_rows(ui.list, app.transfer_rows)
  if #selected == 0 then set_message(lang.select_transfer); return end

  local cancel_active, cancelled = false, 0
  local queued_refs, folder_indexes = {}, {}
  for _, row in ipairs(selected) do
    if row.kind == "active" then
      cancel_active = true
    elseif row.kind == "queued" then
      queued_refs[row.ref] = true
    elseif row.kind == "folder" then
      folder_indexes[#folder_indexes + 1] = row.extra
    end
  end

  for index = #app.transfer_queue, 1, -1 do
    if queued_refs[app.transfer_queue[index]] then
      table.remove(app.transfer_queue, index)
      cancelled = cancelled + 1
    end
  end
  table.sort(folder_indexes, function(a, b) return a > b end)
  if app.folder_batch then
    for _, index in ipairs(folder_indexes) do
      if index > app.folder_batch.index and index <= #app.folder_batch.files then
        table.remove(app.folder_batch.files, index)
        app.folder_batch.total = app.folder_batch.total - 1
        cancelled = cancelled + 1
      end
    end
  end

  if cancel_active then
    cancelled = cancelled + 1
    local batch = app.folder_batch
    cancel_transfer(true)
    if batch then
      batch.failed = batch.failed + 1
      start_next_folder_file()
    else
      start_next_queued_transfer()
    end
  elseif not app.transfer then
    if app.folder_batch then start_next_folder_file()
    else start_next_queued_transfer() end
  end

  refresh_transfers()
  if cancelled > 0 then
    set_message(string.format(lang.selected_transfers_cancelled, cancelled))
  else
    set_message(lang.no_cancellable_transfers)
  end
end

function click_remove_completed_transfers()
  if app.view ~= "transfers" or not ui.list then return end
  local selected = selected_widget_rows(ui.list, app.transfer_rows)
  if #selected == 0 then set_message(lang.select_transfer); return end

  local remove, count = {}, 0
  for _, row in ipairs(selected) do
    if row.kind == "complete" then remove[row.ref] = true end
  end
  for index = #app.transfer_history, 1, -1 do
    if remove[app.transfer_history[index]] then
      table.remove(app.transfer_history, index)
      count = count + 1
    end
  end
  refresh_transfers()
  if count > 0 then
    set_message(string.format(lang.completed_transfers_removed, count))
  else
    set_message(lang.no_completed_transfers)
  end
end

function click_choose_download_dir()
  if folder_picker:busy() then set_message(lang.folder_picker_busy); return end
  app.download_dir = trim(ui.download_dir and ui.download_dir:get_text()
                          or app.download_dir or "")
  local started = folder_picker:open(lang.folder_picker_prompt,
                                     app.download_dir)
  if started and folder_picker:busy() then
    set_message(lang.folder_picker_opening)
    arm_tick()
  elseif started then
    -- The native Windows picker completes synchronously and its callback has
    -- already published the selected/cancelled status.
  else set_message(lang.folder_picker_unavailable) end
end

local function show_connect()
  close_dialog()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(620, 0)
  dlg:add_label(lang.account, 1, 1, 3, 1)
  dlg:add_label(lang.username, 1, 2, 1, 1)
  ui.username = dlg:add_text_input(app.username or "", 2, 2, 2, 1, click_connect)
  dlg:add_label(lang.password, 1, 3, 1, 1)
  ui.password = dlg:add_password(app.password or "", 2, 3, 2, 1, click_connect)
  dlg:add_label(lang.listen_port, 1, 4, 1, 1)
  ui.port = dlg:add_text_input(tostring(app.listen_port), 2, 4, 2, 1, click_connect)
  dlg:add_label(lang.port_hint, 1, 5, 3, 1)
  ui.upnp = dlg:add_check_box(lang.upnp, app.upnp_enabled, 1, 6, 3, 1)
  dlg:add_label(lang.upnp_hint, 1, 7, 3, 1)
  ui.remember = dlg:add_check_box(lang.remember, app.remember, 1, 8, 3, 1)
  dlg:add_button(lang.forget, click_forget, 1, 9, 1, 1)
  dlg:add_button(lang.connect, click_connect, 2, 9, 2, 1)
  ui.message = dlg:add_label("", 1, 10, 3, 1)
  dlg:add_label(lang.privacy, 1, 11, 3, 1)
  dlg:show()
  if app.secret_plain then set_message(lang.saved_plain) end
end

function click_forget()
  if have_keystore() then
    vlc.keystore.remove(keystore_service(), app.username or "user")
  end
  app.username, app.password, app.remember = "", "", false
  save_settings()
  ui.username:set_text("")
  ui.password:set_text("")
  ui.remember:set_checked(false)
end

function click_connect()
  local raw_username = ui.username:get_text() or ""
  local username = trim(raw_username)
  local password = ui.password:get_text() or ""
  local port = tonumber(trim(ui.port:get_text()))
  local upnp_enabled = ui.upnp:get_checked()
  if username == "" or #username > 30 or username ~= raw_username
     or string.find(username, "[^ -~]") or password == ""
     or not port or port < 1 or port > 65535 then
    set_message(lang.bad_fields)
    return
  end
  port = math.floor(port)
  set_message(lang.connecting)
  disconnect()

  local listener, actual_port = listen_on_requested_port(port)
  if not listener then
    set_message(string.format(lang.network_failed, "listening port unavailable"))
    return
  end
  local ok, fd = pcall(vlc.net.connect_tcp, SERVER_HOST, SERVER_PORT, 10000)
  if not ok or not fd or fd < 0 then
    ok, fd = pcall(vlc.net.connect_tcp, SERVER_IPV4_FALLBACK,
                   SERVER_PORT, 10000)
  end
  if not ok or not fd or fd < 0 then
    pcall(function() listener:close() end)
    set_message(string.format(lang.network_failed, "server connection failed"))
    return
  end
  local hash = vlc.strings.md5(username .. password)
  local payload = pstr(username) .. pstr(password) .. p32(CLIENT_MAJOR)
               .. pstr(hash) .. p32(CLIENT_MINOR)
  if not send_all(fd, server_frame(1, payload)) then
    close_fd(fd); pcall(function() listener:close() end)
    set_message(string.format(lang.network_failed, "login write failed"))
    return
  end
  local reply, err, leftover = read_login_reply(fd)
  if not reply then
    close_fd(fd); pcall(function() listener:close() end)
    set_message(string.format(lang.network_failed, err or lang.unknown))
    return
  end
  local login, reason = parse_login(reply)
  if not login then
    close_fd(fd); pcall(function() listener:close() end)
    set_message(string.format(lang.login_failed, reason or lang.unknown))
    return
  end

  app.username, app.password = username, password
  app.listen_port, app.remember = actual_port, ui.remember:get_checked()
  app.upnp_enabled = upnp_enabled
  app.listener = listener
  app.server = { fd = fd, buffer = leftover or "" }
  app.connected, app.stopping = true, false
  app.last_ping = os.time()
  server_send(2, p32(actual_port))
  server_send(28, p32(2))
  server_send(35, p32(0) .. p32(0))
  if #app.server.buffer > 0 then parse_server_frames() end
  if not app.connected then return end
  local upnp_notice = nil
  if app.upnp_enabled then
    set_message(lang.upnp_opening)
    local mapping, upnp_error = open_upnp_mapping(actual_port)
    app.upnp_mapping = mapping
    if mapping then
      upnp_notice = string.format(lang.upnp_opened, actual_port)
    else
      upnp_notice = string.format(lang.upnp_failed, upnp_error or lang.unknown)
    end
  end
  save_settings()
  show_search()
  if app.secret_plain then set_message(lang.saved_plain)
  elseif upnp_notice then set_message(upnp_notice) end
  arm_tick()
end

function activate()
  load_lang()
  json = require("dkjson")
  math.randomseed(os.time())
  app.token = math.random(1000, 4000000)
  load_settings()
  local home = vlc.config and vlc.config.homedir and vlc.config.homedir() or "."
  local old_default = home .. "/Downloads"
  if not app.download_dir or app.download_dir == ""
     or app.download_dir == old_default then
    app.download_dir = old_default .. "/PowerVLC Soulseek"
  end
  local cache = vlc.config and vlc.config.cachedir and vlc.config.cachedir() or home
  folder_picker = require("pvlc_folder_picker").new("soulseek", {
    done=function(path, reason)
      if path then
        app.download_dir = path
        if ui.download_dir then ui.download_dir:set_text(path) end
        save_settings()
        set_message(string.format(lang.folder_selected, path))
      elseif reason == "cancelled" then
        set_message(lang.folder_picker_cancelled)
      else
        set_message(lang.folder_picker_unavailable)
      end
    end,
  })
  app.cache_dir = cache .. "/powervlc-soulseek-streams"
  purge_stale_stream_files()
  if not vlc.net or not vlc.net.poll or not vlc.net.listen_tcp
     or not vlc.strings or not vlc.strings.inflate then
    show_connect()
    set_message(lang.needs_core)
    return
  end
  show_connect()
end

function deactivate()
  app.stopping = true
  if folder_picker then folder_picker:close() end
  disconnect()
  cleanup_stream_caches(true)
  close_dialog()
end

function close()
  vlc.deactivate()
end

if POWERVLC_SOULSEEK_TEST then
  soulseek_test = {
    p32 = p32,
    p64 = p64,
    pstr = pstr,
    reader = reader,
    u32 = u32,
    u64 = u64,
    ustr = ustr,
    parse_search_response = parse_search_response,
    parse_share_response = parse_share_response,
    parse_folder_response = parse_folder_response,
    merge_share_sources = merge_share_sources,
    combined_user_shares = combined_user_shares,
    parse_user_info = parse_user_info,
    profile_html = profile_html,
    filter_user_items = filter_user_items,
    immediate_children = immediate_children,
    collect_folder_files = collect_folder_files,
    infer_track_metadata = infer_track_metadata,
    playlist_contains_path = playlist_contains_path,
    playlist_item_id = playlist_item_id,
    discard_transfer_requests = discard_transfer_requests,
    selected_search_users = selected_search_users,
    resolve_control_url = resolve_control_url,
    open_upnp_mapping = open_upnp_mapping,
    soap_request = soap_request,
    server_frame = server_frame,
    peer_frame = peer_frame,
    init_frame = init_frame,
    has_flag = has_flag,
    open_stream_listener = open_stream_listener,
    serve_stream_client = serve_stream_client,
    stream_start_ready = stream_start_ready,
    stream_initial_buffer = STREAM_INITIAL_BUFFER,
    sortable_size = sortable_size,
    sortable_speed = sortable_speed,
    sortable_quality = sortable_quality,
    quality_sort_value = quality_sort_value,
    app = app,
  }
end
