local extension_path, module_path = arg[1], arg[2]
assert(extension_path and module_path, "usage: check_twitch_extension.lua EXT MODULES")
package.path = module_path .. "/?.lua;" .. package.path

local json = require("dkjson")
local posted, replies, played = {}, {}, {}
local current_dialog

local function check(value, message)
  if not value then
    error(message or "check failed", 2)
  end
end

local function contains(text, part)
  return type(text) == "string" and string.find(text, part, 1, true) ~= nil
end

local function widget(kind, text, callback)
  local w = {
    kind = kind,
    text = text or "",
    callback = callback,
    value = -1,
    values = {},
    selection = {},
  }
  function w:set_text(value) self.text = value or "" end
  function w:get_text() return self.text end
  function w:set_value(value) self.value = value end
  function w:get_value() return self.value end
  function w:add_value(value, id)
    table.insert(self.values, { text = value, id = id })
  end
  function w:clear()
    self.values = {}
    self.selection = {}
  end
  function w:set_sort(column, ascending)
    self.sort_column = column
    self.sort_ascending = ascending
  end
  function w:get_selection() return self.selection end
  return w
end

local function dialog(title)
  local d = {
    title = title,
    text_inputs = {},
    dropdowns = {},
    lists = {},
    labels = {},
    buttons = {},
  }
  function d:set_size(width, height) self.width, self.height = width, height end
  function d:add_label(text)
    local w = widget("label", text)
    table.insert(self.labels, w)
    return w
  end
  function d:add_text_input(text, _, _, _, _, callback)
    local w = widget("text", text, callback)
    table.insert(self.text_inputs, w)
    return w
  end
  function d:add_dropdown(_, _, _, _, callback)
    local w = widget("dropdown", "", callback)
    table.insert(self.dropdowns, w)
    return w
  end
  function d:add_list(_, _, _, _, callback)
    local w = widget("list", "", callback)
    table.insert(self.lists, w)
    return w
  end
  function d:add_button(text, callback)
    local w = widget("button", text, callback)
    table.insert(self.buttons, w)
    return w
  end
  function d:del_widget(target)
    local groups = { self.text_inputs, self.dropdowns, self.lists,
                     self.labels, self.buttons }
    for _, group in ipairs(groups) do
      for index, candidate in ipairs(group) do
        if candidate == target then
          table.remove(group, index)
          return
        end
      end
    end
  end
  function d:update() self.updated = true end
  function d:show() self.shown = true end
  function d:hide() self.hidden = true end
  function d:delete() self.deleted = true end
  current_dialog = d
  return d
end

local function encode_uri(value)
  return (string.gsub(tostring(value or ""), "[^%w%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function queue(data, status)
  table.insert(replies, { status = status or 200, body = json.encode(data) })
end

POWERVLC_TWITCH_TEST = true
vlc = {
  config = {
    language = function() return "en" end,
    datadir = function() return "share" end,
  },
  strings = { encode_uri_component = encode_uri },
  dialog = dialog,
  http = {
    post = function(url, body, content_type, authorization, headers)
      table.insert(posted, {
        url = url,
        body = json.decode(body),
        content_type = content_type,
        authorization = authorization,
        headers = headers,
      })
      local reply = table.remove(replies, 1)
      check(reply, "unexpected HTTP request")
      return reply.status, reply.body
    end,
  },
  playlist = {
    add = function(items)
      for _, item in ipairs(items) do table.insert(played, item) end
    end,
  },
  msg = { dbg = function() end },
  deactivate = function() end,
}

assert(loadfile(extension_path))()

check(descriptor().title == "Twitch", "descriptor title")
local target = twitch_test.parse_twitch_url(" https://www.twitch.tv/Caedrel?x=1 ")
check(target and target.kind == "channel" and target.login == "caedrel",
      "channel URL parsing")
target = twitch_test.parse_twitch_url("https://twitch.tv/videos/2853131280")
check(target and target.kind == "video" and target.id == "2853131280",
      "video URL parsing")
check(twitch_test.parse_twitch_url("caedrel") == nil, "plain query is not a URL")
check(twitch_test.parse_twitch_url("https://www.twitch.tv/directory/game/Music") == false,
      "directory URL must not become a channel")
check(twitch_test.parse_twitch_url("https://clips.twitch.tv/example") == false,
      "unsupported Twitch subdomain")

activate()
check(current_dialog and current_dialog.shown, "dialog shown")
local query = current_dialog.text_inputs[1]
local mode = current_dialog.dropdowns[1]
local results = current_dialog.lists[1]
check(#current_dialog.dropdowns == 1,
      "category controls are hidden in channel mode")

queue({ data = {
  user = {
    displayName = "Caedrel",
    stream = { id = "1", title = "Live title", viewersCount = 42,
               game = { name = "League of Legends" } },
  },
  streamPlaybackAccessToken = { value = '{"channel":"caedrel"}', signature = "sig" },
} })
query:set_text("https://www.twitch.tv/caedrel")
click_search()
check(#played == 1, "full channel URL starts playback")
check(contains(played[1].path, "usher.ttvnw.net/api/channel/hls/caedrel.m3u8"),
      "live usher URL")
check(contains(played[1].path, "token=%7B%22channel%22%3A%22caedrel%22%7D"),
      "playback token is escaped")
check(posted[#posted].headers["Client-ID"], "Client-ID header")

queue({ data = {
  video = { id = "2853131280", title = "A VOD",
            owner = { login = "caedrel", displayName = "Caedrel" } },
  videoPlaybackAccessToken = { value = "vod token", signature = "vod sig" },
} })
query:set_text("https://www.twitch.tv/videos/2853131280")
click_search()
check(#played == 2 and contains(played[2].path, "/vod/2853131280.m3u8"),
      "full video URL starts playback")

queue({ data = { searchUsers = {
  edges = {
    { node = { login = "live_one", displayName = "LiveOne", stream = {
      id = "10", title = "First", viewersCount = 1200,
      game = { id = "1", displayName = "Music" },
    } } },
    { node = { login = "offline_one", displayName = "OfflineOne", stream = nil } },
  },
} } })
mode:set_value(1)
query:set_text("music")
click_search()
check(#results.values == 2, "channel search fills a list")
check(posted[#posted].body.variables.limit == 30, "channel result limit")
check(results.sort_column == 3 and results.sort_ascending == false,
      "viewers descending is the default sort")
check(contains(results.values[1].text, "1 200\0311200"), "numeric viewer sort key")

results.selection = { [1] = results.values[1].text }
queue({ data = {
  user = {
    displayName = "LiveOne",
    stream = { id = "10", title = "First", viewersCount = 1200,
               game = { displayName = "Music" } },
  },
  streamPlaybackAccessToken = { value = "live token", signature = "live sig" },
} })
click_play()
check(#played == 3 and played[3].artist == "LiveOne", "selected result playback")

queue({ data = { searchFor = {
  channels = { edges = {} },
  games = { edges = {
    { item = { id = "2", name = "League of Legends: Wild Rift",
               displayName = "League of Legends: Wild Rift" } },
    { item = { id = "1", name = "League of Legends",
               displayName = "League of Legends" } },
  } },
} } })
queue({ data = { game = {
  id = "1", name = "League of Legends", displayName = "League of Legends",
  streams = { edges = {
    { node = { id = "20", title = "Big stream", viewersCount = 5000,
      broadcaster = { login = "big", displayName = "Big" },
      game = { id = "1", displayName = "League of Legends" } } },
    { node = { id = "21", title = "Small stream", viewersCount = 10,
      broadcaster = { login = "small", displayName = "Small" },
      game = { id = "1", displayName = "League of Legends" } } },
  } },
} } })
mode:set_value(2)
click_mode_changed()
check(#current_dialog.dropdowns == 2,
      "category controls appear in category mode")
local category = current_dialog.dropdowns[2]
query:set_text("League of Legends")
click_search()
check(#category.values == 2 and category.value == 2,
      "exact category is selected among matches")
check(posted[#posted].body.variables.name == "League of Legends",
      "selected category is queried")
check(posted[#posted].body.variables.limit == 30, "category result limit")
check(#results.values == 2 and results.sort_column == 3
      and results.sort_ascending == false, "category streams list and sorting")

mode:set_value(1)
click_mode_changed()
check(#current_dialog.dropdowns == 1,
      "category controls disappear when leaving category mode")

check(#replies == 0, "all mocked replies consumed")
deactivate()
check(current_dialog.deleted, "dialog deleted on deactivation")
print("ok - Twitch extension behavior")
