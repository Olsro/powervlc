--[[
 emule.lua: lightweight eD2k/Kad download controller for PowerVLC

 The network engine is a bundled, headless amuled.  This extension talks to
 it directly through the binary External Connections protocol on loopback;
 there is no HTTP service, web UI, chat UI or upload-management UI in between.

 Copyright (C) 2026 the PowerVLC team
 License: GPL-2.0-or-later
--]]

local ec = require("pvlc_ec")
local lang = {}

local TICK_MS = 100
local EC_PORT = 47122
local DEFAULT_ED2K_PORT = 46620
local LEGACY_DEFAULT_UDP_PORT = 46720
local DEFAULT_UDP_PORT = DEFAULT_ED2K_PORT
local MAX_RESULTS = 3000
local DEFAULT_SERVER_MET_URL = "http://upd.emule-security.org/server.met"
local DEFAULT_NODES_URL = "https://upd.emule-security.org/nodes.dat"
local LIST_PAD = "      "
local STREAM_CHUNK = 32768
local STREAM_BURST = 4
local STREAM_INITIAL_BUFFER = 1024 * 1024
local STREAM_CATEGORY = 1
local STREAM_CATEGORY_TITLE = "PowerVLC Streaming"

local dlg = nil
local ui = {}
local folder_picker = nil
local set_message, render
local app = {
  state_dir = nil, stream_cache_dir = nil,
  config_path = nil, log_path = nil, pid_path = nil,
  download_dir = nil, ec_hash = nil,
  server_met_url = DEFAULT_SERVER_MET_URL, server_update_pending = false,
  ec_port = EC_PORT, ed2k_port = DEFAULT_ED2K_PORT,
  udp_port = DEFAULT_UDP_PORT, upnp = true, engine = nil, launcher = nil,
  upnp_started = false, upnp_state = "pending", upnp_error = nil,
  upnp_gateway = nil, upnp_mappings = {}, upnp_recheck_done = false,
  launch_failures = 0, launch_probe_until = 0,
  bootstrap_done = false, bootstrap_warning = nil,
  configuration_passed = false, engine_enabled = false,
  engine_stop_pending = false, probe_existing = false,
  restart_pending = false,
  network_restart_pending = false,
  socket = nil, input = "", auth = "down",
  queue = {}, pending = nil, reconnect_at = 0, launched = false,
  stopping = false, view = "search", message = "",
  rendered_status = nil,
  -- The extension discovery pass deliberately replaces require() with a
  -- no-op. Keep descriptor scanning side-effect free; activation reloads the
  -- script with the real EC module before this value is ever consumed.
  search_query = "", search_kind = ec and ec.SEARCH.GLOBAL or 1,
  result_filter = "",
  search_active = false, search_progress = nil, search_results = {},
  result_order = {}, result_rows = {}, downloads = {}, download_order = {},
  download_history = {}, download_history_order = {},
  dismissed_downloads = {},
  download_rows = {}, last_search_poll = 0, last_queue_poll = 0,
  last_stats_poll = 0, last_render = 0, dirty = true, list_dirty = true,
  dl_speed = 0, ul_speed = 0, stream_request = nil, stream_queue = {}, streams = {},
  ed2k_id_state = "unknown", ed2k_id = nil,
  transfer_intent = {}, stream_category_ready = false,
  last_stream_cleanup = 0, cleanup_shutdown_pending = false,
}

function descriptor()
  return {
    title = "eMule",
    version = "1.0",
    author = "PowerVLC",
    url = "https://github.com/amule-org/amule",
    shortdesc = "eMule",
    description = "Search eD2k/Kad with a lightweight bundled amuled and "
               .. "download through a direct in-process EC connection. "
               .. "No web service and no chat interface.",
    capabilities = {},
  }
end

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("emule") })
end

local function now_ms()
  if vlc.misc and vlc.misc.mdate then return math.floor(vlc.misc.mdate() / 1000) end
  return os.time() * 1000
end

local function trim(value)
  return (string.gsub(value or "", "^%s*(.-)%s*$", "%1"))
end

local function file_exists(path)
  local file = path and io.open(path, "rb") or nil
  if file then file:close(); return true end
  return false
end

local function complete_file_exists(path, expected_size)
  local file = path and io.open(path, "rb") or nil
  if not file then return false end
  local size = file:seek("end")
  file:close()
  expected_size = tonumber(expected_size) or 0
  return size ~= nil and (expected_size <= 0 or size == expected_size)
end

local function copy_file(source, destination)
  local input = io.open(source, "rb")
  if not input then return false end
  local output = io.open(destination, "wb")
  if not output then input:close(); return false end
  local ok = true
  while true do
    local chunk = input:read(65536)
    if not chunk then break end
    if not output:write(chunk) then ok = false; break end
  end
  input:close()
  output:close()
  if not ok then pcall(os.remove, destination) end
  return ok
end

local function move_file(source, destination)
  if file_exists(destination) then return false end
  if os.rename(source, destination) then return true end
  if not copy_file(source, destination) then return false end
  pcall(os.remove, source)
  return true
end

local function mkdir_p(path)
  if not (vlc.io and vlc.io.mkdir) then return false end
  path = string.gsub(path or "", "\\", "/")
  local drive = string.match(path, "^([A-Za-z]:)/")
  local built = drive and (drive .. "/")
             or (string.sub(path, 1, 1) == "/" and "/" or "")
  if drive then path = string.sub(path, 4) end
  for part in string.gmatch(path, "[^/]+") do
    built = built .. part
    pcall(vlc.io.mkdir, built, "0755")
    built = built .. "/"
  end
  return true
end

local function format_size(value)
  value = tonumber(value) or 0
  if value >= 1073741824 then return string.format("%.2f GiB", value / 1073741824) end
  if value >= 1048576 then return string.format("%.1f MiB", value / 1048576) end
  if value >= 1024 then return string.format("%.0f KiB", value / 1024) end
  return string.format("%d B", value)
end

-- Extension list cells may append an invisible US separator followed by the
-- value used for sorting.  Keep the friendly binary-unit label on screen,
-- but order sizes by their byte count instead of lexicographically.
local function sortable_size(value)
  value = tonumber(value) or 0
  return format_size(value) .. string.char(31) .. string.format("%.0f", value)
end

local function format_speed(value)
  value = tonumber(value) or 0
  if value >= 1048576 then return string.format("%.1f MiB/s", value / 1048576) end
  if value >= 1024 then return string.format("%.0f KiB/s", value / 1024) end
  return string.format("%d B/s", value)
end

local function close_fd(fd)
  if fd and fd >= 0 then pcall(vlc.net.close, fd) end
end

-- Decode the RLE_Data representation used by EC_TAG_PARTFILE_GAP_STATUS.
-- Full queue requests reset amuled's differential encoder, so each value is
-- self-contained and does not need a previous UI frame.
local function decode_gap_status(raw)
  raw = raw or ""
  local bytes, i = {}, 1
  while i <= #raw do
    local value = string.byte(raw, i)
    if i <= #raw - 2 and string.byte(raw, i + 1) == value then
      local count = string.byte(raw, i + 2)
      for _ = 1, count do bytes[#bytes + 1] = value end
      i = i + 3
    else
      bytes[#bytes + 1] = value
      i = i + 1
    end
  end
  if #bytes % 8 ~= 0 then return nil end
  local count, values = #bytes / 8, {}
  for index = 1, count do
    local value, factor = 0, 1
    for byte = 0, 7 do
      value = value + bytes[index + byte * count] * factor
      factor = factor * 256
    end
    values[index] = value
  end
  local gaps = {}
  for index = 1, #values - 1, 2 do
    gaps[#gaps + 1] = { values[index], values[index + 1] }
  end
  return gaps
end

local function contiguous_prefix(size, gap_raw)
  local gaps = decode_gap_status(gap_raw)
  if not gaps then return 0 end
  local prefix = tonumber(size) or 0
  for _, gap in ipairs(gaps) do
    if gap[1] < prefix then prefix = gap[1] end
  end
  return math.max(0, prefix)
end

local function stream_start_ready(item)
  local size = tonumber(item and item.size) or 0
  local prefix = tonumber(item and item.prefix) or 0
  if item and (item.complete or size > 0 and prefix >= size) then return true end
  if size <= 0 then return prefix >= STREAM_INITIAL_BUFFER end
  return prefix >= math.min(size, STREAM_INITIAL_BUFFER)
end

local function percent(done, size)
  if not size or size <= 0 then return 0 end
  return math.min(100, math.floor((done or 0) * 1000 / size + 0.5) / 10)
end

local function ini_escape(value)
  value = tostring(value or "")
  return string.gsub(value, "[\r\n]", "")
end

local function amule_ini_escape(value)
  value = ini_escape(value)
  if package and package.config and package.config:sub(1, 1) == "\\" then
    -- wxFileConfig treats backslashes as escapes even on Windows. A literal
    -- C:\Users\... written once consequently became C:sers... in aMule and
    -- made the configured Temp/Incoming directories unusable.
    value = string.gsub(value, "\\", "\\\\")
  end
  return value
end

local function read_settings(path)
  local values = {}
  local file = io.open(path, "rb")
  if not file then return values end
  for line in file:lines() do
    local key, value = string.match(line, "^([%w_]+)=(.*)$")
    if key then values[key] = value end
  end
  file:close()
  return values
end

local function valid_port(value)
  local text = trim(tostring(value or ""))
  if not string.match(text, "^%d+$") then return nil end
  local port = tonumber(text)
  if not port or port < 1024 or port > 65535 then return nil end
  return math.floor(port)
end

local function engine_requested()
  return app.configuration_passed and app.engine_enabled
end

local function write_settings()
  local file = io.open(app.state_dir .. "/powervlc.conf", "wb")
  if not file then return false end
  file:write("download_dir=", ini_escape(app.download_dir), "\n")
  file:write("ec_hash=", ini_escape(app.ec_hash), "\n")
  file:write("ec_port=", tostring(app.ec_port), "\n")
  file:write("upnp=", app.upnp and "1" or "0", "\n")
  file:write("ed2k_port=", tostring(app.ed2k_port), "\n")
  file:write("udp_port=", tostring(app.udp_port), "\n")
  file:write("configuration_passed=", app.configuration_passed and "1" or "0", "\n")
  file:write("engine_enabled=", app.engine_enabled and "1" or "0", "\n")
  file:write("server_met_url=", ini_escape(app.server_met_url), "\n")
  file:close()
  return true
end

local function have_direct_upnp()
  return vlc.net and vlc.net.upnp_discover and vlc.http
     and vlc.http.get and vlc.http.post
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
  return xml_unescape(string.match(block or "", "<" .. name
    .. "[^>]*>%s*(.-)%s*</" .. name .. ">"))
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

local function upnp_soap(gateway, action, arguments)
  local fields = {}
  for _, item in ipairs(arguments or {}) do
    fields[#fields + 1] = "<" .. item[1] .. ">" .. tostring(item[2] or "")
                       .. "</" .. item[1] .. ">"
  end
  local body = '<?xml version="1.0"?>'
    .. '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    .. 's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    .. '<s:Body><u:' .. action .. ' xmlns:u="' .. gateway.service .. '">'
    .. table.concat(fields) .. '</u:' .. action .. '></s:Body></s:Envelope>'
  local ok, status, response = pcall(vlc.http.post, gateway.control, body,
    'text/xml; charset="utf-8"', nil,
    { SOAPAction = '"' .. gateway.service .. '#' .. action .. '"' })
  if not ok then return false, tostring(status) end
  if status == 200 then return true end
  return false, xml_text(response, "errorDescription")
             or xml_text(response, "errorCode") or tostring(status)
end

local function discover_upnp_gateway()
  if not have_direct_upnp() then return nil, lang.upnp_unavailable end
  local ok, location, local_ip = pcall(vlc.net.upnp_discover, 3000)
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
    -- Accept IGD v1 and v2. aMule 3.0.1's built-in client rejects the
    -- WANIPConnection:2 service advertised first by current Liveboxes.
    if candidate and (string.find(candidate, ":WANIPConnection:", 1, true)
                   or string.find(candidate, ":WANPPPConnection:", 1, true)) then
      service, control = candidate, xml_text(block, "controlURL")
      break
    end
  end
  local resolved = resolve_control_url(location, xml_text(description, "URLBase"),
                                       control)
  if not service or not resolved then return nil, lang.upnp_service_missing end
  return { service = service, control = resolved, local_ip = local_ip }
end

local function add_upnp_mapping(gateway, port, protocol)
  local arguments = {
    { "NewRemoteHost", "" }, { "NewExternalPort", port },
    { "NewProtocol", protocol }, { "NewInternalPort", port },
    { "NewInternalClient", gateway.local_ip }, { "NewEnabled", 1 },
    { "NewPortMappingDescription", "PowerVLC eMule" },
    { "NewLeaseDuration", 0 },
  }
  local added, err = upnp_soap(gateway, "AddPortMapping", arguments)
  if not added and (string.find(tostring(err), "718", 1, true)
                 or string.find(tostring(err), "ConflictInMappingEntry", 1, true)) then
    -- This is normally our persistent mapping from an earlier extension
    -- session. Replace it so a DHCP address change cannot leave it stale.
    upnp_soap(gateway, "DeletePortMapping", {
      { "NewRemoteHost", "" }, { "NewExternalPort", port },
      { "NewProtocol", protocol },
    })
    added, err = upnp_soap(gateway, "AddPortMapping", arguments)
  end
  return added, err
end

local function delete_upnp_mapping(gateway, port, protocol)
  if not gateway or not port then return end
  pcall(upnp_soap, gateway, "DeletePortMapping", {
    { "NewRemoteHost", "" }, { "NewExternalPort", port },
    { "NewProtocol", protocol },
  })
end

local function close_upnp_mappings()
  local gateway, mappings = app.upnp_gateway, app.upnp_mappings or {}
  if gateway then
    delete_upnp_mapping(gateway, mappings.tcp, "TCP")
    delete_upnp_mapping(gateway, mappings.udp, "UDP")
  end
  app.upnp_gateway, app.upnp_mappings = nil, {}
end

local function setup_upnp()
  if app.upnp_started then return end
  app.upnp_started = true
  if not app.upnp then app.upnp_state = "disabled"; return end
  if not have_direct_upnp() then
    -- The bundled daemon deliberately has no UPnP implementation. Keeping
    -- one owner prevents duplicate mappings and avoids a second SOAP stack.
    app.upnp_state, app.upnp_error = "failed", lang.upnp_unavailable
    app.dirty = true
    return
  end
  local gateway, err = discover_upnp_gateway()
  if not gateway then
    app.upnp_state, app.upnp_error = "failed", err
    app.dirty = true
    return
  end
  app.upnp_gateway = gateway
  local tcp, tcp_error = add_upnp_mapping(gateway, app.ed2k_port, "TCP")
  local udp, udp_error = add_upnp_mapping(gateway, app.udp_port, "UDP")
  app.upnp_mappings = { tcp = tcp and app.ed2k_port or nil,
                        udp = udp and app.udp_port or nil }
  if tcp and udp then
    app.upnp_state, app.upnp_error = "open", nil
  elseif tcp then
    app.upnp_state, app.upnp_error = "partial", udp_error
  else
    app.upnp_state, app.upnp_error = "failed", tcp_error or udp_error
  end
  app.dirty = true
end

-- Preserve daemon-owned preferences and only replace PowerVLC's small set.
local function update_ini(path, changes)
  local sections, order, current = {}, {}, ""
  sections[current] = { lines = {}, keys = {} }
  local file = io.open(path, "rb")
  if file then
    for line in file:lines() do
      local section = string.match(line, "^%[([^%]]+)%]%s*$")
      if section then
        current = section
        if not sections[current] then
          sections[current] = { lines = {}, keys = {} }
          order[#order + 1] = current
        end
      else
        local key = string.match(line, "^([^=;#]+)=")
        if key then key = trim(key); sections[current].keys[key] = #sections[current].lines + 1 end
        sections[current].lines[#sections[current].lines + 1] = line
      end
    end
    file:close()
  end
  for section, values in pairs(changes) do
    if not sections[section] then
      sections[section] = { lines = {}, keys = {} }
      order[#order + 1] = section
    end
    local bucket = sections[section]
    for key, value in pairs(values) do
      local line = key .. "=" .. amule_ini_escape(value)
      local index = bucket.keys[key]
      if index then bucket.lines[index] = line
      else bucket.lines[#bucket.lines + 1] = line; bucket.keys[key] = #bucket.lines end
    end
  end
  local out = io.open(path, "wb")
  if not out then return false end
  for _, line in ipairs(sections[""].lines) do out:write(line, "\n") end
  for _, section in ipairs(order) do
    out:write("[", section, "]\n")
    for _, line in ipairs(sections[section].lines) do out:write(line, "\n") end
  end
  out:close()
  return true
end

local function configure_daemon()
  mkdir_p(app.state_dir)
  mkdir_p(app.state_dir .. "/Temp")
  mkdir_p(app.stream_cache_dir)
  mkdir_p(app.download_dir)
  return update_ini(app.config_path, {
    General = { Count = "1" },
    ["Cat#1"] = {
      Title = STREAM_CATEGORY_TITLE, Incoming = app.stream_cache_dir,
      Comment = "Temporary progressive playback cache",
      Color = "0", Priority = "0",
    },
    eMule = {
      Nick = "PowerVLC", MaxDownload = "0", MaxUpload = "16",
      SlotAllocation = "2", Port = tostring(app.ed2k_port), UDPEnable = "1",
      UDPPort = tostring(app.udp_port),
      -- PowerVLC is the sole UPnP owner. The bundled daemon is built without
      -- its legacy client, and this remains off even with an external engine.
      UPnPEnabled = "0",
      MaxSourcesPerFile = "150", MaxConnections = "120",
      MaxConnectionsPerFiveSeconds = "10", ConnectToKad = "1",
      ConnectToED2K = "1", Autoconnect = "1", Reconnect = "1",
      IncomingDir = app.download_dir, TempDir = app.state_dir .. "/Temp",
      PreviewPrio = "1", AllocateFullFile = "0", CreateSparseFiles = "1",
      CheckDiskspace = "1", GeoIPEnabled = "0", Notifications = "0",
      Ed2kServersUrl = app.server_met_url,
      KadNodesUrl = DEFAULT_NODES_URL,
    },
    ExternalConnect = {
      AcceptExternalConnections = "1", ECAddress = "127.0.0.1",
      ECPort = tostring(app.ec_port), ECPassword = app.ec_hash,
      UPnPECEnabled = "0", UseSecIdent = "1",
    },
    PowerManagement = { PreventSleepWhileDownloading = "0" },
  })
end

-- Bootstrap through PowerVLC's own HTTP(S)/GnuTLS stack. The embedded daemon
-- deliberately contains no wxWebRequest/libcurl backend: duplicating a second
-- HTTP and TLS stack would cost both disk and memory on the machines this
-- extension targets. These files are only needed on first use; aMule then
-- maintains them itself from the eD2k/Kad networks.
local function download_bootstrap_file(name, url, force, staged)
  local path = app.state_dir .. "/" .. name .. (staged and ".download" or "")
  local function valid_existing_file()
    local file = io.open(path, "rb")
    if not file then return false end
    local header = file:read(1)
    local size = file:seek("end") or 0
    file:close()
    if name == "server.met" then
      local marker = header and string.byte(header) or -1
      return size > 5 and (marker == 0x0e or marker == 0xe0)
    end
    -- A current Kad contact record is much larger; this also rejects aMule's
    -- five-byte empty placeholder left by a first start without networking.
    return size > 32
  end
  if not force and valid_existing_file() then return true end
  if not (vlc.http and vlc.http.get) then return false, "HTTP unavailable" end

  set_message(string.format(lang.bootstrap_downloading, name))
  render(true)
  local ok, status, body = pcall(vlc.http.get, url)
  if not ok then return false, tostring(status) end
  local code = tonumber(status)
  if code == nil or code < 200 or code >= 300
     or type(body) ~= "string" or #body < 4 then
    return false, tostring(status)
  end

  local temporary = path .. ".part"
  local file = io.open(temporary, "wb")
  if not file then return false, "write failed" end
  local wrote = file:write(body)
  file:close()
  local moved = wrote and os.rename(temporary, path)
  if not moved and wrote and file_exists(path) then
    pcall(os.remove, path)
    moved = os.rename(temporary, path)
  end
  if not moved then
    pcall(os.remove, temporary)
    return false, "write failed"
  end
  return true
end

local function bootstrap_network()
  if app.bootstrap_done then return end
  app.bootstrap_done = true
  local failed = {}
  local files = {
    { "server.met", app.server_met_url },
    { "nodes.dat", DEFAULT_NODES_URL },
  }
  for _, item in ipairs(files) do
    local ok = download_bootstrap_file(item[1], item[2])
    if not ok then failed[#failed + 1] = item[1] end
  end
  if #failed > 0 then
    app.bootstrap_warning = string.format(lang.bootstrap_failed,
                                          table.concat(failed, ", "))
    set_message(app.bootstrap_warning)
  end
end

local function initialize_paths()
  local base = vlc.config and vlc.config.userdatadir and vlc.config.userdatadir() or "."
  local home = vlc.config and vlc.config.homedir and vlc.config.homedir() or "."
  app.state_dir = base .. "/emule"
  app.stream_cache_dir = app.state_dir .. "/StreamCache"
  mkdir_p(app.state_dir)
  local saved = read_settings(app.state_dir .. "/powervlc.conf")
  app.download_dir = trim(saved.download_dir or "")
  if app.download_dir == "" then app.download_dir = home .. "/Downloads/PowerVLC eMule" end
  app.ec_port = tonumber(saved.ec_port) or EC_PORT
  if app.ec_port < 1024 or app.ec_port > 65535 then app.ec_port = EC_PORT end
  app.ed2k_port = valid_port(saved.ed2k_port) or DEFAULT_ED2K_PORT
  if app.ed2k_port == app.ec_port then app.ed2k_port = DEFAULT_ED2K_PORT end
  app.udp_port = valid_port(saved.udp_port) or DEFAULT_UDP_PORT
  if saved.configuration_passed == nil
     and app.ed2k_port == DEFAULT_ED2K_PORT
     and app.udp_port == LEGACY_DEFAULT_UDP_PORT then
    app.udp_port = DEFAULT_UDP_PORT
  end
  app.configuration_passed = saved.configuration_passed == "1"
  app.engine_enabled = app.configuration_passed and saved.engine_enabled == "1"
  app.upnp = saved.upnp ~= "0"
  app.server_met_url = trim(saved.server_met_url or DEFAULT_SERVER_MET_URL)
  if not string.match(app.server_met_url, "^https?://") then
    app.server_met_url = DEFAULT_SERVER_MET_URL
  end
  app.server_update_pending = file_exists(app.state_dir .. "/server.met.download")
  app.ec_hash = saved.ec_hash
  if not app.ec_hash or #app.ec_hash ~= 32 then
    local seed = app.state_dir .. ":" .. tostring(now_ms()) .. ":PowerVLC"
    app.ec_hash = vlc.strings.md5(seed)
  end
  app.config_path = app.state_dir .. "/amule.conf"
  app.log_path = app.state_dir .. "/amuled.log"
  app.pid_path = app.state_dir .. "/amuled.pid"
  app.engine = vlc.config and vlc.config.helper
               and vlc.config.helper("emule-engine") or nil
  write_settings()
  configure_daemon()
end

-- Keep a small extension-side trace next to aMule's own log.  Finder does not
-- preserve PowerVLC's stderr on the old macOS releases, which otherwise makes
-- a failed helper launch indistinguishable from a button that was not clicked.
local function trace_engine(message)
  if not app.state_dir then return end
  local file = io.open(app.state_dir .. "/powervlc-extension.log", "ab")
  if not file then return end
  file:write(os.date("%Y-%m-%d %H:%M:%S"), " ", tostring(message), "\n")
  file:close()
end

set_message = function(message)
  message = message or ""
  if app.message == message then return end
  app.message = message
  app.dirty = true
end

local function close_socket()
  if app.socket then pcall(vlc.net.close, app.socket) end
  app.socket, app.input, app.pending = nil, "", nil
  app.auth = "down"
  app.queue = {}
end

local function send_all(data)
  if not app.socket then return false end
  local pos = 1
  while pos <= #data do
    local sent = vlc.net.send(app.socket, string.sub(data, pos))
    if not sent or sent <= 0 then return false end
    pos = pos + sent
  end
  return true
end

local function queue_request(kind, packet, data)
  app.queue[#app.queue + 1] = { kind = kind, packet = packet, data = data }
end

local function request_packet(kind, opcode, tags, data)
  queue_request(kind, ec.packet(opcode, tags), data)
end

local function request_download(item, for_stream)
  app.dismissed_downloads[item.hash] = nil
  if for_stream and app.transfer_intent[item.hash] ~= "download" then
    app.transfer_intent[item.hash] = "stream"
  elseif not for_stream then
    app.transfer_intent[item.hash] = "download"
  end
  request_packet(for_stream and "stream-download" or "download",
    ec.OP.DOWNLOAD_SEARCH_RESULT, {
      ec.hash(ec.TAG.PARTFILE, item.hash, {
        ec.integer(ec.TAG.PARTFILE_CAT,
                   for_stream and STREAM_CATEGORY or 0),
      }),
    }, item)
end

local function category_tag(index)
  return ec.integer(ec.TAG.CATEGORY, index, {
    ec.string(ec.TAG.CATEGORY_PATH, app.stream_cache_dir),
    ec.string(ec.TAG.CATEGORY_COMMENT,
              "Temporary progressive playback cache"),
    ec.integer(ec.TAG.CATEGORY_COLOR, 0),
    ec.integer(ec.TAG.CATEGORY_PRIO, 0),
    ec.string(ec.TAG.CATEGORY_TITLE, STREAM_CATEGORY_TITLE),
  })
end

local function find_tag_recursive(container, name, value)
  for _, tag in ipairs(container.tags or container.children or {}) do
    if tag.name == name and (value == nil or tag.value == value) then
      return tag
    end
    local found = find_tag_recursive(tag, name, value)
    if found then return found end
  end
  return nil
end

local function request_stream_categories()
  request_packet("stream-categories", ec.OP.GET_PREFERENCES, {
    ec.integer(ec.TAG.SELECT_PREFS, 1),
    ec.integer(ec.TAG.DETAIL_LEVEL, ec.DETAIL.FULL),
  })
end

local function begin_engine_session()
  request_stream_categories()
  request_packet("connect", ec.OP.CONNECT, {})
  if app.server_update_pending then
    request_packet("server-update", ec.OP.SERVER_UPDATE_FROM_URL,
      { ec.string(ec.TAG.SERVERS_UPDATE_URL, app.server_met_url) })
    app.server_update_pending = false
  end
end

local function child_value(tag, name, fallback)
  local value = ec.child(tag, name)
  if value then return value.value end
  return fallback
end

local function collect_search_tags(container, out)
  for _, tag in ipairs(container.tags or container.children or {}) do
    if tag.name == ec.TAG.SEARCHFILE then
      out[#out + 1] = tag
      collect_search_tags(tag, out)
    end
  end
end

local start_stream, complete_stream_request, queue_stream_request

local function remember_download(item)
  if not item or not item.hash then return end
  local remembered = app.download_history[item.hash]
  if not remembered then
    remembered = {}
    app.download_history[item.hash] = remembered
    app.download_history_order[#app.download_history_order + 1] = item.hash
  end
  remembered.hash = item.hash
  remembered.name = item.name or remembered.name or item.hash
  remembered.size = tonumber(item.size) or remembered.size or 0
  remembered.final_path = (app.download_dir or ".") .. "/" .. remembered.name
end

local function cache_path(item)
  return app.stream_cache_dir .. "/" .. (item.name or item.hash)
end

local function promote_download(item)
  if not item or not item.hash then return false end
  app.dismissed_downloads[item.hash] = nil
  app.transfer_intent[item.hash] = "download"
  remember_download(item)
  local remembered = app.download_history[item.hash]
  local source = cache_path(item)
  local destination = remembered.final_path
  mkdir_p(app.download_dir)

  if complete_file_exists(destination, item.size) then
    pcall(os.remove, source)
    if app.streams[item.hash] then
      app.streams[item.hash].final_path = destination
    end
    set_message(string.format(lang.download_already_present, destination))
    return true
  end
  if complete_file_exists(source, item.size) and move_file(source, destination) then
    if app.streams[item.hash] then
      app.streams[item.hash].final_path = destination
      app.streams[item.hash].complete = true
    end
    set_message(lang.download_promoted)
    app.last_queue_poll = 0
    return true
  end

  local active = app.downloads[item.hash]
  if active or (app.stream_request and app.stream_request.hash == item.hash) then
    request_packet("promote-download", ec.OP.PARTFILE_SET_CAT, {
      ec.hash(ec.TAG.PARTFILE, item.hash, {
        ec.integer(ec.TAG.PARTFILE_CAT, 0),
      }),
    }, item)
    if app.streams[item.hash] then
      app.streams[item.hash].final_path = destination
    end
    set_message(lang.download_promoting)
    return true
  end
  request_download(item, false)
  return true
end

local function parse_search_results(packet)
  local tags = {}
  local changed = false
  collect_search_tags(packet, tags)
  for _, tag in ipairs(tags) do
    local hash = child_value(tag, ec.TAG.PARTFILE_HASH)
    local name = child_value(tag, ec.TAG.PARTFILE_NAME)
    if hash and name and not app.search_results[hash] and #app.result_order < MAX_RESULTS then
      app.search_results[hash] = {
        hash = hash, ecid = tag.value, name = name,
        size = child_value(tag, ec.TAG.PARTFILE_SIZE_FULL, 0),
        sources = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT, 0),
        complete = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT_XFER, 0),
      }
      app.result_order[#app.result_order + 1] = hash
      changed = true
    elseif hash and app.search_results[hash] then
      local item = app.search_results[hash]
      local sources = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT, item.sources)
      local complete = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT_XFER, item.complete)
      if sources ~= item.sources or complete ~= item.complete then changed = true end
      item.sources, item.complete = sources, complete
    end
  end
  if changed then
    app.list_dirty = true
    app.dirty = true
  end
end

local function parse_downloads(packet)
  local fresh, order = {}, {}
  for _, tag in ipairs(packet.tags or {}) do
    if tag.name == ec.TAG.PARTFILE then
      local hash = child_value(tag, ec.TAG.PARTFILE_HASH)
      if hash then
        local gap = ec.child(tag, ec.TAG.PARTFILE_GAP_STATUS)
        local size = child_value(tag, ec.TAG.PARTFILE_SIZE_FULL, 0)
        local done = child_value(tag, ec.TAG.PARTFILE_SIZE_DONE, 0)
        local category = child_value(tag, ec.TAG.PARTFILE_CAT, 0)
        fresh[hash] = {
          hash = hash, name = child_value(tag, ec.TAG.PARTFILE_NAME, hash),
          partmet = child_value(tag, ec.TAG.PARTFILE_PARTMETID),
          size = size, done = done,
          transferred = child_value(tag, ec.TAG.PARTFILE_SIZE_XFER, 0),
          speed = child_value(tag, ec.TAG.PARTFILE_SPEED, 0),
          status = child_value(tag, ec.TAG.PARTFILE_STATUS, 0),
          sources = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT, 0),
          active = child_value(tag, ec.TAG.PARTFILE_SOURCE_COUNT_XFER, 0),
          category = category,
          prefix = done >= size and size
                   or contiguous_prefix(size, gap and gap.raw or nil),
        }
        local intent = app.transfer_intent[hash]
        if not intent then
          intent = category == STREAM_CATEGORY and "stream" or "download"
          app.transfer_intent[hash] = intent
        end
        if intent == "download" and not app.dismissed_downloads[hash] then
          remember_download(fresh[hash])
          order[#order + 1] = hash
        end
      end
    end
  end
  -- amuled removes a file from EC_OP_GET_DLOAD_QUEUE as soon as it is
  -- complete (and never adds it when the same final file already exists).
  -- Keep files requested during this extension session visible at 100%, so
  -- this view is also a short download history rather than only a snapshot
  -- of work still in progress.
  for _, hash in ipairs(app.download_history_order) do
    if not fresh[hash] then
      local remembered = app.download_history[hash]
      if remembered and complete_file_exists(remembered.final_path,
                                              remembered.size) then
        fresh[hash] = {
          hash = hash, name = remembered.name, size = remembered.size,
          done = remembered.size, transferred = remembered.size,
          speed = 0, status = 0, sources = 0, active = 0,
          prefix = remembered.size, complete = true,
          final_path = remembered.final_path,
        }
        order[#order + 1] = hash
      end
    end
  end
  app.downloads, app.download_order = fresh, order
  app.list_dirty = true
  for hash, stream in pairs(app.streams) do
    local item = fresh[hash]
    if item then
      stream.prefix = math.max(stream.prefix or 0, item.prefix or 0)
      stream.complete = item.done >= item.size and item.size > 0
      if item.partmet then
        stream.part_path = app.state_dir .. "/Temp/"
                         .. string.format("%03d.part", item.partmet)
      end
    elseif file_exists(stream.final_path) then
      stream.prefix, stream.complete = stream.size, true
    end
  end
  if app.stream_request then
    local item = fresh[app.stream_request.hash]
    if item and (item.partmet or item.complete) then
      if start_stream(item, app.stream_request.result) then
        complete_stream_request()
      end
    end
  end
  app.dirty = true
end

local function has_flag(value, flag)
  value, flag = math.floor(value or 0), math.floor(flag or 0)
  -- On Jaguar the poll compatibility constants are composite masks.  A
  -- ready descriptor reports one member bit, so look for any overlap rather
  -- than treating the whole mask as a single power of two.
  while value > 0 and flag > 0 do
    if value % 2 == 1 and flag % 2 == 1 then return true end
    value, flag = math.floor(value / 2), math.floor(flag / 2)
  end
  return false
end

local function parse_connection_state(packet)
  local connection = ec.child(packet, ec.TAG.CONNSTATE)
  if not connection then
    app.ed2k_id_state, app.ed2k_id = "unknown", nil
    return
  end
  local state = tonumber(connection.value) or 0
  if has_flag(state, 0x01) then
    local id = child_value(connection, ec.TAG.ED2K_ID)
    app.ed2k_id = tonumber(id)
    if app.ed2k_id then
      app.ed2k_id_state = app.ed2k_id < 16777216 and "low" or "high"
      if app.ed2k_id_state == "low" and app.upnp_mappings.tcp
         and not app.upnp_recheck_done then
        -- A detached daemon may already have logged into a server before
        -- PowerVLC repaired the mapping. Reconnect once to request a new ID.
        app.upnp_recheck_done = true
        request_packet("upnp-disconnect", ec.OP.DISCONNECT, {})
        request_packet("upnp-connect", ec.OP.CONNECT, {})
        set_message(lang.upnp_reconnecting)
      end
    else
      app.ed2k_id_state = "unknown"
    end
  elseif has_flag(state, 0x02) then
    app.ed2k_id_state, app.ed2k_id = "connecting", nil
  else
    app.ed2k_id_state, app.ed2k_id = "disconnected", nil
  end
end

local function add_listener_fds(listener, pollfds)
  if not listener then return end
  for _, fd in ipairs({ listener:fds() }) do pollfds[fd] = vlc.net.POLLIN end
end

local function listener_ready(listener, pollfds)
  if not listener then return false end
  for _, fd in ipairs({ listener:fds() }) do
    if has_flag(pollfds[fd], vlc.net.POLLIN) then return true end
  end
  return false
end

local function close_stream_client(stream)
  close_fd(stream.proxy_fd)
  if stream.file then pcall(function() stream.file:close() end) end
  stream.proxy_fd, stream.file = nil, nil
  stream.offset, stream.buffer = 0, ""
end

local function destroy_stream(hash)
  local stream = app.streams[hash]
  if not stream then return end
  close_stream_client(stream)
  if stream.listener then pcall(function() stream.listener:close() end) end
  app.streams[hash] = nil
  if app.transfer_intent[hash] == "stream" then
    if app.auth == "ready" then
      request_packet("discard-stream", ec.OP.PARTFILE_DELETE,
                     { ec.hash(ec.TAG.PARTFILE, hash) })
    end
    pcall(os.remove, stream.final_path)
    app.transfer_intent[hash] = nil
    app.downloads[hash] = nil
  end
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

local function current_stream()
  if not (vlc.playlist and vlc.playlist.current and vlc.playlist.get) then
    return nil
  end
  local ok_id, id = pcall(vlc.playlist.current)
  if not ok_id or not id then return nil end
  local ok_item, item = pcall(vlc.playlist.get, id, false)
  if not ok_item or type(item) ~= "table" then return nil end
  for hash, stream in pairs(app.streams) do
    if playlist_contains_path(item, stream.uri) then return hash, stream end
  end
  return nil
end

local function cleanup_streams(force)
  local now = os.time()
  if not force and now - app.last_stream_cleanup < 3 then return end
  app.last_stream_cleanup = now
  local playlist
  if not force and vlc.playlist and vlc.playlist.get then
    local ok, value = pcall(vlc.playlist.get, nil, false)
    if ok and type(value) == "table" then playlist = value end
  end
  for hash, stream in pairs(app.streams) do
    if force or (playlist and now - stream.created >= 5
                 and not playlist_contains_path(playlist, stream.uri)) then
      destroy_stream(hash)
    end
  end
  if not force and app.view == "hidden" and not next(app.streams) then
    app.cleanup_shutdown_pending = true
  end
  if not force and app.cleanup_shutdown_pending and not next(app.streams)
     and not app.stream_request and #app.stream_queue == 0
     and #app.queue == 0 and not app.pending
     and vlc.deactivate then
    app.cleanup_shutdown_pending = false
    deactivate()
    vlc.deactivate()
  end
end

local function infer_metadata(name)
  local base = string.match(name or "", "^(.*)%.[^%.]+$") or name or "eMule"
  local artist, album, title = string.match(base,
    "^(.-)%s+%-%s+(.-)%s+%-%s+(.+)$")
  if title then return title, artist, album end
  artist, title = string.match(base, "^(.-)%s+%-%s+(.+)$")
  return title or base, artist, nil
end

local function add_stream_to_playlist(stream, item, enqueue_only)
  local playlist_item = {
    path = stream.uri, name = stream.title, title = stream.title,
    artist = stream.artist, album = stream.album,
    meta = { ["eD2k hash"] = item.hash, ["eMule file"] = item.name },
  }
  if enqueue_only and vlc.playlist.enqueue then
    vlc.playlist.enqueue({ playlist_item })
  else
    vlc.playlist.add({ playlist_item })
  end
end

start_stream = function(item, result, enqueue_only)
  if enqueue_only == nil and app.stream_request
     and app.stream_request.hash == item.hash then
    enqueue_only = app.stream_request.enqueue_only
  end
  local existing = app.streams[item.hash]
  if existing then
    -- This is an explicit user action. Add the cached relay again even when
    -- an older occurrence is still in playlist history; otherwise pressing
    -- Stream on a previously played result appears to do nothing.
    add_stream_to_playlist(existing, item, enqueue_only)
    return true
  end
  local part_path = item.partmet and (app.state_dir .. "/Temp/"
                    .. string.format("%03d.part", item.partmet)) or nil
  local persistent_path = app.download_dir .. "/" .. item.name
  local temporary_path = cache_path(item)
  local persistent = app.transfer_intent[item.hash] == "download"
  local final_path = persistent and persistent_path or temporary_path
  if complete_file_exists(persistent_path, item.size) then
    final_path, persistent = persistent_path, true
    app.transfer_intent[item.hash] = "download"
  end
  local has_part = part_path and file_exists(part_path)
  local has_final = complete_file_exists(final_path, item.size)
  if not has_part and not has_final then return false end
  -- Do not hand VLC an empty TCP source. Its first input attempt times out
  -- before aMule has downloaded the beginning, leaving a stopped playlist
  -- item that only works after the user starts it again. Keep the download
  -- request pending and create the playlist item once a useful contiguous
  -- prefix is already readable from disk.
  if not has_final and not stream_start_ready(item) then
    set_message(lang.stream_prebuffering)
    return false
  end
  local ok, listener = pcall(vlc.net.listen_tcp, "127.0.0.1", 0)
  if not ok or not listener or not listener.port then
    set_message(lang.stream_unavailable); return false
  end
  local port = listener:port()
  if not port then pcall(function() listener:close() end); return false end
  local title, artist, album = infer_metadata((result and result.name) or item.name)
  local stream = {
    hash = item.hash, name = item.name, title = title, artist = artist,
    album = album,
    size = item.size, prefix = has_final and item.size or (item.prefix or 0),
    part_path = part_path, final_path = final_path, complete = has_final,
    listener = listener, uri = "tcp://127.0.0.1:" .. tostring(port),
    offset = 0, buffer = "", created = os.time(),
  }
  app.streams[item.hash] = stream
  set_message(lang.stream_buffering)
  add_stream_to_playlist(stream, item, enqueue_only)
  return true
end

local function begin_stream_request(request)
  local item = request.result
  app.stream_request = request
  if app.streams[item.hash] then
    if start_stream(item, item, request.enqueue_only) then
      complete_stream_request()
    end
  elseif app.downloads[item.hash] then
    local download = app.downloads[item.hash]
    if start_stream(download, item, request.enqueue_only) then
      complete_stream_request()
    end
  elseif complete_file_exists(cache_path(item), item.size)
      or complete_file_exists(app.download_dir .. "/" .. item.name,
                              item.size) then
    local complete = {
      hash = item.hash, name = item.name, size = item.size,
      done = item.size, prefix = item.size, complete = true,
    }
    if start_stream(complete, item, request.enqueue_only) then
      complete_stream_request()
    end
  else
    request_download(item, true)
  end
end

complete_stream_request = function()
  app.stream_request = nil
  if #app.stream_queue > 0 then
    begin_stream_request(table.remove(app.stream_queue, 1))
  end
end

queue_stream_request = function(item, enqueue_only)
  if not item or not item.hash then return false end
  local request = { hash = item.hash, result = item,
                    enqueue_only = enqueue_only and true or false }
  if app.stream_request then
    app.stream_queue[#app.stream_queue + 1] = request
  else
    begin_stream_request(request)
  end
  return true
end

local function accept_stream(stream)
  if stream.proxy_fd then return end
  local fd = stream.listener:accept()
  if not fd or fd < 0 then return end
  local path = file_exists(stream.part_path) and stream.part_path or stream.final_path
  local file = vlc.io.open(path, "rb")
  if not file then close_fd(fd); return end
  stream.proxy_fd, stream.file = fd, file
  stream.offset, stream.buffer = 0, ""
end

local function serve_stream(stream)
  if not stream.proxy_fd or not stream.file then return end
  for _ = 1, STREAM_BURST do
    if stream.buffer == "" and stream.offset < (stream.prefix or 0) then
      stream.file:seek("set", stream.offset)
      stream.buffer = stream.file:read(math.min(STREAM_CHUNK,
        (stream.prefix or 0) - stream.offset)) or ""
    end
    if stream.buffer == "" then break end
    local sent = vlc.net.send(stream.proxy_fd, stream.buffer)
    -- The local player socket is non-blocking.  Keep the pending bytes when
    -- its send buffer is temporarily full and retry after the next POLLOUT.
    if not sent or sent <= 0 then return end
    stream.offset = stream.offset + sent
    stream.buffer = string.sub(stream.buffer, sent + 1)
  end
  if stream.complete and stream.offset >= stream.size and stream.buffer == "" then
    close_stream_client(stream)
  end
end

local function poll_streams()
  if not next(app.streams) then return end
  local pollfds = {}
  for _, stream in pairs(app.streams) do
    if stream.proxy_fd then
      pollfds[stream.proxy_fd] = stream.offset < (stream.prefix or 0)
                                 and vlc.net.POLLOUT or vlc.net.POLLIN
    else add_listener_fds(stream.listener, pollfds) end
  end
  local ok = pcall(vlc.net.poll, pollfds, 0)
  if not ok then return end
  for _, stream in pairs(app.streams) do
    if not stream.proxy_fd and listener_ready(stream.listener, pollfds) then
      accept_stream(stream)
    elseif stream.proxy_fd then
      local flags = pollfds[stream.proxy_fd]
      if has_flag(flags, vlc.net.POLLOUT) then serve_stream(stream)
      elseif has_flag(flags, vlc.net.POLLERR)
          or has_flag(flags, vlc.net.POLLHUP)
          or has_flag(flags, vlc.net.POLLNVAL) then close_stream_client(stream)
      elseif has_flag(flags, vlc.net.POLLIN) then
        local probe = vlc.net.recv(stream.proxy_fd, 1)
        if not probe then close_stream_client(stream) end
      end
    end
  end
  cleanup_streams(false)
end

local function handle_reply(packet)
  if app.auth == "salt" then
    if packet.opcode ~= ec.OP.AUTH_SALT then
      set_message(lang.authentication_failed); close_socket(); return
    end
    local salt = ec.child(packet, ec.TAG.PASSWD_SALT)
    if not salt or not send_all(ec.auth_password(app.ec_hash, salt,
                                                 vlc.strings.md5)) then
      set_message(lang.authentication_failed); close_socket(); return
    end
    app.auth = "password"
    return
  elseif app.auth == "password" then
    if packet.opcode ~= ec.OP.AUTH_OK then
      set_message(lang.authentication_failed); close_socket(); return
    end
    app.auth = "ready"
    app.probe_existing = false
    if not app.engine_enabled then
      if app.engine_stop_pending then
        request_packet("engine-stop", ec.OP.SHUTDOWN, {})
        set_message(lang.engine_stopping)
      else
        set_message(lang.engine_running_disabled)
      end
      return
    end
    set_message(app.bootstrap_warning or lang.connected)
    if app.network_restart_pending then
      app.network_restart_pending = false
      app.restart_pending = true
      request_packet("restart", ec.OP.SHUTDOWN, {})
      set_message(lang.restarting_network)
      return
    end
    begin_engine_session()
    return
  end

  local pending = app.pending
  app.pending = nil
  if not pending then return end
  if packet.opcode == ec.OP.FAILED or packet.opcode == ec.OP.AUTH_FAIL then
    local detail = packet.tags and packet.tags[1] and packet.tags[1].value
    set_message(string.format(lang.request_failed, tostring(detail or pending.kind)))
    if pending.kind == "stream-download" and app.stream_request
       and pending.data and app.stream_request.hash == pending.data.hash then
      complete_stream_request()
    end
    return
  end
  if pending.kind == "stream-categories" then
    local category = find_tag_recursive(packet, ec.TAG.CATEGORY,
                                        STREAM_CATEGORY)
    if category then
      local title = child_value(category, ec.TAG.CATEGORY_TITLE, "")
      local path = child_value(category, ec.TAG.CATEGORY_PATH, "")
      if title == STREAM_CATEGORY_TITLE and path == app.stream_cache_dir then
        app.stream_category_ready = true
      else
        request_packet("stream-category-ready", ec.OP.UPDATE_CATEGORY,
                       { category_tag(STREAM_CATEGORY) })
      end
    else
      request_packet("stream-category-ready", ec.OP.CREATE_CATEGORY,
                     { category_tag(0xffffffff) })
    end
  elseif pending.kind == "stream-category-ready" then
    app.stream_category_ready = true
  elseif pending.kind == "search-start" then
    app.search_active, app.search_progress = true, 0
    app.last_search_poll = 0
    set_message(lang.searching)
  elseif pending.kind == "search-results" and packet.opcode == ec.OP.SEARCH_RESULTS then
    parse_search_results(packet)
  elseif pending.kind == "search-progress" then
    local status = ec.child(packet, ec.TAG.SEARCH_STATUS)
    if status then
      app.search_progress = status.value
      if status.value >= 100 then app.search_active = false end
      app.dirty = true
    end
  elseif pending.kind == "downloads" and packet.opcode == ec.OP.DLOAD_QUEUE then
    parse_downloads(packet)
  elseif pending.kind == "stats" and packet.opcode == ec.OP.STATS then
    app.ul_speed = child_value(packet, ec.TAG.STATS_UL_SPEED, app.ul_speed)
    app.dl_speed = child_value(packet, ec.TAG.STATS_DL_SPEED, app.dl_speed)
    parse_connection_state(packet)
    app.dirty = true
  elseif pending.kind == "download" or pending.kind == "stream-download" then
    local remembered
    if pending.kind == "download" then
      remember_download(pending.data)
      remembered = pending.data and app.download_history[pending.data.hash]
    end
    local already_present = remembered and
      complete_file_exists(remembered.final_path, remembered.size)
    if pending.kind == "stream-download" then
      -- Adding the result to amuled is only the internal prerequisite for
      -- progressive playback. Do not report it as a manual download action.
      local stream_item = pending.data
      local cached_path = stream_item and cache_path(stream_item)
      local already_cached = stream_item and
        complete_file_exists(cached_path, stream_item.size)
      if already_cached and app.stream_request then
        local complete = {
          hash = stream_item.hash, name = stream_item.name,
          size = stream_item.size, done = stream_item.size,
          prefix = stream_item.size, complete = true,
          final_path = cached_path,
        }
        if start_stream(complete, app.stream_request.result) then
          complete_stream_request()
        end
      elseif not already_cached then
        set_message(lang.stream_buffering)
      end
    elseif already_present then
      set_message(string.format(lang.download_already_present,
                                remembered.final_path))
    else
      set_message(lang.download_added)
    end
    app.last_queue_poll = 0
  elseif pending.kind == "promote-download" then
    remember_download(pending.data)
    set_message(lang.download_promoted)
    app.last_queue_poll = 0
  elseif pending.kind == "server-update" then
    pcall(os.remove, app.state_dir .. "/server.met.download")
    set_message(lang.server_met_updated)
  elseif pending.kind == "engine-stop" then
    close_socket()
    app.engine_stop_pending = false
    app.restart_pending, app.network_restart_pending = false, false
    app.probe_existing = false
    app.reconnect_at = now_ms() + 1000
    set_message(lang.engine_stopped)
  elseif pending.kind == "restart" or pending.kind == "helper-migration" then
    close_socket()
    app.restart_pending = false
    app.reconnect_at, app.launched = now_ms() + 750, false
  elseif pending.kind == "connect" then
    app.last_stats_poll, app.last_queue_poll = 0, 0
  end
end

local function poll_socket()
  if not app.socket then return end
  local pollfds = { [app.socket] = vlc.net.POLLIN }
  local ok, ready = pcall(vlc.net.poll, pollfds, 0)
  if not ok then close_socket(); app.reconnect_at = now_ms() + 1000; return end
  if ready > 0 and pollfds[app.socket] then
    local chunk = vlc.net.recv(app.socket, 65536)
    if not chunk then
      local restarting = app.restart_pending
      local stopping_engine = app.engine_stop_pending or not app.engine_enabled
      close_socket()
      app.restart_pending = false
      if restarting then app.launched, app.launcher = false, nil end
      if stopping_engine then
        app.engine_stop_pending = false
        app.launched, app.launcher = false, nil
        app.probe_existing = false
        set_message(lang.engine_stopped)
      end
      app.reconnect_at = now_ms() + (restarting and 1000 or 500)
      return
    end
    app.input = app.input .. chunk
    local packets, rest, err = ec.frames(app.input)
    app.input = rest or ""
    if err then set_message(string.format(lang.protocol_error, err)); close_socket(); return end
    for _, packet in ipairs(packets) do handle_reply(packet) end
  end
end

local function start_next_request()
  if app.auth ~= "ready" or app.pending or #app.queue == 0 then return end
  local request = table.remove(app.queue, 1)
  if not send_all(request.packet) then
    close_socket(); app.reconnect_at = now_ms() + 1000; return
  end
  app.pending = request
end

local function launch_daemon()
  if not engine_requested() then
    trace_engine("launch skipped: engine not requested")
    return
  end
  if app.launched then return end
  if not app.engine then
    trace_engine("launch failed: bundled engine not found")
    set_message(lang.engine_missing)
    render(true)
    return
  end
  if not (vlc.process and vlc.process.start) then
    trace_engine("launch failed: process API unavailable")
    set_message(lang.process_missing)
    render(true)
    return
  end
  configure_daemon()
  -- Do not use amuled --full-daemon on macOS: the official wxCocoa build has
  -- worker threads by then and the Objective-C runtime aborts the forked
  -- child. PowerVLC's process launcher already backgrounds without a shell.
  local argv = { app.engine, "--config-dir=" .. app.state_dir }
  -- aMule intentionally compiles --disable-fatal out on Windows, where its
  -- Unix fatal-signal handler is not used. Keep the watchdog-friendly switch
  -- on macOS/Linux without making the Windows daemon reject its command line.
  if not (package and package.config and package.config:sub(1, 1) == "\\") then
    argv[#argv + 1] = "--disable-fatal"
  end
  local handle, err = vlc.process.start(argv, app.log_path, true)
  if not handle then
    trace_engine("launch failed: " .. tostring(err))
    app.launch_failures = app.launch_failures + 1
    app.reconnect_at = now_ms() + math.min(15000,
                                           1000 + app.launch_failures * 2000)
    set_message(string.format(lang.engine_failed, tostring(err)))
    return
  end
  trace_engine("engine launched: " .. tostring(app.engine))
  app.launcher, app.launched = handle, true
  app.reconnect_at = now_ms() + 350
  set_message(lang.engine_starting)
end

local function poll_launcher()
  if not app.launcher then return end
  local ok, running, code = pcall(app.launcher.status, app.launcher)
  if ok and running then return end
  app.launcher, app.launched = nil, false
  if app.socket then return end
  if not app.engine_enabled then
    app.engine_stop_pending = false
    app.probe_existing = false
    set_message(lang.engine_stopped)
    return
  end
  -- A clean, immediate exit normally means that another amuled owns the
  -- state directory (muleLock). Its EC listener can still be coming up, so
  -- probe it for a few seconds instead of reporting a spurious engine crash
  -- or repeatedly launching duplicate helpers.
  if ok and tonumber(code) == 0 then
    local now = now_ms()
    app.launch_probe_until = now + 5000
    app.reconnect_at = now + 250
    set_message(lang.engine_starting)
    return
  end
  app.launch_failures = app.launch_failures + 1
  app.reconnect_at = now_ms() + math.min(15000,
                                         1000 + app.launch_failures * 2000)
  if not ok then
    set_message(string.format(lang.engine_failed, tostring(running)))
  else
    set_message(string.format(lang.engine_exited, tostring(code or "?")))
  end
end

local function valid_socket_fd(fd)
  return type(fd) == "number" and fd >= 0
end

local function connect_ec(allow_launch)
  local now = now_ms()
  if app.socket or now < app.reconnect_at then return end
  local ok, fd = pcall(vlc.net.connect_tcp, "127.0.0.1", app.ec_port, 100)
  -- The native binding returns -1 on connection failure. Unlike nil/false,
  -- -1 is truthy in Lua; accepting it here prevented amuled from ever being
  -- launched when no EC listener existed yet (most visible on Jaguar).
  if not ok or not valid_socket_fd(fd) then
    if allow_launch then
      if not app.launched and now >= app.launch_probe_until then launch_daemon()
      else app.reconnect_at = now_ms() + 500 end
    else
      app.probe_existing = false
      if app.engine_stop_pending then
        app.engine_stop_pending = false
        set_message(lang.engine_stopped)
      end
      app.reconnect_at = now_ms() + 1000
    end
    return
  end
  app.socket, app.input, app.auth = fd, "", "salt"
  app.launched = app.launcher ~= nil
  app.launch_probe_until = 0
  app.launch_failures = 0
  if not send_all(ec.auth_request()) then close_socket(); app.reconnect_at = now_ms() + 500 end
end

local function schedule_polling()
  if app.auth ~= "ready" or not app.engine_enabled then return end
  -- Finish a queued aMule cancellation before a hidden extension shuts
  -- down. Additional polling requests could otherwise postpone it forever.
  if app.cleanup_shutdown_pending then return end
  local now = now_ms()
  if app.search_active and now - app.last_search_poll >= 1200 then
    request_packet("search-results", ec.OP.SEARCH_RESULTS,
      { ec.integer(ec.TAG.DETAIL_LEVEL, ec.DETAIL.FULL) })
    request_packet("search-progress", ec.OP.SEARCH_PROGRESS, {})
    app.last_search_poll = now
  end
  local queue_interval = (next(app.streams) or app.stream_request
                          or #app.stream_queue > 0) and 750 or 1800
  if now - app.last_queue_poll >= queue_interval then
    request_packet("downloads", ec.OP.GET_DLOAD_QUEUE,
      { ec.integer(ec.TAG.DETAIL_LEVEL, ec.DETAIL.FULL) })
    app.last_queue_poll = now
  end
  if now - app.last_stats_poll >= 2500 then
    request_packet("stats", ec.OP.STAT_REQ, {})
    app.last_stats_poll = now
  end
end

local function close_dialog()
  if dlg then dlg:delete(); dlg = nil end
  ui = {}
  app.rendered_status = nil
end

local function selected_row(rows, list)
  list = list or ui.list
  if not list then return nil end
  for id in pairs(list:get_selection()) do return rows[tonumber(id) or id] end
  return nil
end

local function selected_rows(rows, list)
  local selected, ids = {}, {}
  list = list or ui.list
  if not list then return selected end
  for id in pairs(list:get_selection() or {}) do
    ids[#ids + 1] = tonumber(id) or id
  end
  table.sort(ids, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(ids) do
    local item = rows[id]
    if item then selected[#selected + 1] = item end
  end
  return selected
end

local function selected_hashes(rows, list)
  local hashes = {}
  list = list or ui.list
  if not list then return hashes end
  for id in pairs(list:get_selection()) do
    local item = rows[tonumber(id) or id]
    if item and item.hash then hashes[item.hash] = true end
  end
  return hashes
end

local function result_matches_filter(item, query)
  query = string.lower(trim(query or app.result_filter or ""))
  if query == "" then return true end
  if not item.filter_key then
    item.filter_key = string.lower(item.name or "")
  end
  return string.find(item.filter_key, query, 1, true) ~= nil
end

local function refresh_results()
  if not ui.list then return end
  local selected = selected_hashes(app.result_rows)
  ui.list:clear()
  ui.list:set_text(lang.file .. "\t" .. lang.size .. "\t" .. lang.sources
                   .. "\t" .. lang.complete .. LIST_PAD)
  app.result_rows = {}
  local row, selected_row_ids = 0, {}
  for _, hash in ipairs(app.result_order) do
    local item = app.search_results[hash]
    if item and result_matches_filter(item) then
      row = row + 1; app.result_rows[row] = item
      if selected[item.hash] then selected_row_ids[row] = true end
      ui.list:add_value(item.name .. "\t" .. sortable_size(item.size) .. "\t"
        .. tostring(item.sources) .. "\t" .. tostring(item.complete) .. LIST_PAD, row)
    end
  end
  if next(selected_row_ids) and ui.list.set_selection then
    ui.list:set_selection(selected_row_ids)
  end
end

local function status_text()
  if app.auth ~= "ready" then return app.message end
  local id_labels = {
    high = lang.high_id, low = lang.low_id,
    connecting = lang.id_connecting, disconnected = lang.id_disconnected,
    unknown = lang.id_unknown,
  }
  local identity = id_labels[app.ed2k_id_state] or lang.id_unknown
  if app.view == "configuration" then
    if app.ed2k_id_state == "low" then
      if app.upnp_state == "failed" then
        identity = identity .. " · "
          .. string.format(lang.upnp_failed, app.upnp_error or lang.id_unknown)
      elseif app.upnp_state == "partial" then
        identity = identity .. " · " .. lang.upnp_partial
      end
    elseif app.upnp_state == "open" then
      identity = identity .. " · " .. lang.upnp_open
    end
  end
  local first_line = app.message ~= "" and (app.message .. " — " .. identity)
                                      or identity
  return first_line .. "\n"
    .. string.format(lang.speed_status, format_speed(app.dl_speed),
                     format_speed(app.ul_speed))
end

local function refresh_downloads()
  if not ui.list then return end
  local selected = selected_hashes(app.download_rows)
  ui.list:clear()
  ui.list:set_text(lang.file .. "\t" .. lang.progress .. "\t" .. lang.speed
                   .. "\t" .. lang.sources .. LIST_PAD)
  app.download_rows = {}
  local row, selected_row_ids = 0, {}
  for _, hash in ipairs(app.download_order) do
    local item = app.downloads[hash]
    if item then
      row = row + 1; app.download_rows[row] = item
      if selected[item.hash] then selected_row_ids[row] = true end
      ui.list:add_value(item.name .. "\t" .. string.format("%.1f%%", percent(item.done, item.size))
        .. "\t" .. format_speed(item.speed) .. "\t"
        .. tostring(item.active) .. "/" .. tostring(item.sources) .. LIST_PAD, row)
    end
  end
  if next(selected_row_ids) and ui.list.set_selection then
    ui.list:set_selection(selected_row_ids)
  end
end

render = function(force)
  local now = now_ms()
  if not force and (not app.dirty or now - app.last_render < 500) then return end
  if force or app.list_dirty then
    if app.view == "search" then refresh_results() else refresh_downloads() end
    app.list_dirty = false
  end
  if ui.message then
    local text = status_text()
    if text ~= app.rendered_status then
      ui.message:set_text(text)
      app.rendered_status = text
    end
  end
  -- Widget changes are flushed once by the host when this callback returns.
  app.last_render, app.dirty = now, false
end

local function add_download_folder(row)
  dlg:add_label(lang.download_location, 1, row, 1, 1)
  ui.download_dir = dlg:add_text_input(app.download_dir, 2, row, 4, 1)
  dlg:add_button(lang.choose_folder, click_choose_download_dir, 6, row, 1, 1)
end

local function add_server_met_url(row)
  dlg:add_label(lang.server_met_url, 1, row, 1, 1)
  ui.server_met_url = dlg:add_text_input(app.server_met_url, 2, row, 4, 1)
  dlg:add_button(lang.update_server_met, click_update_server_met, 6, row, 1, 1)
end

local function show_configuration()
  if app.view ~= "configuration" then
    app.config_return_view = app.view == "downloads" and "downloads" or "search"
  end
  app.view = "configuration"
  close_dialog()
  dlg = vlc.dialog(lang.title_configuration)
  dlg:set_size(900, 420)
  if engine_requested() then
    dlg:add_button(lang.back, click_close_configuration, 1, 1, 1, 1)
    dlg:add_label(lang.configuration, 2, 1, 5, 1)
  else
    dlg:add_button(lang.validate_configuration, click_validate_configuration,
                   1, 1, 2, 1)
    dlg:add_label(lang.configuration, 3, 1, 4, 1)
  end
  add_download_folder(2)
  add_server_met_url(3)
  ui.upnp = dlg:add_check_box(lang.upnp_enabled, app.upnp, 1, 4, 6, 1)
  dlg:add_label(lang.tcp_port, 1, 5, 1, 1)
  ui.ed2k_port = dlg:add_text_input(tostring(app.ed2k_port), 2, 5, 1, 1)
  dlg:add_label(lang.udp_port, 3, 5, 1, 1)
  ui.udp_port = dlg:add_text_input(tostring(app.udp_port), 4, 5, 1, 1)
  dlg:add_button(lang.apply_network, click_apply_network, 5, 5, 2, 1)
  dlg:add_button(lang.start_engine, click_start_engine, 1, 6, 3, 1)
  dlg:add_button(lang.stop_engine, click_stop_engine, 4, 6, 3, 1)
  ui.ports_hint = dlg:add_label(
    string.format(lang.incoming_ports, app.ed2k_port, app.udp_port),
    1, 7, 6, 1)
  dlg:add_label(lang.download_only, 1, 8, 6, 1)
  ui.message = dlg:add_label("", 1, 9, 6, 2)
  dlg:show()
  app.dirty, app.list_dirty = true, false
  render(true)
end

local function show_search()
  app.view = "search"
  close_dialog()
  dlg = vlc.dialog(lang.title)
  dlg:set_size(900, 590)
  dlg:add_label(lang.search, 1, 1, 1, 1)
  ui.query = dlg:add_text_input(app.search_query, 2, 1, 3, 1, click_search)
  ui.search_kind = dlg:add_dropdown(5, 1, 1, 1)
  ui.search_kind:add_value(lang.global_search, ec.SEARCH.GLOBAL)
  ui.search_kind:add_value(lang.kad_search, ec.SEARCH.KAD)
  dlg:add_button(lang.search_button, click_search, 6, 1, 1, 1)
  dlg:add_label(lang.filter_results, 1, 2, 1, 1)
  -- Text-change callbacks are debounced for 300 ms by every dialog provider;
  -- Enter uses the activation callback to apply the filter immediately.
  ui.filter = dlg:add_text_input(app.result_filter or "", 2, 2, 5, 1,
                                 click_filter_results, click_filter_results)
  ui.list = dlg:add_list(1, 3, 6, 6, click_stream)
  dlg:add_button(lang.play, click_stream, 1, 9, 1, 1)
  dlg:add_button(lang.enqueue, click_enqueue, 2, 9, 1, 1)
  dlg:add_button(lang.stop_stream, click_stop_stream, 3, 9, 1, 1)
  dlg:add_button(lang.download, click_download, 4, 9, 1, 1)
  dlg:add_button(lang.downloads, click_show_downloads, 5, 9, 1, 1)
  dlg:add_button(lang.refresh, click_refresh, 6, 9, 1, 1)
  ui.message = dlg:add_label("", 1, 10, 4, 1)
  dlg:add_button(lang.configuration, click_show_configuration, 5, 10, 2, 1)
  dlg:show()
  app.dirty, app.list_dirty = true, true; render(true)
end

local function show_downloads()
  app.view = "downloads"
  close_dialog()
  dlg = vlc.dialog(lang.title_downloads)
  dlg:set_size(900, 590)
  ui.list = dlg:add_list(1, 1, 6, 7, click_stream)
  dlg:add_button(lang.back_search, click_show_search, 1, 8, 1, 1)
  dlg:add_button(lang.play, click_stream, 2, 8, 1, 1)
  dlg:add_button(lang.enqueue, click_enqueue, 3, 8, 1, 1)
  dlg:add_button(lang.stop_stream, click_stop_stream, 4, 8, 1, 1)
  dlg:add_button(lang.pause, click_pause, 5, 8, 1, 1)
  dlg:add_button(lang.resume, click_resume, 6, 8, 1, 1)
  ui.message = dlg:add_label("", 1, 9, 4, 1)
  dlg:add_button(lang.remove, click_remove, 5, 9, 1, 1)
  dlg:add_button(lang.refresh, click_refresh, 6, 9, 1, 1)
  dlg:add_label(lang.daemon_persists, 1, 10, 6, 1)
  dlg:show()
  app.last_queue_poll = 0
  app.dirty, app.list_dirty = true, true
  render(true)
end

local function start_search(query, kind)
  query = trim(query)
  if query == "" then set_message(lang.enter_search); return false end
  app.search_query, app.search_kind = query, kind or ec.SEARCH.GLOBAL
  app.result_filter = ""
  if ui.filter then ui.filter:set_text("") end
  app.search_results, app.result_order = {}, {}
  app.list_dirty = true
  app.search_progress, app.search_active = nil, false
  request_packet("search-start", ec.OP.SEARCH_START, {
    ec.integer(ec.TAG.SEARCH_TYPE, app.search_kind, {
      ec.string(ec.TAG.SEARCH_NAME, query),
      ec.string(ec.TAG.SEARCH_FILE_TYPE, ""),
    }),
  })
  set_message(lang.search_queued)
  return true
end

function click_search()
  local kind = ui.search_kind and ui.search_kind:get_value() or app.search_kind
  start_search(ui.query and ui.query:get_text() or app.search_query, kind)
end

function click_filter_results()
  if app.view ~= "search" or not ui.filter then return end
  local query = string.lower(trim(ui.filter:get_text() or ""))
  if query == app.result_filter then return end
  app.result_filter = query
  app.list_dirty, app.dirty = true, true
  render(true)
end

function click_download()
  local items = selected_rows(app.result_rows)
  if #items == 0 then set_message(lang.select_result); return end
  for _, item in ipairs(items) do
    if app.transfer_intent[item.hash] == "stream"
       or complete_file_exists(cache_path(item), item.size) then
      promote_download(item)
    else
      request_download(item, false)
    end
  end
  set_message(string.format(lang.downloads_queued, #items))
end

function click_stream()
  local items
  if app.view == "downloads" then
    items = selected_rows(app.download_rows)
    for index, item in ipairs(items) do
      remember_download(item)
      queue_stream_request(item, index > 1)
    end
  else
    items = selected_rows(app.result_rows)
    for index, item in ipairs(items) do
      queue_stream_request(item, index > 1)
    end
  end
  if #items == 0 then set_message(lang.select_stream); return end
  app.last_queue_poll = 0
  set_message(string.format(lang.files_queued, #items))
end

function click_enqueue()
  local rows = app.view == "downloads" and app.download_rows or app.result_rows
  local items = selected_rows(rows)
  if #items == 0 then set_message(lang.select_stream); return end
  for _, item in ipairs(items) do
    if app.view == "downloads" then remember_download(item) end
    queue_stream_request(item, true)
  end
  app.last_queue_poll = 0
  set_message(string.format(lang.files_queued, #items))
end

local function cancel_pending_stream()
  local request = app.stream_request
  if not request then return false end
  local hash = request.hash
  app.stream_request = nil
  app.stream_queue = {}
  if app.transfer_intent[hash] == "stream" then
    if app.auth == "ready" then
      request_packet("discard-stream", ec.OP.PARTFILE_DELETE,
                     { ec.hash(ec.TAG.PARTFILE, hash) })
    end
    local item = request.result or app.downloads[hash]
    if item then pcall(os.remove, cache_path(item)) end
    app.transfer_intent[hash] = nil
    app.downloads[hash] = nil
  end
  app.last_queue_poll = 0
  return true
end

function click_stop_stream()
  local _, stream = current_stream()
  if stream then
    if vlc.playlist and vlc.playlist.stop then pcall(vlc.playlist.stop) end
    close_stream_client(stream)
    set_message(lang.stream_stopped_cached)
  elseif cancel_pending_stream() then
    set_message(lang.stream_cancelled)
  else
    set_message(lang.no_stream_playing)
  end
end

function click_refresh()
  if app.view == "downloads" then app.last_queue_poll = 0
  elseif app.search_active then app.last_search_poll = 0 end
end

function click_update_server_met()
  local url = trim(ui.server_met_url and ui.server_met_url:get_text()
                   or app.server_met_url)
  if not string.match(url, "^https?://") then
    set_message(lang.server_met_invalid); return
  end
  app.server_met_url = url
  write_settings()
  configure_daemon()
  local ok = download_bootstrap_file("server.met", url, true, true)
  if not ok then
    set_message(string.format(lang.bootstrap_failed, "server.met")); return
  end
  app.server_update_pending = true
  if app.auth == "ready" and app.engine_enabled then
    request_packet("server-update", ec.OP.SERVER_UPDATE_FROM_URL,
      { ec.string(ec.TAG.SERVERS_UPDATE_URL, app.server_met_url) })
    app.server_update_pending = false
    set_message(lang.server_met_applying)
  else
    set_message(lang.server_met_queued)
  end
end

function click_show_downloads() show_downloads() end
function click_show_search() show_search() end
function click_show_configuration() show_configuration() end

function click_close_configuration()
  if app.config_return_view == "downloads" then show_downloads()
  else show_search() end
end

local function apply_network_configuration()
  set_message(lang.engine_starting)
  render(true)
  trace_engine("network configuration callback")
  local tcp = valid_port(ui.ed2k_port and ui.ed2k_port:get_text())
  local udp = valid_port(ui.udp_port and ui.udp_port:get_text())
  if not tcp or not udp then
    set_message(lang.invalid_ports)
    return false
  end
  if tcp == app.ec_port then
    set_message(string.format(lang.port_conflicts_ec, app.ec_port))
    return false
  end
  local upnp = ui.upnp and ui.upnp:get_checked() or false
  local was_configured, was_enabled = app.configuration_passed,
                                      app.engine_enabled
  local changed = tcp ~= app.ed2k_port or udp ~= app.udp_port
               or upnp ~= app.upnp
  if changed then close_upnp_mappings() end
  app.ed2k_port, app.udp_port, app.upnp = tcp, udp, upnp
  app.configuration_passed, app.engine_enabled = true, true
  app.engine_stop_pending, app.probe_existing = false, false
  write_settings()
  configure_daemon()
  if changed or not was_enabled then
    app.upnp_started, app.upnp_recheck_done = false, false
    app.upnp_state, app.upnp_error = "pending", nil
  end

  -- Download with PowerVLC's HTTP stack before the first daemon launch. The
  -- bundled aMule HTTP client cannot negotiate with the current bootstrap
  -- host on Jaguar, and aMule only reads these files during startup.
  if not app.bootstrap_done then pcall(bootstrap_network) end

  -- Launch/reconnect after staging any first-use network data.  A failed
  -- optional download still never prevents the daemon from starting.
  app.reconnect_at = 0
  -- Always probe EC first. A detached amuled can outlive a closed extension;
  -- launching before this probe merely creates a duplicate which sees
  -- muleLock, exits cleanly, and makes the UI claim that the engine stopped.
  if not app.socket then connect_ec(true) end
  trace_engine("connect requested; launched=" .. tostring(app.launched)
               .. " socket=" .. tostring(app.socket))
  pcall(setup_upnp)

  if ui.ed2k_port then ui.ed2k_port:set_text(tostring(tcp)) end
  if ui.udp_port then ui.udp_port:set_text(tostring(udp)) end
  if ui.ports_hint then
    ui.ports_hint:set_text(string.format(lang.incoming_ports, tcp, udp))
  end
  if changed and app.auth == "ready" then
    app.restart_pending = true
    request_packet("restart", ec.OP.SHUTDOWN, {})
    set_message(lang.restarting_network)
  elseif changed and (app.socket or app.launched) then
    app.network_restart_pending = true
    set_message(lang.network_saved_restart_pending)
  elseif app.auth == "ready" then
    begin_engine_session()
    set_message(changed and lang.network_saved or lang.connected)
  else
    app.reconnect_at = 0
    set_message((not was_configured or not was_enabled)
                and lang.engine_starting or lang.network_unchanged)
  end
  render(true)
  return true
end

function click_apply_network() apply_network_configuration() end
function click_start_engine() apply_network_configuration() end
function click_validate_configuration()
  if apply_network_configuration() then show_search() end
end

function click_stop_engine()
  app.engine_enabled = false
  write_settings()
  close_upnp_mappings()
  app.upnp_started, app.upnp_recheck_done = false, false
  app.upnp_state, app.upnp_error = "disabled", nil
  app.queue = {}

  if app.auth == "ready" then
    app.engine_stop_pending = true
    request_packet("engine-stop", ec.OP.SHUTDOWN, {})
    set_message(lang.engine_stopping)
  elseif app.socket then
    app.engine_stop_pending = true
    set_message(lang.engine_stopping)
  elseif app.launcher then
    pcall(app.launcher.cancel, app.launcher)
    app.engine_stop_pending = true
    app.probe_existing = false
    set_message(lang.engine_stopping)
  else
    -- Probe once so this button can also stop a detached daemon left by an
    -- earlier extension session. A failed loopback connection means it is
    -- already stopped and never launches a new process.
    app.engine_stop_pending = true
    app.probe_existing = true
    app.reconnect_at = 0
    set_message(lang.engine_stopping)
  end
end

local function command_selected(opcode)
  local item = selected_row(app.download_rows)
  if not item then set_message(lang.select_download); return end
  request_packet("file-command", opcode, { ec.hash(ec.TAG.PARTFILE, item.hash) })
  app.last_queue_poll = 0
end

function click_pause() command_selected(ec.OP.PARTFILE_PAUSE) end
function click_resume() command_selected(ec.OP.PARTFILE_RESUME) end

local function remove_hash_from_order(order, hash)
  for index = #order, 1, -1 do
    if order[index] == hash then table.remove(order, index) end
  end
end

local function remove_download_items(items)
  local completed, cancelled = 0, 0
  for _, item in ipairs(items) do
    local remembered = app.download_history[item.hash]
    local final_path = item.final_path
      or remembered and remembered.final_path
      or (app.download_dir .. "/" .. item.name)
    local is_complete = item.complete
      or (tonumber(item.size) or 0) > 0
         and (tonumber(item.done) or 0) >= (tonumber(item.size) or 0)
      or complete_file_exists(final_path, item.size)

    app.dismissed_downloads[item.hash] = true
    app.download_history[item.hash] = nil
    app.downloads[item.hash] = nil
    remove_hash_from_order(app.download_history_order, item.hash)
    remove_hash_from_order(app.download_order, item.hash)

    if is_complete then
      -- "Supprimer" means removing completed history from this view. The
      -- user's finished file is deliberately left untouched on disk.
      completed = completed + 1
    else
      request_packet("file-command", ec.OP.PARTFILE_DELETE,
                     { ec.hash(ec.TAG.PARTFILE, item.hash) })
      cancelled = cancelled + 1
    end
  end
  app.list_dirty, app.dirty = true, true
  app.last_queue_poll = 0
  return completed, cancelled
end

function click_remove()
  local items = {}
  if ui.list then
    for id in pairs(ui.list:get_selection()) do
      local item = app.download_rows[tonumber(id) or id]
      if item then items[#items + 1] = item end
    end
  end
  if #items == 0 then set_message(lang.select_download); return end
  local completed, cancelled = remove_download_items(items)
  if completed > 0 then set_message(lang.completed_removed)
  elseif cancelled > 0 then set_message(lang.download_cancelled) end
  render(true)
end

function click_choose_download_dir()
  if folder_picker:busy() then set_message(lang.folder_picker_busy); return end
  local started = folder_picker:open(lang.folder_picker_prompt,
                                     app.download_dir)
  if started and folder_picker:busy() then
    set_message(lang.folder_picker_opening)
  elseif started then
    -- Native Windows picker: callback already reported the result.
  else set_message(lang.folder_picker_unavailable) end
end

local function emule_tick_once()
  if app.stopping then return end
  if folder_picker then folder_picker:poll() end
  poll_launcher()
  local should_run = engine_requested()
  if not app.socket and (should_run or app.probe_existing
                         or app.engine_stop_pending) then
    connect_ec(should_run)
  end
  if should_run then
    pcall(setup_upnp)
    if not app.bootstrap_done then pcall(bootstrap_network) end
  end
  poll_socket()
  schedule_polling()
  start_next_request()
  poll_streams()
  if app.stopping then return end
  render(false)
  if vlc.keep_alive then pcall(vlc.keep_alive) end
end

function emule_tick()
  local ok, err = pcall(emule_tick_once)
  if not ok then
    vlc.msg.err("PowerVLC eMule tick: " .. tostring(err))
  end
  if not app.stopping and vlc.timer then
    vlc.timer(TICK_MS, "emule_tick")
  end
end

function activate()
  load_lang()
  initialize_paths()
  trace_engine("extension activated; engine=" .. tostring(app.engine)
               .. " process=" .. tostring(vlc.process ~= nil))
  folder_picker = require("pvlc_folder_picker").new("emule", {
    done=function(value, reason)
      if value then
        app.download_dir = value
        mkdir_p(value)
        write_settings()
        configure_daemon()
        if ui.download_dir then ui.download_dir:set_text(value) end
        set_message(string.format(lang.folder_selected, value))
        if app.auth == "ready" and app.engine_enabled then
          app.restart_pending = true
          request_packet("restart", ec.OP.SHUTDOWN, {})
          set_message(lang.restarting_engine)
        end
      elseif reason == "cancelled" then
        set_message(lang.folder_picker_cancelled)
      else
        set_message(lang.folder_picker_unavailable)
      end
    end,
  })
  app.stopping = false
  -- Opening the extension is never consent to start a network daemon. Keep
  -- the saved values as form defaults, but require an explicit validation or
  -- Start click for every PowerVLC session.
  app.engine_enabled = false
  -- A detached daemon may outlive a closed extension, but the old Lua
  -- process handle does not. A later explicit Start will reconnect or launch.
  app.launcher, app.launched = nil, false
  app.launch_failures = 0
  app.launch_probe_until = 0
  app.upnp_started, app.upnp_recheck_done = false, false
  app.upnp_state, app.upnp_error = "pending", nil
  app.upnp_gateway, app.upnp_mappings = nil, {}
  app.cleanup_shutdown_pending = false
  app.engine_stop_pending = false
  app.probe_existing = false
  show_configuration()
  if not app.configuration_passed then
    set_message(lang.configuration_required)
  else
    set_message(lang.engine_stopped)
  end
  app.reconnect_at = 0
  if vlc.timer then vlc.timer(10, "emule_tick") end
end

function deactivate()
  app.stopping = true
  if vlc.timer then pcall(vlc.timer, 0) end
  if folder_picker then folder_picker:close() end
  local exiting = vlc.app_exiting and vlc.app_exiting()
  if exiting and app.auth == "ready" and app.socket then
    -- Ask an engine that we launched or rejoined to persist its state and
    -- stop cleanly. The native process registry remains the final fallback.
    pcall(send_all, ec.packet(ec.OP.SHUTDOWN, {}))
  end
  close_socket()
  cleanup_streams(true)
  if app.launcher then pcall(function() app.launcher:status() end) end
  app.launcher = nil
  close_dialog()
end

function close()
  if next(app.streams) then
    app.view = "hidden"
    close_dialog()
  else
    deactivate()
    if vlc.deactivate then vlc.deactivate() end
  end
end

if POWERVLC_EMULE_TEST then
  emule_test = {
    format_size = format_size, sortable_size = sortable_size, percent = percent,
    parse_search_results = parse_search_results,
    parse_downloads = parse_downloads, start_search = start_search,
    remember_download = remember_download,
    decode_gap_status = decode_gap_status, contiguous_prefix = contiguous_prefix,
    infer_metadata = infer_metadata,
    has_flag = has_flag,
    valid_socket_fd = valid_socket_fd,
    selected_row = selected_row, selected_hashes = selected_hashes,
    result_matches_filter = result_matches_filter,
    parse_connection_state = parse_connection_state,
    resolve_control_url = resolve_control_url,
    playlist_contains_path = playlist_contains_path,
    current_stream = current_stream,
    cancel_pending_stream = cancel_pending_stream,
    serve_stream = serve_stream,
    stream_start_ready = stream_start_ready,
    request_download = request_download, promote_download = promote_download,
    remove_download_items = remove_download_items,
    cache_path = cache_path,
    valid_port = valid_port,
    engine_requested = engine_requested,
    stream_category = STREAM_CATEGORY,
    stream_initial_buffer = STREAM_INITIAL_BUFFER,
    ed2k_port = DEFAULT_ED2K_PORT, udp_port = DEFAULT_UDP_PORT,
    default_server_met_url = DEFAULT_SERVER_MET_URL,
    app = app, ec = ec,
  }
end
