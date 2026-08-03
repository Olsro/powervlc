--[[
 invidious.lua : Invidious browser extension for PowerVLC

 Browse Invidious instances, search videos / channels and play a
 stream at the chosen quality, without ever leaving VLC.

 Uses only plain dialog widgets (no HTML) so it renders correctly on
 every interface, including the legacy Mac OS X one.

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

local DIRECTORY_URL = "https://api.invidious.io/instances.json?sort_by=type,users"
local READ_CHUNK = 65536
local SEARCH_FIELDS = "type,title,videoId,author,authorId,published,publishedText"

            --[[ Translations ]]--

local translations = {
  en = {
    title_connect = "Invidious — Connection",
    title_search = "Invidious — Search",
    title_video = "Invidious — Video",
    -- ISO on purpose: the column sort is lexicographic
    date_fmt = "%Y-%m-%d",
    col_instance = "Instance",
    col_region = "Region",
    col_uptime = "Uptime",
    col_title = "Title",
    col_channel = "Channel",
    col_date = "Published",
    col_subs = "Subscribers",

    btn_list_instances = "List public instances",
    btn_use_selection = "Use selected instance",
    lbl_instance = "Instance:",
    chk_proxy = "Proxy streams through the instance (recommended)",
    btn_connect = "Connect",
    msg_fetching_instances = "Fetching public instances...",
    msg_no_instances = "No usable instance found",
    msg_instances_count = "%d instances — select one, then 'Use selected instance'",
    msg_select_first = "Select an instance in the list first",
    msg_enter_url = "Enter an instance URL first",
    msg_connecting = "Connecting...",
    msg_connect_fail = "Connection failed: ",
    msg_search_blocked = "Instance reachable, but it blocks anonymous API "
                      .. "search (anti-bot) — try another one or a "
                      .. "personal instance",

    mode_videos = "Videos",
    mode_channels = "Channels",
    btn_search = "Search",
    btn_open = "Open selection",
    btn_change_instance = "< Instance",
    msg_enter_query = "Enter something to search for",
    msg_searching = "Searching...",
    msg_no_results = "No result",
    msg_results_count = "%d results (newest first)",
    msg_channel_loading = "Fetching channel videos...",
    msg_search_fail = "Search failed: ",
    msg_select_result = "Select a result in the list first",

    lbl_quality = "Quality:",
    lbl_by = "by",
    audio_only = "Audio only",
    combined = "audio+video",
    video_only = "video only",
    live_hls = "HLS stream (live)",
    btn_play = "Play",
    btn_copy = "Copy stream URL",
    btn_back = "< Back",
    msg_loading_video = "Fetching video info...",
    msg_video_fail = "Could not fetch video info: ",
    msg_fallback_formats = "Video API blocked by the instance — standard streams probed instead",
    msg_trying_html = "JSON API closed — trying the HTML pages...",
    msg_html_mode = "Connected in HTML mode (API closed on this instance)",
    dash_auto = "Automatic quality (DASH)",
    msg_no_formats = "No playable stream found for this video",
    msg_playing = "Playback started",
    msg_copied = "Stream URL copied to the clipboard",
    msg_copy_fallback = "Auto-copy unavailable — select the URL below",
  },
  fr = {
    title_connect = "Invidious — Connexion",
    title_search = "Invidious — Recherche",
    title_video = "Invidious — Vidéo",
    -- ISO à dessein : le tri des colonnes est lexicographique
    date_fmt = "%Y-%m-%d",
    col_instance = "Instance",
    col_region = "Région",
    col_uptime = "Dispo.",
    col_title = "Titre",
    col_channel = "Chaîne",
    col_date = "Publiée",
    col_subs = "Abonnés",

    btn_list_instances = "Lister les instances publiques",
    btn_use_selection = "Utiliser l'instance sélectionnée",
    lbl_instance = "Instance :",
    chk_proxy = "Relayer les flux par l'instance (recommandé)",
    btn_connect = "Connexion",
    msg_fetching_instances = "Récupération des instances publiques...",
    msg_no_instances = "Aucune instance utilisable trouvée",
    msg_instances_count = "%d instances — sélectionnez-en une puis « Utiliser l'instance sélectionnée »",
    msg_select_first = "Sélectionnez d'abord une instance dans la liste",
    msg_enter_url = "Saisissez d'abord l'URL d'une instance",
    msg_connecting = "Connexion...",
    msg_connect_fail = "Échec de la connexion : ",
    msg_search_blocked = "L'instance répond mais bloque la recherche "
                      .. "anonyme (anti-bot) — essayez-en une autre ou "
                      .. "une instance personnelle",

    mode_videos = "Vidéos",
    mode_channels = "Chaînes",
    btn_search = "Chercher",
    btn_open = "Ouvrir la sélection",
    btn_change_instance = "< Instance",
    msg_enter_query = "Saisissez un terme à chercher",
    msg_searching = "Recherche...",
    msg_no_results = "Aucun résultat",
    msg_results_count = "%d résultats (plus récents d'abord)",
    msg_channel_loading = "Récupération des vidéos de la chaîne...",
    msg_search_fail = "Échec de la recherche : ",
    msg_select_result = "Sélectionnez d'abord un résultat dans la liste",

    lbl_quality = "Qualité :",
    lbl_by = "par",
    audio_only = "Audio seul",
    combined = "audio+vidéo",
    video_only = "vidéo seule",
    live_hls = "Flux HLS (direct)",
    btn_play = "Lire",
    btn_copy = "Copier le lien du flux",
    btn_back = "< Retour",
    msg_loading_video = "Récupération des informations de la vidéo...",
    msg_video_fail = "Impossible de récupérer la vidéo : ",
    msg_fallback_formats = "API vidéos bloquée par l'instance — flux standards sondés à la place",
    msg_trying_html = "API JSON fermée — essai par les pages HTML...",
    msg_html_mode = "Connecté en mode HTML (API fermée sur cette instance)",
    dash_auto = "Qualité automatique (DASH)",
    msg_no_formats = "Aucun flux lisible trouvé pour cette vidéo",
    msg_playing = "Lecture lancée",
    msg_copied = "Lien du flux copié dans le presse-papiers",
    msg_copy_fallback = "Copie auto indisponible — sélectionnez le lien ci-dessous",
  }
}
local lang = translations.en

            --[[ State ]]--

local app = {
  instance = nil,    -- base URL of the connected instance
  mode = "api",      -- "api" (JSON) or "html" (front-end scraping)
  last_url = "https://",
  proxy = true,      -- rewrite stream URLs through the instance (local=true)
  instances = {},    -- id -> instance base URL
  results = {},      -- id -> { kind, id, title, author, published }
  video = nil,       -- currently opened video { title, author, ... }
  formats = {},      -- id -> { label, url }
  -- What the list was showing last, so that coming back from a video
  -- lands on it again rather than on an empty search: the query and mode
  -- as typed, the items themselves, and the channel they came from when
  -- the list is a channel's videos rather than a search.
  last_query = "",
  last_mode = 1,
  view_items = nil,
  view_kind = nil,
  view_channel = nil,
}

local dlg = nil
local ui = {}

            --[[ VLC entry points ]]--

function descriptor()
  return {
    title = "Invidious",
    version = "1.0",
    author = "PowerVLC",
    url = "https://invidious.io/",
    shortdesc = "Invidious",
    description = "Browse Invidious instances, search YouTube videos "
               .. "and channels, and play streams at the chosen quality.",
    capabilities = {}
  }
end

function activate()
  vlc.msg.dbg("[Invidious] Welcome")
  json = require("dkjson")
  local sys_lang = os.getenv("LANGUAGE") or os.getenv("LC_ALL")
                or os.getenv("LC_MESSAGES") or os.getenv("LANG") or ""
  if string.match(string.lower(sys_lang), "^fr") then
    lang = translations.fr
  end
  show_connect()
end

function deactivate()
  vlc.msg.dbg("[Invidious] Bye")
  close_dlg()
end

function close()
  vlc.deactivate()
end

function meta_changed()
end

            --[[ Helpers ]]--

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
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

-- HTTP(S) GET through VLC's stream layer.
-- Returns the raw body or nil, error-string.
local function get_body(url)
  vlc.msg.dbg("[Invidious] GET " .. url)
  local ok, stream, msg = pcall(vlc.stream, url)
  if not ok or not stream then
    return nil, tostring(msg or stream or "stream error")
  end
  local parts = {}
  while true do
    local chunk = stream:read(READ_CHUNK)
    if not chunk or #chunk == 0 then
      break
    end
    table.insert(parts, chunk)
  end
  local body = table.concat(parts)
  if #body == 0 then
    return nil, "empty response"
  end
  return body
end

-- Same, decoded as JSON. Returns table or nil, error-string.
local function get_json(url)
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  local obj, _, err = json.decode(body)
  if obj == nil then
    return nil, tostring(err or "invalid JSON")
  end
  if type(obj) == "table" and obj.error ~= nil then
    -- Invidious reports failures as {"error": "..."}
    return nil, tostring(obj.error)
  end
  return obj
end

            --[[ HTML front-end fall-back ]]--

-- Most public instances now switch their JSON API off (the operator's
-- "Endpoint disabled", or a 403 from the reverse proxy) while serving
-- their ordinary HTML pages to any client. These helpers read those
-- pages -- exactly what a browser fetches, no challenge involved.

local ENTITIES = {
  quot = '"', apos = "'", lt = "<", gt = ">", amp = "&", nbsp = " ",
}

local function html_decode(s)
  if not s then
    return nil
  end
  -- inline markup lives inside the very elements we read: the "verified"
  -- badge sits in <p class="channel-name">, so strip tags before text
  s = string.gsub(s, "<[^>]*>", "")
  s = string.gsub(s, "&#(%d+);", function(n)
    local code = tonumber(n)
    -- ASCII only: anything above needs UTF-8 encoding we do not need here
    return (code and code < 128) and string.char(code) or ""
  end)
  s = string.gsub(s, "&(%a+);", function(name)
    return ENTITIES[string.lower(name)] or ""
  end)
  return trim((string.gsub(s, "%s+", " ")))
end

-- "Shared 3 months ago" -> an approximate epoch, so that HTML results can
-- be sorted with the same "newest first" rule as API results.
local UNIT_SECONDS = {
  second = 1, minute = 60, hour = 3600, day = 86400,
  week = 604800, month = 2629800, year = 31557600,
}

local function parse_relative_date(text)
  if not text then
    return nil
  end
  local count, unit = string.match(string.lower(text), "(%d+)%s+(%a+)%s+ago")
  if not count then
    return nil
  end
  unit = string.gsub(unit, "s$", "")
  local secs = UNIT_SECONDS[unit]
  if not secs then
    return nil
  end
  return os.time() - tonumber(count) * secs
end

-- Walks the video/channel cards of a search or channel page.
-- The channel name is a <p> on cards and a <span> on the watch page, and
-- carries the "verified" badge inside it. Stop at the first closing tag
-- and let html_decode() strip what markup came along.
local CHANNEL_NAME = 'class="channel%-name"[^>]*>(.-)</'

local function html_parse_cards(html, kind)
  local items = {}
  local link = (kind == "channel")
    and 'href="/channel/([%w_%-]+)">%s*<p class="channel%-name"'
    or  'href="/watch%?v=([%w_%-]+)"><p dir="auto">'
  local pos = 1

  while true do
    local first, last, id = string.find(html, link, pos)
    if not first then
      break
    end
    -- bound the per-card searches by the start of the next card
    local nextFirst = string.find(html, link, last) or (#html + 1)

    local item = { id = id }
    if kind == "channel" then
      local _, e, name = string.find(html, CHANNEL_NAME, first)
      if e and e < nextFirst then
        item.author = html_decode(name)
      end
      local _, se, subs = string.find(html,
        "<p>([^<]*subscribers?)</p>", last)
      if se and se < nextFirst then
        item.subCount = html_decode(subs)
      end
    else
      local _, te, title = string.find(html,
        '<p dir="auto">(.-)</p>', first)
      if te and te < nextFirst then
        item.title = html_decode(title)
      end
      local _, ae, author = string.find(html, CHANNEL_NAME, last)
      if ae and ae < nextFirst then
        item.author = html_decode(author)
      end
      local _, de, date = string.find(html,
        'video%-data"[^>]*>(.-)</p>', last)
      if de and de < nextFirst then
        item.publishedText = html_decode(date)
        item.published = parse_relative_date(item.publishedText)
        item.approx = true
      end
    end

    if kind == "channel" then
      item.authorId = id
    else
      item.videoId = id
    end
    -- the same video may appear twice (thumbnail + title link)
    if not items[id] then
      items[id] = true
      table.insert(items, item)
    end
    pos = last
  end

  return items
end

local function html_search(instance, query, kind)
  local url = instance .. "/search?q="
           .. vlc.strings.encode_uri_component(query)
           .. "&type=" .. (kind == "channel" and "channel" or "video")
  if kind ~= "channel" then
    url = url .. "&sort=upload_date"
  end
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  return html_parse_cards(body, kind)
end

local function html_channel_videos(instance, channel_id)
  local body, err = get_body(instance .. "/channel/" .. channel_id)
  if not body then
    return nil, err
  end
  local items = html_parse_cards(body, "video")
  -- A channel page is strictly newest-first, so its order is finer than
  -- the rounded wording of its own dates. Search pages are not: instances
  -- answer them by relevance whatever sort was asked for.
  items.ordered = true
  return items
end

-- Reads the watch page and returns the same shape as the videos API.
local function html_video(instance, video_id)
  local url = instance .. "/watch?v=" .. video_id
  if app.proxy then
    url = url .. "&local=true"
  end
  local body, err = get_body(url)
  if not body then
    return nil, err
  end
  if string.find(body, "not a bot", 1, true) then
    return nil, "challenge"
  end

  local info = { sources = {} }
  info.title = html_decode(string.match(body, '"title":%s*"(.-)"')
    or string.match(body, "<title>(.-)</title>"))
  info.author = html_decode(string.match(body, CHANNEL_NAME))

  for tag in string.gmatch(body, "<source[^>]*>") do
    local src = string.match(tag, 'src="(.-)"')
    local label = string.match(tag, 'label="(.-)"')
    local mime = string.match(tag, "type=['\"](.-)[;'\"]")
    if src then
      -- only the ampersands need undoing here: html_decode() would also
      -- collapse whitespace and drop entities a URL may legitimately carry
      src = (string.gsub(src, "&amp;", "&"))
      table.insert(info.sources,
        { url = src, label = label, mime = mime })
    end
  end
  return info
end

local function normalize_instance_url(url)
  url = trim(url)
  if url == "" or url == "https://" or url == "http://" then
    return nil
  end
  if not string.match(url, "^https?://") then
    url = "https://" .. url
  end
  return (string.gsub(url, "/+$", ""))
end

-- one table cell: tabs are the column separator, so strip them
local function cell(s)
  return (string.gsub(tostring(s or "?"), "[\t\r\n\031]", " "))
end

-- A cell the interface must sort on a real value rather than on its
-- label: "display\031key". Dates sort chronologically and counts
-- numerically, whatever the format they are displayed in.
local function sortable(display, key)
  if not key then
    return cell(display)
  end
  return cell(display) .. "\031" .. tostring(key)
end

local function format_date(item)
  -- HTML pages only give "Shared 7 months ago": showing that as an exact
  -- day would be a lie, so the relative wording is kept as-is.
  if item.approx then
    return (string.gsub(item.publishedText or "?", "^Shared%s+", ""))
  end
  if type(item.published) == "number" and item.published > 0 then
    return os.date(lang.date_fmt, item.published)
  end
  return item.publishedText or "?"
end

-- The displayed date, with the value the column must sort on. Approximate
-- dates collapse whole years onto one point, so they sort on the rank the
-- instance returned instead -- that ordering is exact.
local function date_cell(item, rank)
  return sortable(format_date(item), rank or item.published)
end

-- vlc.clipboard is this fork's native API (macOS + Windows); on other
-- platforms it reports failure and the URL stays selectable in the field.
local function copy_to_clipboard(text)
  if vlc.clipboard and vlc.clipboard.set then
    return vlc.clipboard.set(text)
  end
  return false
end

function close_dlg()
  if dlg ~= nil then
    dlg:hide()
  end
  dlg = nil
  ui = {}
  collectgarbage()
end

            --[[ View 1: connection ]]--

-- Instance URLs and video titles are long; the natural width of the
-- widgets truncates them. Ask for room up front (a hint: the user can
-- still resize, and the interface may need more).
local DIALOG_WIDTH = 720
local DIALOG_HEIGHT = 460

function show_connect()
  close_dlg()
  dlg = vlc.dialog(lang.title_connect)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  dlg:add_button(lang.btn_list_instances, click_list_instances, 1, 1, 3, 1)
  -- selecting an instance fills the field, double-clicking connects
  ui.instances = dlg:add_list(1, 2, 3, 1, click_instance_activated,
                             click_instance_selected)
  ui.instances:set_text(lang.col_instance .. "\t" .. lang.col_region
                        .. "\t" .. lang.col_uptime)
  dlg:add_button(lang.btn_use_selection, click_use_selection, 1, 3, 3, 1)
  dlg:add_label(lang.lbl_instance, 1, 4, 1, 1)
  -- Enter in the field connects straight away
  ui.url = dlg:add_text_input(app.last_url, 2, 4, 2, 1, click_connect)
  ui.proxy = dlg:add_check_box(lang.chk_proxy, app.proxy, 1, 5, 3, 1)
  dlg:add_button(lang.btn_connect, click_connect, 1, 6, 1, 1)
  ui.message = dlg:add_label("", 1, 7, 3, 1)
  dlg:show()
end

function click_list_instances()
  set_message(lang.msg_fetching_instances)
  app.instances = {}
  ui.instances:clear()

  local obj, err = get_json(DIRECTORY_URL)
  if not obj then
    set_message(lang.msg_connect_fail .. err)
    return
  end

  local id = 0
  for _, entry in ipairs(obj) do
    local info = entry[2]
    -- Keep every clearnet instance. onion/i2p/ygg need a network stack
    -- VLC does not have. The directory's "api" flag is NOT a filter: it
    -- is false on instances that do serve the API but answer the
    -- monitor's probe with an anti-bot challenge. The Connect button
    -- probes the real endpoint and says what it found.
    if type(info) == "table" and info.type == "https" and info.uri then
      local mon = info.monitor
      local uptime = mon and (mon.uptime
                     or (mon["30dRatio"] and mon["30dRatio"].ratio))
      id = id + 1
      app.instances[id] = (string.gsub(info.uri, "/+$", ""))
      ui.instances:add_value(cell(app.instances[id]) .. "\t"
        .. cell(info.region) .. "\t"
        .. sortable(uptime and (string.format("%.1f", uptime) .. "%") or "",
                    uptime), id)
    end
  end

  if id == 0 then
    set_message(lang.msg_no_instances)
  else
    set_message(string.format(lang.msg_instances_count, id))
  end
end

function click_use_selection()
  local selection = ui.instances:get_selection()
  for id in pairs(selection) do
    ui.url:set_text(app.instances[id])
    set_message("")
    return true
  end
  set_message(lang.msg_select_first)
  return false
end

-- Selecting a row fills the field. Silent on purpose: this fires on every
-- selection change, including the empty one a sort leaves behind, and it
-- must not overwrite the status message.
function click_instance_selected()
  for id in pairs(ui.instances:get_selection()) do
    if app.instances[id] then
      ui.url:set_text(app.instances[id])
    end
    return
  end
end

function click_instance_activated()
  if click_use_selection() then
    click_connect()
  end
end

function click_connect()
  local url = normalize_instance_url(ui.url:get_text())
  if not url then
    set_message(lang.msg_enter_url)
    return
  end
  set_message(lang.msg_connecting)
  app.proxy = ui.proxy:get_checked()

  -- Prefer the JSON API: it carries exact dates and every quality.
  local obj = get_json(url .. "/api/v1/search?q=vlc&fields=type")
  if obj then
    app.mode = "api"
  else
    -- API switched off by the operator: fall back to the HTML pages the
    -- instance serves to browsers.
    set_message(lang.msg_trying_html)
    local items, err = html_search(url, "vlc", "video")
    if not items or #items == 0 then
      -- Tell apart "the instance is unreachable" from "it is up but
      -- lets neither route through" (anti-bot challenge on both).
      if get_json(url .. "/api/v1/stats") then
        set_message(lang.msg_search_blocked)
      else
        set_message(lang.msg_connect_fail .. tostring(err or "HTML"))
      end
      return
    end
    app.mode = "html"
  end

  if app.instance ~= url then
    -- another instance: its results are not this one's
    app.view_items, app.view_kind, app.view_channel = nil, nil, nil
  end
  app.instance = url
  app.last_url = url
  show_search()
  if app.mode == "html" then
    set_message(lang.msg_html_mode)
  end
end

            --[[ View 2: search ]]--

-- defined below, needed by show_search to put the list back as it was
local fill_results

function show_search()
  close_dlg()
  dlg = vlc.dialog(lang.title_search)
  dlg:set_size(DIALOG_WIDTH, DIALOG_HEIGHT)
  ui.mode = dlg:add_dropdown(1, 1, 1, 1)
  ui.mode:add_value(lang.mode_videos, 1)
  ui.mode:add_value(lang.mode_channels, 2)
  ui.mode:set_value(app.last_mode or 1)
  -- Enter in the box searches, no need to reach for the button
  ui.query = dlg:add_text_input(app.last_query or "", 2, 1, 1, 1, click_search)
  dlg:add_button(lang.btn_search, click_search, 3, 1, 1, 1)
  -- double-clicking a result opens it (video view / channel videos)
  ui.results = dlg:add_list(1, 2, 3, 1, click_open_result)
  ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                      .. "\t" .. lang.col_date)
  dlg:add_button(lang.btn_open, click_open_result, 1, 3, 1, 1)
  dlg:add_button(lang.btn_change_instance, show_connect, 2, 3, 1, 1)
  ui.message = dlg:add_label("", 1, 4, 3, 1)
  -- Whatever the list held last -- a search, or the videos of a channel
  -- someone opened -- is put back: coming out of a video to an empty
  -- form meant typing the search again to reach the next episode.
  if app.view_items then
    fill_results(app.view_items, app.view_kind)
  end
  dlg:show()
end

function fill_results(list, kind)
  app.view_items, app.view_kind = list, kind
  app.results = {}
  ui.results:clear()
  if kind == "channel" then
    ui.results:set_text(lang.col_channel .. "\t" .. lang.col_subs)
  else
    ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                        .. "\t" .. lang.col_date)
  end
  local items = {}
  for _, item in ipairs(list) do
    if kind == "channel" or item.videoId then
      table.insert(items, item)
    end
  end
  -- Sort here, unless the source already came back in a true chronological
  -- order finer than its own rounded dates (a channel page).
  local approx = (#items > 0) and items[1].approx
  local ordered = approx and (type(list) == "table") and list.ordered
  if kind == "video" and not ordered then
    table.sort(items, function(a, b)
      return (a.published or 0) > (b.published or 0)
    end)
  end
  for i, item in ipairs(items) do
    local line
    if kind == "channel" then
      app.results[i] = { kind = "channel", id = item.authorId,
                         title = item.author }
      -- HTML gives "565,000 subscribers", the API a bare number: sort on
      -- the digits either way
      local subs = item.subCount and tostring(item.subCount) or ""
      line = cell(item.author) .. "\t"
          .. sortable(subs, tonumber((string.gsub(subs, "[^%d]", ""))))
    else
      app.results[i] = { kind = "video", id = item.videoId,
                         title = item.title or "?",
                         author = item.author or "?",
                         published = item.published }
      line = cell(item.title) .. "\t" .. cell(item.author)
          .. "\t" .. date_cell(item, ordered and (#items - i) or nil)
    end
    ui.results:add_value(line, i)
  end
  if #items == 0 then
    set_message(lang.msg_no_results)
  elseif app.view_channel then
    -- say whose videos these are: the search box still holds the words
    -- that found the channel, and the two would read as one otherwise
    set_message(app.view_channel .. " — "
                .. string.format(lang.msg_results_count, #items))
  else
    set_message(string.format(lang.msg_results_count, #items))
  end
end

function click_search()
  local query = trim(ui.query:get_text())
  if query == "" then
    set_message(lang.msg_enter_query)
    return
  end
  set_message(lang.msg_searching)
  local mode = ui.mode:get_value()
  local kind = (mode == 2) and "channel" or "video"
  local obj, err
  -- a new search replaces whatever channel the list was showing
  app.last_query, app.last_mode, app.view_channel = query, mode, nil

  if app.mode == "html" then
    obj, err = html_search(app.instance, query, kind)
  elseif kind == "channel" then
    obj, err = get_json(app.instance .. "/api/v1/search?q="
       .. vlc.strings.encode_uri_component(query)
       .. "&type=channel&fields=type,author,authorId,subCount")
  else
    obj, err = get_json(app.instance .. "/api/v1/search?q="
       .. vlc.strings.encode_uri_component(query)
       .. "&type=video&sort_by=upload_date&fields=" .. SEARCH_FIELDS)
  end

  if not obj then
    set_message(lang.msg_search_fail .. tostring(err))
    return
  end
  fill_results(obj, kind)
end

function click_open_result()
  local selection = ui.results:get_selection()
  local result = nil
  for id in pairs(selection) do
    result = app.results[id]
    break
  end
  if not result then
    set_message(lang.msg_select_result)
    return
  end
  if result.kind == "channel" then
    set_message(lang.msg_channel_loading)
    local obj, err
    if app.mode == "html" then
      obj, err = html_channel_videos(app.instance, result.id)
    else
      obj, err = get_json(app.instance .. "/api/v1/channels/" .. result.id
                          .. "/videos?fields=videos," .. SEARCH_FIELDS)
    end
    if not obj then
      set_message(lang.msg_search_fail .. tostring(err))
      return
    end
    -- older Invidious returns a bare array, newer wraps it in .videos
    app.view_channel = result.title
    fill_results(obj.videos or obj, "video")
  else
    open_video(result)
  end
end

            --[[ View 3: video ]]--

local function quality_rank(label)
  local n = tonumber(string.match(label or "", "(%d+)p"))
  return n or 0
end

-- True when the URL actually serves data (follows redirects; a 4xx
-- makes the access fail, so dead itags are filtered out).
local function probe_stream(url)
  local ok, stream = pcall(vlc.stream, url)
  if not ok or not stream then
    return false
  end
  local chunk = stream:read(1024)
  return chunk ~= nil and #chunk > 0
end

-- Many instances block /api/v1/videos (nginx 403) while their
-- latest_version stream exit still works without authentication.
-- Probe the standard combined/audio itags and offer whichever answer.
local function fallback_formats(result)
  local candidates = {
    { itag = "22", label = "720p — mp4 (" .. lang.combined .. ")" },
    { itag = "18", label = "360p — mp4 (" .. lang.combined .. ")" },
    { itag = "140", label = lang.audio_only .. " — 128 kb/s (m4a)" },
  }
  local formats = {}
  for _, c in ipairs(candidates) do
    local url = app.instance .. "/latest_version?id=" .. result.id
             .. "&itag=" .. c.itag
    if app.proxy then
      url = url .. "&local=true"
    end
    if probe_stream(url) then
      table.insert(formats, { label = c.label, url = url })
    end
  end
  return formats
end

-- A DASH manifest holds one adaptation set per codec, and VLC surfaces
-- those as unnamed "Track 2 / Track 3" with no way to pick a resolution.
-- Reading the manifest ourselves turns them into real quality entries:
-- one video stream per height, with its audio attached as a slave input.
local CODEC_RANK = { avc = 1, vp0 = 2, vp9 = 2, av0 = 3 }

local function dash_formats(manifest_url)
  local body = get_body(manifest_url)
  if not body then
    return nil
  end
  local origin = string.match(manifest_url, "^(https?://[^/]+)") or ""

  local function absolute(url)
    url = (string.gsub(url, "&amp;", "&"))
    if not string.match(url, "^https?://") then
      url = origin .. url
    end
    return url
  end

  local audio, audio_rate = nil, -1
  local videos = {}

  for set in string.gmatch(body, "<AdaptationSet.-</AdaptationSet>") do
    local is_audio = string.find(set, 'contentType="audio"', 1, true)
                  or string.find(set, 'mimeType="audio', 1, true)
    for rep in string.gmatch(set, "<Representation.-</Representation>") do
      local url = string.match(rep, "<BaseURL>(.-)</BaseURL>")
      local rate = tonumber(string.match(rep, 'bandwidth="(%d+)"') or "") or 0
      if url then
        if is_audio then
          if rate > audio_rate then
            audio, audio_rate = absolute(url), rate
          end
        else
          local height = tonumber(string.match(rep, 'height="(%d+)"') or "")
          if height then
            table.insert(videos, {
              height = height,
              codec = string.match(rep, 'codecs="([^".]*)') or "?",
              url = absolute(url),
            })
          end
        end
      end
    end
  end

  if not audio or #videos == 0 then
    return nil
  end

  -- one entry per resolution, keeping the most widely decodable codec:
  -- AV1 is out of reach of the machines this fork exists for
  local best = {}
  for _, v in ipairs(videos) do
    local rank = CODEC_RANK[string.sub(v.codec, 1, 3)] or 9
    if not best[v.height] or rank < best[v.height].rank then
      best[v.height] = { rank = rank, video = v }
    end
  end

  local formats = {}
  for _, entry in pairs(best) do
    table.insert(formats, {
      height = entry.video.height,
      label = entry.video.height .. "p — " .. entry.video.codec,
      url = entry.video.url,
      -- the video stream carries no sound of its own
      options = { ":input-slave=" .. audio },
      -- pasting a video-only URL would be useless: hand out the manifest
      copy = manifest_url,
    })
  end
  table.sort(formats, function(a, b) return a.height > b.height end)
  return formats
end

-- HTML mode: the watch page offers a DASH manifest (adaptive, every
-- resolution, audio included) and sometimes a progressive stream. VLC
-- reads both, so they go straight into the quality list.
local function open_video_html(result)
  local info, err = html_video(app.instance, result.id)
  if not info then
    return false, err
  end

  local formats = {}
  for _, src in ipairs(info.sources) do
    local label
    if src.label == "dash" or (src.mime and string.find(src.mime, "dash", 1, true)) then
      -- expand the manifest into per-resolution entries, and keep the
      -- manifest itself as the last "let VLC decide" option
      local expanded = dash_formats(src.url)
      if expanded then
        for _, f in ipairs(expanded) do
          table.insert(formats, f)
        end
      end
      label = lang.dash_auto
    else
      label = (src.label or "?") .. " — "
           .. (src.mime and string.match(src.mime, "/([%w-]+)") or "?")
           .. " (" .. lang.combined .. ")"
    end
    table.insert(formats, { label = label, url = src.url })
  end
  if #formats == 0 then
    return false, "no source"
  end

  app.video = { title = info.title or result.title,
                author = info.author or result.author or "?",
                published = result.published,
                publishedText = result.publishedText }
  app.formats = formats
  return true
end

function open_video(result)
  set_message(lang.msg_loading_video)

  if app.mode == "html" then
    local ok, err = open_video_html(result)
    if ok then
      show_video()
      return
    end
    set_message(lang.msg_video_fail .. tostring(err))
    return
  end

  local url = app.instance .. "/api/v1/videos/" .. result.id
           .. "?fields=title,author,published,publishedText,"
           .. "formatStreams,adaptiveFormats,hlsUrl,liveNow"
  if app.proxy then
    url = url .. "&local=true"
  end
  local obj, err = get_json(url)
  if not obj then
    local formats = fallback_formats(result)
    if #formats == 0 then
      set_message(lang.msg_video_fail .. err)
      return
    end
    app.video = { title = result.title, author = result.author or "?",
                  published = result.published }
    app.formats = formats
    show_video()
    set_message(lang.msg_fallback_formats)
    return
  end

  local formats = {}
  local combined = {}
  for _, fs in ipairs(obj.formatStreams or {}) do
    if fs.url then
      local quality = fs.qualityLabel or fs.resolution or fs.quality or "?"
      local container = string.match(fs.type or "", "/([%w-]+)") or "?"
      table.insert(combined, {
        label = quality .. " — " .. container .. " (" .. lang.combined .. ")",
        url = fs.url,
        rank = quality_rank(quality)
      })
    end
  end
  table.sort(combined, function(a, b) return a.rank > b.rank end)
  for _, f in ipairs(combined) do
    table.insert(formats, f)
  end
  if obj.hlsUrl and obj.hlsUrl ~= "" then
    table.insert(formats, { label = lang.live_hls, url = obj.hlsUrl })
  end
  for _, af in ipairs(obj.adaptiveFormats or {}) do
    if af.url and string.match(af.type or "", "^audio/") then
      local rate = tonumber(af.bitrate)
      local container = string.match(af.type or "", "/([%w-]+)") or "?"
      table.insert(formats, {
        label = lang.audio_only
             .. (rate and (" — " .. math.floor(rate / 1000) .. " kb/s") or "")
             .. " (" .. container .. ")",
        url = af.url
      })
    end
  end

  app.video = { title = obj.title or result.title,
                author = obj.author or result.author or "?",
                published = obj.published or result.published,
                publishedText = obj.publishedText }
  app.formats = formats
  show_video()
end

function show_video()
  close_dlg()
  dlg = vlc.dialog(lang.title_video)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(app.video.title, 1, 1, 3, 1)
  dlg:add_label(lang.lbl_by .. " " .. app.video.author .. " — "
                .. format_date(app.video), 1, 2, 3, 1)
  dlg:add_label(lang.lbl_quality, 1, 3, 1, 1)
  ui.quality = dlg:add_dropdown(2, 3, 2, 1)
  for i, f in ipairs(app.formats) do
    ui.quality:add_value(f.label, i)
  end
  dlg:add_button(lang.btn_play, click_play, 1, 4, 1, 1)
  dlg:add_button(lang.btn_copy, click_copy, 2, 4, 1, 1)
  dlg:add_button(lang.btn_back, show_search, 3, 4, 1, 1)
  ui.link = dlg:add_text_input("", 1, 5, 3, 1)
  ui.message = dlg:add_label("", 1, 6, 3, 1)
  if #app.formats == 0 then
    set_message(lang.msg_no_formats)
  end
  dlg:show()
end

local function selected_format()
  if #app.formats == 0 then
    set_message(lang.msg_no_formats)
    return nil
  end
  return app.formats[ui.quality:get_value()] or app.formats[1]
end

function click_play()
  local f = selected_format()
  if not f then
    return
  end
  vlc.playlist.add({{
    path = f.url,
    title = app.video.title .. " — " .. app.video.author,
    options = f.options,   -- carries the separate audio stream, if any
  }})
  set_message(lang.msg_playing)
end

function click_copy()
  local f = selected_format()
  if not f then
    return
  end
  -- a per-resolution DASH stream has no audio on its own: what gets
  -- copied is the manifest, which plays as-is elsewhere
  local url = f.copy or f.url
  ui.link:set_text(url)
  if copy_to_clipboard(url) then
    set_message(lang.msg_copied)
  else
    set_message(lang.msg_copy_fallback)
  end
end
