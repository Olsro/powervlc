-- Lightweight UPnP AV client shared by PowerVLC Lua modules.
-- SSDP stays in the C core; HTTP, SOAP and XML reuse PowerVLC's existing
-- bindings. No libupnp/libixml process or dependency is involved.

local M = {}
local simplexml = require("simplexml")

local function local_name(name)
  return tostring(name or ""):match("([^:]+)$") or ""
end

local function element_children(node, wanted)
  local out = {}
  if type(node) ~= "table" then return out end
  for _, child in ipairs(node.children or {}) do
    if type(child) == "table"
       and (not wanted or local_name(child.name) == wanted) then
      out[#out + 1] = child
    end
  end
  return out
end

local function first_child(node, wanted)
  local children = element_children(node, wanted)
  return children[1]
end

local function node_text(node)
  if type(node) == "string" then return node end
  if type(node) ~= "table" then return nil end
  local parts = {}
  for _, child in ipairs(node.children or {}) do
    local value = node_text(child)
    if value then parts[#parts + 1] = value end
  end
  return table.concat(parts)
end

local function child_text(node, wanted)
  return node_text(first_child(node, wanted))
end

local function find_first(node, wanted)
  if type(node) ~= "table" then return nil end
  if local_name(node.name) == wanted then return node end
  for _, child in ipairs(node.children or {}) do
    local found = find_first(child, wanted)
    if found then return found end
  end
end

local function walk(node, wanted, output)
  if type(node) ~= "table" then return end
  if local_name(node.name) == wanted then output[#output + 1] = node end
  for _, child in ipairs(node.children or {}) do walk(child, wanted, output) end
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

function M.resolve_url(base, relative)
  relative = trim(relative)
  if relative:match("^https?://") then return relative end
  local origin = tostring(base or ""):match("^(https?://[^/]+)")
  if not origin then return nil end
  if relative:sub(1, 1) == "/" then return origin .. relative end
  local directory = tostring(base) == origin and origin
                    or tostring(base):match("^(.*)/[^/]*$") or origin
  return directory .. "/" .. relative
end

local function http_get(url)
  local status, body = vlc.http.get(url, { Accept="text/xml, application/xml" })
  if status ~= 200 or type(body) ~= "string" then
    return nil, tostring(body or status or "HTTP error")
  end
  return body
end

function M.parse_description(location, body)
  if not body then
    local err
    body, err = http_get(location)
    if not body then return nil, err end
  end
  local ok, tree = pcall(simplexml.parse_string, body)
  if not ok or type(tree) ~= "table" then return nil, "invalid device XML" end

  local url_base = trim(node_text(find_first(tree, "URLBase")))
  if url_base == "" then url_base = location end
  local devices = {}; walk(tree, "device", devices)
  local servers = {}
  for _, device in ipairs(devices) do
    local device_type = trim(child_text(device, "deviceType"))
    if device_type:find(":MediaServer:", 1, true) then
      local service_list = first_child(device, "serviceList")
      for _, service in ipairs(element_children(service_list, "service")) do
        local service_type = trim(child_text(service, "serviceType"))
        if service_type:find(":ContentDirectory:", 1, true) then
          local control = M.resolve_url(url_base,
                                       child_text(service, "controlURL"))
          if control then
            local icon
            local icon_list = first_child(device, "iconList")
            local best_area = -1
            for _, candidate in ipairs(element_children(icon_list, "icon")) do
              local width = tonumber(child_text(candidate, "width")) or 0
              local height = tonumber(child_text(candidate, "height")) or 0
              local url = M.resolve_url(url_base, child_text(candidate, "url"))
              if url and width * height > best_area then
                icon, best_area = url, width * height
              end
            end
            servers[#servers + 1] = {
              location=location, control=control, service=service_type,
              name=trim(child_text(device, "friendlyName")),
              udn=trim(child_text(device, "UDN")), icon=icon,
              manufacturer=trim(child_text(device, "manufacturer")),
              model=trim(child_text(device, "modelName")),
            }
          end
        end
      end
    end
  end
  return servers
end

function M.discover_media(timeout_ms)
  local replies, err = vlc.net.ssdp_discover({
    "urn:schemas-upnp-org:device:MediaServer:1",
    "urn:schemas-upnp-org:device:MediaServer:2",
  }, timeout_ms or 2200)
  if not replies then return nil, err end
  local servers, seen = {}, {}
  for _, reply in ipairs(replies) do
    local found = M.parse_description(reply.location)
    for _, server in ipairs(found or {}) do
      local key = server.udn ~= "" and server.udn or server.control
      if not seen[key] then
        seen[key] = true
        server.ssdp = reply
        servers[#servers + 1] = server
      end
    end
  end
  return servers
end

local function duration_seconds(value)
  local h, m, s = tostring(value or ""):match("^(%d+):(%d+):([%d%.]+)")
  if not h then return nil end
  return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

local function item_resource(node)
  local fallback
  for _, resource in ipairs(element_children(node, "res")) do
    local url = trim(node_text(resource))
    if url ~= "" then
      fallback = fallback or resource
      local protocol = tostring((resource.attributes or {}).protocolInfo or "")
      if protocol:match("^https?%-get:") or protocol:match("^http%-get:") then
        return resource
      end
    end
  end
  return fallback
end

local function parse_didl(body)
  local ok, tree = pcall(simplexml.parse_string, body)
  if not ok or type(tree) ~= "table" then return nil, "invalid DIDL XML" end
  local root = local_name(tree.name) == "DIDL-Lite" and tree
               or find_first(tree, "DIDL-Lite")
  if not root then return nil, "missing DIDL-Lite" end
  local entries = {}
  for _, node in ipairs(element_children(root)) do
    local kind = local_name(node.name)
    if kind == "container" then
      entries[#entries + 1] = {
        kind="container", id=tostring((node.attributes or {}).id or ""),
        title=trim(child_text(node, "title")),
        class=trim(child_text(node, "class")),
      }
    elseif kind == "item" then
      local resource = item_resource(node)
      local path = resource and trim(node_text(resource)) or ""
      if path ~= "" then
        local attrs = resource.attributes or {}
        entries[#entries + 1] = {
          kind="item", id=tostring((node.attributes or {}).id or ""),
          path=path, title=trim(child_text(node, "title")),
          artist=trim(child_text(node, "artist")),
          album=trim(child_text(node, "album")),
          genre=trim(child_text(node, "genre")),
          date=trim(child_text(node, "date")),
          arturl=trim(child_text(node, "albumArtURI")),
          class=trim(child_text(node, "class")),
          duration=duration_seconds(attrs.duration),
          protocol=attrs.protocolInfo,
        }
      end
    end
  end
  return entries
end

function M.browse(server, object_id, start_index, requested_count)
  object_id = tostring(object_id or "0")
  start_index = tonumber(start_index) or 0
  requested_count = tonumber(requested_count) or 256
  local escape = vlc.strings.convert_xml_special_chars
  local action = server.service .. "#Browse"
  local body = '<?xml version="1.0" encoding="utf-8"?>'
    .. '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    .. 's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    .. '<s:Body><u:Browse xmlns:u="' .. escape(server.service) .. '">'
    .. '<ObjectID>' .. escape(object_id) .. '</ObjectID>'
    .. '<BrowseFlag>BrowseDirectChildren</BrowseFlag>'
    .. '<Filter>*</Filter><StartingIndex>' .. tostring(start_index)
    .. '</StartingIndex><RequestedCount>' .. tostring(requested_count)
    .. '</RequestedCount><SortCriteria></SortCriteria>'
    .. '</u:Browse></s:Body></s:Envelope>'
  local status, response = vlc.http.post(server.control, body,
    'text/xml; charset="utf-8"', nil, { SOAPAction='"' .. action .. '"' })
  if status ~= 200 or type(response) ~= "string" then
    return nil, tostring(response or status or "SOAP error")
  end
  local ok, envelope = pcall(simplexml.parse_string, response)
  if not ok or type(envelope) ~= "table" then return nil, "invalid SOAP XML" end
  local result = trim(node_text(find_first(envelope, "Result")))
  local returned = tonumber(trim(node_text(find_first(envelope,
                                                       "NumberReturned"))))
  local total = tonumber(trim(node_text(find_first(envelope, "TotalMatches"))))
  if result == "" then return {}, nil, returned or 0, total or 0 end
  local entries, err = parse_didl(result)
  return entries, err, returned or (entries and #entries or 0), total
end

M._test = {
  local_name=local_name, node_text=node_text, parse_didl=parse_didl,
  duration_seconds=duration_seconds,
}

return M
