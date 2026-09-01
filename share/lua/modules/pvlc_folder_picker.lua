-- Asynchronous native folder picker shared by PowerVLC Lua extensions.
--
-- Usage:
--   local picker = require("pvlc_folder_picker").new("my-extension", {
--     done = function(path, reason) ... end,
--   })
--   picker:open("Choose a folder", current_path)
--   -- Call picker:poll() from the extension timer while picker:busy().

local M = {}
local Picker = {}
Picker.__index = Picker

local function trim(value)
  return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function is_windows()
  return package and package.config and package.config:sub(1, 1) == "\\"
end

local function detect_platform()
  if is_windows() then return "windows" end
  local file = io.open("/usr/bin/osascript", "rb")
  if file then file:close(); return "macos" end
  if package and type(package.cpath) == "string"
     and package.cpath:find(".dylib", 1, true) then
    return "macos"
  end
  return "unix"
end

local function safe_name(value)
  local name = trim(value):gsub("[^%w_.-]", "-")
  return name ~= "" and name or "extension"
end

local function output_path(prefix)
  local directory = vlc.config and vlc.config.cachedir
                    and vlc.config.cachedir() or ""
  if directory == "" and vlc.config and vlc.config.userdatadir then
    directory = vlc.config.userdatadir() or ""
  end
  if directory == "" then directory = is_windows() and "." or "/tmp" end
  local separator = is_windows() and "\\" or "/"
  return directory .. separator .. ".powervlc-" .. safe_name(prefix)
      .. "-folder-picker.out"
end

local function apple_string(value)
  return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function powershell_string(value)
  return tostring(value or ""):gsub("'", "''")
end

local function candidates(platform, prompt, current, result_path)
  prompt = trim(prompt)
  if prompt == "" then prompt = "Choose a folder" end
  current = trim(current)

  if platform == "macos" then
    local command = "try\nset selectedFolder to choose folder with prompt \""
                 .. apple_string(prompt) .. "\""
    if current ~= "" then
      command = command .. " default location POSIX file \""
             .. apple_string(current) .. "\""
    end
    command = command .. "\nreturn POSIX path of selectedFolder"
             .. "\non error number -128\nreturn \"\"\nend try"
    -- Jaguar occasionally reports an empty redirected stdout for osascript
    -- even after the user accepted the panel.  Persist the result from inside
    -- AppleScript as well; polling this dedicated file avoids mistaking a
    -- successful selection for Cancel.
    local persistence = "\nset selectedPath to POSIX path of selectedFolder"
      .. "\ndo shell script \"/bin/echo \" & quoted form of selectedPath "
      .. "& \" > \" & quoted form of resultPath"
      .. "\nreturn selectedPath"
    command = "set resultPath to \"" .. apple_string(result_path or "") .. "\"\n"
           .. command:gsub("\nreturn POSIX path of selectedFolder", persistence)
    return {{ "/usr/bin/osascript", "-e", command }}
  end

  if platform == "windows" then
    local command = "Add-Type -AssemblyName System.Windows.Forms; "
      .. "$d=New-Object System.Windows.Forms.FolderBrowserDialog; "
      .. "$d.Description='" .. powershell_string(prompt) .. "'; "
      .. "$d.ShowNewFolderButton=$true; "
    if current ~= "" then
      command = command .. "$d.SelectedPath='"
             .. powershell_string(current) .. "'; "
    end
    command = command
      .. "if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)"
      .. "{$d.SelectedPath}"
    return {{ "powershell.exe", "-NoProfile", "-STA", "-Command", command }}
  end

  local zenity = { "zenity", "--file-selection", "--directory",
                   "--title", prompt }
  if current ~= "" then
    local initial = current:gsub("/+$", "") .. "/"
    table.insert(zenity, "--filename")
    table.insert(zenity, initial)
  end
  return {
    zenity,
    { "kdialog", "--getexistingdirectory", current, "--title", prompt },
  }
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local body = file:read("*a") or ""
  file:close()
  return body
end

local function selected_path(body, platform)
  local value = tostring(body or ""):gsub("[\r\n]+$", "")
  if value == "" then return "" end
  if platform == "windows" then
    if not value:match("^%a:[\\/]$") then value = value:gsub("[\\/]+$", "") end
  elseif value ~= "/" then
    value = value:gsub("/+$", "")
  end
  return value
end

function M.new(prefix, callbacks, options)
  options = options or {}
  return setmetatable({
    callbacks = callbacks or {},
    platform = options.platform or detect_platform(),
    output = options.output or output_path(prefix),
    result = (options.output or output_path(prefix)) .. ".selected",
    job = nil,
    entries = nil,
  }, Picker)
end

function Picker:busy()
  return self.job ~= nil
end

function Picker:_notify(path, reason)
  local callback = self.callbacks.done
  if callback then
    local ok, err = pcall(callback, path, reason)
    if not ok and vlc.msg and vlc.msg.warn then
      vlc.msg.warn("[folder-picker] callback failed: " .. tostring(err))
    end
  end
end

function Picker:_start(index)
  local argv = self.entries and self.entries[index]
  if not argv or not (vlc.process and vlc.process.start) then
    self.entries, self.job = nil, nil
    self:_notify(nil, "unavailable")
    return false, "unavailable"
  end

  pcall(os.remove, self.output)
  pcall(os.remove, self.result)
  local handle, err = vlc.process.start(argv, self.output)
  if not handle then
    if self.entries[index + 1] then return self:_start(index + 1) end
    self.entries = nil
    self:_notify(nil, "unavailable")
    return false, err or "unavailable"
  end
  self.job = { handle = handle, index = index }
  return true
end

function Picker:open(prompt, current)
  if self:busy() then return false, "busy" end
  if (self.platform == "windows" or self.platform == "macos") and vlc.config
     and type(vlc.config.select_directory) == "function" then
    local ok, path, reason = pcall(vlc.config.select_directory,
                                    prompt, current)
    if ok then
      path = selected_path(path, self.platform)
      self:_notify(path ~= "" and path or nil,
                   path ~= "" and nil or (reason or "cancelled"))
      return true
    end
  end
  self.entries = candidates(self.platform, prompt, current, self.result)
  return self:_start(1)
end

function Picker:poll()
  local job = self.job
  if not job then return false end
  local running, code = job.handle:status()
  if running then return true end

  local body = self.platform == "macos" and read_file(self.result)
                                      or read_file(self.output)
  local value = selected_path(body, self.platform)
  pcall(os.remove, self.output)
  pcall(os.remove, self.result)
  self.job = nil

  if job.cancelled then
    self.entries = nil
    self:_notify(nil, "cancelled")
  elseif code == 0 and value ~= "" then
    self.entries = nil
    self:_notify(value, nil)
  elseif code == 0 or code == 1 or code == 130 then
    self.entries = nil
    self:_notify(nil, "cancelled")
  elseif self.entries and self.entries[job.index + 1] then
    return self:_start(job.index + 1)
  else
    self.entries = nil
    self:_notify(nil, "unavailable")
  end
  return self:busy()
end

function Picker:cancel()
  if not self.job then return false end
  self.job.cancelled = true
  return self.job.handle:cancel()
end

function Picker:close()
  if self.job then pcall(function() self.job.handle:cancel() end) end
  if self.job and self.job.handle.close then
    pcall(function() self.job.handle:close() end)
  end
  self.job, self.entries = nil, nil
  pcall(os.remove, self.output)
  pcall(os.remove, self.result)
end

M.platform = detect_platform
return M
