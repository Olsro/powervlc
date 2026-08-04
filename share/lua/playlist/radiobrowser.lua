--[[
 Radio-Browser.info station list parser

 Copyright © 2026 the PowerVLC team

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

--[[
 Expands the station-list URLs used by the radiobrowser services
 discovery (share/lua/sd/radiobrowser.lua).  The community database is
 full of entries with stray whitespace, duplicates and raw byte-order
 sorting, so the reply cannot be fed to VLC as a plain playlist: the
 XML is parsed with the (C-backed) vlc.xml reader, then the names are
 trimmed and the list is deduplicated and sorted properly.
--]]

function probe()
    return (vlc.access == "http" or vlc.access == "https")
        and string.match(vlc.path, "api%.radio%-browser%.info/xml/stations/")
end

-- Same helper as the service discovery: "_" is one of the keywords
-- po/Makevars hands to xgettext, so the string below lands in po/vlc.pot.
local function _(s)
    if vlc.gettext then
        return vlc.gettext._(s)
    end
    return s
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--[[
 Case-insensitive sort key; leading ASCII punctuation is ignored so
 that entries like ".. Atlantica Radio.." sort with the As instead of
 piling up on top of the list.  Bytes >= 128 (UTF-8) are kept.
--]]
local function sortkey(name)
    local key = name:lower():gsub("^[^%w\128-\255]+", "")
    if key == "" then
        key = name:lower()
    end
    return key
end

--[[
 Quality score, used to rank same-named stations (multiple relays of a
 national radio...) best first: bitrate, with lossless far on top and a
 slight edge for AAC over MP3 at equal bitrate.
--]]
local function quality(attrs)
    local q = tonumber(attrs.bitrate) or 0
    -- the API reports codecs in uppercase already; no :upper() here, the
    -- ctype-backed string functions are unreliable in the PowerPC Lua
    local codec = attrs.codec or ""
    if codec:find("FLAC", 1, true) then
        q = q + 100000
    elseif codec:find("AAC", 1, true) then
        q = q * 1.4
    end
    return q
end

function parse()
    local chunks = {}
    while true do
        local chunk = vlc.read(65536)
        if not chunk or #chunk == 0 then
            break
        end
        chunks[#chunks + 1] = chunk
    end

    --[[
     The xml object and the stream MUST be kept in locals for the whole
     parse: the C reader references them without holding a Lua
     reference, so anonymous temporaries would be garbage-collected
     mid-parse (use-after-free crash in the xml reader).
    --]]
    local xml = vlc.xml()
    local stream = vlc.memory_stream(table.concat(chunks))
    local reader = xml and stream and xml:create_reader(stream)
    if not reader then
        vlc.msg.err("radiobrowser: cannot parse the station list")
        return {}
    end

    local stations = {}
    local nodetype, nodename = reader:next_node()
    while nodetype > 0 do
        if nodetype == 1 and nodename == "station" then
            local attrs = {}
            local attr, value = reader:next_attr()
            while attr ~= nil do
                attrs[attr] = value
                attr, value = reader:next_attr()
            end

            local url = attrs.url_resolved
            if not url or url == "" then
                url = attrs.url
            end
            if url and url ~= "" then
                local name = trim(attrs.name or "")
                if name == "" then
                    name = url
                end
                local bitrate = tonumber(attrs.bitrate) or 0
                local codec = trim(attrs.codec or "")
                local desc = nil
                if codec ~= "" and bitrate > 0 then
                    desc = string.format("%s %d kbps", codec, bitrate)
                elseif codec ~= "" then
                    desc = codec
                elseif bitrate > 0 then
                    desc = string.format("%d kbps", bitrate)
                end
                local country = trim(attrs.country or "")
                local code = trim(attrs.countrycode or "")
                stations[#stations + 1] = {
                    name = name,
                    path = url,
                    key = sortkey(name),
                    quality = quality(attrs),
                    genre = attrs.tags,
                    arturl = attrs.favicon,
                    description = desc,
                    -- only used to build the random entry of the country
                    country = country ~= "" and country or nil,
                    countrycode = code ~= "" and code or nil,
                }
            end
        end
        nodetype, nodename = reader:next_node()
    end

    table.sort(stations, function(a, b)
        if a.key ~= b.key then
            return a.key < b.key
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        return a.path < b.path
    end)

    local items = {}

    --[[
     The random entry of the country goes on top, like the ones the service
     discovery puts at the head of its own lists.  Both the code and the
     display name are read off the stations themselves: the API spells the
     country the very same way in /json/countries (which is what the node
     above is titled after) and in the station attributes.
    --]]
    if string.match(vlc.path, "/bycountrycodeexact/") and stations[1] then
        local code, country
        for _, station in ipairs(stations) do
            code = code or station.countrycode
            country = country or station.country
            if code and country then
                break
            end
        end
        if code and code:match("^[A-Z][A-Z]$") then
            items[1] = {
                path = "radiobrowser://random/cc/" .. code,
                name = string.format(_("Play a random station (%s)"),
                                     country or code),
            }
        end
    end

    local previous = nil
    for _, station in ipairs(stations) do
        if not previous
           or previous.name ~= station.name
           or previous.path ~= station.path then
            items[#items + 1] = {
                path = station.path,
                name = station.name,
                genre = station.genre ~= "" and station.genre or nil,
                arturl = station.arturl ~= "" and station.arturl or nil,
                description = station.description,
            }
        end
        previous = station
    end
    return items
end
