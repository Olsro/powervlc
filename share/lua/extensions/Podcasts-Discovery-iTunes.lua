--[[
 Podcasts-Discovery-iTunes.lua : podcast directory for PowerVLC

 Searches Apple's public iTunes Search API for podcasts and episodes,
 shows what it found in a sortable list, and opens any of them on a page
 carrying the artwork, the show's own description -- read from its feed,
 which is the only place it exists -- and a button that subscribes to it.
 Subscribing writes the feed into "podcast-urls", the very preference the
 Podcasts service reads, so the show then appears in the sidebar next to
 the ones added by hand, and survives the next launch.

 Uses only plain dialog widgets (no HTML) so it renders correctly on
 every interface, including the legacy Mac OS X one.

 API reference:
 https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/

 Copyright (C) 2026 the PowerVLC team

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

local json = nil

            --[[ Constants ]]--

local READ_CHUNK = 65536

-- A feed is read only as far as its first <item>: the show's own
-- description sits above them, and a long-running podcast ships several
-- megabytes of episodes after it. Whatever arrives past that ceiling
-- without an <item> in sight is a feed we give up describing.
local FEED_HEAD_MAX = 262144

-- Read further, but only for the shows the directory lists no episode
-- for -- which is most of Radio France, among others. Stops as soon as
-- EPISODE_LIMIT items have gone by, so a feed with a thousand of them
-- costs the same as one with twenty.
local FEED_ITEMS_MAX = 786432

-- The directory withholds the feed of a great many shows -- measured on
-- 05/08/2026: 85 of the first 100 answers to "france" in the French
-- store, Radio France's whole catalogue among them -- and neither
-- lookup nor version=1 brings it back. The show's page on Apple's site
-- does carry it, in the data it embeds; that page is three quarters of
-- a megabyte, and the marker sits about 300 kB in, so it is read as a
-- stream and dropped the moment the address turns up. Paid once per
-- show: the answer is kept in the settings file for good.
local FEED_MARK = "\"feedUrl\":\""
local FEED_PAGE_MAX = 1572864

local ARTWORK_SIZE = 260
local DESCRIPTION_MAX_CHARS = 900
-- Twenty episodes is what the page shows and about ninety kilobytes of
-- answer; thirty costs half as much again for a list nobody scrolls to
-- the end of, and the download is what an old machine waits on.
local EPISODE_LIMIT = 20

-- What the API honours, measured against it on 05/08/2026 rather than
-- taken from the documentation, which is fifteen years old:
--   term, country, media, entity, limit  work;
--   attribute (titleTerm, descriptionTerm, ...) is ignored -- the same
--     search with two different attributes returns the very same
--     collection ids, in the same order;
--   explicit=Yes/No is ignored likewise;
--   entity=podcastAuthor always answers zero results;
--   lang changes nothing outside the two values it accepts;
--   limit is documented up to 200 but never yields more than 100.
-- So genre and explicit content are filtered here, on what came back,
-- and the boxes that would have done nothing are not offered at all.
local SEARCH_LIMITS = { 25, 50, 100 }

local STOREFRONTS = { "AR", "AU", "AT", "BE", "BR", "CA", "CL", "CN",
                      "CZ", "DK", "FI", "FR", "DE", "GR", "HU", "IN",
                      "IE", "IL", "IT", "JP", "KR", "MX", "NL", "NZ",
                      "NO", "PL", "PT", "RO", "RU", "ZA", "ES", "SE",
                      "CH", "TR", "UA", "GB", "US" }

-- A storefront for a language that does not name one on its own
local LANG_STORE = {
  ar = "AR", cs = "CZ", da = "DK", de = "DE", el = "GR", en = "US",
  es = "ES", fi = "FI", fr = "FR", he = "IL", hu = "HU", it = "IT",
  ja = "JP", ko = "KR", nb = "NO", nl = "NL", no = "NO", pl = "PL",
  pt = "PT", ro = "RO", ru = "RU", sv = "SE", tr = "TR", uk = "UA",
  zh = "CN",
}

-- Channel-level tags worth keeping, by the name the reader hands back
-- (libxml2 gives the qualified name, prefix included).
local FEED_FIELDS = {
  ["description"] = "description",
  ["itunes:summary"] = "summary",
  ["itunes:subtitle"] = "subtitle",
  ["itunes:author"] = "author",
  ["language"] = "language",
  ["copyright"] = "copyright",
  ["link"] = "link",
  ["title"] = "title",
}

-- Same, inside an <item>
local ITEM_FIELDS = {
  ["title"] = "title",
  ["pubDate"] = "date",
  ["itunes:duration"] = "duration",
}

local MONTHS = {
  Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
  Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

            --[[ Translations ]]--

-- The name the user sees -- in the Extensions menu, in the extension
-- manager and on the windows -- in every language this fork translates.
-- The dialogs themselves speak English or French, as the other
-- extensions do; a language missing here falls back to English, which is
-- the rule the fork already follows for its own strings.
local EXT_NAMES = {
  en = "Podcast Discovery (iTunes)",
  fr = "Découverte de Podcasts (iTunes)",
  de = "Podcast-Entdeckung (iTunes)",
  es = "Descubrimiento de podcasts (iTunes)",
  it = "Scoperta di podcast (iTunes)",
  pt_PT = "Descoberta de podcasts (iTunes)",
  pt_BR = "Descoberta de podcasts (iTunes)",
  nl = "Podcasts ontdekken (iTunes)",
  ru = "Поиск подкастов (iTunes)",
  uk = "Пошук подкастів (iTunes)",
  pl = "Odkrywanie podcastów (iTunes)",
  cs = "Objevování podcastů (iTunes)",
  sv = "Upptäck poddar (iTunes)",
  tr = "Podcast Keşfi (iTunes)",
  ja = "ポッドキャストを探す (iTunes)",
  zh_CN = "播客发现 (iTunes)",
  zh_TW = "Podcast 探索 (iTunes)",
  ko = "팟캐스트 찾기 (iTunes)",
}

--[[ Translations ]]--

-- One file per language under share/lua/i18n/podcasts/, and only the one in
-- use is ever read: eighteen catalogues parsed at every activation, to keep
-- one, is not free on the machines this fork exists for. English sits
-- underneath, string by string, so an untranslated key shows in English
-- rather than as a hole.
-- ⚠ Le catalogue ne peut PAS être chargé ici. Le scanner charge ce fichier
-- dans un état Lua nu pour y lire descriptor() : aucune bibliothèque de base,
-- et require() y est un bouchon qui rend nil (vlclua_dummy_require, dans
-- modules/lua/extension.c). Tout appel de bibliothèque au niveau du fichier
-- tue donc l'extension avant même qu'elle soit listée -- « attempt to index a
-- nil value » au scan, extension absente du menu. La table reste vide ici et
-- se remplit dans activate(), qui tourne dans un état complet : tous les
-- lang.x du fichier sont inchangés, ils lisent à travers __index.
local lang = {}

local function load_lang()
  setmetatable(lang, { __index = require("pvlc_i18n").load("podcasts") })
end

-- Worked out as the file loads rather than in activate(): descriptor()
-- is what names the menu entry, and the core asks for it long before the
-- extension is ever activated.
-- What PowerVLC is actually running in, asked of the core and of nothing
-- else. Working out the language from the environment is the core's job,
-- not an extension's: each interface applies the user's choice its own
-- way, and only the player knows what it ended up reading in. No answer
-- means English, which is what the player itself falls back to.
-- ⚠⚠ This runs while the extension is being SCANNED, in a Lua state that
-- holds almost nothing: the string library and a vlc table carrying
-- config.language(), and that is all -- not even the base library, so no
-- pcall, no type, no tostring. Touching anything else here does not fail
-- loudly: the extension simply never appears in the menu, with one line
-- in the log to say why.
local function system_locale()
  local config = vlc and vlc.config
  local ask = config and config.language
  if not ask then
    return ""
  end
  local name = ask()
  if not name or name == "" then
    return ""
  end
  if not string then
    return name
  end
  return string.lower(name)
end

local sys_lang = system_locale()
local sys_region = string.upper(string.match(sys_lang, "^%a%a[_%-](%a%a)")
                                or "")

-- The tag the translation tables are keyed by: the two languages this
-- fork ships in two written forms need their region to tell them apart.
local function locale_tag()
  if not string then
    return "en"
  end
  local code = string.match(sys_lang, "^(%a%a)") or "en"
  if code == "pt" then
    return sys_region == "BR" and "pt_BR" or "pt_PT"
  end
  if code == "zh" then
    if sys_region == "TW" or sys_region == "HK" or sys_region == "MO" then
      return "zh_TW"
    end
    return "zh_CN"
  end
  return code
end

local EXT_NAME = EXT_NAMES[locale_tag()] or EXT_NAMES.en
            --[[ State ]]--

local app = {
  -- search view
  query = "",
  kind = 1,              -- 1 = podcasts, 2 = episodes
  country = "US",
  limit = 50,
  genre = 1,             -- id picked in the genre drop-down
  genres = {},           -- id -> genre name, id 1 being "all"
  hide_explicit = false,
  results = {},          -- everything the last search returned
  rows = {},             -- row id -> result, as the list currently shows
  -- podcast view
  podcast = nil,
  episodes = {},
  ep_rows = {},
  art = nil,             -- file the artwork was written to
  description = nil,
  -- subscriptions view
  sub_rows = {},
  -- feed address -> { title, author }, so that a subscription taken here
  -- shows a name rather than a URL when it comes back in the list
  known = {},
  -- collection id -> feed address, for the shows whose feed the
  -- directory withholds and whose page had to be read to find it
  feeds = {},
}

local dlg = nil
local ui = {}

            --[[ Helpers ]]--

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- Long work has to say it is still there. The core watches the extension
-- thread and, after ten seconds without a sign of life, offers to kill
-- it -- and kills it outright when it cannot even show that question.
-- Reading a feed on a slow machine is not a hung script.
local function still_alive()
  if vlc.keep_alive then
    pcall(vlc.keep_alive)
  end
end

local function set_message(text)
  if ui.message then
    ui.message:set_text(text or "")
    -- push the update to the interface NOW: without this, a message set
    -- right before a blocking network call only shows once the call ends
    if dlg then
      dlg:update()
    end
  end
end

function close_dlg()
  if dlg ~= nil then
    dlg:hide()
    -- now rather than at the whim of the garbage collector: the
    -- finalizer blocks on the interface, possibly in the middle of
    -- building the next dialog
    dlg:delete()
  end
  dlg = nil
  ui = {}
end

-- A list cell: the tab separates columns and the unit separator carries
-- a sort key, so neither may travel inside a value.
local function cell(s)
  return (string.gsub(tostring(s or ""), "[\t\r\n\031]", " "))
end

-- "display\031key": what is shown and what it is sorted on, when the two
-- differ (a rank reads as text but orders as a number, a subscribed show
-- carries a tick that has no business dragging it to the top).
local function sortable(display, key)
  if key == nil then
    return cell(display)
  end
  return cell(display) .. "\031" .. tostring(key)
end

-- A label carrying markup is parsed as HTML by the interfaces, so a show
-- called "Rock & Roll <live>" would lose half its name. Only the few
-- labels that want bold text go through here.
local function bold(text)
  local escaped = string.gsub(cell(text), "&", "&amp;")
  escaped = string.gsub(escaped, "<", "&lt;")
  escaped = string.gsub(escaped, ">", "&gt;")
  return "<b>" .. escaped .. "</b>"
end

local function fold_accents(s)
  s = s or ""
  if vlc.strings and vlc.strings.fold then
    local ok, folded = pcall(vlc.strings.fold, s)
    if ok and folded then
      return folded
    end
  end
  return string.lower(s)
end

-- Long descriptions would stretch the dialog: keep the first words only
local function shorten(text, max)
  text = trim(string.gsub(text or "", "%s+", " "))
  if #text <= max then
    return text
  end
  local cut = string.sub(text, 1, max)
  -- never cut inside a UTF-8 sequence (continuation bytes are 8x/Bx)
  while #cut > 0 and string.byte(cut, #cut) >= 128
                 and string.byte(cut, #cut) < 192 do
    cut = string.sub(cut, 1, #cut - 1)
  end
  cut = string.match(cut, "^(.*)%s%S*$") or cut
  return cut .. "…"
end

-- Lua 5.1 has no string.char above 255
local function utf8_char(cp)
  if cp < 128 then
    return string.char(cp)
  elseif cp < 2048 then
    return string.char(192 + math.floor(cp / 64), 128 + cp % 64)
  elseif cp < 65536 then
    return string.char(224 + math.floor(cp / 4096),
                       128 + math.floor(cp / 64) % 64, 128 + cp % 64)
  end
  return string.char(240 + math.floor(cp / 262144),
                     128 + math.floor(cp / 4096) % 64,
                     128 + math.floor(cp / 64) % 64, 128 + cp % 64)
end

local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'",
  nbsp = " ", hellip = "…", mdash = "—", ndash = "–",
  rsquo = "’", lsquo = "‘", ldquo = "“", rdquo = "”",
}

-- Feed descriptions are HTML wrapped in CDATA: the XML reader hands that
-- back verbatim, markup, entities and all.
local function html_to_text(s)
  s = s or ""
  s = string.gsub(s, "<[bB][rR]%s*/?>", " ")
  s = string.gsub(s, "</[pP]>", " ")
  s = string.gsub(s, "<[^>]*>", "")
  s = string.gsub(s, "&#[xX](%x+);", function(hex)
    return utf8_char(tonumber(hex, 16) or 63)
  end)
  s = string.gsub(s, "&#(%d+);", function(dec)
    return utf8_char(tonumber(dec) or 63)
  end)
  s = string.gsub(s, "&(%a+);", function(name)
    return ENTITIES[name] or ("&" .. name .. ";")
  end)
  return trim(string.gsub(s, "%s+", " "))
end

-- vlc.clipboard is this fork's native API (macOS + Windows); elsewhere it
-- reports failure and the address stays selectable in its field.
local function copy_to_clipboard(text)
  if vlc.clipboard and vlc.clipboard.set then
    local ok, done = pcall(vlc.clipboard.set, text)
    if ok and done then
      return true
    end
  end
  return false
end

-- "2026-07-28T20:06:00Z" -> "2026-07-28". Kept in ISO form on purpose:
-- the interface sorts cells as text, and only this shape sorts right.
local function iso_date(stamp)
  return string.match(tostring(stamp or ""), "^(%d%d%d%d%-%d%d%-%d%d)")
end

-- "Tue, 04 Aug 2026 08:40:18 +0000" -> "2026-08-04". A feed that already
-- writes ISO is taken as it is.
local function feed_date(stamp)
  local day, mon, year = string.match(tostring(stamp or ""),
                                      "(%d%d?)%s+(%a%a%a)%s+(%d%d%d%d)")
  local month = day and MONTHS[mon]
  if month then
    return string.format("%04d-%02d-%02d", tonumber(year), month,
                         tonumber(day))
  end
  return nil
end

-- <itunes:duration> is written as h:mm:ss, as mm:ss, or as a plain
-- number of seconds, depending on who publishes the feed.
local function feed_duration_ms(text)
  text = trim(text or "")
  if text == "" then
    return nil
  end
  local h, m, s = string.match(text, "^(%d+):(%d+):(%d+)$")
  if h then
    return ((tonumber(h) * 60 + tonumber(m)) * 60 + tonumber(s)) * 1000
  end
  local mm, ss = string.match(text, "^(%d+):(%d+)$")
  if mm then
    return (tonumber(mm) * 60 + tonumber(ss)) * 1000
  end
  local seconds = tonumber(text)
  if seconds then
    return math.floor(seconds) * 1000
  end
  return nil
end

-- "1 abonnements" reads as a bug even when the number is right
local function plural(n, one, many)
  if n == 1 and one then
    return one
  end
  return many
end

local function format_duration(ms)
  local total = math.floor((tonumber(ms) or 0) / 1000)
  if total <= 0 then
    return nil, nil
  end
  local hours = math.floor(total / 3600)
  local minutes = math.floor(total / 60) % 60
  local seconds = total % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds), total
  end
  return string.format("%d:%02d", minutes, seconds), total
end

            --[[ Settings kept between sessions ]]--

-- The store and the kind of search are a habit, not a choice to make
-- again every time; the shows subscribed to from here keep their name so
-- that the subscription list reads as names rather than as addresses.
local function settings_path()
  local dir = vlc.config and vlc.config.userdatadir
               and vlc.config.userdatadir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/podcasts.json"
end

local function copy_map(t)
  local out = {}
  if type(t) == "table" then
    for key, value in pairs(t) do
      if type(key) == "string" then
        out[key] = value
      end
    end
  end
  return out
end

local function load_settings()
  local path = settings_path()
  if not (path and json) then
    return
  end
  local f = io.open(path, "r")
  if not f then
    return
  end
  local body = f:read("*a")
  f:close()
  local obj = json.decode(body or "")
  if type(obj) ~= "table" then
    return
  end
  if type(obj.country) == "string" and lang.countries[obj.country] then
    app.country = obj.country
  end
  if type(obj.kind) == "number" and (obj.kind == 1 or obj.kind == 2) then
    app.kind = obj.kind
  end
  if type(obj.limit) == "number" then
    for _, n in ipairs(SEARCH_LIMITS) do
      if n == obj.limit then
        app.limit = n
      end
    end
  end
  -- an explicit false must be able to untick the box, which
  -- "obj.hide_explicit or false" would do; the type test is the point
  if type(obj.hide_explicit) == "boolean" then
    app.hide_explicit = obj.hide_explicit
  end
  -- ⚠⚠ Copied key by key, never taken as they are. An empty table is
  -- written as "[]", and dkjson brings that back TAGGED AS AN ARRAY
  -- (__jsontype) -- put string keys in it afterwards and the next save
  -- silently drops every one of them. A map saved empty once would then
  -- stay empty for good. Rebuilding the table drops the tag with it.
  app.known = copy_map(obj.known)
  app.feeds = copy_map(obj.feeds)
end

-- A file that cannot be written is not worth a word to the user: nothing
-- is lost but the shortcut.
local function save_settings()
  local path = settings_path()
  if not (path and json) then
    return
  end
  local f = io.open(path, "w")
  if not f then
    vlc.msg.dbg("[Podcasts] cannot write " .. path)
    return
  end
  f:write(json.encode({
    country = app.country,
    kind = app.kind,
    limit = app.limit,
    hide_explicit = app.hide_explicit,
    known = app.known,
    feeds = app.feeds,
  }, { indent = true }))
  f:close()
end

            --[[ HTTP ]]--

-- ⚠⚠⚠ vlc.stream() is NOT usable here. It goes through
-- vlc_stream_NewMRL(), which chains every content filter that recognises
-- what is arriving -- and the "playlist" filter turns anything VLC knows
-- how to parse into a DIRECTORY stream. A podcast feed is exactly that:
-- the log says "using podcast reader", every read returns nothing, and
-- no error is raised anywhere. vlc.raw_stream() opens the same address
-- and hands back the bytes.
local function open_stream(url)
  local open = vlc.raw_stream or vlc.stream
  local ok, s = pcall(open, url)
  if not ok or not s then
    return nil
  end
  return s
end

-- HTTP(S) GET through VLC's stream layer.
-- Returns the raw body, or nil and a message.
local function get_body(url)
  vlc.msg.dbg("[Podcasts] GET " .. url)
  local s = open_stream(url)
  if not s then
    return nil, lang.msg_net_fail
  end
  local parts = {}
  while true do
    still_alive()
    local chunk = s:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      break
    end
    table.insert(parts, chunk)
  end
  local body = table.concat(parts)
  if body == "" then
    return nil, lang.msg_net_fail
  end
  return body
end

local function get_json(url)
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  local obj = json.decode(body)
  if type(obj) ~= "table" then
    return nil, lang.msg_bad_answer
  end
  return obj
end

            --[[ The iTunes Search API ]]--

local function esc(s)
  if vlc.strings and vlc.strings.encode_uri_component then
    return vlc.strings.encode_uri_component(tostring(s or ""))
  end
  return (string.gsub(tostring(s or ""), "[^%w%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Apple serves every size of a picture from the same path, the last
-- element naming it. Asking for the size actually displayed saves both a
-- 600x600 download and a rescale on machines that have neither to spare.
local function artwork_url(entry, size)
  local url = entry.art_big or entry.art_small
  if not url or url == "" then
    return nil
  end
  return (string.gsub(url, "/%d+x%d+bb%.", "/" .. size .. "x" .. size .. "bb."))
end

-- One shape for both kinds of result, so that the list, the detail view
-- and the playlist all read the same fields.
local function normalize(r)
  if type(r) ~= "table" then
    return nil
  end
  -- A show states its genres as plain names, an episode as objects
  -- carrying the name and Apple's genre id. Same field, two shapes.
  local genres = {}
  if type(r.genres) == "table" then
    for _, g in ipairs(r.genres) do
      local name = (type(g) == "table") and g.name or g
      -- every podcast is filed under "Podcasts": saying so filters nothing
      if type(name) == "string" and name ~= "Podcasts" and name ~= "Podcast" then
        table.insert(genres, name)
      end
    end
  end
  local e = {
    id = r.collectionId or r.trackId,
    collection_id = r.collectionId,
    title = r.trackName or r.collectionName or "?",
    collection_name = r.collectionName,
    author = r.artistName,
    feed = r.feedUrl,
    -- an episode names no primary genre: its first one stands in, so
    -- that the genre column and its filter work on both kinds of row
    genre = r.primaryGenreName or genres[1],
    genres = genres,
    art_small = r.artworkUrl100 or r.artworkUrl60,
    art_big = r.artworkUrl600 or r.artworkUrl100,
    count = tonumber(r.trackCount),
    released = iso_date(r.releaseDate),
    country = r.country,
    view_url = r.trackViewUrl or r.collectionViewUrl,
    description = r.description or r.shortDescription,
    -- collectionExplicitness reads "notExplicit" on every single podcast
    -- the API returns, whatever the show; contentAdvisoryRating is the
    -- field that actually tells them apart (measured, 100 results).
    explicit = (r.contentAdvisoryRating == "Explicit")
               or (r.trackExplicitness == "explicit")
               or (r.collectionExplicitness == "explicit"),
  }
  if r.wrapperType == "podcastEpisode" or r.kind == "podcast-episode" then
    e.kind = "episode"
    e.media = r.episodeUrl
    e.duration_ms = tonumber(r.trackTimeMillis)
  else
    e.kind = "podcast"
  end
  -- Folded once, here. The filter box refilters at every keystroke and
  -- the list is redrawn each time: folding the same hundred rows over
  -- and over is work an old machine should not be made to repeat.
  e.sort_key = fold_accents(e.collection_name or e.title)
  e.search_key = fold_accents(table.concat({
    e.title or "", e.author or "", e.collection_name or "", e.genre or "",
  }, " "))
  return e
end

-- Apple names the genres in the store's own language unless told
-- otherwise, and "lang" is the only say we have in it -- it accepts
-- exactly two values, no more. Asked for only when the player's own
-- language is one of them: an English player browsing the Japanese
-- store would otherwise be handed genre names it cannot read, while for
-- every other language the store's own wording beats forcing English.
local function lang_param()
  local code = string.match(sys_lang, "^(%a%a)")
  if code == "ja" then
    return "&lang=ja_jp"
  end
  if code == "en" then
    return "&lang=en_us"
  end
  return ""
end

local function itunes_search(term, kind, country, limit)
  local entity = (kind == 2) and "podcastEpisode" or "podcast"
  local url = "https://itunes.apple.com/search?media=podcast"
           .. "&entity=" .. entity
           .. "&country=" .. esc(country)
           .. "&limit=" .. tostring(limit)
           .. lang_param()
           .. "&term=" .. esc(term)
  local obj, err = get_json(url)
  if not obj then
    return nil, err
  end
  -- The directory lists the same show more than once: one RSS feed
  -- submitted twice to the store gets two collection ids, and both come
  -- back. Nothing tells them apart on screen -- same name, same author,
  -- same artwork -- so they read as a plain bug ("La dernière", measured
  -- 06/08: 6 rows of 74 were a repeat of another). What the two entries
  -- share is the feed they point at, which is the podcast itself; for
  -- episodes it is the audio file. First one wins: the store returns
  -- them in relevance order and that is the one to keep.
  local out, seen = {}, {}
  for _, r in ipairs(obj.results or {}) do
    local e = normalize(r)
    if e then
      local key
      if e.kind == "episode" then
        key = e.media
      elseif e.feed then
        key = string.lower((string.gsub(e.feed, "/+$", "")))
      end
      -- an entry with nothing to compare on is kept: better a repeat
      -- than a show silently dropped
      if not key then
        table.insert(out, e)
      elseif not seen[key] then
        seen[key] = true
        table.insert(out, e)
      end
    end
  end
  return out
end

-- One lookup gives the show in full plus its latest episodes, which is
-- all the detail view needs whichever kind of row was opened.
local function itunes_lookup(id, country)
  local url = "https://itunes.apple.com/lookup?id=" .. esc(id)
           .. "&entity=podcastEpisode"
           .. "&limit=" .. tostring(EPISODE_LIMIT)
           .. "&country=" .. esc(country)
           .. lang_param()
  local obj, err = get_json(url)
  if not obj then
    return nil, nil, err
  end
  local podcast, episodes = nil, {}
  for _, r in ipairs(obj.results or {}) do
    local e = normalize(r)
    if e and e.kind == "episode" then
      table.insert(episodes, e)
    elseif e and not podcast then
      podcast = e
    end
  end
  return podcast, episodes
end

            --[[ Feeds the directory does not hand out ]]--

-- Reads the show's page on Apple's site and stops at the address, which
-- is embedded in the data the page carries. Nothing here is scraped out
-- of the layout: the marker is a field name in a JSON payload.
local function scrape_feed(url)
  local s = open_stream(url)
  if not s then
    return nil
  end
  local carry, read = "", 0
  while read < FEED_PAGE_MAX do
    still_alive()
    local chunk = s:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      break
    end
    read = read + #chunk
    local buf = carry .. chunk
    local at = string.find(buf, FEED_MARK, 1, true)
    if at then
      local rest = string.sub(buf, at + #FEED_MARK)
      -- the address may straddle the chunk boundary: read on until the
      -- quote that closes it has been seen
      while not string.find(rest, "\"", 1, true) and read < FEED_PAGE_MAX do
        local more = s:read(READ_CHUNK)
        if not more or #more == 0 then
          break
        end
        read = read + #more
        rest = rest .. more
      end
      local feed = string.match(rest, "^([^\"]*)")
      -- JSON writes its slashes escaped
      feed = string.gsub(feed or "", "\\/", "/")
      if string.match(feed, "^https?://") then
        return feed
      end
      return nil
    end
    -- keep enough of the tail for a marker split across two reads
    carry = string.sub(buf, -1024)
  end
  return nil
end

-- The one door to a feed address, whichever view asks for it.
local function ensure_feed(entry)
  if not entry then
    return nil
  end
  if entry.feed and entry.feed ~= "" then
    return entry.feed
  end
  local id = entry.collection_id or entry.id
  local cached = id and app.feeds[tostring(id)]
  if cached then
    entry.feed = cached
    return cached
  end
  if not entry.view_url then
    return nil
  end
  set_message(lang.msg_finding_feed)
  local feed = scrape_feed(entry.view_url)
  if feed and id then
    app.feeds[tostring(id)] = feed
    save_settings()
  end
  entry.feed = feed
  return feed
end

            --[[ The show's own feed ]]--

-- The directory does not carry a podcast description -- not in search,
-- not in lookup. The feed does, above its episodes, so that is where it
-- is read from, and by default reading stops at the very first <item>: a
-- show with a thousand episodes is megabytes long and none of that is
-- wanted here (measured: 2.6 kB read instead of 2.1 MB).
--
-- want_items goes further, as far as EPISODE_LIMIT items, and is asked
-- for only when the directory listed no episode at all.
local function fetch_feed(url, want_items)
  vlc.msg.dbg("[Podcasts] FEED " .. url
              .. (want_items and " (with items)" or " (head only)"))
  local s = open_stream(url)
  if not s then
    vlc.msg.dbg("[Podcasts] feed unreachable")
    return nil
  end
  local ceiling = want_items and FEED_ITEMS_MAX or FEED_HEAD_MAX
  local buf, truncated = "", false
  local seen, scan = 0, 1
  while true do
    if #buf >= ceiling then
      truncated = true
      break
    end
    still_alive()
    local chunk = s:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      break
    end
    buf = buf .. chunk
    if want_items then
      -- counted from where the last count stopped, not from the top
      while true do
        local at = string.find(buf, "<item[%s>]", scan)
        if not at then
          break
        end
        seen = seen + 1
        scan = at + 5
      end
      if seen > EPISODE_LIMIT then
        truncated = true
        break
      end
    else
      local at = string.find(buf, "<item[%s>]")
      if at then
        buf = string.sub(buf, 1, at - 1)
        truncated = true
        break
      end
    end
  end
  s = nil
  if buf == "" then
    return nil
  end
  if truncated and want_items then
    -- drop the item that was cut in half
    local last, from = nil, 1
    while true do
      local a, b = string.find(buf, "</item>", from, true)
      if not a then
        break
      end
      last, from = b, b + 1
    end
    if last then
      buf = string.sub(buf, 1, last)
    end
  end
  if truncated then
    -- what was cut away took the closing tags with it
    buf = buf .. "</channel></rss>"
  end

  -- Locals keep xml and stream alive for the whole parse: the C reader
  -- holds no Lua reference, and the GC freeing them mid-parse is a
  -- segfault, not an error.
  vlc.msg.dbg("[Podcasts] feed: " .. #buf .. " bytes read, "
              .. (truncated and "stopped early" or "whole"))
  local xml = vlc.xml()
  local stream = vlc.memory_stream(buf)
  local reader = xml and stream and xml:create_reader(stream)
  if not reader then
    vlc.msg.dbg("[Podcasts] no XML reader")
    return nil
  end

  local info = { items = {} }
  local item, current, text = nil, nil, nil
  local nodetype, nodename = reader:next_node()
  while nodetype > 0 do
    if nodetype == 1 then
      current, text = nodename, ""
      if nodename == "item" then
        item = {}
      elseif nodename == "enclosure" and item then
        -- an empty element: its attributes are all it has, and the
        -- reader raises no closing event for it
        local attr, value = reader:next_attr()
        while attr ~= nil do
          if attr == "url" and not item.url then
            item.url = value
          end
          attr, value = reader:next_attr()
        end
      elseif nodename == "itunes:image" and not item then
        local attr, value = reader:next_attr()
        while attr ~= nil do
          if attr == "href" and not info.image then
            info.image = value
          end
          attr, value = reader:next_attr()
        end
      end
    elseif nodetype == 3 then
      -- text arrives in as many pieces as the reader feels like
      if current then
        text = (text or "") .. nodename
      end
    elseif nodetype == 2 then
      if nodename == "item" then
        if item and item.url and #info.items < EPISODE_LIMIT then
          table.insert(info.items, item)
          still_alive()
        end
        item = nil
      else
        -- an item's fields are its own; outside one they are the
        -- channel's. First one wins on both sides: the channel states
        -- its title, its link and its description before <image> and
        -- <owner> restate theirs.
        local target = item or info
        local key = item and ITEM_FIELDS[nodename] or FEED_FIELDS[nodename]
        if key and current == nodename and not target[key]
           and text and trim(text) ~= "" then
          target[key] = trim(text)
        end
      end
      current, text = nil, nil
    end
    nodetype, nodename = reader:next_node()
  end
  vlc.msg.dbg("[Podcasts] feed parsed: description "
              .. (info.description and #info.description or -1)
              .. ", summary " .. (info.summary and #info.summary or -1)
              .. ", " .. #info.items .. " items")
  return info
end

-- The items a feed carries, in the shape the rest of the script uses
local function episodes_from_feed(info, podcast)
  local out = {}
  for _, it in ipairs((info and info.items) or {}) do
    local title = html_to_text(it.title)
    if title == "" then
      title = it.title or "?"
    end
    table.insert(out, {
      kind = "episode",
      title = title,
      collection_name = podcast.collection_name or podcast.title,
      collection_id = podcast.collection_id,
      author = podcast.author,
      released = feed_date(it.date) or iso_date(it.date),
      duration_ms = feed_duration_ms(it.duration),
      media = it.url,
      art_small = podcast.art_small,
      art_big = podcast.art_big,
      genres = {},
    })
  end
  return out
end

-- Feeds disagree on which tag holds the real text: some write a sentence
-- in <description> and the whole presentation in <itunes:summary>, some
-- the other way round. Take whichever says the most.
local function best_description(info)
  if type(info) ~= "table" then
    return nil
  end
  local best = nil
  for _, key in ipairs({ "description", "summary", "subtitle" }) do
    local candidate = html_to_text(info[key])
    if candidate ~= "" and (not best or #candidate > #best) then
      best = candidate
    end
  end
  return best
end

            --[[ Artwork ]]--

local function fetch_artwork(entry)
  local dir = vlc.config and vlc.config.userdatadir
               and vlc.config.userdatadir()
  local url = artwork_url(entry, ARTWORK_SIZE)
  if not url or not dir or dir == "" or not entry.id then
    return nil
  end
  local path = dir .. "/podcast-art-" .. tostring(entry.id)
            .. "-" .. ARTWORK_SIZE .. ".jpg"
  local cached = io.open(path, "rb")
  if cached then
    local size = cached:seek("end")
    cached:close()
    if size and size > 128 then
      return path
    end
  end

  local body = get_body(url)
  if not body or #body < 128 then
    return nil
  end
  -- Apple's thumbnails are JPEG and already the size asked for, so the
  -- normal path pays no decoding at all; the detour only serves the odd
  -- feed picture that comes back as something else.
  local is_jpeg = string.byte(body, 1) == 255 and string.byte(body, 2) == 216
  local raw = path .. ".part"
  local f = io.open(raw, "wb")
  if not f then
    return nil
  end
  f:write(body)
  f:close()

  local scaled = false
  if not is_jpeg and vlc.misc and vlc.misc.image_scale then
    local ok, width = pcall(vlc.misc.image_scale, raw, path,
                            ARTWORK_SIZE, ARTWORK_SIZE)
    if ok and width then
      local check = io.open(path, "rb")
      if check then
        local written = check:seek("end")
        check:close()
        scaled = written ~= nil and written > 128
      end
    end
  end
  if scaled then
    os.remove(raw)
  else
    os.remove(path)
    os.rename(raw, path)
  end
  return path
end

            --[[ Subscriptions ]]--

-- The same feed written with and without its trailing slash is one
-- subscription, not two.
local function feed_key(url)
  return (string.gsub(trim(url or ""), "/+$", ""))
end

-- "podcast-urls" is one pipe-separated string, shared by the Podcasts
-- service and its stored preference -- the very same the sidebar writes.
local function subscribed_list()
  local raw = nil
  -- config_GetType() only knows the setting once the module holding it
  -- has been seen: an unreadable preference is an empty list, not a
  -- broken extension
  local ok, value = pcall(vlc.config.get, "podcast-urls")
  if ok then
    raw = value
  end
  local out = {}
  for url in string.gmatch(tostring(raw or ""), "[^|]+") do
    url = trim(url)
    if url ~= "" then
      table.insert(out, url)
    end
  end
  return out
end

-- Filling a hundred rows must not read the preference a hundred times:
-- the set is built once and thrown away the moment it is written to.
local sub_set = nil

local function subscribed_set()
  if not sub_set then
    sub_set = {}
    for _, url in ipairs(subscribed_list()) do
      sub_set[feed_key(url)] = true
    end
  end
  return sub_set
end

local function write_subscriptions(list)
  local joined = table.concat(list, "|")
  local ok = pcall(vlc.config.set, "podcast-urls", joined)
  if not ok then
    return false
  end
  sub_set = nil
  -- the preference carries the list over to the next launch, the
  -- playlist variable wakes the running module up so that the node is
  -- rebuilt on the spot; the variable only exists while it runs, and its
  -- absence is not a failure
  local pl = vlc.object and vlc.object.playlist and vlc.object.playlist()
  if pl then
    pcall(vlc.var.set, pl, "podcast-urls", joined)
  end
  return true
end

local function same_feed(a, b)
  a, b = feed_key(a), feed_key(b)
  return a ~= "" and a == b
end

local function is_subscribed(url)
  local key = feed_key(url)
  return key ~= "" and subscribed_set()[key] == true
end

local function subscribe(entry)
  local url = ensure_feed(entry)
  if not url or url == "" then
    return false, lang.msg_feed_hidden
  end
  if is_subscribed(url) then
    return false, lang.msg_already
  end
  local list = subscribed_list()
  table.insert(list, url)
  if not write_subscriptions(list) then
    return false, lang.msg_sub_failed
  end
  app.known[url] = {
    title = entry.collection_name or entry.title,
    author = entry.author,
  }
  save_settings()
  -- Subscribing to a service that is not shown would be a preference
  -- nobody ever sees: switch Podcasts on, which is where the show has
  -- just been filed.
  if vlc.sd and vlc.sd.is_loaded and not vlc.sd.is_loaded("podcast") then
    pcall(vlc.sd.add, "podcast")
  end
  return true, lang.msg_subscribed
end

local function unsubscribe(url)
  local list = subscribed_list()
  local kept = {}
  local found = false
  for _, known in ipairs(list) do
    if same_feed(known, url) then
      found = true
    else
      table.insert(kept, known)
    end
  end
  if not found then
    return false
  end
  if not write_subscriptions(kept) then
    return false
  end
  return true
end

            --[[ Playback ]]--

local function playlist_item(entry)
  local item = {
    path = (entry.kind == "episode") and entry.media or entry.feed,
    name = entry.title,
    title = entry.title,
    artist = entry.author or entry.collection_name,
    album = entry.collection_name,
  }
  if entry.kind == "episode" then
    item.album = entry.collection_name
    local _, seconds = format_duration(entry.duration_ms)
    item.duration = seconds
  end
  -- 300 and not the 600 Apple offers: the player only ever shows this
  -- small, and a machine of that age pays for every pixel it decodes
  local art = artwork_url(entry, 300)
  if art then
    item.arturl = art
  end
  return item
end

local function play_entries(entries, queue)
  local items = {}
  for _, e in ipairs(entries) do
    -- a show plays through its feed, which may still have to be found
    if e.kind ~= "episode" then
      ensure_feed(e)
    end
    local item = playlist_item(e)
    if item.path and item.path ~= "" then
      table.insert(items, item)
    end
  end
  if #items == 0 then
    set_message(lang.msg_no_feed)
    return
  end
  if queue then
    vlc.playlist.enqueue(items)
    set_message(lang.msg_queued)
  else
    vlc.playlist.add(items)
    set_message(lang.msg_playing)
  end
end

            --[[ Results: filtering and filling ]]--

local function selected_genre()
  local id = ui.genre and ui.genre:get_value() or app.genre
  -- a drop-down never touched answers -1
  if type(id) ~= "number" or id < 1 then
    id = 1
  end
  app.genre = id
  return app.genres[id]
end

local function entry_has_genre(entry, name)
  if not name then
    return true
  end
  if entry.genre == name then
    return true
  end
  for _, g in ipairs(entry.genres or {}) do
    if g == name then
      return true
    end
  end
  return false
end

local function entry_matches(entry, needle)
  if needle == "" then
    return true
  end
  return string.find(entry.search_key or "", needle, 1, true) ~= nil
end

local function build_genres()
  -- what was picked before, by name: the ids are rebuilt with the list
  local wanted = app.genres[app.genre]
  local seen, names = {}, {}
  for _, e in ipairs(app.results) do
    for _, g in ipairs(e.genres or {}) do
      if not seen[g] then
        seen[g] = true
        table.insert(names, g)
      end
    end
    if e.genre and not seen[e.genre] then
      seen[e.genre] = true
      table.insert(names, e.genre)
    end
  end
  table.sort(names)
  app.genres = {}
  app.genre = 1
  if not ui.genre then
    return
  end
  ui.genre:clear()
  ui.genre:add_value(lang.all_genres, 1)
  for i, name in ipairs(names) do
    app.genres[i + 1] = name
    ui.genre:add_value(cell(name), i + 1)
    if name == wanted then
      app.genre = i + 1
      ui.genre:set_value(i + 1)
    end
  end
end

local function podcast_row(entry, rank)
  local subscribed = entry.feed and is_subscribed(entry.feed)
  local name = entry.collection_name or entry.title
  return table.concat({
    sortable(rank, rank),
    -- the tick says what is already subscribed to without disturbing the
    -- order a click on the header gives
    sortable((subscribed and "✓ " or "") .. cell(name), entry.sort_key),
    cell(entry.author or ""),
    cell(entry.genre or ""),
    entry.count and sortable(entry.count, entry.count) or "",
    cell(entry.released or ""),
  }, "\t")
end

local function episode_row(entry, rank)
  local length, seconds = format_duration(entry.duration_ms)
  return table.concat({
    sortable(rank, rank),
    cell(entry.title),
    cell(entry.collection_name or ""),
    cell(entry.released or ""),
    length and sortable(length, seconds) or "",
  }, "\t")
end

function fill_results()
  if not ui.results then
    return
  end
  local needle = fold_accents(trim(ui.filter and ui.filter:get_text() or ""))
  local genre = selected_genre()
  local hide = ui.explicit and ui.explicit:get_checked() or false
  app.hide_explicit = hide
  -- read once per fill, not once per row, and never stale: the sidebar
  -- may have added or dropped a feed while this window was open
  sub_set = nil

  app.rows = {}
  ui.results:clear()
  local shown = 0
  for rank, entry in ipairs(app.results) do
    if entry_matches(entry, needle) and entry_has_genre(entry, genre)
       and not (hide and entry.explicit) then
      shown = shown + 1
      if shown % 200 == 0 then
        still_alive()
      end
      app.rows[shown] = entry
      ui.results:add_value(app.kind == 2 and episode_row(entry, rank)
                                          or podcast_row(entry, rank), shown)
    end
  end

  if #app.results == 0 then
    set_message(app.query == "" and lang.msg_hint or lang.msg_no_result)
  else
    set_message(string.format(
      plural(#app.results, lang.msg_count_one, lang.msg_count),
      shown, #app.results))
  end
end

local function selected_results()
  if not ui.results then
    return {}
  end
  local sel = ui.results:get_selection()
  local out = {}
  for id, entry in pairs(app.rows) do
    if sel[id] then
      table.insert(out, entry)
    end
  end
  return out
end

local function selected_episodes()
  if not ui.episodes then
    return {}
  end
  local sel = ui.episodes:get_selection()
  local out = {}
  for id, entry in pairs(app.ep_rows) do
    if sel[id] then
      table.insert(out, entry)
    end
  end
  -- Nothing picked, but this page was opened FROM an episode: that episode
  -- is what the user came for, so play and enqueue act on it rather than
  -- telling them to select something they already selected once.
  if #out == 0 and app.opened_episode then
    table.insert(out, app.opened_episode)
  end
  return out
end

-- Make sure the episode that opened this page is in the list.
--
-- The directory hands back a show's LATEST episodes and the feed read stops
-- at a ceiling, so an episode a few months old is very often in neither: the
-- page opened on a list that did not contain what had just been clicked, with
-- no way to scroll to it because it was never there. Its own search row
-- carries everything a row needs -- title, date, length and the audio URL --
-- so it is put in when it is missing.
local function ensure_opened_episode()
  local want = app.opened_episode
  if not want then
    return
  end
  for _, ep in ipairs(app.episodes) do
    if (want.media and ep.media == want.media)
    or (want.title and ep.title == want.title) then
      return
    end
  end
  table.insert(app.episodes, 1, want)
end

            --[[ Actions ]]--

function do_search()
  local term = trim(ui.term and ui.term:get_text() or "")
  if term == "" then
    set_message(lang.msg_enter_term)
    return
  end
  app.query = term
  -- a drop-down nobody touched answers -1: keep what was already chosen
  local kind = ui.kind and ui.kind:get_value()
  if kind == 1 or kind == 2 then
    app.kind = kind
  end
  local store = ui.store and ui.store:get_value()
  if type(store) == "number" and STOREFRONTS[store] then
    app.country = STOREFRONTS[store]
  end
  local limit = ui.limit and ui.limit:get_value()
  if type(limit) == "number" and SEARCH_LIMITS[limit] then
    app.limit = SEARCH_LIMITS[limit]
  end
  save_settings()

  set_message(lang.msg_searching)
  local results, err = itunes_search(app.query, app.kind, app.country,
                                     app.limit)
  if not results then
    app.results = {}
    fill_results()
    set_message(err or lang.msg_net_fail)
    return
  end
  app.results = results
  -- the columns change with the kind of result, so the view is rebuilt
  -- rather than refilled; the search itself is already done
  show_search()
end

-- Whichever kind of row was opened, the show is what the page describes:
-- an episode names the collection it belongs to, and one lookup on that
-- id brings back the show in full together with its latest episodes.
function open_entry(entry)
  -- Opening an episode opens the show it belongs to, which is the page worth
  -- reading -- but the episode itself must not be lost on the way there.
  -- See ensure_opened_episode() and selected_episodes().
  app.opened_episode = ( entry.kind == "episode" and entry.media )
                       and entry or nil

  local id = entry.collection_id or entry.id
  if not id then
    set_message(lang.msg_no_feed)
    return
  end
  set_message(lang.msg_loading)
  local podcast, episodes, err = itunes_lookup(id, app.country)
  if not podcast then
    -- The row already carries enough to show a page. Copied and not
    -- borrowed: an episode row must stay an episode in the list it came
    -- from, whatever the page it opened turns it into here.
    if err then
      vlc.msg.dbg("[Podcasts] lookup failed: " .. tostring(err))
    end
    podcast = {
      kind = "podcast",
      id = id,
      collection_id = id,
      title = entry.collection_name or entry.title,
      collection_name = entry.collection_name or entry.title,
      author = entry.author,
      feed = entry.feed,
      view_url = entry.view_url,
      genre = entry.genre,
      genres = entry.genres,
      art_small = entry.art_small,
      art_big = entry.art_big,
      released = entry.released,
      count = entry.count,
      explicit = entry.explicit,
    }
    episodes = {}
  end
  app.podcast = podcast
  app.episodes = episodes or {}
  app.art = fetch_artwork(podcast)

  -- the row that was opened may already know an address the lookup does
  -- not carry, and either of them may need the show's page read
  if not podcast.feed then
    podcast.feed = entry.feed
    podcast.view_url = podcast.view_url or entry.view_url
    ensure_feed(podcast)
  end

  app.description = nil
  if podcast.feed then
    set_message(lang.msg_loading_feed)
    -- The directory lists no episode for a great many shows; theirs are
    -- read from the feed instead, which costs going past its first
    -- item -- so it is only ever done when there is nothing else.
    local need_items = #app.episodes == 0
    local info = fetch_feed(podcast.feed, need_items)
    app.description = best_description(info)
    if info and info.author and not podcast.author then
      podcast.author = info.author
    end
    if need_items and info then
      app.episodes = episodes_from_feed(info, podcast)
    end
  end
  -- No made-up stand-in when the feed says nothing: an episode's own
  -- summary would read as the show's, and it is not.
  ensure_opened_episode()
  show_podcast()
end

            --[[ Widget callbacks ]]--

function click_search()
  do_search()
end

function click_filter_changed()
  fill_results()
end

function click_genre_changed()
  fill_results()
end

function click_explicit_toggled()
  app.hide_explicit = ui.explicit and ui.explicit:get_checked() or false
  save_settings()
  fill_results()
end

function click_open_result()
  local rows = selected_results()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  open_entry(rows[1])
end

function click_play_result()
  local rows = selected_results()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  play_entries(rows, false)
end

function click_subscribe_result()
  local rows = selected_results()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  local subscribed, message = subscribe(rows[1])
  set_message(message)
  if subscribed then
    -- the tick belongs on the row now
    fill_results()
  end
end

function click_subscribe()
  local subscribed, message = subscribe(app.podcast)
  if subscribed then
    show_podcast()
  end
  set_message(message)
end

function click_unsubscribe()
  if app.podcast and app.podcast.feed and unsubscribe(app.podcast.feed) then
    show_podcast()
    set_message(lang.msg_unsubscribed)
  else
    set_message(lang.msg_sub_failed)
  end
end

function click_copy_feed()
  local url = app.podcast and app.podcast.feed or ""
  set_message(copy_to_clipboard(url) and lang.msg_copied
                                      or lang.msg_copy_failed)
end

function click_play_podcast()
  play_entries({ app.podcast }, false)
end

function click_play_episode()
  local rows = selected_episodes()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  play_entries(rows, false)
end

function click_enqueue_episode()
  local rows = selected_episodes()
  if #rows == 0 then
    set_message(lang.msg_select_first)
    return
  end
  play_entries(rows, true)
end

function click_unsubscribe_selected()
  if not ui.subs then
    return
  end
  local sel = ui.subs:get_selection()
  local dropped = 0
  for id, url in pairs(app.sub_rows) do
    if sel[id] then
      if unsubscribe(url) then
        dropped = dropped + 1
      end
    end
  end
  if dropped == 0 then
    set_message(lang.msg_select_first)
    return
  end
  show_subscriptions()
  set_message(lang.msg_unsubscribed)
end

function click_play_subscription()
  if not ui.subs then
    return
  end
  local sel = ui.subs:get_selection()
  local entries = {}
  for id, url in pairs(app.sub_rows) do
    if sel[id] then
      local known = app.known[url] or {}
      table.insert(entries, { kind = "podcast", feed = url,
                              title = known.title or url,
                              author = known.author })
    end
  end
  if #entries == 0 then
    set_message(lang.msg_select_first)
    return
  end
  play_entries(entries, false)
end

            --[[ Views ]]--

-- Fits an 800x600 screen, which is what the oldest machines this fork
-- still runs on have; the providers clamp anything wider to the screen
-- anyway, but a window that never needed clamping never flickers.
local DIALOG_WIDTH = 720

-- The search page: what the directory is asked, then what came back.
-- The top two rows are the query itself -- everything there costs a
-- round trip -- and the third row filters the answer on the spot.
function show_search()
  close_dlg()
  dlg = vlc.dialog(EXT_NAME)
  dlg:set_size(DIALOG_WIDTH, 480)

  dlg:add_label(lang.lbl_term, 1, 1, 1, 1)
  ui.term = dlg:add_text_input(app.query, 2, 1, 2, 1, click_search)
  dlg:add_button(lang.btn_search, click_search, 4, 1, 1, 1)

  -- Row 2 and 3 are the question put to the directory, row 4 filters the
  -- answer already in hand. Four columns and no more: eight controls on
  -- one line would not fit the 800x600 screens still in service.
  dlg:add_label(lang.lbl_kind, 1, 2, 1, 1)
  ui.kind = dlg:add_dropdown(2, 2, 1, 1)
  ui.kind:add_value(lang.kind_podcasts, 1)
  ui.kind:add_value(lang.kind_episodes, 2)
  ui.kind:set_value(app.kind)

  -- Stores in the language's own alphabetical order, and the one in use
  -- selected where it belongs rather than dragged to the top.
  dlg:add_label(lang.lbl_store, 3, 2, 1, 1)
  ui.store = dlg:add_dropdown(4, 2, 1, 1)
  local stores = {}
  for i, code in ipairs(STOREFRONTS) do
    table.insert(stores, { id = i, code = code,
                           name = lang.countries[code] or code })
  end
  table.sort(stores, function(a, b) return a.name < b.name end)
  for _, store in ipairs(stores) do
    ui.store:add_value(cell(store.name), store.id)
    if store.code == app.country then
      ui.store:set_value(store.id)
    end
  end

  dlg:add_label(lang.lbl_limit, 1, 3, 1, 1)
  ui.limit = dlg:add_dropdown(2, 3, 1, 1)
  for i, n in ipairs(SEARCH_LIMITS) do
    ui.limit:add_value(tostring(n), i)
    if n == app.limit then
      ui.limit:set_value(i)
    end
  end
  dlg:add_label(lang.lbl_genre, 3, 3, 1, 1)
  ui.genre = dlg:add_dropdown(4, 3, 1, 1, click_genre_changed)

  dlg:add_label(lang.lbl_filter, 1, 4, 1, 1)
  ui.filter = dlg:add_text_input("", 2, 4, 1, 1,
                                 click_filter_changed, click_filter_changed)
  ui.explicit = dlg:add_check_box(lang.chk_explicit, app.hide_explicit,
                                  3, 4, 2, 1, click_explicit_toggled)

  ui.results = dlg:add_list(1, 5, 4, 1, click_open_result)
  if app.kind == 2 then
    ui.results:set_text(table.concat({ lang.col_rank, lang.col_episode,
                                       lang.col_podcast, lang.col_date,
                                       lang.col_duration }, "\t"))
  else
    ui.results:set_text(table.concat({ lang.col_rank, lang.col_name,
                                       lang.col_author, lang.col_genre,
                                       lang.col_episodes,
                                       lang.col_latest }, "\t"))
  end
  -- The order the directory answered in is its relevance ranking, which
  -- is worth keeping; showing it as a column means a click on any other
  -- header can be undone by a click on this one.
  ui.results:set_sort(1, true)

  dlg:add_button(lang.btn_details, click_open_result, 1, 6, 1, 1)
  dlg:add_button(lang.btn_play, click_play_result, 2, 6, 1, 1)
  dlg:add_button(lang.btn_subscribe, click_subscribe_result, 3, 6, 1, 1)
  dlg:add_button(lang.btn_subs, show_subscriptions, 4, 6, 1, 1)

  ui.message = dlg:add_label("", 1, 7, 4, 1)

  build_genres()
  fill_results()
  dlg:show()
end

-- The page a result opens on: the picture, what the directory knows, the
-- description the feed carries, and the button that subscribes to it.
function show_podcast()
  close_dlg()
  local pod = app.podcast or {}
  local name = pod.collection_name or pod.title or "?"
  dlg = vlc.dialog(EXT_NAME .. " — " .. name)
  -- A stated height, not the natural one. Legacy grows a window until
  -- its list fits; the modern provider takes the natural height at its
  -- word, and the natural height of a list is one row -- so asking for
  -- nothing gave twenty episodes a single visible line. The extra height
  -- goes to the row holding the list, which is the only one that wants
  -- it. Without episodes there is no list, and nothing to ask for.
  dlg:set_size(DIALOG_WIDTH, #app.episodes > 0 and 560 or 0)

  -- four columns of text, the fifth being the artwork's when there is one
  local cols = 4
  local row = 1
  app.ep_rows = {}
  sub_set = nil

  dlg:add_label(bold(name), 1, row, cols, 1)
  row = row + 1
  if pod.author then
    dlg:add_label(string.format(lang.lbl_by, cell(pod.author)),
                  1, row, cols, 1)
    row = row + 1
  end

  local facts = {}
  if pod.genre then
    table.insert(facts, cell(pod.genre))
  end
  if pod.count and pod.count > 0 then
    table.insert(facts, string.format(
      plural(pod.count, lang.lbl_count_one, lang.lbl_count), pod.count))
  end
  if pod.released then
    table.insert(facts, string.format(lang.lbl_latest, pod.released))
  end
  table.insert(facts, string.format(lang.lbl_store_of,
               lang.countries[app.country] or app.country))
  if pod.explicit then
    table.insert(facts, lang.lbl_explicit)
  end
  dlg:add_label(table.concat(facts, " — "), 1, row, cols, 1)
  row = row + 1

  -- One label, no line breaks of our own: the interface wraps it to
  -- whatever width the window gives it, so it reflows on a resize and
  -- reads as a paragraph. Only its length is our business.
  dlg:add_label(cell(shorten(app.description or lang.no_description,
                             DESCRIPTION_MAX_CHARS)), 1, row, cols, 1)
  row = row + 1

  -- A show whose feed nobody hands out can be read about but not
  -- subscribed to: say so where the address would have been, rather
  -- than offer a button that could only fail.
  if pod.feed and pod.feed ~= "" then
    dlg:add_label(lang.lbl_feed, 1, row, 1, 1)
    ui.feed = dlg:add_text_input(pod.feed, 2, row, cols - 1, 1)
  else
    dlg:add_label(cell(lang.msg_feed_hidden), 1, row, cols, 1)
  end
  row = row + 1

  local artwork_rows = row - 1

  if pod.feed and pod.feed ~= "" then
    if is_subscribed(pod.feed) then
      dlg:add_button(lang.btn_unsubscribe, click_unsubscribe, 1, row, 1, 1)
    else
      dlg:add_button(lang.btn_subscribe, click_subscribe, 1, row, 1, 1)
    end
    dlg:add_button(lang.btn_play_podcast, click_play_podcast, 2, row, 1, 1)
    dlg:add_button(lang.btn_copy_feed, click_copy_feed, 3, row, 1, 1)
  end
  dlg:add_button(lang.btn_back_search, show_search, 4, row, 1, 1)
  row = row + 1

  if #app.episodes > 0 then
    dlg:add_label(bold(lang.lbl_episodes), 1, row, cols, 1)
    row = row + 1
    ui.episodes = dlg:add_list(1, row, cols, 1, click_play_episode)
    ui.episodes:set_text(table.concat({ lang.col_date, lang.col_episode,
                                        lang.col_duration }, "\t"))
    ui.episodes:set_sort(1, false)
    app.ep_rows = {}
    for i, ep in ipairs(app.episodes) do
      app.ep_rows[i] = ep
      local length, seconds = format_duration(ep.duration_ms)
      ui.episodes:add_value(table.concat({
        cell(ep.released or ""),
        cell(ep.title),
        length and sortable(length, seconds) or "",
      }, "\t"), i)
    end
    row = row + 1
    dlg:add_button(lang.btn_play_episode, click_play_episode, 1, row, 1, 1)
    dlg:add_button(lang.btn_enqueue_episode, click_enqueue_episode,
                   2, row, 1, 1)
    row = row + 1
  end

  ui.message = dlg:add_label("", 1, row, cols, 1)

  -- Last, and with its bounds stated: the layout then knows the size the
  -- picture is meant to take even if the file that arrived is bigger.
  if app.art then
    dlg:add_image(app.art, 5, 1, 1, artwork_rows,
                  ARTWORK_SIZE, ARTWORK_SIZE)
  end

  if #app.episodes == 0 then
    set_message(lang.msg_no_episodes)
  end
  dlg:show()
end

-- What PowerVLC remembers, and the way back out of it: a subscription
-- taken here is one click from being dropped again.
function show_subscriptions()
  close_dlg()
  dlg = vlc.dialog(EXT_NAME .. " — " .. lang.title_subs)
  dlg:set_size(DIALOG_WIDTH, 420)

  ui.subs = dlg:add_list(1, 1, 4, 1, click_play_subscription)
  ui.subs:set_text(lang.col_name .. "\t" .. lang.col_feed)
  ui.subs:set_sort(1, true)

  app.sub_rows = {}
  local urls = subscribed_list()
  for i, url in ipairs(urls) do
    app.sub_rows[i] = url
    local known = app.known[url] or {}
    local name = known.title or url
    ui.subs:add_value(sortable(cell(name), fold_accents(name))
                      .. "\t" .. cell(url), i)
  end

  dlg:add_button(lang.btn_unsubscribe, click_unsubscribe_selected,
                 1, 2, 1, 1)
  dlg:add_button(lang.btn_play, click_play_subscription, 2, 2, 1, 1)
  dlg:add_button(lang.btn_back_search, show_search, 3, 2, 1, 1)

  ui.message = dlg:add_label("", 1, 3, 4, 1)
  set_message(#urls == 0 and lang.msg_no_subs
              or string.format(plural(#urls, lang.msg_subs_count_one,
                                      lang.msg_subs_count), #urls))
  dlg:show()
end

            --[[ VLC entry points ]]--

function descriptor()
  return {
    title = EXT_NAME,
    version = "1.0",
    author = "PowerVLC",
    url = "https://podcasts.apple.com/",
    shortdesc = EXT_NAME,
    -- descriptor() tourne au scan, où le catalogue est encore vide :
    -- littéral anglais, comme dans les trois autres extensions.
    description = "Search the Apple podcast directory, read what a "
               .. "show is about and subscribe to it without leaving "
               .. "PowerVLC.",
    capabilities = {}
  }
end

function activate()
  load_lang()
  vlc.msg.dbg("[Podcasts] Welcome")
  json = require("dkjson")

  -- The store the user is most likely to want is the one their system
  -- names; a language that names no country still points at one.
  if lang.countries[sys_region] then
    app.country = sys_region
  else
    local code = LANG_STORE[string.sub(sys_lang, 1, 2)]
    if code then
      app.country = code
    end
  end

  load_settings()
  show_search()
end

function deactivate()
  vlc.msg.dbg("[Podcasts] Bye")
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end
