--[[ pvlc_i18n.lua: one catalogue per language, loaded one at a time.

 An extension used to carry every translation in its own source: sixteen
 languages parsed at every activation to keep one. That is not free on the
 machines this fork exists for, and it buried the code under ten screens of
 strings nobody could review.

 Now each extension ships share/lua/i18n/<name>/<code>.lua, a file that
 returns a plain table, and this loads the one that matches -- plus English
 underneath, so a string nobody has translated yet shows in English rather
 than as a hole.

 Usage, from an extension:

   local lang = require("pvlc_i18n").load("invidious")
   dlg:add_button(lang.btn_connect, ...)

 Copyright (C) 2026 the PowerVLC team -- GPL v2 or later.
]]

local M = {}

-- The language the interface really runs in. vlc.config.language() is this
-- fork's own binding: the "language" option has been obsolete since 2.1 and
-- every interface applies the user's choice its own way, so the process
-- locale is the only answer that is true everywhere.
local function ui_locale()
  if vlc.config and vlc.config.language then
    local ok, value = pcall(vlc.config.language)
    if ok and type(value) == "string" and value ~= "" then
      return string.lower(value)
    end
  end
  for _, name in ipairs({ "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" }) do
    local value = os.getenv(name)
    if value and value ~= "" then
      return string.lower(value)
    end
  end
  return "en"
end

-- Which catalogues to try, best first. Regional variants are only kept
-- apart where they really differ -- pt_BR is not pt_PT and zh_TW is not
-- zh_CN, while fr_CA reads fr perfectly well.
local function candidates()
  local locale = ui_locale()
  local lang, country = string.match(locale, "^(%a%a)[_%-](%a%a)")
  local two = lang or string.match(locale, "^(%a%a)") or "en"
  country = country and string.upper(country) or nil

  local list = {}
  if two == "pt" then
    table.insert(list, country == "BR" and "pt_BR" or "pt_PT")
  elseif two == "zh" then
    table.insert(list, (country == "TW" or country == "HK") and "zh_TW"
                                                            or "zh_CN")
  elseif country then
    table.insert(list, two .. "_" .. country)   -- e.g. a future en_GB
  end
  table.insert(list, two)
  return list
end

local function load_one(name, code)
  if not (vlc.config and vlc.config.datadir) then
    return nil
  end
  local path = vlc.config.datadir() .. "/lua/i18n/" .. name .. "/"
               .. code .. ".lua"
  local chunk = loadfile(path)
  if not chunk then
    return nil
  end
  local ok, table_ = pcall(chunk)
  if ok and type(table_) == "table" then
    return table_
  end
  return nil
end

-- Returns the catalogue for this extension, English underneath.
function M.load(name)
  local english = load_one(name, "en") or {}

  for _, code in ipairs(candidates()) do
    if code ~= "en" then
      local translated = load_one(name, code)
      if translated then
        -- String by string, not file by file: a key the translation has
        -- not got yet reads through to English instead of leaving a hole
        -- where a label belongs.
        setmetatable(translated, { __index = english })
        return translated
      end
    end
  end

  return english
end

return M
