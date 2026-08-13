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

-- A download moves on the extension's own timer, in bounded slices: a
-- click queues up behind one slice rather than behind a whole file, and
-- the progress line visibly lives. A video is a great deal bigger than
-- the pages everything else here fetches, hence a megabyte a tick.
local DL_TICK_MS = 15
local DL_CHUNKS_PER_TICK = 8
-- How long a tick may keep the thread before handing it back, whatever
-- it managed to fetch. It used to stop on a byte count instead, and that
-- is only the same thing at one speed: 4 MiB is five seconds of video
-- stream and THIRTY-SEVEN of an audio one, so the progress bar sat still
-- for half a minute at a time and Cancel took as long to answer. What
-- the user watches is time, so time is what bounds this.
local DL_TICK_BUDGET_US = 250000
-- How many connections at once. The ceiling being worked around is per
-- connection and applies to each stream at roughly its own bitrate, so
-- this is the multiplier -- and it has to be this high because an audio
-- track is a quarter of the bitrate of its video and would otherwise
-- take just as long to fetch. Each one costs a request and a prefetch
-- buffer, which on the machines this fork exists for is not free.
local DL_CONNECTIONS = 8
local DL_MIN_PARALLEL = 2 * 1024 * 1024
-- A connection asks for a bounded piece and comes back for another, so
-- that a file with fewer pieces than connections still uses them all,
-- and so that one dead connection costs a piece rather than a quarter of
-- the download.
local DL_CHUNK_MIN = 1024 * 1024
local DL_CHUNK_MAX = 8 * 1024 * 1024
-- A dropped connection is put back in the queue; this bounds how often
-- that may happen before the download is called failed rather than slow.
local DL_MAX_RETRIES = 12

-- The thumbnail. YouTube publishes mqdefault at 320x180 -- the smallest
-- of the 16:9 ones, and the only size worth fetching on the machines
-- this fork exists for: hqdefault is 4:3 with black bars baked in.
--
-- Two bounds because there are two possible files. Qt hangs the picture
-- in a QLabel and only CLIPS it to the size stated (no setScaledContents),
-- so a file bigger than its bounds comes out cut rather than shrunk: what
-- is on disk has to be the size the layout is told about. The core's
-- scaler gives us 240 wide, a third of the dialog; without it the file
-- stays as it came and is declared at its own 320.
local THUMB_SOURCE = "mqdefault.jpg"
local THUMB_RAW_W, THUMB_RAW_H = 320, 180
local THUMB_W, THUMB_H = 240, 135

            --[[ Translations ]]--

-- The catalogues live one file per language under share/lua/i18n/invidious/
-- and only the one in use is ever read: sixteen languages parsed at every
-- activation, to keep one, is not free on the machines this fork exists for
-- -- and it buried this file under ten screens of strings. English sits
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
  setmetatable(lang, { __index = require("pvlc_i18n").load("invidious") })
end

            --[[ Region of the results ]]--

-- YouTube decides what to show from a country, and Invidious passes ours
-- through: the "region" parameter is honoured by the JSON API and by the
-- HTML /search route alike (it reads uri_params["region"] before falling
-- back to the instance's own preferences). Without it, a search on an
-- instance hosted in Spain answers with what YouTube shows in Spain --
-- which is the whole of the effect, not a property of the search.
--
-- Only the languages this fork is translated into, plus the handful a
-- French or English speaker is likely to want. "Any" is deliberately not
-- offered: there is no such thing, an absent region simply means the
-- instance's own.
local REGIONS = {
  { "FR", "France" },        { "BE", "Belgique / België" },
  { "CH", "Suisse / Schweiz" }, { "CA", "Canada" },
  { "US", "United States" }, { "GB", "United Kingdom" },
  { "DE", "Deutschland" },   { "AT", "Österreich" },
  { "ES", "España" },        { "MX", "México" },
  { "IT", "Italia" },        { "PT", "Portugal" },
  { "BR", "Brasil" },        { "NL", "Nederland" },
  { "PL", "Polska" },        { "CZ", "Česko" },
  { "SE", "Sverige" },       { "TR", "Türkiye" },
  { "RU", "Россия" },        { "UA", "Україна" },
  { "JP", "日本" },          { "KR", "대한민국" },
  { "CN", "中国" },          { "TW", "臺灣" },
}

local function region_index(code)
  for i, entry in ipairs(REGIONS) do
    if entry[1] == code then
      return i
    end
  end
  return nil
end

-- The language the interface is actually running in. On macOS the chosen
-- language becomes LANG at startup (bin/darwinvlc.m), and "auto" leaves it
-- to the system -- so the environment is the answer to both cases.
local function ui_language()
  -- The player knows, and now says so: vlc.config.language() answers with
  -- the locale the interface is really running in, whatever way that
  -- interface applied the user's choice. Added to the core for this.
  if vlc.config and vlc.config.language then
    local ok, value = pcall(vlc.config.language)
    if ok and type(value) == "string" and value ~= "" then
      return string.lower(value)
    end
  end
  -- A core without it: read what macOS puts there anyway. The first
  -- variable that is SET AND NOT EMPTY -- an exported but empty LANGUAGE
  -- is common, and "or" hands back the empty string, which would send
  -- every locale to the default region.
  for _, name in ipairs({ "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" }) do
    local value = os.getenv(name)
    if value and value ~= "" then
      return string.lower(value)
    end
  end
  return ""
end

-- The country a speaker of that language most likely wants. A guess, and
-- only a default: the menu is there to be told otherwise.
local LANGUAGE_REGION = {
  fr = "FR", en = "US", de = "DE", es = "ES", it = "IT", nl = "NL",
  pl = "PL", cs = "CZ", sv = "SE", tr = "TR", ru = "RU", uk = "UA",
  ja = "JP", ko = "KR", pt = "PT",
}

local function default_region()
  local l = ui_language()
  local lang_part, country = string.match(l, "^(%a%a)[_%-](%a%a)")

  -- The country the locale names, when the menu offers it: fr_CA is
  -- Canada and not France, es_MX is Mexico and not Spain, and guessing
  -- from the language alone would override what the user already said.
  if country then
    local code = string.upper(country)
    if region_index(code) then
      return code
    end
    -- Chinese is written the same in several places the menu does not
    -- list one by one; Hong Kong watches what Taiwan watches.
    if lang_part == "zh" then
      return (country == "tw" or country == "hk") and "TW" or "CN"
    end
  end

  local two = lang_part or string.match(l, "^(%a%a)")
  return (two and LANGUAGE_REGION[two]) or "US"
end

            --[[ State ]]--

local app = {
  instance = nil,    -- base URL of the connected instance
  mode = "api",      -- "api" (JSON) or "html" (front-end scraping)
  last_url = "https://",
  proxy = true,      -- rewrite stream URLs through the instance (local=true)
  region = nil,      -- ISO 3166 country the results are asked for
  instances = {},    -- id -> instance base URL
  results = {},      -- id -> { kind, id, title, author, published }
  video = nil,       -- currently opened video { id, title, author, ... }
  formats = {},      -- id -> { label, url }
  thumb = nil,       -- the picture of that video { path, w, h }
  -- The picture and sound just downloaded separately, when there are
  -- any: { video, audio, out, dir }. What the Combine button acts on.
  combine = nil,
  thumb_for = nil,   -- which video id it was fetched for
  -- What the list was showing last, so that coming back from a video
  -- lands on it again rather than on an empty search: the query and mode
  -- as typed, the items themselves, and the channel they came from when
  -- the list is a channel's videos rather than a search.
  last_query = "",
  last_mode = 1,
  view_items = nil,
  view_kind = nil,
  view_channel = nil,
  -- Sessions a browser earned on an anti-bot check, per instance URL:
  -- { cookie = "...", user_agent = "..." }. The user agent belongs with
  -- the cookie: the check binds one to the other, so replaying the cookie
  -- under VLC's own name would just earn a fresh challenge.
  sessions = {},
  handoff = nil,     -- the local page waiting for the browser's answer
  challenge_instance = nil,  -- which instance that handover is for
  challenge_url = nil,       -- the exact address that got guarded
  tried_cookie = nil,        -- the session already tried and refused
  tried_seq = nil,           -- how many handovers we have already acted on
  tried_relay = false,       -- the relay has had its go
  stale_session = false,     -- the last try carried a session that failed
  refused = {},              -- instances that gave a session and refused it
  navigating = false,        -- the tab is opening the page we asked for
  retry = nil,       -- what to re-run once the session comes back
  awaiting_challenge = false,  -- the challenge view is up and polling
}

-- The download in progress. Kept out of `app` because it outlives the
-- view it was started from: going back to the list, or opening another
-- video, leaves the bytes coming.
local dl = {
  active = false,
  files = {},        -- { url, path, name } -- two when picture and sound
  idx = 0,           -- which of them is being fetched (1-based once started)
  -- The connections fetching the current file, one per part of it:
  -- { stream, off = where its next byte goes, last = where it stops }.
  slices = {},
  queue = {},        -- the pieces not yet handed to a connection
  retries = 0,       -- pieces put back after a connection dropped
  fh = nil,
  got = 0,           -- bytes of the current file, over all its slices
  started = nil,     -- when it began, for the rate shown beside the bar
  total = 0,         -- what that file announced, 0 when it would not say
  written = {},      -- the paths finished, for the closing message
  failed = 0,
  dir = nil,         -- where they land
  cancelled = false,
}

local dlg = nil
local ui = {}

            --[[ Settings kept between sessions ]]--

-- Whoever always uses the same instance should not have to go and ask
-- api.invidious.io for a list of them first: the address that worked last
-- time comes back in the field, and Connect is one click away. Only what
-- the connection view holds is kept -- the address and the proxy box --
-- and the mode is deliberately not, so that an instance which reopens its
-- API is found out on the next connection rather than staying on the
-- fallback for ever.
local function settings_path()
  local dir = vlc.config and vlc.config.userdatadir
               and vlc.config.userdatadir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/invidious.json"
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
  if type(obj.instance) == "string" and obj.instance ~= "" then
    app.last_url = obj.instance
  end
  -- The box defaults to ticked, so only an explicit false may untick it:
  -- "obj.proxy or true" would ignore the very value being read.
  if type(obj.proxy) == "boolean" then
    app.proxy = obj.proxy
  end
  -- an unknown code means a settings file from a later version, or a hand
  -- edit: fall back rather than show a menu with nothing selected
  if type(obj.region) == "string" and region_index(obj.region) then
    app.region = obj.region
  end
end

-- Called on a connection that worked. A file that cannot be written is
-- not worth a word to the user: nothing is lost but the shortcut.
local function save_settings()
  local path = settings_path()
  if not (path and json) then
    return
  end
  local f = io.open(path, "w")
  if not f then
    vlc.msg.dbg("[Invidious] cannot write " .. path)
    return
  end
  f:write(json.encode({ instance = app.last_url, proxy = app.proxy,
                        region = app.region }, { indent = true }))
  f:close()
end

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
  load_lang()
  vlc.msg.dbg("[Invidious] Welcome")
  json = require("dkjson")
  load_settings()
  show_connect()
end

function deactivate()
  vlc.msg.dbg("[Invidious] Bye")
  -- the loopback server outlives the dialog otherwise, and its pages hold
  -- a secret that has no reason to stay reachable
  if vlc.timer then
    vlc.timer(0)
  end
  -- A download has no thread of its own: with the timer gone nothing
  -- would ever finish it, so the half-written file is closed here rather
  -- than left to the garbage collector. What was written stays -- unlike
  -- a cancellation, quitting is not the user saying they did not want it.
  dl.active = false
  if dl.fh then
    dl.fh:close()
    dl.fh = nil
  end
  dl.slices = {}
  if app.handoff then
    app.handoff:close()
    app.handoff = nil
  end
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

-- Long work has to say it is still there. The core watches the extension
-- thread and, after ten seconds without a sign of life, offers to kill
-- it -- and kills it outright when it cannot even show that question.
-- Probing a handful of public instances, or waiting on a slow one, is
-- not a hung script.
local function still_alive()
  if vlc.keep_alive then
    pcall(vlc.keep_alive)
  end
end

-- A string a file system accepts as a name. The length is capped without
-- ever cutting inside a UTF-8 sequence -- a video title is whatever its
-- author felt like, and half a character is not a name.
local function sanitize_filename(s)
  s = tostring(s or "")
  s = string.gsub(s, "[/\\:%*%?\"<>|%c]", "_")
  s = trim(s)
  s = string.gsub(s, "^%.+", "_")
  if s == "" then
    s = "_"
  end
  if #s > 120 then
    -- Judged on the first byte DROPPED, not on the last one kept: a
    -- continuation byte there is what says the cut falls inside a
    -- character. Walking back from the last byte kept instead throws away
    -- a whole character when the cut happened to land cleanly -- and, on
    -- a lead byte, leaves it dangling with its continuation gone, which
    -- is not text any more.
    local cut = 120
    while cut > 0 do
      local b = string.byte(s, cut + 1)
      if not b or b < 128 or b >= 192 then
        break
      end
      cut = cut - 1
    end
    s = trim(string.sub(s, 1, cut))
  end
  return s
end

local function file_exists(path)
  local f = path and io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

-- vlc.io.mkdir creates one level at a time
local function mkdir_p(path)
  if not (vlc.io and vlc.io.mkdir) then
    return false
  end
  local built = ""
  if string.sub(path, 1, 1) == "/" then
    built = "/"
  end
  for part in string.gmatch(path, "[^/]+") do
    built = built .. part
    vlc.io.mkdir(built, "0755")
    built = built .. "/"
  end
  return true
end

local function format_bytes(bytes)
  bytes = tonumber(bytes)
  if not bytes or bytes < 0 then
    return "?"
  end
  if bytes >= 1073741824 then
    return string.format("%.2f", bytes / 1073741824) .. " GiB"
  end
  if bytes >= 1048576 then
    return string.format("%.1f", bytes / 1048576) .. " MiB"
  end
  return math.floor(bytes / 1024) .. " KiB"
end

-- Drawn out of block characters rather than asked of the interface: the
-- dialog API has no progress widget, and this one line is rewritten in
-- place several times a second.
local function progress_bar(got, total)
  local width = 24
  local filled = 0
  if total > 0 then
    filled = math.floor(got * width / total)
  end
  if filled > width then
    filled = width
  end
  return string.rep("\226\150\136", filled)
      .. string.rep("\226\150\145", width - filled)
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

            --[[ Anti-bot checks ]]--

-- Instances put very different guards in front of their pages -- Anubis
-- (proof of work), captchaproxy driving cap.js or hCaptcha, Cloudflare.
-- What they have in common is a small interstitial page instead of the
-- one that was asked for, so recognise the shape rather than the product.
local CHALLENGE_MARKERS = {
  "not a bot", "anubis", "captchaproxy", "cap%-widget", "just a moment",
  "challenge%-platform", "hcaptcha", "turnstile", "cf%-chl",
  "enable javascript and cookies", "goaway", "gandalf",
}

-- Every page Invidious serves -- search, watch, channel, playlist --
-- carries its own chrome. A 200 without a trace of it is not the site
-- answering: nerdvpn hands a robot pages of randomly generated novel
-- text instead of its own, which parses to nothing and would otherwise
-- be reported as "no results".
local INVIDIOUS_MARKS = { 'id="contents"', "pure%-u", "h%-box",
                          "channel%-name" }

-- The decoy test only makes sense on a page. The instance directory
-- answers JSON, the API answers JSON and a DASH manifest is XML: none of
-- them carries any of the site's chrome, and judging them by it would
-- turn every single one into a "challenge".
local function looks_like_html(body)
  local head = string.sub(body, 1, 200)
  return string.find(head, "<!DOCTYPE", 1, true) ~= nil
      or string.find(head, "<html", 1, true) ~= nil
end

local function looks_like_invidious(body)
  for _, mark in ipairs(INVIDIOUS_MARKS) do
    if string.find(body, mark) then
      return true
    end
  end
  return false
end

-- status may be nil when the caller has none to give.
local function is_challenge(body, status)
  -- A decoy is a 200 that lies. Any other status already tells the truth
  -- -- nginx's own 401, 404 or 502 page is HTML without a trace of the
  -- site's chrome, and taking it for a decoy sent the browser to fetch an
  -- address that answers "Authorization Required", which opens a password
  -- box in the user's face. A guard that answers with a status of its own
  -- (go-away's 418) still names itself in the body, so the markers below
  -- catch it either way.
  local ok_status = status == nil or (status >= 200 and status < 300)
  if ok_status and body and #body > 0 and looks_like_html(body)
     and not looks_like_invidious(body) then
    return true
  end
  -- Size is the discriminator: an interstitial is around 4 kB, where a real
  -- search page is 70 kB and a watch page 40. Do NOT rule one out on the
  -- presence of "/watch?v=" -- measured, captchaproxy puts the address it
  -- will send you back to in a hidden field, so the challenge standing in
  -- front of a video does contain it.
  if not body or #body > 32768 then
    return false
  end
  local head = string.lower(string.sub(body, 1, 8192))
  for _, marker in ipairs(CHALLENGE_MARKERS) do
    if string.find(head, marker) then
      return true
    end
  end
  return false
end

-- True when the URL is served by that instance and not merely prefixed by
-- its name -- "https://inv.example.com" must not match a host that only
-- starts the same way.
local function on_instance(url, base)
  if not url or not base or string.sub(url, 1, #base) ~= base then
    return false
  end
  local rest = string.sub(url, #base + 1, #base + 1)
  return rest == "" or rest == "/" or rest == "?"
end

-- The session belongs to the instance that issued it and to nothing else:
-- the DASH manifests and the stream URLs point at googlevideo, and the
-- directory at api.invidious.io. Neither has any business seeing it.
local function session_for(url)
  for base, session in pairs(app.sessions) do
    if on_instance(url, base) then
      return session
    end
  end
  return nil
end

-- Replaying a session means presenting the request the way the browser
-- that earned it would have. Measured on go-away: from the very tab that
-- was displaying a page -- same connection, same cookie, same user agent
-- -- an XMLHttpRequest for that same address still came back 418, and
-- only the kind of request differed. Those Sec-Fetch fields are what say
-- so, and a page's script is forbidden from setting them; PowerVLC is
-- not, and what they state is true: a page the user just asked for.
-- Bisected against go-away with the exact request a browser had just been
-- served: User-Agent, Accept-Language and Accept-Encoding are part of what
-- the check is bound to, down to the q-values -- "fr" alone, a reordering,
-- or a missing Accept-Encoding each earn a fresh challenge. Accept,
-- Referer, the Sec-Fetch fields and even the HTTP version are not. So the
-- three that matter are replayed verbatim from the browser, and nothing
-- here is guessed.
local NAVIGATION_HEADERS = {
  ["Sec-Fetch-Mode"] = "navigate",
  ["Sec-Fetch-Dest"] = "document",
  ["Sec-Fetch-Site"] = "same-origin",
  ["Sec-Fetch-User"] = "?1",
  ["Upgrade-Insecure-Requests"] = "1",
  ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,"
            .. "*/*;q=0.8",
}

local function session_headers(url)
  local session = session_for(url)
  if not session then
    return nil
  end
  local headers = {}
  for name, value in pairs(NAVIGATION_HEADERS) do
    headers[name] = value
  end
  if session.cookie and session.cookie ~= "" then
    headers["Cookie"] = session.cookie
  end
  if session.user_agent and session.user_agent ~= "" then
    headers["User-Agent"] = session.user_agent
  end
  if session.accept_language and session.accept_language ~= "" then
    headers["Accept-Language"] = session.accept_language
  end
  if session.accept_encoding and session.accept_encoding ~= "" then
    headers["Accept-Encoding"] = session.accept_encoding
  end
  return headers
end

-- Feeds the player's own jar, so that a stream relayed by the instance
-- (the "local=true" option) carries the same session the script uses.
local function store_cookies(instance, cookies)
  if not (vlc.http and vlc.http.setcookie) then
    return
  end
  for one in string.gmatch(cookies or "", "[^;]+") do
    one = trim(one)
    if one ~= "" and string.find(one, "=", 1, true) then
      vlc.http.setcookie(instance .. "/", one .. "; path=/")
    end
  end
end

-- The tab that solved the check, when it is still there. Only ever used
-- for the instance it was opened on.
local function relay_for(url)
  if not (app.handoff and app.challenge_instance) then
    return nil
  end
  if not on_instance(url, app.challenge_instance) then
    return nil
  end
  if not app.handoff:relay() then
    return nil
  end
  return app.handoff
end

            --[[ HTTP ]]--

-- HTTP(S) GET through VLC's stream layer.
-- Returns the raw body or nil, error-string.
local function stream_body(url)
  local ok, stream, msg = pcall(vlc.stream, url)
  if not ok or not stream then
    return nil, tostring(msg or stream or "stream error")
  end
  local parts = {}
  while true do
    still_alive()
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

-- Same, but able to carry the session the browser handed back. vlc.stream()
-- sets no header at all, so it only stands in when this fork's native
-- vlc.http is missing.
local function direct_body(url)
  if not (vlc.http and vlc.http.get) then
    return stream_body(url)
  end
  local status, body = vlc.http.get(url, session_headers(url))
  if not status then
    return nil, tostring(body or "http error")
  end
  -- Read the page before judging the status. A guard is free to answer
  -- with anything at all -- measured, go-away serves its check as
  -- "418 I'm a teapot" -- and going by the status alone throws that page
  -- away unread, reporting a transport error where there is in fact a
  -- check the browser could pass.
  if is_challenge(body, status) then
    return nil, "challenge"
  end
  if status >= 400 then
    return nil, "HTTP " .. status
  end
  if not body or #body == 0 then
    return nil, "empty response"
  end
  return body
end

-- Asks the relay tab for the page. It is the browser that fetches, with
-- whatever session the site gave it -- including one PowerVLC is not
-- allowed to see.
local function relay_body(handoff, url)
  local status, body = handoff:fetch(url, 30)
  if not status then
    return nil, tostring(body or "relay error")
  end
  -- The tab has gone to open the page instead of fetching it; nothing is
  -- refused, it just has to be handed over once it is there.
  if body == "PVLC_NAVIGATING" then
    app.navigating = true
    if app.challenge_instance then
      app.refused[app.challenge_instance] = nil
    end
    return nil, "challenge"
  end
  if is_challenge(body, status) then
    return nil, "challenge"
  end
  if status >= 400 then
    return nil, "HTTP " .. status
  end
  if not body or #body == 0 then
    return nil, "empty response"
  end
  return body
end

-- The relay reports itself live as soon as its page polls, which can be
-- before the cookie it carried has reached us. Picking the session up here
-- rather than only at resume time takes that race out: whichever arrives
-- first, the next request uses it.
local function absorb_session()
  if not (app.handoff and app.challenge_instance) then
    return
  end
  if app.sessions[app.challenge_instance] then
    return
  end
  local answer = app.handoff:poll()
  -- Never pick the same refused state back up: poll() keeps handing out
  -- whatever the browser last sent, so without this the session dropped a
  -- moment ago is restored at once and the whole thing spins.
  if answer and answer.cookie == app.tried_cookie then
    return
  end
  if answer and answer.cookie and answer.cookie ~= "" then
    app.tried_cookie = answer.cookie
    app.sessions[app.challenge_instance] =
      { cookie = answer.cookie, user_agent = answer.user_agent or "",
        accept_language = answer.accept_language or "",
        accept_encoding = answer.accept_encoding or "" }
    store_cookies(app.challenge_instance, answer.cookie)
    vlc.msg.dbg("[Invidious] session picked up for "
                .. app.challenge_instance)
  end
end

local function get_body(url)
  absorb_session()
  local relay = relay_for(url)

  -- Always ask for ourselves first. Handing everything to the browser as
  -- soon as a relay exists meant asking it for addresses that are simply
  -- refused -- nerdvpn's API answers 401, and the browser then puts a
  -- password box in front of the user and blocks until it is answered.
  local body, err = direct_body(url)

  -- Only a guard is worth a second try through the browser: a 401, a 403
  -- on an API the operator closed, or a 500 would come back exactly the
  -- same, and that round trip is a second lost on every connection.
  if err == "challenge" and relay then
    vlc.msg.dbg("[Invidious] falling back to the browser relay")
    body, err = relay_body(relay, url)
  end

  if body and is_challenge(body) then
    body, err = nil, "challenge"
  end
  -- One line per request, carrying its outcome: the address alone said
  -- nothing, and the pair "address" + "what came back" is what every
  -- diagnosis has needed.
  vlc.msg.dbg("[Invidious] " .. url .. " -> "
              .. (err or (#body .. " o")))
  if err == "challenge" then
    -- The address the browser has to be pointed at. Instances do not all
    -- guard the same thing: go-away on nadeko guards /watch and nothing
    -- else, so sending someone to the home page has them "pass" a check
    -- that was never asked there, and the relay still gets its 418.
    app.challenge_url = url
    -- Measured on go-away: the state is handed out in stages -- 380 bytes
    -- just to browse, 685 after the proof of work, 913 once a second check
    -- is passed, and only that last one opens /watch. A session that still
    -- gets challenged was therefore never a pass. Dropping it here is what
    -- turns "this instance refuses PowerVLC" into the truth, which is that
    -- the check has not been carried through.
    for base in pairs(app.sessions) do
      if on_instance(url, base) then
        app.sessions[base] = nil
        app.stale_session = true
      end
    end
  end
  return body, err
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
--
-- ⚠ This reads the page in whatever language the page came in. Asking the
-- instance for our own language (&hl=) is what stops a French search from
-- answering with Spanish titles -- and it also translates this very line,
-- so a parser that only knew English would silently lose every date and
-- with it the ordering. Hence a unit table per language, and a number that
-- is looked for on its own rather than inside an English sentence.
local UNIT_SECONDS = {
  -- English
  second = 1, minute = 60, hour = 3600, day = 86400,
  week = 604800, month = 2629800, year = 31557600,
  -- French: "il y a 3 mois", "il y a 1 an"
  seconde = 1, heure = 3600, jour = 86400, semaine = 604800,
  mois = 2629800, an = 31557600, ["année"] = 31557600,
  -- Spanish / Portuguese
  segundo = 1, minuto = 60, hora = 3600, ["día"] = 86400, dia = 86400,
  semana = 604800, mes = 2629800, ["mês"] = 2629800,
  ["año"] = 31557600, ano = 31557600,
  -- German ("Minute" is spelt as in English)
  sekunde = 1, stunde = 3600, tag = 86400,
  woche = 604800, monat = 2629800, jahr = 31557600,
  -- Italian, plurals included: they are not formed by adding a letter
  secondo = 1, secondi = 1, minuto_it = 60, minuti = 60,
  ora = 3600, ore = 3600, giorno = 86400, giorni = 86400,
  settimana = 604800, settimane = 604800,
  mese = 2629800, mesi = 2629800, anno = 31557600, anni = 31557600,
}

local function parse_relative_date(text)
  if not text then
    return nil
  end
  local lower = string.lower(text)
  -- the number, then the first word after it: true of every phrasing seen
  -- ("3 months ago", "il y a 3 mois", "hace 3 meses", "vor 3 Monaten")
  local count, unit = string.match(lower, "(%d+)%s+([%a\128-\255]+)")
  if not count then
    return nil
  end
  -- plurals, in the languages that just add one
  local secs = UNIT_SECONDS[unit]
        or UNIT_SECONDS[string.gsub(unit, "s$", "")]
        or UNIT_SECONDS[string.gsub(unit, "en$", "")]
        or UNIT_SECONDS[string.gsub(unit, "n$", "")]
        or UNIT_SECONDS[string.gsub(unit, "i$", "o")]
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
  -- The three card shapes differ only by the link they hang on. Videos
  -- take anything after the id: inside a playlist the link carries
  -- "&list=...&index=N", and the old pattern, anchored on the closing
  -- quote, matched none of them.
  local link = (kind == "channel")
    and 'href="/channel/([%w_%-]+)">%s*<p class="channel%-name"'
    or (kind == "playlist")
    and 'href="/playlist%?list=([%w_%-]+)"><p dir="auto">'
    or  'href="/watch%?v=([%w_%-]+)[^"]*"><p dir="auto">'
  local pos = 1

  while true do
    local first, last, id = string.find(html, link, pos)
    if not first then
      break
    end
    -- bound the per-card searches by the start of the next card
    local nextFirst = string.find(html, link, last) or (#html + 1)

    local item = { id = id }
    if kind == "playlist" then
      local _, te, title = string.find(html,
        '<p dir="auto">(.-)</p>', first)
      if te and te < nextFirst then
        item.title = html_decode(title)
      end
      local _, ae, author = string.find(html, CHANNEL_NAME, last)
      if ae and ae < nextFirst then
        item.author = html_decode(author)
      end
      -- "9 videos" sits in the same overlay a video uses for its length,
      -- and that overlay comes BEFORE the title link: searching forward
      -- from the title picks up the next card's count. Take the last one
      -- standing between the previous card and this title.
      local from = pos
      while true do
        local cs, ce, count = string.find(html,
          '<p class="length">([^<]*)</p>', from)
        if not cs or cs > first then
          break
        end
        item.videoCount = html_decode(count)
        from = ce
      end
    elseif kind == "channel" then
      local _, e, name = string.find(html, CHANNEL_NAME, first)
      if e and e < nextFirst then
        item.author = html_decode(name)
      end
      local _, se, subs = string.find(html,
        "<p>([^<]*%d[^<]*)</p>", last)
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
    elseif kind == "playlist" then
      item.playlistId = id
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

-- The country to ask for, ready to append. Empty when nothing was ever
-- chosen, so that a build without the setting behaves as it always did.
local function region_param()
  local code = app.region
  return code and ("&region=" .. code) or ""
end

-- ... and the language the titles come back in, which is NOT the same
-- thing. "region" is YouTube's gl: it decides WHICH videos surface.
-- Titles and descriptions are localised by "hl", and a search on an
-- instance whose own locale is Spanish answers with Spanish titles for a
-- video that has a French one -- whatever region was asked for.
--
-- Invidious reads it in before_all.cr ("locale = env.params.query["hl"]?
-- || preferences.locale"), so it works on the HTML pages as well as on
-- the API, and it overrides the instance's own setting for that request.
local LOCALE_CODE = {
  ["pt_br"] = "pt-BR", ["zh_tw"] = "zh-TW", ["zh_hk"] = "zh-TW",
  ["zh_cn"] = "zh-CN",
}

local function hl_param()
  local l = ui_language()
  local lang_part, country = string.match(l, "^(%a%a)[_%-](%a%a)")
  local code = lang_part and LOCALE_CODE[lang_part .. "_" .. country]
  if not code then
    code = lang_part or string.match(l, "^(%a%a)")
  end
  return code and ("&hl=" .. code) or ""
end

-- What every request for the instance's own content carries. The video
-- page and a channel take the language too: their titles are localised
-- the same way, and a French list that opens on a Spanish page would be
-- the same bug one click further.
local function content_params()
  return hl_param()
end

local function search_params()
  return region_param() .. hl_param()
end

local function html_search(instance, query, kind)
  local url = instance .. "/search?q="
           .. vlc.strings.encode_uri_component(query)
           .. "&type=" .. (kind == "channel" and "channel" or "video")
           .. search_params()
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
  local body, err = get_body(instance .. "/channel/" .. channel_id
                             .. "?" .. string.sub(content_params(), 2))
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

local function html_playlist_videos(instance, list_id)
  local body, err = get_body(instance .. "/playlist?list=" .. list_id
                             .. content_params())
  if not body then
    return nil, err
  end
  local items = html_parse_cards(body, "video")
  -- a playlist is in its own order, which is finer than the rounded dates
  items.ordered = true
  items.title = html_decode(string.match(body, "<h3>%s*(.-)%s*</"))
  return items
end

-- Recognises an address the user pasted instead of words to search for.
-- Returns the kind and the id, or nil. Deliberately narrow: the markers
-- it looks for do not occur in ordinary search terms.
local function detect_target(text)
  local q = trim(text)
  -- a video first: "watch?v=X&list=Y" is a video someone reached through
  -- a playlist, and it is the video they mean
  local id = string.match(q, "watch%?v=([%w_%-]+)")
           or string.match(q, "youtu%.be/([%w_%-]+)")
  if id then
    return "video", id
  end
  id = string.match(q, "playlist%?list=([%w_%-]+)")
       or string.match(q, "[?&]list=([%w_%-]+)")
  if id then
    return "playlist", id
  end
  id = string.match(q, "/channel/([%w_%-]+)")
  if id then
    return "channel", id
  end
  return nil
end

-- Reads the watch page and returns the same shape as the videos API.
local function html_video(instance, video_id)
  local url = instance .. "/watch?v=" .. video_id .. content_params()
  if app.proxy then
    url = url .. "&local=true"
  end
  local body, err = get_body(url)
  if not body then
    return nil, err
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
    -- "Shared " only prefixes the English wording; the others say it
    -- their own way and there is nothing to strip.
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

-- Copying an address and pasting it into a browser is two steps too many
-- when the player knows how to open one.
local function open_in_browser(url)
  if not (url and url ~= "" and vlc.browser and vlc.browser.open) then
    return false
  end
  return vlc.browser.open(url) and true or false
end

function close_dlg()
  -- Leaving the challenge view stops its poll: every other view goes
  -- through here, so nothing else has to remember to disarm it.
  app.awaiting_challenge = false
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
  dlg:add_label(lang.lbl_region, 1, 6, 1, 1)
  ui.region = dlg:add_dropdown(2, 6, 2, 1)
  for i, entry in ipairs(REGIONS) do
    ui.region:add_value(entry[2] .. " (" .. entry[1] .. ")", i)
  end
  ui.region:set_value(region_index(app.region or default_region())
                      or region_index("US"))
  dlg:add_button(lang.btn_connect, click_connect, 1, 7, 1, 1)
  ui.message = dlg:add_label("", 1, 8, 3, 1)
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
    still_alive()
    local info = entry[2]
    -- Keep every clearnet instance. onion/i2p need a network stack VLC
    -- does not have, and the directory types them apart. The "api" flag
    -- is NOT a filter: it is false on instances that do serve the API but
    -- answer the monitor's probe with an anti-bot challenge. The Connect
    -- button probes the real endpoint and says what it found.
    --
    -- Carrying no monitoring at all is another matter: the directory
    -- publishes uptime for everything it can reach, so an entry without
    -- any is one the directory itself cannot reach either. That is how a
    -- Yggdrasil address slips through typed as "https" -- and it is the
    -- directory's own verdict, not a list of names kept here.
    local mon = type(info) == "table" and info.monitor or nil
    local uptime = mon and (mon.uptime
                   or (mon["30dRatio"] and mon["30dRatio"].ratio))
    if type(info) == "table" and info.type == "https" and info.uri
       and mon ~= nil then
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
  app.proxy = ui.proxy:get_checked()
  -- a dropdown nobody touched answers -1, hence the fallbacks
  local picked = ui.region and ui.region:get_value()
  local entry = (type(picked) == "number") and REGIONS[picked] or nil
  app.region = entry and entry[1] or app.region or default_region()
  connect_to(url)
end

-- What to search for when all we want to know is whether an instance
-- answers at all.
--
-- It used to be "vlc", which reads as a statement of who is asking; and
-- on the guarded instances (chocolatemoo, nerdvpn) the check carries the
-- query along, so the user was sent to a browser page searching for
-- "VLC" without ever having asked for it. A neutral word is friendlier
-- and gives away nothing.
--
-- ⚠ NOT an empty query, tempting as it is: measured 2026-08-07 on three
-- instances, `?q=` answers 200 with an empty results page (~6 kB, zero
-- items) while `?q=test` gives ~57 kB of real ones. The HTML probe below
-- judges an instance on `#items == 0`, so an empty search would declare
-- every instance dead.
local PROBE_QUERY = "test"

function connect_to(url)
  set_message(lang.msg_connecting)

  -- Prefer the JSON API: it carries exact dates and every quality.
  local obj, jerr = get_json(url .. "/api/v1/search?q=" .. PROBE_QUERY
                             .. "&fields=type")
  if obj then
    app.mode = "api"
  else
    -- API switched off by the operator: fall back to the HTML pages the
    -- instance serves to browsers.
    set_message(lang.msg_trying_html)
    local items, err = html_search(url, PROBE_QUERY, "video")
    if not items or #items == 0 then
      -- Guarded rather than closed: the browser can pass the check, so
      -- offer that instead of writing the instance off.
      if err == "challenge" or jerr == "challenge" then
        start_challenge(url, function() connect_to(url) end)
        return
      end
      -- Tell apart "the instance is unreachable" from "it is up but
      -- lets neither route through".
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
  save_settings()
  show_search()
  if app.mode == "html" then
    set_message(lang.msg_html_mode)
  end
end

            --[[ Anti-bot check: handed over to the browser ]]--

-- Two ways in, because the instances do not all leave the same one open.
--
--  * Some hand out a session cookie the page can read (Anubis does). Once
--    PowerVLC has it, it talks to the instance itself and the browser can
--    go away.
--  * Others mark it HttpOnly, so no script will ever see it -- measured on
--    captchaproxy. There, the tab that solved the check stays open and
--    fetches for us. Its own pages are same-origin, which is exactly what
--    the instances' "connect-src 'self'" allows; talking to 127.0.0.1 from
--    that page would not be. So the tab only ever postMessage()s, which no
--    Content-Security-Policy governs, and PowerVLC's own page -- served
--    from here, under no policy -- does the local half.
--
-- Either way the check itself is solved by the person in front of the
-- machine, in a real browser.

local function attr_escape(s)
  return (string.gsub(string.gsub(s or "", "&", "&amp;"), '"', "&quot;"))
end

-- Anything of ours that lands inside a JavaScript string literal has to be
-- escaped for it. One French message was enough to prove it: "l'onglet"
-- closed the literal, the whole relay script failed to parse, and a page
-- whose script does not parse simply does nothing -- no error anywhere,
-- and the failure surfaced three steps away as "PowerVLC is not
-- answering". The English strings carry no apostrophe, so it only ever
-- broke in French.
local function js_escape(s)
  s = string.gsub(s or "", "\\", "\\\\")
  s = string.gsub(s, "'", "\\'")
  s = string.gsub(s, "\r", "")
  return (string.gsub(s, "\n", " "))
end

-- gsub() reads "%" in a replacement string; a function never lets it.
local function js_put(subject, token, text)
  return (string.gsub(subject, token, function() return js_escape(text) end))
end

-- The same marker tables the player judges a body with, turned into one
-- JavaScript alternation. The page-side test and the player-side test
-- have to be the same test: a page the script calls real and the player
-- calls a challenge would loop between them for ever.
local function js_regex(markers)
  local parts = {}
  for _, mark in ipairs(markers) do
    -- Lua patterns escape with "%", JavaScript with "\", and a stray "/"
    -- would close the literal.
    local lit = string.gsub(mark, "%%(.)", "%1")
    lit = string.gsub(lit, "[%^%$%(%)%%%.%[%]%*%+%-%?%{%}|/\\]", "\\%0")
    table.insert(parts, lit)
  end
  return table.concat(parts, "|")
end

local function html_escape(s)
  s = string.gsub(s or "", "&", "&amp;")
  s = string.gsub(s, "<", "&lt;")
  return (string.gsub(s, ">", "&gt;"))
end

-- Runs on the instance's page, put there by the user's own click: the
-- policy leaves no other way to get a line of ours onto that origin.
-- Every step of this reports what happened, on the page itself. The first
-- version failed silently on each of its three dead ends -- clicked on the
-- wrong page, popup refused, nobody listening -- which left "nothing
-- happens" as the only symptom for all of them.
local BOOKMARKLET = "javascript:(function(){"
  .. "var O='{{ORIGIN}}';"
  .. "var here=location.protocol+'//'+location.host;"
  -- clicked on our own page instead of being dragged: the most natural
  -- mistake, and the one that used to look exactly like a broken build
  .. "if(here===O){alert('{{M_DRAG}}');return;}"
  .. "function say(t,bad){var d=document.getElementById('pvlcmsg');"
  .. "if(!d){d=document.createElement('div');d.id='pvlcmsg';"
  .. "document.body.appendChild(d);}"
  .. "d.style.cssText='position:fixed;z-index:2147483647;top:0;left:0;"
  .. "right:0;padding:8px;font:14px sans-serif;text-align:center;"
  .. "color:#fff;background:'+(bad?'#8a1a1e':'#1a7f37');"
  .. "d.textContent=t;}"
  -- Ambient reporting ("connected", "not answering") belongs on a page
  -- the user opened FOR the player -- clicked bookmark, or a page the
  -- player sent this tab to. Elsewhere the banner is just graffiti.
  .. "function note(t,bad){if(!AUTO||OURS)say(t,bad);}"
  -- Handing the page over means the browser is done with it: leaving the
  -- player running there would have the video going twice at once.
  .. "function stop(){try{var m=document.querySelectorAll('video,audio');"
  .. "for(var k=0;k<m.length;k++){m[k].pause();}}catch(err){}}"
  -- ... and pausing is not enough. The page keeps its player, so it goes
  -- on filling its buffer, and Invidious starts playing again a moment
  -- later on its own -- two copies of the same video coming down the same
  -- line, on machines whose whole problem is bandwidth. So empty the
  -- element and keep it empty: anything that starts playing afterwards is
  -- paused on the spot. Only ever called once the page has been handed
  -- over, never while the user is merely browsing.
  -- ⚠ Emptying the body DETACHES the player without stopping it: a media
  -- element goes on playing once it is out of the document, and a `play'
  -- listener on the document no longer hears it, so the guard below stops
  -- guarding at the very moment it is needed. Reported: page blank in the
  -- browser, sound still coming out of it. So remember the elements the
  -- first time round and work on that list afterwards, hang the guard on
  -- each element rather than only on the document, and drop `autoplay'
  -- before load() -- load() on an element that still carries it is an
  -- invitation to start over.
  .. "function stophard(){try{var m=document.querySelectorAll('video,audio');"
  .. "if(m.length){S.m=[];for(var j=0;j<m.length;j++)S.m.push(m[j]);}}"
  .. "catch(err){}"
  .. "var L=S.m||[];"
  .. "for(var k=0;k<L.length;k++){try{L[k].pause();"
  .. "L[k].autoplay=false;L[k].removeAttribute('autoplay');"
  .. "L[k].removeAttribute('src');try{L[k].src='';}catch(e4){}"
  .. "var q=L[k].getElementsByTagName('source');"
  .. "while(q.length){q[0].parentNode.removeChild(q[0]);}"
  .. "L[k].load();L[k].pause();"
  .. "if(!L[k].__pvlcg){L[k].__pvlcg=1;"
  .. "L[k].addEventListener('play',function(e){"
  .. "try{e.target.pause();}catch(e5){}},true);}}catch(e2){}}"
  .. "if(!S.k){S.k=1;document.addEventListener('play',function(e){"
  .. "try{e.target.pause();}catch(e3){}},true);}}"
  -- Is this the page, or the check standing in front of it? The very
  -- discriminants the player uses (CHALLENGE_MARKERS and INVIDIOUS_MARKS
  -- above), so that the two halves can never disagree about what a page
  -- is. Measured 05/08: every public instance now answers a plain client
  -- with an interstitial, and none of them carries a mark of the site.
  -- The answer is cached once it is yes: a check that passes navigates,
  -- which brings a new document and a new run of this script, and
  -- serialising a 70 kB page every two seconds is not free on the
  -- machines this fork is for.
  -- The tab is here to be read, not to play: once the check is passed,
  -- keep a copy of the page and then empty it. Invidious autoplays, and a
  -- video decoded in the browser AND in the player is the same stream
  -- pulled twice down the same line, on a machine that has neither the
  -- processor nor the bandwidth to spare. The copy is what the player
  -- gets afterwards, so nothing is lost by clearing the page.
  .. "function ready(){if(S.page)return 1;if(!real())return 0;"
  .. "try{S.page=document.documentElement.outerHTML;}catch(e1){}"
  -- Emptied only when this page is the player's: one it sent this tab to,
  -- or one it is about to be handed. Anywhere else the tab belongs to
  -- whoever is reading it, and an add-on that blanks the site as you
  -- browse it is not a companion, it is a nuisance.
  .. "if(OURS)wipe();return 1;}"
  -- Twice on purpose: once while the player is still in the document, and
  -- once on the remembered elements after it has been taken out of it.
  .. "function wipe(){stophard();"
  .. "try{var b=document.body;if(b){while(b.firstChild)"
  .. "b.removeChild(b.firstChild);}}catch(e2){}"
  .. "stophard();"
  .. "say('{{M_TAKEN}}');}"
  .. "function real(){if(S.real)return 1;try{"
  .. "var h=document.documentElement.outerHTML;"
  .. "if(/{{CHALLENGE_RE}}/i.test(h))return 0;"
  .. "if(/{{INVIDIOUS_RE}}/.test(h)){S.real=1;return 1;}"
  .. "return 0;}catch(err){return 1;}}"
  .. "var S=window.__pvlc;"
  .. "if(!S){S=window.__pvlc={};"
  .. "window.addEventListener('message',function(e){if(e.origin!==O)return;"
  .. "var d=e.data;if(!d||d.pv!==1)return;"
  -- The answer to hello says which video the player is waiting for. If it
  -- is the one this tab is showing, then this page exists BECAUSE the
  -- player asked for it -- nobody opened it to watch it here -- so silence
  -- it at once instead of waiting for the handover. Autoplay starts the
  -- moment the check is passed, and the handover is a hello, a poll and a
  -- round trip later: on a G3 that is several seconds of the same video
  -- playing twice, which is exactly what the whole page-handover design
  -- exists to avoid. Pause only, never stophard(): the DOM must still be
  -- intact when it is serialised and sent.
  -- The answer to hello says which video the player is waiting for. When
  -- it is the one this tab is showing, this page exists BECAUSE the
  -- player asked for it -- nobody opened it to watch it here -- so the
  -- tab is ours and gets the full treatment at once: take a copy of the
  -- page, then empty it.
  --
  -- Emptying rather than pausing, and as early as we possibly can. On
  -- these machines letting the browser finish standing its player up is
  -- one of the heaviest things that can happen: it pins the processor,
  -- decodes a second copy of a video the player is already decoding, and
  -- keeps pulling it off the instance for nothing. A pause leaves all of
  -- that in place. So the moment the page is known to be real, it goes.
  --
  -- Order matters and is not negotiable: `ready()' serialises outerHTML
  -- BEFORE wipe() rewrites the DOM, so the copy handed over later is the
  -- page as it was. And it only fires once the page IS the page: on a
  -- check still standing in front of it `ready()' answers 0 and nothing
  -- is touched -- wiping an interstitial would destroy the very check we
  -- are waiting on.
  .. "if(d.ack){S.ack=1;"
  .. "try{if(d.want){var wv=(d.want.match(/[?&]v=([^&]*)/)||[])[1];"
  .. "var mv=(location.search.match(/[?&]v=([^&]*)/)||[])[1];"
  -- ⚠ wipe() is called HERE and not left to ready(): the first hello, sent
  -- the instant the script is injected, has already run ready() and filled
  -- S.page, so every later call returns on `if(S.page)' before it ever
  -- looks at OURS. Setting the flag and calling ready() again therefore
  -- wiped nothing at all -- caught in simulation, never on the machine.
  .. "if(wv&&mv&&wv===mv){OURS=1;"
  .. "if(ready()){if(!S.wiped){S.wiped=1;wipe();}say('{{M_TAKING}}');}"
  .. "else{stop();}"
  .. "return;}}}catch(e6){}"
  .. "note('{{M_OK}}');return;}"
  .. "if(!d.url)return;"
  -- The page asked for may be the very one this tab is displaying. Hand
  -- that over instead of fetching it again: on the instances that only
  -- grant a pass for one navigation, re-fetching is exactly what cannot
  -- work, while the page is already here and paid for.
  .. "var a=(d.url.match(/[?&]v=([^&]*)/)||[])[1];"
  .. "var b=(location.search.match(/[?&]v=([^&]*)/)||[])[1];"
  -- The page goes first and the player is cut afterwards: emptying the
  -- <video> rewrites the very DOM being serialised.
  .. "if(a&&b&&a===b){say('{{M_PAGE}}');OURS=1;"
  .. "S.w.postMessage({pv:1,id:d.id,s:200,"
  .. "body:S.page||document.documentElement.outerHTML},O);"
  .. "wipe();return;}"
  .. "var x=new XMLHttpRequest();x.open('GET',d.url,true);"
  .. "x.onreadystatechange=function(){if(x.readyState==4){"
  .. "var t=x.responseText||'';"
  -- Refused, and both sides name a video: this tab can go and open it,
  -- which is the one thing a guard that only grants single navigations
  -- does accept. Last resort only -- where fetching works, fetching keeps
  -- the tab where it is.
  .. "if(a&&b&&(x.status==418||/not a bot|goaway/i.test(t.substring(0,4000))))"
  .. "{stop();say('{{M_NAV}}');"
  .. "S.w.postMessage({pv:1,id:d.id,s:200,body:'PVLC_NAVIGATING'},O);"
  -- The page this tab is about to load IS the player's; sessionStorage
  -- carries that one bit across the navigation, and is cleared on the
  -- way in so a later visit by hand is not caught by it.
  .. "try{sessionStorage.setItem('pvlc','1');}catch(e4){}"
  .. "location.href=d.url;return;}"
  .. "S.w.postMessage({pv:1,id:d.id,s:x.status,body:t},O);}};"
  .. "x.send();},false);}"
  -- A tab still working through a check has nothing to give: saying so
  -- keeps the player from asking, and keeps its half-earned cookie out of
  -- the player's hands -- measured on go-away, the state grows in stages
  -- and only the last one opens anything.
  -- `auto` says which of the two paths is live: put there by the add-on,
  -- or run from a click on the bookmark. The local page needs it to stop
  -- asking for a click that, on the browsers this fork exists for, can
  -- never work -- and to name the thing that did connect.
  .. "function h(){if(!S.w)return;var ok=ready();"
  .. "S.w.postMessage({pv:1,hello:1,busy:ok?0:1,auto:AUTO,"
  .. "cookie:ok?document.cookie:'',ua:navigator.userAgent},O);}"
  -- Run by the browser add-on rather than clicked, this page was never
  -- opened from PowerVLC's own, so there is no opener to find: the add-on
  -- hands the window over instead. Bare name on purpose -- the add-on
  -- sets it on the sandbox, which is not window.
  .. "var w=(typeof __pvlcw!=='undefined'&&__pvlcw)||window.opener;"
  -- Clicked, the bookmark IS the intent to hand this page over, so the
  -- player is stopped at once. Injected by the add-on, the script runs on
  -- every page of the instance, including ones the user is watching in
  -- the browser and never asked to send anywhere: pausing there would be
  -- the add-on breaking their browsing.
  .. "var AUTO=(typeof __pvlcauto!=='undefined'&&__pvlcauto)?1:0;"
  .. "var OURS=AUTO?0:1;"
  .. "try{if(AUTO&&sessionStorage.getItem('pvlc')==='1'){OURS=1;"
  .. "sessionStorage.removeItem('pvlc');}}catch(e5){}"
  -- ⛔ Injected, never open a window. The address baked into this script
  -- is the one the player had WHEN THE SCRIPT WAS FETCHED, and a player
  -- that has been restarted since is behind a new secret: opening it
  -- lands on a 404, and the retry below did it again four seconds later.
  -- Reported as "404 not found" with the browser opening pages nobody
  -- asked for. In add-on mode the player's window is the add-on's to
  -- know (__pvlcw): if it has none, there is nothing to relay to and
  -- this tab has no business opening anything. The bookmark path keeps
  -- the window, since a click IS the intent -- but it stops after one
  -- try instead of leaving a timer running against a dead address.
  .. "if((!w||w.closed)&&!AUTO){w=window.open('{{BASE}}','powervlc');}"
  .. "if(!w||w.closed){if(!AUTO)say('{{M_POPUP}}',1);return;}"
  .. "S.w=w;if(!S.t){S.t=setInterval(h,2000);}h();if(!AUTO)stop();"
  .. "if(!S.ack)note('{{M_WAIT}}');"
  -- the opener may be some other page entirely, in which case the messages
  -- go nowhere: no acknowledgement means open our own window and retry
  .. "setTimeout(function(){if(S.ack)return;"
  .. "if(!AUTO){var w2=window.open('{{BASE}}','powervlc');"
  .. "if(w2){S.w=w2;h();}}"
  .. "setTimeout(function(){if(S.ack)return;"
  .. "if(S.t){clearInterval(S.t);S.t=0;}S.gone=1;"
  .. "note('{{M_FAIL}}',1);},4000);},4000);"
  .. "})()"

-- Runs on our own page. Nothing here is subject to the instance's policy.
local RELAY_JS = [==[
(function(){
 var BASE='{{BASE}}', TARGET='__TARGET__', WANT='__WANT__';
 var tab=null, lastHello=0, lastCookie='', job=null, busy=false, live=null;
 var pending=null;
 var st=document.getElementById('st');
 function say(t){ if(st) st.innerHTML=t; }
 /* The bookmark half of the page is only of use until something is
    relaying. Hidden rather than rewritten so nothing has to be
    translated twice, and so the add-on note stays put when it is the
    add-on that connected. */
 var stepsDone=false;
 function hideSteps(auto){
   if(stepsDone) return; stepsDone=true;
   var ids=auto?['steps','addon']:['steps'];
   for(var i=0;i<ids.length;i++){
     var el=document.getElementById(ids[i]);
     if(el) el.style.display='none';
   }
 }
 function xhr(m,u,b,cb){
   var x=new XMLHttpRequest(); x.open(m,u,true);
   x.onreadystatechange=function(){ if(x.readyState==4&&cb) cb(x); };
   try{ x.send(b||null); }catch(err){ if(cb) cb(x); }
   return x;
 }
 window.addEventListener('message',function(e){
   if(e.origin!==TARGET) return;
   var d=e.data; if(!d||d.pv!==1) return;
   if(d.hello){
     tab=e.source; lastHello=new Date().getTime();
     var was=busy; busy=!!d.busy;
     /* the parked /next says "free" or "busy" for as long as it sits
        there: when the tab changes its mind, cut it short so the next
        one speaks the truth -- and so a job is not handed to a poll
        that predates the check the tab walked into */
     if(pending&&was!==busy){ try{pending.abort();}catch(e9){} }
     /* tell the page its messages are arriving: without this it has no
        way to know whether the opener it found is really us */
     /* tell it which video is wanted, so that a tab showing that very
        one can clear itself straight away rather than at handover.
        WANT was baked in when this page was built and names the first
        guarded video for ever -- a second one reuses this same page --
        so ask the player, and keep the baked value only as a starting
        point. The answer lands a tick late, which costs one hello. */
     try{ e.source.postMessage({pv:1,ack:1,want:(job&&job.url)||live||WANT},
                               TARGET); }catch(err){}
     xhr('GET',BASE+'/want',null,function(x){
       if(x.status==200&&x.responseText) live=x.responseText; });
     /* the state grows as checks are passed, so send it again every
        time it changes -- once only would freeze the first, useless one */
     if(d.cookie&&d.cookie!==lastCookie){ lastCookie=d.cookie;
       xhr('GET','{{RETURN}}?ua='+encodeURIComponent(d.ua||'')
           +'&c='+encodeURIComponent(d.cookie)
           +'&o='+encodeURIComponent(TARGET)); }
     /* The tab may have navigated since the job was handed out -- which
        is exactly what we ask it to do -- so a fresh hello means it is
        ready again and the job has to be put to it once more. Handing it
        out once left the player waiting for its whole timeout. */
     if(job&&!busy){ tab.postMessage({pv:1,id:job.id,url:job.url},TARGET); }
     /* Something is answering, so the instructions have done their job:
        take them away rather than leave the page asking for a click that
        already happened -- or, with the add-on, for one that must never
        happen and would do nothing if it did. */
     hideSteps(!!d.auto);
     say(busy?'__BUSY__':(d.auto?'__ONADDON__':'__ON__')); return;
   }
   if(d.id!==undefined){ job=null; post(d.id,d.s,d.body||''); }
 },false);
 /* The player's HTTP server turns down a body of 64 kB or more, and a
    results page is bigger than that, so send it in slices. 16000 UTF-16
    units are at most 48 kB once encoded -- and never cut a surrogate
    pair, which would corrupt the character sitting on the seam. */
 function post(id,s,body){
   var CH=16000,i=0,n=body.length;
   function step(){
     var end=i+CH;
     if(end<n){ var c=body.charCodeAt(end-1);
                if(c>=0xD800&&c<=0xDBFF) end--; }
     else end=n;
     var last=(end>=n)?1:0;
     xhr('POST',BASE+'/reply?id='+id+'&s='+s+'&last='+last,
         body.substring(i,end),
         function(){ i=end; if(!last) step(); });
   }
   if(n===0){ xhr('POST',BASE+'/reply?id='+id+'&s='+s+'&last=1',''); return; }
   step();
 }
 /* A tab still working through a check is not a relay: it has nothing to
    answer with, and asking it anyway is what had the player fed one
    interstitial after another. Stopping the polling is the whole of it --
    the player sees no relay at all and simply waits, which is what it
    already does well. */
 function loop(){
   var quiet = tab ? (new Date().getTime()-lastHello) : 1e9;
   if(!tab||busy||quiet>6000){
     /* Not free to take work -- but if a tab is there and was heard from
        recently enough, it is working, not gone. Keep knocking so the
        player can tell the two apart: a challenge chain silences the tab
        for the seconds it takes to walk it (7 to 9 measured on the G3),
        and its script dies with each document on the way. Without this
        the player declared "relay gone" on a browser that was busy
        earning the very session it had been asked for. Busy knocks are
        answered at once, so the beat stays at one a second. */
     if(tab&&quiet<=25000){ xhr('GET',BASE+'/next?busy=1'); }
     say(busy?'__BUSY__':'__OFF__'); setTimeout(loop,1000); return;
   }
   /* The player holds this open until it has work or ~10 s pass (long
      poll): an answer is news, not a beat to keep. Asking used to cost
      2.5 requests a second for nothing, which the core's byte-by-byte
      header reads turned into ~1300 system calls a second. */
   pending=xhr('GET',BASE+'/next',null,function(x){
     pending=null;
     var t=x.responseText||'';
     if(t){ var i=t.indexOf(' ');
            job={id:t.substring(0,i),url:t.substring(i+1)};
            /* gone busy while the answer was in flight: hold the job,
               the hello handler puts it to the tab once it is free */
            if(!busy&&tab){ try{ tab.postMessage({pv:1,id:job.id,url:job.url},TARGET); }catch(e8){} } }
     setTimeout(loop,t?150:250);
   });
 }
 loop();
})();
]==]

local WEB_CSS = [==[
<style>
body{font:15px/1.5 -apple-system,'Lucida Grande',Verdana,sans-serif;
margin:0;padding:2em 1em;background:#f4f4f6;color:#1d1d1f}
main{max-width:40em;margin:0 auto;background:#fff;border-radius:10px;
padding:1.5em 2em;box-shadow:0 1px 6px rgba(0,0,0,0.15)}
h1{font-size:1.25em;margin:0 0 .6em;color:#c1272d}
h2{font-size:1.05em;margin:0 0 .4em}
ol{padding-left:1.2em}li{margin:1em 0}
a.bm{display:inline-block;padding:.4em .9em;background:#c1272d;color:#fff;
text-decoration:none;border-radius:6px;font-weight:bold}
a.inst{word-break:break-all}
#st{margin-top:1.2em;padding:.6em .8em;border-radius:6px;background:#eee;
font-size:.92em}
input[type=text]{width:100%;padding:.4em;font-size:1em}
.note{color:#6e6e73;font-size:.9em}
code{background:#f0f0f2;padding:0 .3em;border-radius:3px}
</style>
]==]

local function web_page(title, body, head)
  return '<!DOCTYPE html><html><head><meta charset="utf-8"><title>'
      .. html_escape(title) .. "</title>" .. (head or "") .. WEB_CSS
      .. '</head><body><main><h1>' .. html_escape(title) .. "</h1>"
      .. body .. "</main></body></html>"
end

local function challenge_pages(instance)
  local origin = string.match(instance, "^(https?://[^/]+)") or instance
  -- Send the browser to the page that was actually refused, not to the
  -- instance in general. Same-origin only, so a manifest fetched from
  -- somewhere else could never redirect this.
  local target = instance
  if app.challenge_url and on_instance(app.challenge_url, origin) then
    target = app.challenge_url
  end
  local bm = BOOKMARKLET
  for token, text in pairs({
        M_DRAG = lang.web_m_drag, M_OK = lang.web_m_ok,
        M_POPUP = lang.web_m_popup, M_WAIT = lang.web_m_wait,
        M_FAIL = lang.web_m_fail, M_PAGE = lang.web_m_page,
        M_NAV = lang.web_m_nav, M_TAKEN = lang.web_m_taken,
        M_TAKING = lang.web_m_taking }) do
    bm = js_put(bm, "{{" .. token .. "}}", text)
  end

  bm = string.gsub(bm, "{{CHALLENGE_RE}}",
                   function() return js_regex(CHALLENGE_MARKERS) end)
  bm = string.gsub(bm, "{{INVIDIOUS_RE}}",
                   function() return js_regex(INVIDIOUS_MARKS) end)

  -- The same script the bookmark carries, for the browser add-on to put
  -- on the page itself where a bookmark is refused. One script, one
  -- protocol: the add-on holds no copy of either.
  local inject = string.sub(bm, #"javascript:" + 1)

  -- What the add-on needs and nothing else: where to talk to us, and the
  -- single site it may run the relay on.
  local head = '<meta name="powervlc-handoff" content="{{BASE}}">'
            .. '<meta name="powervlc-origin" content="'
            .. attr_escape(origin) .. '">'

  local js = js_put(RELAY_JS, "__TARGET__", origin)
  js = js_put(js, "__WANT__", target)
  js = js_put(js, "__ON__", lang.web_relay_on)
  js = js_put(js, "__ONADDON__", lang.web_relay_on_addon)
  js = js_put(js, "__OFF__", lang.web_relay_off)
  js = js_put(js, "__BUSY__", lang.web_relay_busy)

  -- The add-on comes FIRST, and the bookmark is what is left for the
  -- browsers that do not need it. It used to be the other way round: the
  -- page opened by telling you to drag a bookmark and to click it once
  -- the check was passed, then explained six lines further down that on
  -- TenFourFox and PowerFox that bookmark can do nothing at all. Someone
  -- who had installed the add-on -- the only path that works there --
  -- was left following instructions for the path that does not, with
  -- nothing on the page ever saying the add-on was in fact connected.
  local landing = web_page(lang.web_title,
    "<p>" .. lang.web_intro .. "</p>"
    .. '<div id="addon"><h2>' .. lang.web_addon_title .. "</h2>"
    .. "<p>" .. lang.web_addon .. "</p>"
    .. "<p><strong>" .. lang.web_addon_lead .. "</strong></p></div>"
    -- rel="opener" on purpose: target="_blank" has implied noopener since
    -- 2021, and the opener is the whole point -- it is what lets the tab
    -- reach this page without any Content-Security-Policy in the way. The
    -- bookmarklet opens a window of its own where that is refused anyway.
    -- Outside the steps: both paths start by opening the instance.
    .. "<hr><p>" .. lang.web_step2 .. "<br><a class=\"inst\" "
       .. "target=\"_blank\" rel=\"opener\" href=\""
       .. attr_escape(target) .. "\">" .. html_escape(target) .. "</a></p>"
    .. '<div id="steps"><hr><h2>' .. lang.web_steps_title .. "</h2><ol>"
    .. "<li>" .. lang.web_step1 .. "<br><a class=\"bm\" href=\""
       .. attr_escape(bm) .. "\">" .. lang.web_bookmark
       .. "</a></li>"
    .. "<li>" .. lang.web_step3 .. "</li></ol></div>"
    .. '<div id="st">' .. lang.web_relay_off .. "</div>"
    .. "<hr><p class=\"note\">" .. lang.web_note .. "</p>"
    .. "<script>" .. js .. "</script>", head)

  local thanks = web_page(lang.web_done_title, "<p>" .. lang.web_done
    .. "</p>")
  local empty = web_page(lang.web_done_title, "<p>" .. lang.web_empty
    .. "</p>")
  return landing, thanks, empty, inject
end

-- Armed while the challenge view is up, so that the browser finishing its
-- part is enough: an extension hears nothing on its own, and vlc.timer is
-- this fork's way of letting one look again without the user asking.
--
-- Declared HERE, above every function that reads it: a local declared
-- further down is simply not in scope above, and the name silently reads
-- as a nil global instead -- which made vlc.timer() raise and the view
-- come up with no poll armed at all.
local CHALLENGE_POLL_MS = 1200

-- One pending timer callback exists per extension -- vlc.timer() replaces
-- whatever was armed before it -- so the two jobs that need waking up
-- share a single tick, and each arming has to ask for the shorter of the
-- two deadlines. Two names would silently disarm each other: opening a
-- guarded video while a download runs would arm the poll over it, and the
-- download would stop dead with no error anywhere.
local function arm_tick()
  if not vlc.timer then
    return
  end
  if dl.active then
    vlc.timer(DL_TICK_MS, "invidious_tick")
  elseif app.awaiting_challenge then
    vlc.timer(CHALLENGE_POLL_MS, "invidious_tick")
  end
end

-- Opens the local page and remembers what to resume once the browser has
-- done its part.
function start_challenge(instance, retry_fn)
  if not (vlc.browser and vlc.browser.handoff) then
    set_message(lang.msg_search_blocked)
    return
  end
  -- A handover that already succeeded and still leaves us refused will
  -- not do better on a second run: some guards only ever accept a genuine
  -- top-level navigation, which nothing here can be. Say so instead of
  -- opening window after window.
  -- The address and the bookmark have not changed: put the same handover
  -- back up rather than mint another one behind a new secret.
  if app.handoff and app.challenge_instance == instance then
    app.retry = retry_fn
    -- The page in the browser was built for the FIRST guarded video and
    -- is not rebuilt here on purpose, so it still names that one. Tell
    -- the handover what is wanted now: it is the only thing the page can
    -- ask, and without it a second video is never recognised as ours --
    -- the tab is left to load a player nobody is going to watch.
    if app.handoff.want then
      pcall(app.handoff.want, app.handoff, app.challenge_url or instance)
    end
    if app.stale_session then
      app.refused[instance] = (app.refused[instance] or 0) + 1
    end
    show_challenge()
    -- Twice with a session in hand and still refused is no longer a
    -- half-finished check: measured on go-away, some instances only ever
    -- grant a token tied to one navigation, and hand out nothing a second
    -- client could replay. Saying so is more use than asking again.
    if app.navigating then
      app.navigating = false
      set_message(lang.msg_challenge_click)
    elseif (app.refused[instance] or 0) >= 2 then
      set_message(lang.msg_challenge_no_session)
    else
      set_message(app.stale_session and lang.msg_challenge_incomplete
                                     or lang.msg_challenge_needed)
    end
    app.stale_session = false
    return
  end
  if app.handoff then
    app.handoff:close()
    app.handoff = nil
  end
  local landing, thanks, empty, inject = challenge_pages(instance)
  local handle, err = vlc.browser.handoff({ landing = landing,
                                            thanks = thanks, empty = empty,
                                            inject = inject })
  if not handle then
    set_message(lang.msg_challenge_fail .. tostring(err))
    return
  end
  app.handoff = handle
  if handle.want then
    pcall(handle.want, handle, app.challenge_url or instance)
  end
  app.challenge_instance = instance
  app.tried_cookie, app.tried_relay, app.tried_seq = nil, false, nil
  app.retry = retry_fn
  show_challenge()
end

function show_challenge()
  close_dlg()
  dlg = vlc.dialog(lang.title_challenge)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(lang.lbl_challenge_1, 1, 1, 4, 1)
  dlg:add_label(lang.lbl_challenge_2, 1, 2, 4, 1)
  -- A label, not a text input: on both macOS providers a label is
  -- selectable but not editable, which is exactly what this address is
  -- for -- reading and copying. As an input it could be typed over or
  -- emptied by accident, and the two buttons beside it read it back, so
  -- a stray keystroke handed the browser a mangled address.
  ui.local_url = dlg:add_label(
    app.handoff and app.handoff:url() or "", 1, 3, 2, 1)
  dlg:add_button(lang.btn_challenge_copy, click_challenge_copy, 3, 3, 1, 1)
  dlg:add_button(lang.btn_challenge_open, click_challenge_open, 4, 3, 1, 1)
  dlg:add_label(lang.lbl_challenge_3, 1, 4, 4, 1)
  dlg:add_button(lang.btn_challenge_done, click_challenge_done, 1, 5, 1, 1)
  dlg:add_button(lang.btn_challenge_cancel, show_connect, 2, 5, 1, 1)
  ui.message = dlg:add_label(lang.msg_challenge_needed, 1, 6, 4, 1)
  dlg:show()
  app.awaiting_challenge = true
  arm_tick()
end

function click_challenge_copy()
  -- Straight from the handover rather than read back off the dialog:
  -- what is shown is a copy, and only the player knows the real address.
  local url = app.handoff and app.handoff:url()
  if not url or url == "" then
    return
  end
  if copy_to_clipboard(url) then
    set_message(lang.msg_challenge_copied)
  else
    set_message(lang.msg_copy_fallback)
  end
end

function click_challenge_open()
  local url = app.handoff and app.handoff:url()
  if not url or url == "" then
    return
  end
  if open_in_browser(url) then
    set_message(lang.msg_challenge_opened)
  else
    set_message(lang.msg_challenge_no_browser)
  end
end

-- The poll half of the shared tick: the browser has nothing to announce
-- itself with, so the answer is looked for again and again while the
-- challenge view is up. challenge_resume() takes the view down itself
-- once something arrives, and app.awaiting_challenge going false is what
-- stops the next arming.
local function challenge_poll()
  if app.awaiting_challenge then
    challenge_resume(true)
  end
end

-- The button does the same thing, for a core without vlc.timer -- and for
-- whoever would rather press something than wait.
function click_challenge_done()
  if not challenge_resume(false) then
    set_message(lang.msg_challenge_waiting)
  end
end

-- Returns true once the browser has handed something over.
function challenge_resume(quiet)
  if not app.handoff then
    if not quiet then
      show_connect()
    end
    return true
  end
  local answer = app.handoff:poll()
  local relaying = app.handoff:relay()
  -- Every click on the bookmark counts, even when it repeats the same
  -- cookie: on an instance that only serves one page at a time, the news
  -- is the page behind it, not the cookie. Going by the cookie alone left
  -- the second video answering "nothing received yet" for ever.
  local fresh = answer and answer.seq and answer.seq ~= app.tried_seq

  -- The timer must not spin -- the browser says hello every two seconds,
  -- so "a relay is there" stays true for ever -- but the button is the
  -- user asking in so many words, and answering "nothing received yet"
  -- when a relay is sitting right there was simply wrong.
  -- A relay that went away and came back is a new chance; one that has
  -- been sitting there all along is not. The tab stops asking for work
  -- while it is on a check, so this is exactly "it is ready again" --
  -- without it, one attempt made while the tab was busy would be the
  -- only one the poll ever made.
  if not relaying then
    app.tried_relay = false
  end
  local may_relay = relaying and (not app.tried_relay or not quiet)
  if not fresh and not may_relay then
    return false
  end
  if relaying then
    app.tried_relay = true
  end

  if fresh then
    app.tried_seq = answer.seq
    app.tried_cookie = answer.cookie
    local instance = app.challenge_instance
    app.sessions[instance] = { cookie = answer.cookie,
                               user_agent = answer.user_agent or "",
                               accept_language = answer.accept_language or "",
                               accept_encoding = answer.accept_encoding or "" }
    -- playback is fetched by the player, not by this script: the shared
    -- jar is the only way a stream relayed by the instance gets the session
    store_cookies(instance, answer.cookie)
  end

  -- The relay is kept alive on purpose: an HttpOnly instance has nothing
  -- else, and closing the handover would strand it.
  local retry = app.retry
  app.retry = nil
  app.awaiting_challenge = false
  set_message(lang.msg_challenge_ok)
  if retry then
    retry()
  else
    show_connect()
  end
  return true
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
  ui.mode:add_value(lang.mode_playlists, 3)
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
  elseif kind == "playlist" then
    ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                        .. "\t" .. lang.col_videos)
  else
    ui.results:set_text(lang.col_title .. "\t" .. lang.col_channel
                        .. "\t" .. lang.col_date)
  end
  local items = {}
  for _, item in ipairs(list) do
    -- A playlist keeps its deleted and private entries: YouTube still
    -- lists them, and Invidious renders them as cards with an empty title
    -- and no channel. They cannot be played, so offering a blank line
    -- that does nothing is worse than leaving them out.
    local usable = kind == "channel" or kind == "playlist"
                   or (item.videoId and trim(item.title or "") ~= "")
    if usable then
      table.insert(items, item)
    end
  end
  -- Sort here, unless the source already came back in a true chronological
  -- order finer than its own rounded dates (a channel page).
  local approx = (#items > 0) and items[1].approx
  -- "the source is already in the right order" stands on its own: a
  -- playlist from the API carries no published date at all, so sorting on
  -- it would shuffle the episodes into an arbitrary order.
  local ordered = (type(list) == "table") and list.ordered
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
    elseif kind == "playlist" then
      app.results[i] = { kind = "playlist", id = item.playlistId,
                         title = item.title or "?",
                         author = item.author or "?" }
      -- "9 videos" from the page, a bare number from the API: sort on the
      -- digits either way
      local n = item.videoCount and tostring(item.videoCount) or ""
      line = cell(item.title) .. "\t" .. cell(item.author) .. "\t"
          .. sortable(n, tonumber((string.gsub(n, "[^%d]", ""))))
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
  -- An address pasted in the box is an intent, not a search: go straight
  -- to what it names rather than looking for its text.
  local target, target_id = detect_target(query)
  if target then
    app.last_query, app.last_mode = query, ui.mode:get_value()
    set_message(lang.msg_target_found)
    if target == "video" then
      open_video({ kind = "video", id = target_id, title = query })
    else
      open_result({ kind = target, id = target_id, title = query })
    end
    return
  end

  set_message(lang.msg_searching)
  local mode = ui.mode:get_value()
  local kind = (mode == 2) and "channel"
            or (mode == 3) and "playlist" or "video"
  local obj, err
  -- a new search replaces whatever channel the list was showing
  app.last_query, app.last_mode, app.view_channel = query, mode, nil

  if app.mode == "html" then
    obj, err = html_search(app.instance, query, kind)
  elseif kind == "channel" then
    obj, err = get_json(app.instance .. "/api/v1/search?q="
       .. vlc.strings.encode_uri_component(query)
       .. "&type=channel&fields=type,author,authorId,subCount"
       .. search_params())
  elseif kind == "playlist" then
    obj, err = get_json(app.instance .. "/api/v1/search?q="
       .. vlc.strings.encode_uri_component(query)
       .. "&type=playlist&fields=type,title,playlistId,author,videoCount"
       .. search_params())
  else
    obj, err = get_json(app.instance .. "/api/v1/search?q="
       .. vlc.strings.encode_uri_component(query)
       .. "&type=video&sort_by=upload_date&fields=" .. SEARCH_FIELDS
       .. search_params())
  end

  if not obj then
    if err == "challenge" then
      start_challenge(app.instance,
                      function() show_search(); click_search() end)
      return
    end
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
  open_result(result)
end

-- Taken apart from the click so that it can be replayed after a check:
-- rebuilding the list loses the selection the click read.
function open_result(result)
  if result.kind == "playlist" then
    set_message(lang.msg_playlist_loading)
    local obj, err
    if app.mode == "html" then
      obj, err = html_playlist_videos(app.instance, result.id)
    else
      obj, err = get_json(app.instance .. "/api/v1/playlists/" .. result.id
                          .. "?fields=title,videos" .. content_params())
    end
    if not obj then
      if err == "challenge" then
        start_challenge(app.instance,
                        function() show_search(); open_result(result) end)
        return
      end
      set_message(lang.msg_search_fail .. tostring(err))
      return
    end
    -- the API wraps them, the page does not
    app.view_channel = obj.title or result.title
    local list = obj.videos or obj
    if type(list) == "table" then
      list.ordered = true
    end
    fill_results(list, "video")
    return
  end
  if result.kind == "channel" then
    set_message(lang.msg_channel_loading)
    local obj, err
    if app.mode == "html" then
      obj, err = html_channel_videos(app.instance, result.id)
    else
      obj, err = get_json(app.instance .. "/api/v1/channels/" .. result.id
                          .. "/videos?fields=videos," .. SEARCH_FIELDS
                          .. content_params())
    end
    if not obj then
      if err == "challenge" then
        start_challenge(app.instance,
                        function() show_search(); open_result(result) end)
        return
      end
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
  -- The type is spelt out rather than read back off the address: these
  -- go through the instance's own /latest_version, which says nothing
  -- about what it is about to serve. It is the itag that decides, and
  -- these three are fixed by YouTube.
  local candidates = {
    { itag = "22", label = "720p — mp4 (" .. lang.combined .. ")",
      mime = "video/mp4" },
    { itag = "18", label = "360p — mp4 (" .. lang.combined .. ")",
      mime = "video/mp4" },
    { itag = "140", label = lang.audio_only .. " — 128 kb/s (m4a)",
      mime = "audio/mp4", sound_only = true },
  }
  local formats = {}
  for _, c in ipairs(candidates) do
    still_alive()
    local url = app.instance .. "/latest_version?id=" .. result.id
             .. "&itag=" .. c.itag
    if app.proxy then
      -- Direct first: without local=true the instance answers with a
      -- redirect straight to googlevideo, which vlc.stream follows -- so
      -- this probe tests the direct stream, and playing this URL later
      -- streams from googlevideo (byte-stable), not through the relay.
      -- The relay stays as the fallback when googlevideo refuses us
      -- (IP-bound URL): see dash_formats for the whole rationale.
      if probe_stream(url) then
        table.insert(formats, { label = c.label, url = url,
                              mime = c.mime,
                              sound_only = c.sound_only })
      else
        url = url .. "&local=true"
        if probe_stream(url) then
          table.insert(formats, { label = c.label, url = url,
                                  mime = c.mime,
                                  sound_only = c.sound_only })
        end
      end
    elseif probe_stream(url) then
      table.insert(formats, { label = c.label, url = url,
                              mime = c.mime,
                              sound_only = c.sound_only })
    end
  end
  return formats
end

-- A DASH manifest holds one adaptation set per codec, and VLC surfaces
-- those as unnamed "Track 2 / Track 3" with no way to pick a resolution.
-- Reading the manifest ourselves turns them into real quality entries:
-- one video stream per height, with its audio attached as a slave input.
local CODEC_RANK = { avc = 1, vp0 = 2, vp9 = 2, av0 = 3 }

-- The same request minus the "local=true" rewriting: the URLs inside the
-- answer then point straight at googlevideo instead of being relayed.
local function without_local(url)
  url = string.gsub(url, "([?&])local=true&", "%1")
  url = string.gsub(url, "[?&]local=true$", "")
  return url
end

-- DASH writes frameRate either as a plain number or as "num/den"
-- (30000/1001). Returns nil when absent or unreadable: an unknown rate must
-- never be held against a stream.
local function parse_frame_rate(s)
  if not s then return nil end
  local num, den = string.match(s, "^(%d+)/(%d+)$")
  if num then
    num, den = tonumber(num), tonumber(den)
    if num and den and den > 0 then return num / den end
    return nil
  end
  return tonumber(s)
end

-- Above this, a stream is "high frame rate": 30000/1001 and 30 stay under,
-- 50 and 60 do not. Those are exactly the ones that push 1080p past H.264
-- level 4.1 -- out of reach of the Crystal HD, and out of reach of software
-- decoding on every machine this fork exists for.
local FPS_PLAIN_MAX = 30.5

local function fps_penalty(fps)
  if not fps then return 0 end   -- unknown: judged as before, on codec alone
  return fps > FPS_PLAIN_MAX and 1 or 0
end

local function parse_dash_manifest(body, origin)
  local function absolute(url)
    url = (string.gsub(url, "&amp;", "&"))
    if not string.match(url, "^https?://") then
      url = origin .. url
    end
    return url
  end

  local audio, audio_rate = nil, -1
  local audio_mime = nil
  local videos = {}

  for set in string.gmatch(body, "<AdaptationSet.-</AdaptationSet>") do
    local is_audio = string.find(set, 'contentType="audio"', 1, true)
                  or string.find(set, 'mimeType="audio', 1, true)
    -- DASH allows mimeType on either element, and Invidious writes it on
    -- the set. Only the download reads it, to give the file a name that
    -- matches what is inside it.
    local set_mime = string.match(set, 'mimeType="([%w%-]+/[%w%-%.]+)"')
    for rep in string.gmatch(set, "<Representation.-</Representation>") do
      local url = string.match(rep, "<BaseURL>(.-)</BaseURL>")
      local rate = tonumber(string.match(rep, 'bandwidth="(%d+)"') or "") or 0
      local mime = string.match(rep, 'mimeType="([%w%-]+/[%w%-%.]+)"')
                or set_mime
      if url then
        if is_audio then
          if rate > audio_rate then
            audio, audio_rate, audio_mime = absolute(url), rate, mime
          end
        else
          local height = tonumber(string.match(rep, 'height="(%d+)"') or "")
          if height then
            table.insert(videos, {
              height = height,
              codec = string.match(rep, 'codecs="([^".]*)') or "?",
              -- DASH allows frameRate on either element; the Representation
              -- wins when both carry it.
              fps = parse_frame_rate(string.match(rep, 'frameRate="([%d/]+)"')
                                  or string.match(set, 'frameRate="([%d/]+)"')),
              mime = mime,
              url = absolute(url),
            })
          end
        end
      end
    end
  end

  return audio, videos, audio_mime
end

local function dash_formats(manifest_url)
  local body = get_body(manifest_url)
  if not body then
    return nil
  end
  local origin = string.match(manifest_url, "^(https?://[^/]+)") or ""

  local audio, videos, audio_mime = parse_dash_manifest(body, origin)

  if not audio or #videos == 0 then
    return nil
  end

  -- Prefer the direct googlevideo URLs over the relayed ones whenever they
  -- actually answer, and keep the relay as the fallback rather than the
  -- default. The relay is not byte-stable: the instance regenerates the
  -- stream, and two connections for the same URL can receive different
  -- bytes -- measured 08/08/2026, it fed the demuxer an index disagreeing
  -- with the data and froze the picture mid-play and on seek. googlevideo
  -- serves one immutable file. Direct URLs are usually bound to the IP of
  -- whoever obtained them (the instance), so this only works when the
  -- binding is loose or absent -- which is exactly what the probe tests.
  --
  -- Whether the instance grants direct URLs at all does not change from
  -- one video to the next: remember the first answer and spare the slow
  -- machines the extra manifest fetch afterwards.
  if app.direct_streams == nil then app.direct_streams = {} end
  if string.find(manifest_url, "local=true", 1, true) and
     app.direct_streams[origin] ~= false then
    -- Opportunistic by nature, so it runs under pcall: whatever goes wrong
    -- in here (this very block once died on a Lua multiple-return trap and
    -- took the whole "open video" flow down with it), the relayed URLs
    -- above remain a complete, playable answer.
    local ok, err = pcall(function()
      local direct_body = get_body(without_local(manifest_url))
      if not direct_body then
        vlc.msg.dbg("[Invidious] direct manifest unavailable, "
                    .. "keeping the instance relay")
        return
      end
      -- NOT inlined into `direct_body and parse_...`: an and/or expression
      -- truncates multiple return values to the first one.
      local direct_audio, direct_videos, direct_audio_mime =
          parse_dash_manifest(direct_body, origin)
      -- "Direct" only counts when the URLs actually leave the instance:
      -- companion-based instances rewrite the BaseURLs to their own
      -- /companion/videoplayback whether or not local=true was asked, and
      -- swapping the relay for itself would claim a win that is not there.
      if direct_audio and
         string.match(direct_audio, "^(https?://[^/]+)") == origin then
        vlc.msg.dbg("[Invidious] instance rewrites stream URLs regardless "
                    .. "of local=true, no direct googlevideo available")
        app.direct_streams[origin] = false
        return
      end
      if not direct_audio or #direct_videos == 0 or
         not probe_stream(direct_audio) then
        vlc.msg.dbg("[Invidious] direct googlevideo unreachable, "
                    .. "keeping the instance relay")
        return
      end
      local function itag_of(url)
        return string.match(url or "", "[?&]itag=(%d+)")
      end
      local by_itag = {}
      for _, v in ipairs(direct_videos) do
        local itag = itag_of(v.url)
        if itag then
          by_itag[itag] = v.url
        end
      end
      local replaced = 0
      for _, v in ipairs(videos) do
        local direct = by_itag[itag_of(v.url)]
        if direct then
          v.url = direct
          replaced = replaced + 1
        end
      end
      if replaced > 0 then
        audio = direct_audio
        audio_mime = direct_audio_mime or audio_mime
        vlc.msg.info("[Invidious] streams: direct googlevideo ("
                     .. replaced .. "/" .. #videos
                     .. " qualities), instance relay kept as fallback")
      end
    end)
    if not ok then
      vlc.msg.warn("[Invidious] direct-stream lookup failed ("
                   .. tostring(err) .. "), keeping the instance relay")
    end
  end

  -- One entry per resolution AND cadence, keeping within each the most
  -- widely decodable codec (AV1 is out of reach of the machines this fork
  -- exists for).
  --
  -- The cadence used to be ignored, so a 60 fps upload -- which YouTube
  -- publishes at both cadences -- collapsed to whichever the manifest
  -- happened to list first, at random. That matters here: 1080p60 is H.264
  -- level 4.2, past the Crystal HD's 4.1 ceiling, and the card takes such a
  -- stream, decodes under a second of it and then stops dead (measured:
  -- 56 pictures). 1080p30 of the same video decodes in hardware.
  --
  -- Both are offered rather than the low one imposed: 60 fps is worth having
  -- on a machine that can carry it, and that is the viewer's call, not ours.
  -- The label says which is which.
  local best = {}
  for _, v in ipairs(videos) do
    local rank = CODEC_RANK[string.sub(v.codec, 1, 3)] or 9
    local key  = v.height .. "/" .. fps_penalty(v.fps)
    if not best[key] or rank < best[key].rank then
      best[key] = { rank = rank, video = v }
    end
  end

  local formats = {}
  for _, entry in pairs(best) do
    table.insert(formats, {
      height = entry.video.height,
      hifps  = fps_penalty(entry.video.fps),
      -- "1080p — avc1 — 60 fps": spelt out rather than folded into the
      -- resolution the way YouTube writes it ("1080p60"), because this is
      -- what the choice actually turns on. Two entries differing only by
      -- their cadence sit next to each other in the menu, and the one the
      -- hardware cannot take is readable as such instead of having to be
      -- deduced. Rounded to the nearest whole frame: 30000/1001 is "30 fps"
      -- to a viewer, and 23.976 is "24". Omitted when the manifest does not
      -- say, which is the one case where nothing can be claimed.
      label = entry.video.height .. "p — " .. entry.video.codec
              .. (entry.video.fps
                    and (" — " .. math.floor(entry.video.fps + 0.5) .. " fps")
                    or ""),
      url = entry.video.url,
      mime = entry.video.mime,
      -- the video stream carries no sound of its own
      options = { ":input-slave=" .. audio },
      -- ... which is why the download has to be told about it by name:
      -- it writes files, and a file of this URL alone would be silent.
      audio = audio,
      audio_mime = audio_mime,
      -- pasting a video-only URL would be useless: hand out the manifest
      copy = manifest_url,
    })
  end
  -- Tallest first, and at equal height the plain cadence before the high one.
  -- The tie-break is not cosmetic: table.sort is not stable, so without it
  -- 1080p and 1080p60 would swap places from one call to the next.
  table.sort(formats, function(a, b)
    if a.height ~= b.height then return a.height > b.height end
    return a.hifps < b.hifps
  end)
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
    local label, manifest
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
      -- a description of where the streams are, not a stream
      manifest = true
    else
      label = (src.label or "?") .. " — "
           .. (src.mime and string.match(src.mime, "/([%w-]+)") or "?")
           .. " (" .. lang.combined .. ")"
    end
    table.insert(formats, { label = label, url = src.url,
                            mime = not manifest and src.mime or nil,
                            playlist = manifest })
  end
  if #formats == 0 then
    return false, "no source"
  end

  app.video = { id = result.id,
                title = info.title or result.title,
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
    if err == "challenge" then
      start_challenge(app.instance,
                      function() show_search(); open_video(result) end)
      return
    end
    set_message(lang.msg_video_fail .. tostring(err))
    return
  end

  local url = app.instance .. "/api/v1/videos/" .. result.id
           .. "?fields=title,author,published,publishedText,"
           .. "formatStreams,adaptiveFormats,hlsUrl,liveNow"
           .. content_params()
  if app.proxy then
    url = url .. "&local=true"
  end
  local obj, err = get_json(url)
  if not obj then
    if err == "challenge" then
      start_challenge(app.instance,
                      function() show_search(); open_video(result) end)
      return
    end
    local formats = fallback_formats(result)
    if #formats == 0 then
      set_message(lang.msg_video_fail .. err)
      return
    end
    app.video = { id = result.id, title = result.title,
                  author = result.author or "?",
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
        mime = fs.type,
        rank = quality_rank(quality)
      })
    end
  end
  table.sort(combined, function(a, b) return a.rank > b.rank end)
  for _, f in ipairs(combined) do
    table.insert(formats, f)
  end
  if obj.hlsUrl and obj.hlsUrl ~= "" then
    -- a playlist of segments, not a file: playable, not downloadable
    table.insert(formats, { label = lang.live_hls, url = obj.hlsUrl,
                            playlist = true })
  end
  for _, af in ipairs(obj.adaptiveFormats or {}) do
    if af.url and string.match(af.type or "", "^audio/") then
      local rate = tonumber(af.bitrate)
      local container = string.match(af.type or "", "/([%w-]+)") or "?"
      table.insert(formats, {
        label = lang.audio_only
             .. (rate and (" — " .. math.floor(rate / 1000) .. " kb/s") or "")
             .. " (" .. container .. ")",
        url = af.url,
        mime = af.type,
        sound_only = true
      })
    end
  end

  app.video = { id = result.id,
                title = obj.title or result.title,
                author = obj.author or result.author or "?",
                published = obj.published or result.published,
                publishedText = obj.publishedText }
  app.formats = formats
  show_video()
end

-- The picture that goes with the video, fetched from the instance and
-- from nowhere else. i.ytimg.com would answer this in one line and never
-- fail -- and would tell Google what is being watched from this machine
-- even when the streams themselves were routed through the instance on
-- purpose. No picture is the better failure.
--
-- It is written next to the other user data because the image widget
-- takes a file rather than bytes. One video at a time: the previous
-- picture goes as soon as another video is opened.
local function fetch_thumbnail(id)
  local dir = vlc.config.userdatadir()
  if not id or not dir or dir == "" then
    return nil
  end

  local function usable(path)
    local f = io.open(path, "rb")
    if not f then
      return false
    end
    local size = f:seek("end")
    f:close()
    return size ~= nil and size > 128
  end
  -- The size is part of the name, and there are two names because there
  -- are two answers the scaler can give: what is on disk is then never
  -- guessed at, and a file kept from a version that asked for other
  -- bounds is not taken for this one.
  local base = dir .. "/invidious-thumb-" .. id .. "-"
  local scaled_path = base .. THUMB_W .. "x" .. THUMB_H .. ".jpg"
  local raw_path = base .. THUMB_RAW_W .. "x" .. THUMB_RAW_H .. ".jpg"

  -- One video at a time. Whatever was kept for the previous one goes
  -- here, at the top, rather than on the way out: this is reached only
  -- when the video has changed, and doing it beside each answer left the
  -- old picture behind on every path that gives none.
  if app.thumb then
    os.remove(app.thumb.path)
    app.thumb = nil
  end

  -- already fetched for this video: opening it again costs nothing
  if usable(scaled_path) then
    return { path = scaled_path, w = THUMB_W, h = THUMB_H }
  end
  if usable(raw_path) then
    return { path = raw_path, w = THUMB_RAW_W, h = THUMB_RAW_H }
  end

  set_message(lang.msg_loading_thumb)
  local body = get_body(app.instance .. "/vi/" .. id .. "/" .. THUMB_SOURCE)
  if not body or #body < 128 then
    return nil
  end
  local f = io.open(raw_path, "wb")
  if not f then
    return nil
  end
  f:write(body)
  f:close()

  -- 320 wide is nearly half the dialog, and an instance is free to answer
  -- with something else entirely -- a proxy that converted to WebP, which
  -- the older machines cannot display at all. The core decodes whatever
  -- came and writes a JPEG of the size the layout is told about. Without
  -- it, the file stays as it arrived and is declared at its own size.
  if vlc.misc and vlc.misc.image_scale then
    local ok, w, h = pcall(vlc.misc.image_scale, raw_path, scaled_path,
                           THUMB_W, THUMB_H)
    if ok and w and h and usable(scaled_path) then
      os.remove(raw_path)
      return { path = scaled_path, w = w, h = h }
    end
    os.remove(scaled_path)
  end
  return { path = raw_path, w = THUMB_RAW_W, h = THUMB_RAW_H }
end

function show_video()
  -- Fetched before the view it belongs to is built, so that the "getting
  -- the thumbnail" line lands on a dialog that is still up -- and once
  -- per video, so that coming back to a video already seen costs nothing.
  if app.video.id and app.thumb_for ~= app.video.id then
    app.thumb_for = app.video.id
    app.thumb = fetch_thumbnail(app.video.id)
  end

  close_dlg()
  dlg = vlc.dialog(lang.title_video)
  dlg:set_size(DIALOG_WIDTH, 0)
  dlg:add_label(app.video.title, 1, 1, 4, 1)
  dlg:add_label(lang.lbl_by .. " " .. app.video.author .. " — "
                .. format_date(app.video), 1, 2, 4, 1)
  dlg:add_label(lang.lbl_quality, 1, 3, 1, 1)
  ui.quality = dlg:add_dropdown(2, 3, 3, 1)
  for i, f in ipairs(app.formats) do
    ui.quality:add_value(f.label, i)
  end
  dlg:add_button(lang.btn_play, click_play, 1, 4, 1, 1)
  -- One button for the two states of the only download there is room to
  -- run: what a download already going offers is to stop it. It also has
  -- to be put back to what it says here, because a download outlives the
  -- view it was started from and this may be a rebuilt one.
  ui.download = dlg:add_button(dl.active and lang.btn_dl_cancel
                                          or lang.btn_download,
                               click_download, 2, 4, 1, 1)
  dlg:add_button(lang.btn_copy, click_copy, 3, 4, 1, 1)
  dlg:add_button(lang.btn_back, show_search, 4, 4, 1, 1)
  -- A second row for the actions that are not the main one: the sound on
  -- its own, and -- once there is a pair on disk -- putting it back
  -- together. The first row stays four plain buttons whatever happens.
  local row = 5
  dlg:add_button(lang.btn_download_audio, click_download_audio, 1, row, 2, 1)
  -- Only when there is really a pair sitting on disk: a button that acts
  -- on files somebody has since moved is worse than no button.
  if app.combine and app.combine.id == app.video.id
                 and file_exists(app.combine.video)
                 and file_exists(app.combine.audio) then
    dlg:add_button(lang.btn_combine, click_combine, 3, row, 2, 1)
  end
  row = row + 1
  ui.link = dlg:add_text_input("", 1, row, 4, 1)
  ui.message = dlg:add_label("", 1, row + 1, 4, 1)
  -- A column of its own for the whole height of the view: the picture
  -- belongs to the video, not to any one row of it. The bounds are the
  -- size of the file itself and are stated because Qt only ever CLIPS an
  -- image to what it is told (a QLabel with no scaled contents), so a
  -- picture declared smaller than it is comes out cut.
  if app.thumb then
    dlg:add_image(app.thumb.path, 5, 1, 1, row + 1, app.thumb.w, app.thumb.h)
  end
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
  -- A stream relayed by the instance is fetched by the player itself, so
  -- it needs the name the session was issued to; the jar supplies the
  -- cookie that goes with it.
  local options = {}
  for _, opt in ipairs(f.options or {}) do
    table.insert(options, opt)
  end
  local session = session_for(f.url)
  if session and session.user_agent and session.user_agent ~= "" then
    table.insert(options, ":http-user-agent=" .. session.user_agent)
  end
  vlc.playlist.add({{
    path = f.url,
    title = app.video.title .. " — " .. app.video.author,
    options = options,     -- carries the separate audio stream, if any
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

            --[[ Putting the two files back together ]]--

-- Above 720p, YouTube has no combined stream and nothing in this player
-- can mux one: the mp4 muxer takes H.264 and AAC and there is no
-- matroska muxer in the bundle at all, so a VP9+Opus pair would have
-- nowhere to go. Rather than half a feature, this hands the job to
-- ffmpeg -- which the user installs, or does not.
--
-- Nothing is run behind anyone's back: a script is written next to the
-- files, and a terminal window is opened on it. The user sees the
-- command, sees ffmpeg's own output, and sees the error if ffmpeg is not
-- there. os.execute is the standard library's (extension.c calls
-- luaL_openlibs), and vlc.browser.open is deliberately not used: it
-- refuses anything that is not http(s), and that guard is worth keeping.

-- ⚠⚠⚠ A FUNCTION, not a top-level value. The scanner reads descriptor()
-- in a bare Lua state -- no libraries at all, `require` a stub (see the
-- note at the top of this file) -- and `package` is nil there. One
-- top-level `package.config` was enough to make the whole extension
-- disappear from the menu: the file raises while being loaded, so it is
-- never listed, and nothing anywhere says why.
local function is_windows()
  return package ~= nil and package.config ~= nil
     and string.sub(package.config, 1, 1) == "\\"
end

local function is_macos()
  local f = io.open("/usr/bin/open", "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Everything that reaches a shell goes through one of these. A video
-- title is whatever its author felt like -- quotes, dollars, backticks --
-- and it ends up in a file name.
local function sh_quote(s)
  return "'" .. string.gsub(tostring(s or ""), "'", "'\\''") .. "'"
end

local function bat_quote(s)
  -- cmd.exe expands %VAR% even inside quotes; doubling is how a percent
  -- survives being a percent
  return '"' .. string.gsub(tostring(s or ""), "%%", "%%%%") .. '"'
end

-- The command itself, for the script and for the clipboard fall-back.
local function ffmpeg_command(c, quote)
  return "ffmpeg -y -i " .. quote(c.video) .. " -i " .. quote(c.audio)
      .. " -c copy " .. quote(c.out)
end

local function write_combine_script(c)
  local path, body
  if is_windows() then
    path = c.dir .. "\\powervlc-combine.bat"
    body = table.concat({
      "@echo off",
      "cd /d " .. bat_quote(c.dir),
      "echo PowerVLC: " .. lang.combine_banner,
      "where ffmpeg >nul 2>nul || (echo " .. lang.combine_no_ffmpeg
        .. " & pause & exit /b 1)",
      ffmpeg_command(c, bat_quote),
      "echo.",
      "echo " .. lang.combine_done .. " " .. bat_quote(c.out),
      "pause",
      "",
    }, "\r\n")
  else
    -- .command rather than .sh: on macOS that is the extension the
    -- Finder and /usr/bin/open hand to Terminal. Elsewhere the name
    -- does not matter, the terminal is told to run it.
    path = c.dir .. "/powervlc-combine.command"
    body = table.concat({
      "#!/bin/sh",
      "# Written by PowerVLC. Safe to delete.",
      "cd " .. sh_quote(c.dir) .. " || exit 1",
      'printf "%s\\n" ' .. sh_quote(lang.combine_banner),
      'if ! command -v ffmpeg >/dev/null 2>&1; then',
      '  printf "%s\\n" ' .. sh_quote(lang.combine_no_ffmpeg),
      '  exit 1',
      'fi',
      ffmpeg_command(c, sh_quote),
      'status=$?',
      '[ "$status" -eq 0 ] && printf "%s\\n" '
        .. sh_quote(lang.combine_done .. " " .. c.out),
      'exit "$status"',
      "",
    }, "\n")
  end
  local f = io.open(path, "wb")
  if not f then
    return nil
  end
  f:write(body)
  f:close()
  return path
end

-- Open a terminal window running that script. Returns true when
-- something was launched -- not that ffmpeg succeeded, which is the
-- window's business to show.
local function launch_terminal(script)
  local cmd
  if is_windows() then
    cmd = 'start "" ' .. bat_quote(script)
  elseif is_macos() then
    -- chmod first: /usr/bin/open hands a .command to Terminal only if it
    -- is executable, and silently opens a text editor otherwise.
    cmd = "/bin/chmod +x " .. sh_quote(script)
       .. " && /usr/bin/open " .. sh_quote(script)
  else
    -- No agreed way to say "open a terminal" on Linux: try the ones that
    -- exist, in the order a desktop is likely to have them.
    local q = sh_quote(script)
    cmd = "/bin/chmod +x " .. q .. " ; "
       .. "for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal"
       .. " mate-terminal xterm ; do "
       .. "command -v \"$t\" >/dev/null 2>&1 && { \"$t\" -e " .. q
       .. " & exit 0 ; } ; done ; exit 1"
  end
  local ok = os.execute(cmd)
  -- os.execute answers true/false in 5.2+, an exit status in 5.1
  return ok == true or ok == 0
end

function click_combine()
  local c = app.combine
  if not (c and file_exists(c.video) and file_exists(c.audio)) then
    set_message(lang.msg_combine_gone)
    return
  end
  local script = write_combine_script(c)
  if script and launch_terminal(script) then
    set_message(lang.msg_combine_launched)
    return
  end
  -- No terminal to be had: the command is still the answer, so hand it
  -- over in the one place the user can paste from.
  local line = ffmpeg_command(c, is_windows() and bat_quote or sh_quote)
  if ui.link then
    ui.link:set_text(line)
  end
  if copy_to_clipboard(line) then
    set_message(lang.msg_combine_copied)
  else
    set_message(lang.msg_combine_fallback)
  end
end

            --[[ Downloading ]]--

-- What the file is called. The address says what is inside it -- every
-- googlevideo URL carries "&mime=video%2Fmp4", and a DASH manifest names
-- the same thing on its Representation -- so the extension follows the
-- contents rather than a guess. Getting it wrong costs a name that does
-- not match the file, which is why the fall-backs are the commonest of
-- each kind rather than nothing at all.
local function stream_extension(mime, url, sound_only)
  mime = mime or ""
  if mime == "" then
    local from_url = string.match(url or "", "[?&]mime=([^&]+)")
    if from_url then
      mime = (string.gsub(from_url, "%%2[Ff]", "/"))
    end
  end
  -- "video/mp4; codecs=..." -- the parameters are not part of the type
  local kind, sub = string.match(mime, "^(%a+)/([%w%-%.]+)")
  if sub then
    sub = string.match(sub, "^[%w%-]+")
  end
  if sound_only or kind == "audio" then
    if sub == "webm" then return "weba" end
    if sub == "mp4" then return "m4a" end
    return sub or "m4a"
  end
  if sub == "3gpp" then return "3gp" end
  return sub or "mp4"
end

-- The folder every browser on the machine would have used, made if it is
-- not there yet.
local function download_dir()
  local home = vlc.config.homedir()
  if not home or home == "" then
    return nil
  end
  local dir = home .. "/Downloads"
  mkdir_p(dir)
  return dir
end

-- The clock, for the rate shown while a download runs. vlc.misc.mdate is
-- this fork's; os.time() answers in whole seconds and os.clock() counts
-- CPU, which is exactly the part a download does NOT spend.
local function now_us()
  return (vlc.misc and vlc.misc.mdate) and vlc.misc.mdate() or nil
end

local function dl_progress()
  if not dl.files[dl.idx] then
    return
  end
  local percent = 0
  if dl.total > 0 then
    percent = math.floor(dl.got * 100 / dl.total)
  end
  -- No file name in here: this line is rewritten several times a second,
  -- and a window that grows to fit a long title never shrinks back. The
  -- names are in the closing message, which is written once.
  local line = string.format(lang.dl_progress,
    progress_bar(dl.got, dl.total), percent, dl.idx, #dl.files,
    format_bytes(dl.got), dl.total > 0 and format_bytes(dl.total) or "?")
  -- The rate, appended rather than put in the catalogues: "KiB/s" reads
  -- the same in every language this fork is translated into, and a figure
  -- the user can watch is what turns "it feels slow" into a measurement.
  if dl.started then
    local wall = (now_us() - dl.started) / 1000000
    -- not before half a second: a rate worked out on a first chunk is a
    -- number that jumps about and says nothing
    if wall > 0.5 then
      line = line .. string.format(" — %.0f KiB/s", dl.got / 1024 / wall)
    end
  end
  set_message(line)
end

local function dl_close_current()
  if dl.fh then
    dl.fh:close()
    dl.fh = nil
  end
  -- Dropping the last reference is what closes a stream -- the Lua API
  -- has no close of its own -- and a download holds several at once, so
  -- letting one go while keeping the others would leak the connection.
  dl.slices = {}
  dl.queue = {}
  collectgarbage()
end

local function dl_finish(cancelled)
  dl_close_current()
  dl.active = false
  if ui.download then
    ui.download:set_text(lang.btn_download)
  end
  if cancelled or dl.failed > 0 then
    -- A half-written file is not something anybody asked for, and a
    -- picture whose sound never arrived is no better: the two streams
    -- were one download and they go together, including into the bin.
    for _, f in ipairs(dl.files) do
      os.remove(f.path)
    end
    set_message(cancelled and lang.dl_cancelled
                          or (lang.dl_error .. tostring(dl.error or "?")))
  elseif #dl.written > 1 then
    -- The two halves are on disk: remember them so the view can offer to
    -- put them back together. Matroska on purpose -- it takes every pair
    -- YouTube serves (H.264+AAC as readily as VP9+Opus), and it cannot
    -- collide with either of the files it is made from.
    local base = string.gsub(dl.written[1], "%.[%w]+$", "")
    app.combine = { video = dl.files[1].path, audio = dl.files[2].path,
                    out = dl.dir .. "/" .. base .. ".mkv", dir = dl.dir,
                    -- Which video these two came from: the record outlives
                    -- the view, and a Combine button offered while another
                    -- video is open would act on the wrong pair.
                    id = app.video and app.video.id or nil }
    -- ⚠ The view was built before the download started, and this runs on
    -- the timer: setting the record above adds no button to a window
    -- that already exists. It has to be built again -- but only when the
    -- video view is the one on screen, since a download outlives the
    -- view it was started from and dragging someone back from their
    -- search results would be worse than no button at all.
    -- ui.quality is the marker: no other view has a quality picker.
    if ui.quality and app.video and app.combine.id == app.video.id then
      show_video()
    end
    set_message(string.format(lang.dl_done_pair, dl.written[1],
                              dl.written[2], dl.dir))
  else
    set_message(string.format(lang.dl_done, dl.written[1] or "?", dl.dir))
  end
end

-- One connection positioned at `from`, or nil and why. The seek is what
-- makes a slice: the HTTP access turns it into a Range request, so each
-- connection asks the server for its own part of the file and nothing
-- else. A server that will not do ranges says so here, by failing the
-- seek, and the caller falls back to one plain connection.
local function dl_open_at(url, from)
  -- vlc.stream reports a refusal two ways -- it returns nil and a
  -- message, and it raises -- so both are read here rather than only the
  -- one that happens to come up first.
  local ok, stream, why = pcall(vlc.stream, url)
  if not ok then
    return nil, tostring(stream)
  end
  if not stream then
    return nil, tostring(why or "stream error")
  end
  if from > 0 and not stream:seek(from) then
    return nil, "not seekable"
  end
  return stream
end

-- Take the next piece off the queue and point this connection at it.
-- False when there is nothing left, or when the connection could not be
-- opened -- in which case the piece goes back for someone else to take.
local function dl_take_chunk(sl, url)
  -- Dropping the reference is what closes a stream (the Lua API has no
  -- close of its own), and it has to happen BEFORE the next one is
  -- opened: waiting for the collector to come round in its own time is
  -- how a download ends up holding a hundred sockets at once.
  sl.stream = nil
  collectgarbage()
  local chunk = table.remove(dl.queue, 1)
  if not chunk then
    return false
  end
  local s = dl_open_at(url, chunk.from)
  if not s then
    table.insert(dl.queue, 1, chunk)
    return false
  end
  sl.stream, sl.off, sl.last = s, chunk.from, chunk.to
  return true
end

-- Open the file the tick is about to fetch, and lay out the pieces it
-- will be fetched in.
--
-- ⚠ Measured 2026-08-12 against googlevideo, twice over: 210 KiB/s per
-- connection on a video whose own bitrate is 210 KiB/s, and 28 KiB/s per
-- connection on its audio track, whose own bitrate is 28 KiB/s. The
-- server hands each connection the stream at the speed it would be
-- played at -- so the count of connections IS the multiplier, and an
-- audio track, at a quarter of the bitrate, takes just as long to fetch
-- as the video it belongs to unless there are enough of them.
--
-- No thread is needed for any of this. Every vlc.stream() carries the
-- "prefetch" filter (added by stream_AccessNew, src/input/access.c),
-- which runs a background thread of its own and reads up to 16 MiB
-- ahead: N streams fill their buffers concurrently while this single Lua
-- thread walks round them taking what has arrived.
local function dl_begin_file(cur)
  local stream, why = dl_open_at(cur.url, 0)
  if not stream then
    return nil, why
  end
  -- getsize() RAISES when the answer carries no length rather than
  -- returning nothing, and a server that will not say how long a stream
  -- is must cost the progress bar -- and the slicing -- not the download.
  local total = 0
  local known, size = pcall(stream.getsize, stream)
  if known and tonumber(size) then
    total = tonumber(size)
  end

  local fh = io.open(cur.path, "wb")
  if not fh then
    return nil, cur.path
  end

  dl.total = total
  dl.got = 0
  dl.started = now_us()
  dl.fh = fh
  dl.queue = {}
  dl.retries = 0

  -- One connection below the threshold, and whenever the length is
  -- unknown: without it there is nothing to divide, and the extra
  -- connections would cost a request each for a file that is over before
  -- they have opened.
  if total < DL_MIN_PARALLEL or DL_CONNECTIONS < 2 then
    dl.slices = { { stream = stream, off = 0, last = total > 0 and total or nil } }
    return true
  end

  -- Twice as many pieces as connections, so that one that finishes early
  -- has something to go on with -- bounded at both ends, because a piece
  -- too small costs more in requests than it carries.
  local span = math.floor(total / (DL_CONNECTIONS * 2))
  if span < DL_CHUNK_MIN then span = DL_CHUNK_MIN end
  if span > DL_CHUNK_MAX then span = DL_CHUNK_MAX end
  local from = 0
  while from < total do
    local to = from + span
    -- a last piece not worth a request of its own joins the one before it
    if to > total or (total - to) < math.floor(span / 4) then
      to = total
    end
    table.insert(dl.queue, { from = from, to = to })
    from = to
  end

  -- The stream opened above has read nothing yet and sits at 0, so it
  -- takes the first piece rather than being thrown away.
  local first = table.remove(dl.queue, 1)
  dl.slices = { { stream = stream, off = first.from, last = first.to } }

  for i = 2, DL_CONNECTIONS do
    local chunk = dl.queue[1]
    if not chunk then
      break
    end
    local s = dl_open_at(cur.url, chunk.from)
    if not s then
      if i == 2 then
        -- Ranges are refused here: one connection reads the whole file
        -- from the top, exactly as it did before any of this existed.
        -- All or nothing -- half a set of pieces is a corrupt file.
        vlc.msg.dbg("[Invidious] no ranged connections here, one it is")
        dl.queue = {}
        dl.slices = { { stream = stream, off = 0, last = total } }
        return true
      end
      break   -- fewer connections than asked for, but the ones open work
    end
    table.remove(dl.queue, 1)
    table.insert(dl.slices, { stream = s, off = chunk.from, last = chunk.to })
  end
  vlc.msg.info("[Invidious] " .. cur.name .. ": " .. #dl.slices
               .. " connections, " .. (#dl.queue + #dl.slices) .. " pieces of "
               .. math.floor(span / 1048576) .. " MiB")
  return true
end

local function dl_step()
  if dl.cancelled then
    dl_finish(true)
    return
  end

  if #dl.slices == 0 then
    dl.idx = dl.idx + 1
    local cur = dl.files[dl.idx]
    if not cur then
      dl_finish(false)
      return
    end
    local ok, why = dl_begin_file(cur)
    if not ok then
      dl.failed = dl.failed + 1
      dl.error = tostring(why or cur.name)
      vlc.msg.err("[Invidious] cannot download " .. cur.url
                  .. " to " .. tostring(cur.path))
      dl_finish(false)
      return
    end
  end

  local url = dl.files[dl.idx].url
  -- Bounded by the clock, and only then by a byte count: what the user
  -- watches is time. Each turn takes one chunk from every connection
  -- that still has something to give -- read in turn on this thread,
  -- while their prefetch threads keep all of them pulling at once.
  local deadline = now_us() and (now_us() + DL_TICK_BUDGET_US) or nil
  local finished = false
  for _ = 1, DL_CHUNKS_PER_TICK do
    -- Between chunks rather than between ticks: a megabyte over a slow
    -- link is well past the ten seconds after which the core offers to
    -- kill the extension, and a download is not a hung script.
    still_alive()

    for _, sl in ipairs(dl.slices) do
      if sl.stream then
        local left = sl.last and (sl.last - sl.off) or nil
        if left and left <= 0 then
          dl_take_chunk(sl, url)          -- this piece is done, next one
        else
          local want = READ_CHUNK
          if left and left < want then
            want = left
          end
          local data = sl.stream:read(want)
          if not data or #data == 0 then
            if left and left > 0 then
              -- The connection went before its piece was complete. What
              -- is left of it goes back in the queue rather than leaving
              -- a hole in the file -- that is the whole reason the work
              -- is a queue and not a fixed carve-up.
              dl.retries = dl.retries + 1
              if dl.retries <= DL_MAX_RETRIES then
                vlc.msg.warn("[Invidious] connection dropped at " .. sl.off
                             .. ", " .. (sl.last - sl.off)
                             .. " o back in the queue")
                table.insert(dl.queue, 1, { from = sl.off, to = sl.last })
              else
                vlc.msg.err("[Invidious] too many dropped connections")
                dl.queue = {}
              end
            end
            dl_take_chunk(sl, url)
          else
            -- Each connection writes where its own piece belongs: one
            -- file, filled from several places at once.
            dl.fh:seek("set", sl.off)
            dl.fh:write(data)
            sl.off = sl.off + #data
            dl.got = dl.got + #data
          end
        end
      end
    end

    local live = false
    for _, sl in ipairs(dl.slices) do
      if sl.stream then
        live = true
      end
    end
    if not live then
      finished = true
      break
    end
    if deadline and now_us() > deadline then
      break
    end
  end

  if finished then
    dl_close_current()
    -- A connection that dropped leaves a file that looks like a download
    -- and is not one. The length announced is what says so; when none was
    -- announced, only an empty answer can be judged.
    if dl.got == 0 or (dl.total > 0 and dl.got < dl.total) then
      dl.failed = dl.failed + 1
      dl.error = dl.files[dl.idx].name
      vlc.msg.err("[Invidious] " .. dl.files[dl.idx].name .. " stopped short: "
                  .. dl.got .. "/" .. dl.total .. " o")
      dl_finish(false)
      return
    end
    table.insert(dl.written, dl.files[dl.idx].name)
  end
  dl_progress()
end

-- The one timer callback this extension has: both jobs are looked at,
-- and arm_tick() re-arms it for whichever still has work to do.
function invidious_tick()
  if dl.active then
    dl_step()
  end
  challenge_poll()
  arm_tick()
end

-- Everything a download needs, whichever button asked for it: the
-- streams to fetch, and the tag that goes in the file name.
local function begin_download(entries, tag)
  if not vlc.timer then
    -- Nothing else moves the bytes along: the extension has no thread of
    -- its own, and a download is what the timer is for.
    set_message(lang.msg_dl_unsupported)
    return
  end
  local dir = download_dir()
  if not dir then
    set_message(lang.msg_dl_no_dir)
    return
  end

  -- "Title [1080p].mp4": the quality belongs in the name, so that the
  -- same video fetched twice at two qualities is two files rather than
  -- one overwritten. Not translated -- it is a file name, and one that
  -- changes with the interface language would not be found again.
  local base = sanitize_filename(app.video.title or "?")
            .. (tag and (" [" .. tag .. "]") or "")

  dl.files = {}
  dl.written = {}
  dl.slices = {}
  dl.queue = {}
  dl.idx, dl.got, dl.total, dl.failed = 0, 0, 0, 0
  dl.error = nil
  dl.cancelled = false
  dl.dir = dir

  for _, e in ipairs(entries) do
    local name = base .. "." .. stream_extension(e.mime, e.url, e.sound_only)
    table.insert(dl.files, { url = e.url, name = name,
                             path = dir .. "/" .. name })
  end

  dl.active = true
  if ui.download then
    ui.download:set_text(lang.btn_dl_cancel)
  end
  set_message(lang.dl_preparing)
  arm_tick()
end

function click_download()
  -- The button is the same one, and a download already running is what it
  -- offers to stop. Only the flag is set here: the tick owns the files.
  if dl.active then
    dl.cancelled = true
    return
  end
  local f = selected_format()
  if not f then
    return
  end
  -- HLS and the DASH manifest are descriptions of where the streams are,
  -- not streams: written to disk they would be a few kilobytes of XML.
  if f.playlist then
    set_message(lang.msg_dl_playlist)
    return
  end
  local entries = { { url = f.url, mime = f.mime, sound_only = f.sound_only } }
  -- A per-resolution DASH stream carries no sound of its own. Playing it
  -- pulls the audio in as a slave input, which a file on disk cannot do,
  -- so the sound is fetched as a second file and the closing message says
  -- the two go together.
  if f.audio then
    table.insert(entries, { url = f.audio, mime = f.audio_mime,
                            sound_only = true })
  end
  begin_download(entries, string.match(f.label or "", "(%d+p)")
                       or (f.sound_only and "audio") or nil)
end

-- The sound of this video on its own. Three places to look, in the order
-- that respects what the user has chosen: the entry selected when it is
-- already a sound-only one, the sound that goes with it when the chosen
-- quality keeps picture and sound apart, and failing both, whatever
-- sound-only stream the list holds -- which is what makes this work in
-- HTML mode, where the quality list has no sound-only entry of its own
-- but every DASH entry names its audio track.
local function audio_only_stream()
  local f = app.formats[ui.quality and ui.quality:get_value() or 1]
  if f and f.sound_only then
    return { url = f.url, mime = f.mime, sound_only = true }
  end
  if f and f.audio then
    return { url = f.audio, mime = f.audio_mime, sound_only = true }
  end
  for _, other in ipairs(app.formats) do
    if other.sound_only then
      return { url = other.url, mime = other.mime, sound_only = true }
    end
    if other.audio then
      return { url = other.audio, mime = other.audio_mime, sound_only = true }
    end
  end
  return nil
end

function click_download_audio()
  if dl.active then
    set_message(lang.msg_dl_busy)
    return
  end
  if #app.formats == 0 then
    set_message(lang.msg_no_formats)
    return
  end
  local sound = audio_only_stream()
  if not sound then
    -- Every stream this video offers carries picture and sound together;
    -- pulling the sound out of one would be a re-encode, which is the
    -- ffmpeg button's business, not this one's.
    set_message(lang.msg_no_audio_stream)
    return
  end
  begin_download({ sound }, "audio")
end
