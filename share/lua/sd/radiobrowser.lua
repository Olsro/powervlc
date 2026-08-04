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

--[[
 Translation helpers.  "_" marks a string to be translated here and now,
 "N_" only marks it for extraction (the continent names live in a table and
 are translated at the point of use).  Both names are the ones po/Makevars
 hands to xgettext, so the strings below end up in po/vlc.pot.
--]]
local function _(s)
    if vlc.gettext then
        return vlc.gettext._(s)
    end
    return s
end

local function N_(s)
    return s
end

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
    { N_("Africa"), "AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA"
        .. " GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE"
        .. " NG RE RW SC SD SH SL SN SO SS ST SZ TD TG TN TZ UG YT ZA"
        .. " ZM ZW" },
    { N_("Asia"), "AE AF AM AZ BD BH BN BT CN GE HK ID IL IN IQ IR JO JP KG"
        .. " KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA"
        .. " SA SG SY TH TJ TL TM TR TW UZ VN YE" },
    { N_("Europe"), "AD AL AT AX BA BE BG BY CH CY CZ DE DK EE ES FI FO FR"
        .. " GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK"
        .. " MT NL NO PL PT RO RS RU SE SI SJ SK SM UA VA XK" },
    { N_("North America"), "AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD"
        .. " GL GP GT HN HT JM KN KY LC MF MQ MS MX NI PA PM PR SV SX"
        .. " TC TT US VC VG VI" },
    { N_("Oceania"), "AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PW SB"
        .. " TK TO TV UM VU WF WS" },
    { N_("South America"), "AR BO BR CL CO EC FK GF GY PE PY SR UY VE" },
}

--[[
 "radiobrowser://" (modules/access/radiobrowser.c) draws a station from the
 API and redirects to it.  A plain API URL could not do the job: the core
 resolves a playlist entry only once — the station it yielded would then be
 replayed for ever — and the mirrors cache their replies, so even a fresh
 "order=random" query would hand out the same station again.

 The API knows nothing about continents and cannot filter on several
 countries at once, hence the "CC:stationcount" list: the access module
 draws a country from it first, each with a probability proportional to its
 station count, so that a random European station is not one chance in
 fifty of coming from the Vatican.
--]]
local function add_random_item(node, context, weights)
    local path = "radiobrowser://random"
    if weights then
        path = path .. "/in/" .. table.concat(weights, ",")
    end
    local item = {
        path = path,
        title = string.format(_("Play a random station (%s)"), context),
    }
    if node then
        node:add_subitem(item)
    else
        vlc.sd.add_item(item)
    end
end

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

    local map = continent_of()
    local nodes = {}
    local other_node = nil

    --[[
     First pass: keep the usable entries and collect, per continent, the
     "CC:stationcount" weights its random entry draws from.  The leftovers
     ("Other") are only known once every country has been sorted out, and
     the random entry must come first in the node it belongs to, so nothing
     may be added to the lists before this pass is over.
    --]]
    local usable = {}
    local weights = {}
    local other_weights = {}

    for _, country in ipairs(countries) do
        local count = tonumber(country.stationcount) or 0
        -- [A-Z] and not %u: the uppercase/complemented pattern classes
        -- are broken in the PowerPC contrib Lua
        if count > 0
           and type(country.iso_3166_1) == "string"
           and country.iso_3166_1:match("^[A-Z][A-Z]$")
           and type(country.name) == "string"
           and country.name ~= "" then
            local index = map[country.iso_3166_1]
            local weight = string.format("%s:%d", country.iso_3166_1, count)
            if index then
                if not weights[index] then
                    weights[index] = {}
                end
                weights[index][#weights[index] + 1] = weight
            else
                other_weights[#other_weights + 1] = weight
            end
            usable[#usable + 1] = country
        end
    end

    add_random_item(nil, _("Global"), nil)

    for index, def in ipairs(continent_defs) do
        nodes[index] = vlc.sd.add_node({ title = _(def[1]) })
        if weights[index] then
            add_random_item(nodes[index], _(def[1]), weights[index])
        end
    end

    if #other_weights > 0 then
        other_node = vlc.sd.add_node({ title = _("Other") })
        add_random_item(other_node, _("Other"), other_weights)
    end

    for _, country in ipairs(usable) do
        local count = tonumber(country.stationcount) or 0
        local node = nodes[map[country.iso_3166_1]] or other_node
        node:add_subitem({
            -- XML: expanded by share/lua/playlist/radiobrowser.lua, which
            -- trims, deduplicates and sorts the station names and puts the
            -- random entry of the country on top.  The explicit limit
            -- matters: without it the API silently caps every reply at
            -- 1000 stations.
            path = api_base .. "/xml/stations/bycountrycodeexact/"
                   .. country.iso_3166_1
                   .. "?hidebroken=true&limit=500000",
            title = string.format("%s (%d)", country.name, count),
            type = "directory",
            uiddata = "radiobrowser-" .. country.iso_3166_1,
        })
    end
end
