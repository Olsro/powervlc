-- OpenSubtitles REST client for PowerVLC. GPL-2.0-or-later.
-- HTTP uses the player's TLS/certificates, including on legacy systems.
local M = {}
local Client = {}
Client.__index = Client
local API = "https://api.opensubtitles.com/api/v1"

-- Register a PowerVLC API consumer before preparing a public release.
-- This identifies the application; user credentials are kept separately.
M.application_key = "Qhr29iEvWk2ph7UUA6TlKGLUnR4ewLPo"

-- Kept deliberately static and ASCII so the settings dialog remains useful
-- when the service is offline and on systems whose locale data is incomplete.
-- /infos/languages augments this list when it is reachable.
M.fallback_languages = {
    {"af", "Afrikaans"}, {"sq", "Albanian"}, {"ar", "Arabic"},
    {"hy", "Armenian"}, {"az", "Azerbaijani"}, {"eu", "Basque"},
    {"be", "Belarusian"}, {"bn", "Bengali"}, {"bs", "Bosnian"},
    {"bg", "Bulgarian"}, {"my", "Burmese"}, {"ca", "Catalan"},
    {"zh-cn", "Chinese (Simplified)"}, {"zh-tw", "Chinese (Traditional)"},
    {"hr", "Croatian"}, {"cs", "Czech"}, {"da", "Danish"},
    {"nl", "Dutch"}, {"en", "English"}, {"eo", "Esperanto"},
    {"et", "Estonian"}, {"fi", "Finnish"}, {"fr", "French"},
    {"gl", "Galician"}, {"ka", "Georgian"}, {"de", "German"},
    {"el", "Greek"}, {"he", "Hebrew"}, {"hi", "Hindi"},
    {"hu", "Hungarian"}, {"is", "Icelandic"}, {"id", "Indonesian"},
    {"ga", "Irish"}, {"it", "Italian"}, {"ja", "Japanese"},
    {"kk", "Kazakh"}, {"ko", "Korean"}, {"ku", "Kurdish"},
    {"lv", "Latvian"}, {"lt", "Lithuanian"}, {"lb", "Luxembourgish"},
    {"mk", "Macedonian"}, {"ms", "Malay"}, {"ml", "Malayalam"},
    {"mt", "Maltese"}, {"mn", "Mongolian"}, {"ne", "Nepali"},
    {"no", "Norwegian"}, {"fa", "Persian"}, {"pl", "Polish"},
    {"pt-br", "Portuguese (Brazil)"}, {"pt-pt", "Portuguese (Portugal)"},
    {"pa", "Punjabi"}, {"ro", "Romanian"}, {"ru", "Russian"},
    {"sr", "Serbian"}, {"si", "Sinhala"}, {"sk", "Slovak"},
    {"sl", "Slovenian"}, {"es", "Spanish"}, {"sv", "Swedish"},
    {"tl", "Tagalog"}, {"ta", "Tamil"}, {"te", "Telugu"},
    {"th", "Thai"}, {"tr", "Turkish"}, {"uk", "Ukrainian"},
    {"ur", "Urdu"}, {"uz", "Uzbek"}, {"vi", "Vietnamese"},
    {"cy", "Welsh"},
}

function M.trim(s)
    return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
end

function M.display_text(value)
    return M.trim(value):gsub("[%c<>]", " "):gsub("%s+", " ")
end

function M.searchable_name(name)
    name = M.trim(name)
    -- Stream names can be full signed URLs or contain user:password@host.
    -- Ask for a title instead of sending these credentials to the provider.
    if name:find("://", 1, true) then return "" end
    return name
end

function M.languages(s)
    local list, seen = {}, {}
    for code in tostring(s or ""):lower():gmatch("[^,%s;]+") do
        if not code:match("^%a%a$") and not code:match("^%a%a%-%a%a$") then
            return nil
        end
        if not seen[code] then list[#list + 1], seen[code] = code, true end
    end
    if #list == 0 or #list > 3 then return nil end
    return list
end

function M.language_catalog(remote)
    local by_code = {}
    for _, entry in ipairs(M.fallback_languages) do
        by_code[entry[1]] = { code = entry[1], name = entry[2] }
    end
    if type(remote) == "table" then
        for _, entry in ipairs(remote) do
            if type(entry) == "table" then
                local code = M.trim(entry.language_code or entry.code):lower()
                local name = M.display_text(entry.language_name or entry.name)
                if (code:match("^%a%a$") or code:match("^%a%a%-%a%a$"))
                   and name ~= "" and not name:find("[%c]") then
                    by_code[code] = { code = code, name = name }
                end
            end
        end
    end
    local out = {}
    for _, entry in pairs(by_code) do out[#out + 1] = entry end
    table.sort(out, function(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        return an == bn and a.code < b.code or an < bn
    end)
    return out
end

local function encode(s)
    return (tostring(s):gsub("([^%w%-._~ ])", function(c)
        return string.format("%%%02X", c:byte())
    end):gsub(" ", "+"))
end

function M.query(params)
    local keys, out = {}, {}
    for key, value in pairs(params) do
        if value ~= nil and value ~= "" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do out[#out + 1] = key .. "=" .. encode(params[key]) end
    return table.concat(out, "&")
end

-- Extract conservative metadata locally. Keep the original release name
-- separately for the first query and for displaying to the user.
function M.identify(name)
    local video_extensions = {mkv=true, mp4=true, avi=true, mov=true, m4v=true,
        webm=true, mpg=true, mpeg=true, ts=true, m2ts=true, wmv=true, flv=true,
        mk3d=true, iso=true, vob=true, ogv=true, divx=true, asf=true, ["3gp"]=true}
    local stem = tostring(name or ""):gsub("%.([%w]+)$", function(ext)
        return video_extensions[ext:lower()] and "" or ("." .. ext)
    end)
    local lower = stem:lower()
    local start, _, season, episode = lower:find("s(%d%d?)[%s%._%-]*e(%d%d?%d?)")
    if not start then start, _, season, episode = lower:find("(%d%d?)x(%d%d?%d?)") end
    local year
    if start then
        stem = stem:sub(1, start - 1)
    else
        local a, _, candidate = (lower .. " "):find("[%.%s_%(%[]([12]%d%d%d)[%.%s_%)%]]")
        if a and tonumber(candidate) >= 1900 and tonumber(candidate) <= 2099 then
            year, stem = tonumber(candidate), stem:sub(1, a - 1)
        else
            -- Release suffixes usually start with resolution or source.
            for _, pattern in ipairs({"[%.%s_]2160p", "[%.%s_]1080p", "[%.%s_]720p",
                    "[%.%s_]480p", "[%.%s_]bluray", "[%.%s_]web%-dl", "[%.%s_]webrip",
                    "[%.%s_]dvdrip", "[%.%s_]hdtv"}) do
                local pos = lower:find(pattern)
                if pos and pos <= #stem then stem = stem:sub(1, pos - 1) end
            end
        end
    end
    local query = M.trim(stem:gsub("[._]", " "):gsub("%s+", " ")):lower()
    -- The API's text search also matches common articles by themselves.
    -- "les indestructibles" otherwise returns many unrelated French films.
    local articles = {the=true, a=true, an=true, le=true, la=true, les=true,
                      un=true, une=true, des=true}
    local first, rest = query:match("^(%a+)%s+(.+)$")
    if articles[first] and #rest >= 3 then query = rest end
    return { query = query,
             year = year, season_number = tonumber(season), episode_number = tonumber(episode) }
end

function M.guessable_name(name)
    name = M.searchable_name(name)
    if name == "" or #name > 255 or name:find("[/\\%c]") then return nil end
    return name
end

function M.imdb_id(value)
    value = M.trim(value):lower():gsub("^tt", ""):gsub("^0+", "")
    if value == "" or not value:match("^%d+$") then return nil end
    -- Keep this as text: Lua 5.1 numbers cannot represent arbitrary long IDs
    -- exactly, and the API expects the leading-zero-free decimal form.
    return value
end

-- Two 32-bit halves avoid Lua 5.1's floating-point loss of 64-bit integers.
function M.hash_blocks(size, first, last)
    if type(size) ~= "number" or size < 65536 or size > 9007199254740991
        or type(first) ~= "string" or #first ~= 65536
        or type(last) ~= "string" or #last ~= 65536 then return nil end
    local base = 4294967296
    local lo, hi = size % base, math.floor(size / base) % base
    for _, block in ipairs({first, last}) do
        for i = 1, #block, 8 do
            local a,b,c,d,e,f,g,h = block:byte(i, i + 7)
            lo = lo + a + b*256 + c*65536 + d*16777216
            hi = (hi + e + f*256 + g*65536 + h*16777216 + math.floor(lo/base)) % base
            lo = lo % base
        end
    end
    -- Format in 16-bit pieces: %x itself takes a signed long on some targets.
    return string.format("%04x%04x%04x%04x", math.floor(hi/65536), hi%65536,
                         math.floor(lo/65536), lo%65536)
end

function M.hash(uri)
    if not tostring(uri):match("^file://") then return nil end
    local stream
    local ok, hash = pcall(function()
        stream = vlc.stream(uri)
        if not stream then return nil end
        local size = stream:getsize()
        if size < 65536 or size > 9007199254740991 then return nil end
        local first = stream:read(65536)
        if not stream:seek(size - 65536) then return nil end
        return M.hash_blocks(size, first, stream:read(65536))
    end)
    stream = nil
    collectgarbage("collect") -- release the separate stream/file descriptor
    return ok and hash or nil
end

local function trusted_url(url)
    local host = type(url) == "string" and url:match("^https://([^/]+)")
    return host and (host == "opensubtitles.com" or host:match("^[%w%-%.]+%.opensubtitles%.com$"))
end

function M.new(key, version)
    return setmetatable({ key = key, json = require("dkjson"), base = API,
        agent = "PowerVLC v" .. tostring(version), token = nil }, Client)
end

function Client:request(method, path, params)
    if not self.key or self.key == "" then return nil, "missing_key" end
    local headers = { ["Api-Key"] = self.key, ["User-Agent"] = self.agent,
                      Accept = "application/json" }
    if self.token and method == "GET" then headers.Authorization = "Bearer " .. self.token end
    local status, body, raw
    if vlc.keep_alive then vlc.keep_alive() end
    if method == "GET" then
        local url = self.base .. path .. "?" .. M.query(params or {})
        -- Follow only HTTPS OpenSubtitles redirects; never forward the key
        -- to an arbitrary host or to cleartext HTTP.
        for _ = 1, 5 do
            status, body, raw = vlc.http.get(url, headers, true)
            if status ~= 301 and status ~= 302 and status ~= 307 and status ~= 308 then break end
            local next_url = (raw or ""):match("[\r\n][Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:%s*([^\r\n]+)")
            if next_url and next_url:sub(1,1) == "/" and next_url:sub(1,2) ~= "//" then
                next_url = url:match("^https://[^/]+") .. next_url
            end
            if not trusted_url(next_url) then return nil, "invalid_response" end
            url = next_url
        end
    else
        status, body = vlc.http.post(self.base .. path, self.json.encode(params or {}),
            "application/json", self.token and ("Bearer " .. self.token) or nil, headers)
    end
    if not status then return nil, "network" end
    local decoded = type(body) == "string" and self.json.decode(body) or nil
    if status < 200 or status >= 300 then
        if status == 401 then return nil, "unauthorized", decoded end
        if status == 403 then return nil, "forbidden", decoded end
        if status == 406 then return nil, "quota", decoded end
        if status == 429 then return nil, "rate_limit", decoded end
        return nil, "http_error", { status = status }
    end
    if type(decoded) ~= "table" then return nil, "invalid_response" end
    return decoded
end

function Client:language_catalog()
    local result, err, detail = self:request("GET", "/infos/languages")
    if not result then return nil, err, detail end
    local data = result.data or result
    if type(data) ~= "table" then return nil, "invalid_response" end
    return M.language_catalog(data)
end

function Client:guess(filename)
    filename = M.guessable_name(filename)
    if not filename then return nil, "invalid_name" end
    local result, err, detail = self:request("GET", "/utilities/guessit",
                                             { filename = filename })
    if not result then return nil, err, detail end
    local data = type(result.data) == "table" and result.data or result
    local title = M.trim(data.title)
    local year = tonumber(data.year)
    local season = tonumber(data.season or data.season_number)
    local episode = tonumber(data.episode or data.episode_number)
    if title == "" and not (season and episode) then
        return nil, "invalid_response"
    end
    return { query = title ~= "" and title or nil,
             year = year, season_number = season, episode_number = episode }
end

function Client:login(user, password)
    self.token, self.base = nil, API
    local result, err = self:request("POST", "/login", {username = user, password = password})
    if not result then return nil, err end
    if type(result.token) ~= "string" or result.token == "" or result.token:find("[%c]") then
        return nil, "invalid_response"
    end
    if result.base_url then
        local base = result.base_url
        if type(base) ~= "string" then return nil, "invalid_response" end
        if not base:match("^https://") then base = "https://" .. base end
        base = base:gsub("/+$", "")
        if not trusted_url(base) or not base:match("^https://[^/]+$") then
            return nil, "invalid_response"
        end
        self.base = base .. "/api/v1"
    end
    self.token = result.token
    return true
end

function Client:account(user, password)
    if user == "" or password == "" then return nil, "missing_credentials" end
    local ok, err = self:login(user, password)
    if not ok then return nil, err end
    local result, info_err, detail = self:request("GET", "/infos/user")
    if not result then return nil, info_err, detail end
    local data = type(result.data) == "table" and result.data or result
    if type(data) ~= "table" then return nil, "invalid_response" end
    local allowed = tonumber(data.allowed_downloads)
    local used = tonumber(data.downloads_count)
    local remaining = tonumber(data.remaining_downloads or data.remaining)
    if not remaining and allowed and used then remaining = math.max(0, allowed - used) end
    return { username = M.trim(data.username) ~= "" and M.trim(data.username) or user,
             level = M.trim(data.level), allowed = allowed, used = used,
             remaining = remaining,
             reset_time = M.trim(data.reset_time_utc or data.reset_time) }
end

function Client:search(params)
    local result, err, detail = self:request("GET", "/subtitles", params)
    if not result then return nil, err, detail end
    if type(result.data) ~= "table" then return nil, "invalid_response" end
    local rows = {}
    for _, item in ipairs(result.data) do
        local a = item.attributes
        if type(a) == "table" and type(a.files) == "table" then
            for _, file in ipairs(a.files) do
                local id = tonumber(file.file_id)
                if id and id > 0 then
                    local uploader = type(a.uploader) == "table" and a.uploader or {}
                    local language = tostring(a.language or "?"):lower()
                    if not language:match("^%a%a[%a%-]*$") then language = "?" end
                    rows[#rows + 1] = { id = id, language = language,
                        release = M.display_text(file.file_name or a.release),
                        feature = type(a.feature_details) == "table" and a.feature_details.feature_id or nil,
                        title = type(a.feature_details) == "table" and a.feature_details.title or nil,
                        hash_match = a.moviehash_match == true, trusted = a.from_trusted == true,
                        hearing_impaired = a.hearing_impaired == true,
                        foreign_only = a.foreign_parts_only == true,
                        hd = a.hd == true, ai_translated = a.ai_translated == true,
                        machine_translated = a.machine_translated == true,
                        downloads = tonumber(a.download_count) or 0,
                        rating = tonumber(a.ratings) or 0, votes = tonumber(a.votes) or 0,
                        fps = tonumber(a.fps), uploader = M.display_text(uploader.name),
                        uploader_rank = M.display_text(uploader.rank),
                        upload_date = M.display_text(a.upload_date) }
                end
            end
        end
    end
    return rows, nil, { page = tonumber(result.page) or 1,
                       pages = tonumber(result.total_pages) or 1 }
end

function M.sort(rows, languages, mode)
    local priority, features, feature_count = {}, {}, 0
    for i, code in ipairs(languages) do priority[code] = i end
    -- Preserve the service's film relevance order. A trusted subtitle for a
    -- different film must not leapfrog a result for the requested film.
    for _, row in ipairs(rows) do
        local feature = row.feature or "unknown"
        if not features[feature] then
            feature_count = feature_count + 1
            features[feature] = feature_count
        end
    end
    table.sort(rows, function(a, b)
        if a.hash_match ~= b.hash_match then return a.hash_match end
        if mode == "downloads" and a.downloads ~= b.downloads then
            return a.downloads > b.downloads
        end
        if mode == "rating" and a.rating ~= b.rating then return a.rating > b.rating end
        local fa, fb = features[a.feature or "unknown"], features[b.feature or "unknown"]
        if fa ~= fb then return fa < fb end
        local pa, pb = priority[a.language] or 99, priority[b.language] or 99
        if pa ~= pb then return pa < pb end
        if a.trusted ~= b.trusted then return a.trusted end
        if a.downloads ~= b.downloads then return a.downloads > b.downloads end
        return a.id < b.id
    end)
end

function Client:download(id, user, password)
    if not self.token and user ~= "" and password ~= "" then
        local ok, err = self:login(user, password)
        if not ok then return nil, err end
    end
    local result, err, detail = self:request("POST", "/download", {file_id = id, sub_format = "srt"})
    -- Tokens expire; retry authentication once, but never retry quota errors
    -- or an ambiguous network failure that may have consumed a download.
    if not result and err == "unauthorized" and self.token and user ~= "" and password ~= "" then
        local ok, login_err = self:login(user, password)
        if not ok then return nil, login_err end
        result, err, detail = self:request("POST", "/download", {file_id = id, sub_format = "srt"})
    end
    if not result then return nil, err, detail end
    if not trusted_url(result.link) then return nil, "invalid_response" end
    -- Download links are signed: send neither account token nor API key.
    local status, body = vlc.http.get(result.link)
    if status ~= 200 then return nil, "network" end
    if type(body) ~= "string" or #body > 8 * 1024 * 1024
        or not body:find("%d%d:%d%d:%d%d[,.]%d+%s*%-%->%s*%d%d:%d%d:%d%d") then
        return nil, "invalid_subtitle"
    end
    return body, nil, result
end

function M.safe_name(s)
    local name = M.trim(s):gsub("[\\/:*?\"<>|%c]", "_"):gsub("[%. ]+$", "")
    if name == "" then name = "subtitle" end
    -- Leave room for language, id and collision suffix within NAME_MAX.
    if #name > 160 then
        name = name:sub(1, 160):gsub("[\194-\244][\128-\191]*$", "")
    end
    return name
end

function M.save(body, directories, stem, row)
    local name = M.safe_name(stem) .. "." .. M.safe_name(row.language)
    for _, directory in ipairs(directories) do
        if directory and directory ~= "" then
            for index = 1, 100 do
                local suffix = index == 1 and "" or ("." .. tostring(row.id) .. "." .. index)
                local path = directory:gsub("[\\/]+$", "") .. "/" .. name .. suffix .. ".srt"
                local file, errno = vlc.io.open_exclusive(path)
                if file then
                    local written = file:write(body)
                    local closed = file:close()
                    if written and closed then return path end
                    vlc.io.unlink(path)
                    break
                elseif errno ~= 17 then -- EEXIST on every supported platform
                    break
                end
            end
        end
    end
    return nil, "save_failed"
end

return M
