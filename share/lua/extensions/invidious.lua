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

-- The catalogues live one file per language under share/lua/i18n/invidious/
-- and only the one in use is ever read: sixteen languages parsed at every
-- activation, to keep one, is not free on the machines this fork exists for
-- -- and it buried this file under ten screens of strings. English sits
-- underneath, string by string, so an untranslated key shows in English
-- rather than as a hole.
local lang = require("pvlc_i18n").load("invidious")

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

function connect_to(url)
  set_message(lang.msg_connecting)

  -- Prefer the JSON API: it carries exact dates and every quality.
  local obj, jerr = get_json(url .. "/api/v1/search?q=vlc&fields=type")
  if obj then
    app.mode = "api"
  else
    -- API switched off by the operator: fall back to the HTML pages the
    -- instance serves to browsers.
    set_message(lang.msg_trying_html)
    local items, err = html_search(url, "vlc", "video")
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
  .. "function stophard(){try{var m=document.querySelectorAll('video,audio');"
  .. "for(var k=0;k<m.length;k++){try{m[k].pause();"
  .. "m[k].removeAttribute('src');"
  .. "var q=m[k].getElementsByTagName('source');"
  .. "while(q.length){q[0].parentNode.removeChild(q[0]);}"
  .. "m[k].load();}catch(e2){}}}catch(err){}"
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
  .. "function wipe(){stophard();"
  .. "try{var b=document.body;if(b){while(b.firstChild)"
  .. "b.removeChild(b.firstChild);}}catch(e2){}"
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
  .. "if(d.ack){S.ack=1;note('{{M_OK}}');return;}"
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
  .. "function h(){if(!S.w)return;var ok=ready();"
  .. "S.w.postMessage({pv:1,hello:1,busy:ok?0:1,"
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
  .. "if(!w||w.closed){w=window.open('{{BASE}}','powervlc');}"
  .. "if(!w){say('{{M_POPUP}}',1);return;}"
  .. "S.w=w;if(!S.t){S.t=setInterval(h,2000);}h();if(!AUTO)stop();"
  .. "if(!S.ack)note('{{M_WAIT}}');"
  -- the opener may be some other page entirely, in which case the messages
  -- go nowhere: no acknowledgement means open our own window and retry
  .. "setTimeout(function(){if(S.ack)return;"
  .. "var w2=window.open('{{BASE}}','powervlc');"
  .. "if(w2){S.w=w2;h();}"
  .. "setTimeout(function(){if(!S.ack)note('{{M_FAIL}}',1);},4000);},4000);"
  .. "})()"

-- Runs on our own page. Nothing here is subject to the instance's policy.
local RELAY_JS = [==[
(function(){
 var BASE='{{BASE}}', TARGET='__TARGET__';
 var tab=null, lastHello=0, lastCookie='', job=null, busy=false;
 var st=document.getElementById('st');
 function say(t){ if(st) st.innerHTML=t; }
 function xhr(m,u,b,cb){
   var x=new XMLHttpRequest(); x.open(m,u,true);
   x.onreadystatechange=function(){ if(x.readyState==4&&cb) cb(x); };
   try{ x.send(b||null); }catch(err){ if(cb) cb(x); }
 }
 window.addEventListener('message',function(e){
   if(e.origin!==TARGET) return;
   var d=e.data; if(!d||d.pv!==1) return;
   if(d.hello){
     tab=e.source; lastHello=new Date().getTime(); busy=!!d.busy;
     /* tell the page its messages are arriving: without this it has no
        way to know whether the opener it found is really us */
     try{ e.source.postMessage({pv:1,ack:1},TARGET); }catch(err){}
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
     say(busy?'__BUSY__':'__ON__'); return;
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
   if(!tab||busy||new Date().getTime()-lastHello>6000){
     say(busy?'__BUSY__':'__OFF__'); setTimeout(loop,600); return;
   }
   xhr('GET',BASE+'/next',null,function(x){
     var t=x.responseText||'';
     if(t){ var i=t.indexOf(' ');
            job={id:t.substring(0,i),url:t.substring(i+1)};
            tab.postMessage({pv:1,id:job.id,url:job.url},TARGET); }
     setTimeout(loop,400);
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
        M_NAV = lang.web_m_nav, M_TAKEN = lang.web_m_taken }) do
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
  js = js_put(js, "__ON__", lang.web_relay_on)
  js = js_put(js, "__OFF__", lang.web_relay_off)
  js = js_put(js, "__BUSY__", lang.web_relay_busy)

  local landing = web_page(lang.web_title,
    "<p>" .. lang.web_intro .. "</p><ol>"
    .. "<li>" .. lang.web_step1 .. "<br><a class=\"bm\" href=\""
       .. attr_escape(bm) .. "\">" .. lang.web_bookmark
       .. "</a></li>"
    -- rel="opener" on purpose: target="_blank" has implied noopener since
    -- 2021, and the opener is the whole point -- it is what lets the tab
    -- reach this page without any Content-Security-Policy in the way. The
    -- bookmarklet opens a window of its own where that is refused anyway.
    .. "<li>" .. lang.web_step2 .. "<br><a class=\"inst\" target=\"_blank\" "
       .. "rel=\"opener\" href=\"" .. attr_escape(target) .. "\">"
       .. html_escape(target) .. "</a></li>"
    .. "<li>" .. lang.web_step3 .. "</li></ol>"
    .. '<div id="st">' .. lang.web_relay_off .. "</div>"
    -- Not a footnote: on the machines this fork exists for, this is the
    -- only path that works at all -- see web_addon.
    .. "<hr><h2>" .. lang.web_addon_title .. "</h2>"
    .. "<p>" .. lang.web_addon .. "</p>"
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
  ui.local_url = dlg:add_text_input(
    app.handoff and app.handoff:url() or "", 1, 3, 2, 1)
  dlg:add_button(lang.btn_challenge_copy, click_challenge_copy, 3, 3, 1, 1)
  dlg:add_button(lang.btn_challenge_open, click_challenge_open, 4, 3, 1, 1)
  dlg:add_label(lang.lbl_challenge_3, 1, 4, 4, 1)
  dlg:add_button(lang.btn_challenge_done, click_challenge_done, 1, 5, 1, 1)
  dlg:add_button(lang.btn_challenge_cancel, show_connect, 2, 5, 1, 1)
  ui.message = dlg:add_label(lang.msg_challenge_needed, 1, 6, 4, 1)
  dlg:show()
  app.awaiting_challenge = true
  if vlc.timer then
    vlc.timer(CHALLENGE_POLL_MS, "challenge_tick")
  end
end

function click_challenge_copy()
  if not ui.local_url then
    return
  end
  if copy_to_clipboard(ui.local_url:get_text()) then
    set_message(lang.msg_challenge_copied)
  else
    set_message(lang.msg_copy_fallback)
  end
end

function click_challenge_open()
  if not ui.local_url then
    return
  end
  if open_in_browser(ui.local_url:get_text()) then
    set_message(lang.msg_challenge_opened)
  else
    set_message(lang.msg_challenge_no_browser)
  end
end

function challenge_tick()
  if not app.awaiting_challenge then
    return
  end
  if challenge_resume(true) then
    return
  end
  if vlc.timer then
    vlc.timer(CHALLENGE_POLL_MS, "challenge_tick")
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
  local candidates = {
    { itag = "22", label = "720p — mp4 (" .. lang.combined .. ")" },
    { itag = "18", label = "360p — mp4 (" .. lang.combined .. ")" },
    { itag = "140", label = lang.audio_only .. " — 128 kb/s (m4a)" },
  }
  local formats = {}
  for _, c in ipairs(candidates) do
    still_alive()
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
