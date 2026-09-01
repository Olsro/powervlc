-- Small asynchronous downloader shared by PowerVLC Lua extensions.
-- It deliberately delegates HTTP redirects and large-file I/O to curl through
-- PowerVLC's argv-safe process API, keeping the Lua UI thread responsive.

local M = {}
local Client = {}
Client.__index = Client

local function trim(value)
  return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function is_windows()
  return package and package.config and package.config:sub(1, 1) == "\\"
end

local function platform()
  if is_windows() then return "windows" end
  local file = io.open("/usr/bin/osascript", "rb")
  if file then file:close(); return "macos" end
  return "unix"
end

function M.sanitize(value)
  local text = trim(value):gsub("[\\/:*?\"<>|%c]", "_")
  text = text:gsub("%s%s+", " "):gsub("[%. ]+$", "")
  if text == "" then text = "download" end
  if #text > 160 then text = text:sub(1, 160) end
  return text
end

function M.extension(url, fallback)
  local path = tostring(url or ""):match("^[^?#]+") or ""
  local ext = path:match("%.([%w%d]+)$")
  if not ext or #ext > 8 then ext = fallback or "bin" end
  return ext:lower()
end

function M.default_directory()
  local home = vlc.config and vlc.config.homedir and vlc.config.homedir() or ""
  if home == "" then return "" end
  return home .. (is_windows() and "\\Downloads" or "/Downloads")
end

function M.join(directory, filename)
  local separator = is_windows() and "\\" or "/"
  return tostring(directory or ""):gsub("[\\/]+$", "")
      .. separator .. M.sanitize(filename)
end

function M.unique_path(directory, filename)
  local clean = M.sanitize(filename)
  local stem, ext = clean:match("^(.*)(%.[^%.]+)$")
  stem, ext = stem or clean, ext or ""
  local path = M.join(directory, clean)
  local index = 2
  while true do
    local file = io.open(path, "rb")
    if not file then return path end
    file:close()
    path = M.join(directory, stem .. " (" .. index .. ")" .. ext)
    index = index + 1
  end
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local body = file:read("*a") or ""
  file:close()
  return body
end

local function prepare_log(path)
  local file = io.open(path, "wb")
  if not file then return false end
  file:close()
  return true
end

local function log_path(prefix)
  local directory = vlc.config and vlc.config.userdatadir
                    and vlc.config.userdatadir() or ""
  if directory == "" then directory = "/tmp" end
  local separator = is_windows() and "\\" or "/"
  return directory .. separator .. ".powervlc-" .. M.sanitize(prefix)
      .. "-download.log"
end

local function curl_candidates()
  if is_windows() then return { "curl.exe", "curl" } end
  if platform() == "macos" then
    return { "/usr/bin/curl", "/opt/homebrew/bin/curl",
             "/usr/local/bin/curl", "curl" }
  end
  return { "curl", "/usr/bin/curl", "/usr/local/bin/curl" }
end

function M.new(prefix, callbacks)
  return setmetatable({
    prefix = prefix or "media",
    callbacks = callbacks or {},
    log = log_path(prefix or "media"),
    job = nil,
    entries = nil,
    index = 0,
    curl = nil,
  }, Client)
end

function Client:busy()
  return self.job ~= nil
end

function Client:_notify(name, ...)
  local callback = self.callbacks[name]
  if callback then pcall(callback, ...) end
end

function Client:_start_process(argv, kind, data)
  if not (vlc.process and vlc.process.start) then
    return false, "process API unavailable"
  end
  prepare_log(self.log)
  local handle, err = vlc.process.start(argv, self.log)
  if not handle then return false, err end
  self.job = { handle = handle, kind = kind, data = data, argv = argv }
  return true
end

function Client:_start_entry()
  self.index = self.index + 1
  local entry = self.entries and self.entries[self.index]
  if not entry then
    local completed = self.entries or {}
    self.entries, self.job = nil, nil
    self:_notify("done", true, completed)
    return true
  end
  local probe = io.open(entry.path, "wb")
  if not probe then
    self.entries, self.job = nil, nil
    self:_notify("done", false, "cannot write " .. tostring(entry.path))
    return false
  end
  probe:close()

  local candidates = self.curl and { self.curl } or curl_candidates()
  local last_error = nil
  for _, executable in ipairs(candidates) do
    local argv = { executable, "--location", "--fail", "--show-error",
                   "--silent", "--output", entry.path, entry.url }
    local started, err = self:_start_process(argv, "download", entry)
    if started then
      self.curl = executable
      self:_notify("file", entry, self.index, #self.entries)
      return true
    end
    last_error = err
  end
  os.remove(entry.path)
  self.entries, self.job = nil, nil
  self:_notify("done", false, tostring(last_error or "curl unavailable"))
  return false
end

function Client:start(entries)
  if self:busy() or self.entries then return false, "busy" end
  if type(entries) ~= "table" or #entries == 0 then return false, "empty" end
  self.entries, self.index = entries, 0
  return self:_start_entry()
end

function Client:cancel()
  if not self.job then return false end
  self.job.cancelled = true
  return self.job.handle:cancel()
end

function Client:poll()
  local job = self.job
  if not job then return false end
  local running, code = job.handle:status()
  if running then return true end
  self.job = nil

  if job.cancelled then
    os.remove(job.data.path)
    self.entries = nil
    self:_notify("done", false, "cancelled")
    return false
  end
  if code ~= 0 then
    os.remove(job.data.path)
    local detail = trim(read_file(self.log))
    self.entries = nil
    self:_notify("done", false, detail ~= "" and detail or ("curl exit " .. code))
    return false
  end
  return self:_start_entry() and self:busy()
end

return M
