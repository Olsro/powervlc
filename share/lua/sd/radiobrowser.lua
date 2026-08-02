--[[
 Radio-Browser.info community radio directory

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
 Lists every country known to the radio-browser.info community database
 as a browsable directory item.  Expanding (or playing) a country fetches
 its station list from the API as a PLS playlist, which the core playlist
 demuxer parses natively — no JSON decoding is needed for the (possibly
 huge) station lists, only for the small country index.

 "all.api.radio-browser.info" is the official round-robin DNS entry that
 spreads the load over the currently available API mirrors.
--]]

local json = nil

-- The API is only reachable over HTTPS
local api_base = "https://all.api.radio-browser.info"

function descriptor()
    return { title = "Radio-Browser.info" }
end

local function fetch_once(url)
    local s = vlc.stream(url)
    if not s then
        return nil
    end
    local parts = {}
    while true do
        local chunk = s:read(65536)
        if not chunk or #chunk == 0 then
            break
        end
        parts[#parts + 1] = chunk
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts)
end

--[[
 The round-robin DNS entry can hand out a mirror that is temporarily
 down (HTTP 503...): each new connection may pick another mirror, so
 simply retry a few times, as recommended by the API documentation.
--]]
local function fetch(url)
    for attempt = 1, 4 do
        local data = fetch_once(url)
        if data then
            return data
        end
        vlc.msg.warn("radiobrowser: fetch attempt " .. attempt
                     .. " failed for " .. url)
    end
    return nil
end

--[[
 The API has no notion of continents: group the countries ourselves
 from their ISO 3166-1 code.  Unknown codes fall back to "Other".
--]]
local continent_defs = {
    { "Africa", "AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA"
        .. " GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE"
        .. " NG RE RW SC SD SH SL SN SO SS ST SZ TD TG TN TZ UG YT ZA"
        .. " ZM ZW" },
    { "Asia", "AE AF AM AZ BD BH BN BT CN GE HK ID IL IN IQ IR JO JP KG"
        .. " KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA"
        .. " SA SG SY TH TJ TL TM TR TW UZ VN YE" },
    { "Europe", "AD AL AT AX BA BE BG BY CH CY CZ DE DK EE ES FI FO FR"
        .. " GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK"
        .. " MT NL NO PL PT RO RS RU SE SI SJ SK SM UA VA XK" },
    { "North America", "AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD"
        .. " GL GP GT HN HT JM KN KY LC MF MQ MS MX NI PA PM PR SV SX"
        .. " TC TT US VC VG VI" },
    { "Oceania", "AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PW SB"
        .. " TK TO TV UM VU WF WS" },
    { "South America", "AR BO BR CL CO EC FK GF GY PE PY SR UY VE" },
}

local function continent_of()
    local map = {}
    for index, def in ipairs(continent_defs) do
        -- [A-Z] and not %u: the uppercase/complemented pattern classes
        -- are broken in the PowerPC contrib Lua
        for code in def[2]:gmatch("[A-Z][A-Z]") do
            map[code] = index
        end
    end
    return map
end

--[[
 A failed discovery would otherwise leave a silent, empty list: show a
 self-explaining placeholder instead.  The interfaces treat a node whose
 only child is a "vlc://nop" leaf as empty, so selecting the service
 again still triggers the automatic reload.
--]]
local function add_error_item()
    local _ = vlc.gettext and vlc.gettext._ or function(s) return s end
    vlc.sd.add_item({
        path = "vlc://nop",
        title = _("Connection to radio-browser.info failed — select this service again to retry"),
    })
end

function main()
    json = require "dkjson"

    local data = fetch(api_base .. "/json/countries")
    if not data then
        vlc.msg.err("radiobrowser: cannot fetch the country list from "
                    .. api_base)
        add_error_item()
        return
    end

    local countries = json.decode(data)
    if type(countries) ~= "table" then
        vlc.msg.err("radiobrowser: unexpected reply for the country list")
        add_error_item()
        return
    end

    table.sort(countries, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    local gettext = vlc.gettext and vlc.gettext._ or function(s) return s end
    local map = continent_of()
    local nodes = {}
    local other_node = nil

    for index, def in ipairs(continent_defs) do
        nodes[index] = vlc.sd.add_node({ title = gettext(def[1]) })
    end

    for _, country in ipairs(countries) do
        local count = tonumber(country.stationcount) or 0
        -- [A-Z] and not %u: the uppercase/complemented pattern classes
        -- are broken in the PowerPC contrib Lua
        if count > 0
           and type(country.iso_3166_1) == "string"
           and country.iso_3166_1:match("^[A-Z][A-Z]$")
           and type(country.name) == "string"
           and country.name ~= "" then
            local node = nodes[map[country.iso_3166_1]]
            if not node then
                if not other_node then
                    other_node = vlc.sd.add_node({ title = gettext("Other") })
                end
                node = other_node
            end
            node:add_subitem({
                -- XML: expanded by share/lua/playlist/radiobrowser.lua,
                -- which trims, deduplicates and sorts the station names.
                -- The explicit limit matters: without it the API silently
                -- caps every reply at 1000 stations.
                path = api_base .. "/xml/stations/bycountrycodeexact/"
                       .. country.iso_3166_1
                       .. "?hidebroken=true&limit=500000",
                title = string.format("%s (%d)", country.name, count),
                type = "directory",
                uiddata = "radiobrowser-" .. country.iso_3166_1,
            })
        end
    end
end
