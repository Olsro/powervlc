-- UPnP AV media-server discovery using PowerVLC's lightweight SSDP/HTTP stack.

local upnp
local MAX_ITEMS = 5000
local MAX_DEPTH = 12
local PAGE_SIZE = 256

function descriptor()
  return {
    title="UPnP media servers",
    short_description="Browse UPnP AV and DLNA media servers on the local network",
    category="lan",
  }
end

local function item_table(entry, server)
  local art = entry.arturl
  if art and art ~= "" then art = upnp.resolve_url(server.location, art) or art end
  return {
    path=entry.path,
    title=entry.title ~= "" and entry.title or entry.path,
    artist=entry.artist ~= "" and entry.artist or nil,
    album=entry.album ~= "" and entry.album or nil,
    genre=entry.genre ~= "" and entry.genre or nil,
    date=entry.date ~= "" and entry.date or nil,
    arturl=art,
    duration=entry.duration,
    type="stream",
    uiddata=(server.udn or server.control) .. ":" .. (entry.id or entry.path),
    meta={ ["UPnP class"]=entry.class or "",
           ["UPnP protocol"]=entry.protocol or "" },
  }
end

local function add_notice(parent, text)
  parent:add_subitem({ path="vlc://nop", title=text, type="node" })
end

local function browse_container(parent, server, object_id, depth, state)
  if depth > MAX_DEPTH then
    add_notice(parent, "More folders are available (depth limit reached)")
    return
  end
  local visit_key = (server.udn or server.control) .. ":" .. tostring(object_id)
  if state.visited[visit_key] then return end
  state.visited[visit_key] = true

  local start, total = 0, nil
  repeat
    local entries, err, returned, matches = upnp.browse(server, object_id,
                                                         start, PAGE_SIZE)
    if not entries then
      add_notice(parent, "Unable to browse this UPnP folder: " .. tostring(err))
      return
    end
    total = matches or total
    for _, entry in ipairs(entries) do
      if state.items >= MAX_ITEMS then
        if not state.capped then
          add_notice(parent, "Additional UPnP items omitted (safety limit)")
          state.capped = true
        end
        return
      end
      state.items = state.items + 1
      if entry.kind == "container" and entry.id ~= "" then
        local child = parent:add_subnode({
          title=entry.title ~= "" and entry.title or "UPnP folder",
        })
        browse_container(child, server, entry.id, depth + 1, state)
      elseif entry.kind == "item" then
        parent:add_subitem(item_table(entry, server))
      end
    end
    returned = tonumber(returned) or #entries
    start = start + returned
    if returned == 0 then break end
  until not total or start >= total or state.items >= MAX_ITEMS
end

function main()
  upnp = require("pvlc_upnp")
  local servers, err = upnp.discover_media(2600)
  if not servers then
    vlc.msg.warn("UPnP media discovery failed: " .. tostring(err))
    return
  end
  for _, server in ipairs(servers) do
    local title = server.name ~= "" and server.name or "UPnP media server"
    local root = vlc.sd.add_node({ title=title, arturl=server.icon })
    browse_container(root, server, "0", 0, { items=0, visited={} })
  end
end
