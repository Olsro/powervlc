-- Lightweight aMule External Connections (EC) v2 codec.
--
-- PowerVLC deliberately negotiates the historical, uncompressed framing on
-- loopback.  That keeps this module small enough for old machines while the
-- daemon remains responsible for eD2k/Kad, hashing and transfer scheduling.

local M = {}

M.FLAG_BASE = 0x20
M.PROTOCOL_VERSION = 0x0204

M.TYPE = {
  CUSTOM = 1, UINT8 = 2, UINT16 = 3, UINT32 = 4, UINT64 = 5,
  STRING = 6, DOUBLE = 7, IPV4 = 8, HASH16 = 9, UINT128 = 10,
}

M.OP = {
  NOOP = 0x01, AUTH_REQ = 0x02, AUTH_FAIL = 0x03, AUTH_OK = 0x04,
  FAILED = 0x05, STRINGS = 0x06, SHUTDOWN = 0x08, STAT_REQ = 0x0A,
  STATS = 0x0C, GET_DLOAD_QUEUE = 0x0D, DLOAD_QUEUE = 0x1F,
  PARTFILE_PAUSE = 0x19, PARTFILE_RESUME = 0x1A,
  PARTFILE_DELETE = 0x1D, PARTFILE_SET_CAT = 0x1E,
  SEARCH_START = 0x26, SEARCH_STOP = 0x27,
  SEARCH_RESULTS = 0x28, SEARCH_PROGRESS = 0x29,
  DOWNLOAD_SEARCH_RESULT = 0x2A, SERVER_UPDATE_FROM_URL = 0x32,
  GET_PREFERENCES = 0x3F, SET_PREFERENCES = 0x40,
  CREATE_CATEGORY = 0x41, UPDATE_CATEGORY = 0x42,
  CONNECT = 0x4A, DISCONNECT = 0x4B, KAD_UPDATE_FROM_URL = 0x4D,
  AUTH_SALT = 0x4F, AUTH_PASSWD = 0x50,
}

M.TAG = {
  STRING = 0x0000, PASSWD_HASH = 0x0001, PROTOCOL_VERSION = 0x0002,
  DETAIL_LEVEL = 0x0004, CONNSTATE = 0x0005, ED2K_ID = 0x0006,
  CLIENT_ID = 0x000A,
  PASSWD_SALT = 0x000B, CAN_MULTI_SEARCH = 0x0015,
  CLIENT_NAME = 0x0100, CLIENT_VERSION = 0x0101,
  STATS_UL_SPEED = 0x0200, STATS_DL_SPEED = 0x0201,
  PARTFILE = 0x0300, PARTFILE_NAME = 0x0301,
  PARTFILE_PARTMETID = 0x0302, PARTFILE_SIZE_FULL = 0x0303,
  PARTFILE_SIZE_XFER = 0x0304,
  PARTFILE_SIZE_DONE = 0x0306, PARTFILE_SPEED = 0x0307,
  PARTFILE_STATUS = 0x0308, PARTFILE_SOURCE_COUNT = 0x030A,
  PARTFILE_SOURCE_COUNT_XFER = 0x030D, PARTFILE_CAT = 0x030F,
  PARTFILE_PART_STATUS = 0x0312, PARTFILE_GAP_STATUS = 0x0313,
  PARTFILE_HASH = 0x031E,
  SEARCHFILE = 0x0700, SEARCH_TYPE = 0x0701, SEARCH_NAME = 0x0702,
  SEARCH_FILE_TYPE = 0x0705, SEARCH_STATUS = 0x0708,
  SEARCH_PARENT = 0x0709, SEARCH_LIFECYCLE_STATE = 0x070A,
  SEARCH_LIFECYCLE_KIND = 0x070B, SEARCH_RESULT_COUNT = 0x070C,
  SEARCH_LIFECYCLE_PERCENT = 0x070D, SEARCH_ID = 0x070E,
  SELECT_PREFS = 0x1000, PREFS_CATEGORIES = 0x1100,
  CATEGORY = 0x1101, CATEGORY_TITLE = 0x1102,
  CATEGORY_PATH = 0x1103, CATEGORY_COMMENT = 0x1104,
  CATEGORY_COLOR = 0x1105, CATEGORY_PRIO = 0x1106,
  SERVERS_UPDATE_URL = 0x170C,
}

M.DETAIL = { CMD = 0, WEB = 1, FULL = 2, UPDATE = 3, INC_UPDATE = 4 }
M.SEARCH = { LOCAL = 0, GLOBAL = 1, KAD = 2 }

local floor = math.floor
local U32 = 4294967296

local function p16(n)
  n = floor(n or 0)
  return string.char(floor(n / 256) % 256, n % 256)
end

local function p32(n)
  n = floor(n or 0)
  return string.char(floor(n / 16777216) % 256,
                     floor(n / 65536) % 256,
                     floor(n / 256) % 256, n % 256)
end

local function p64(n)
  n = floor(n or 0)
  local high = floor(n / U32)
  local low = n - high * U32
  return p32(high) .. p32(low)
end

local function u16(data, pos)
  local a, b = string.byte(data, pos, pos + 1)
  if not b then return nil, pos, "short uint16" end
  return a * 256 + b, pos + 2
end

local function u32(data, pos)
  local a, b, c, d = string.byte(data, pos, pos + 3)
  if not d then return nil, pos, "short uint32" end
  return ((a * 256 + b) * 256 + c) * 256 + d, pos + 4
end

local function uint_value(data)
  local n = 0
  for i = 1, #data do n = n * 256 + string.byte(data, i) end
  return n
end

local function bytes_to_hex(data)
  return (string.gsub(data or "", ".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

local function integer_hex(data)
  -- Do not rely on string.upper() here. The Lua runtime on Mac OS X 10.2
  -- inherits the platform's incomplete locale/ctype implementation and can
  -- leave hexadecimal a-f untouched. aMule hashes the salt's uppercase %lX
  -- representation, so emit uppercase digits directly from string.format.
  local value = (string.gsub(data or "", ".", function(c)
    return string.format("%02X", string.byte(c))
  end))
  value = string.gsub(value, "^0+", "")
  return value == "" and "0" or value
end

function M.hex_to_bytes(hex)
  if type(hex) ~= "string" or #hex % 2 ~= 0 or string.find(hex, "[^%x]") then
    return nil
  end
  return (string.gsub(hex, "(%x%x)", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

function M.tag(name, kind, value, children)
  return { name = name, type = kind, value = value, children = children or {} }
end

function M.empty(name, children)
  return M.tag(name, M.TYPE.CUSTOM, "", children)
end

function M.integer(name, value, children)
  value = floor(tonumber(value) or 0)
  local kind
  if value <= 0xff then kind = M.TYPE.UINT8
  elseif value <= 0xffff then kind = M.TYPE.UINT16
  elseif value <= 0xffffffff then kind = M.TYPE.UINT32
  else kind = M.TYPE.UINT64 end
  return M.tag(name, kind, value, children)
end

function M.string(name, value, children)
  return M.tag(name, M.TYPE.STRING, tostring(value or ""), children)
end

function M.hash(name, hex, children)
  return M.tag(name, M.TYPE.HASH16, assert(M.hex_to_bytes(hex)), children)
end

local function tag_data(tag)
  if tag.type == M.TYPE.STRING then return tostring(tag.value or "") .. "\0" end
  if tag.type == M.TYPE.UINT8 then return string.char((tag.value or 0) % 256) end
  if tag.type == M.TYPE.UINT16 then return p16(tag.value) end
  if tag.type == M.TYPE.UINT32 then return p32(tag.value) end
  if tag.type == M.TYPE.UINT64 then return p64(tag.value) end
  return tag.value or ""
end

local function encode_tag(tag)
  local children = tag.children or {}
  local child_blob = ""
  if #children > 0 then
    local parts = { p16(#children) }
    for i = 1, #children do parts[#parts + 1] = encode_tag(children[i]) end
    child_blob = table.concat(parts)
  end
  local own = tag_data(tag)
  local wire_name = tag.name * 2 + (#children > 0 and 1 or 0)
  -- EC's tag length includes every serialized child, but not this tag's own
  -- uint16 child-count field. It is therefore two bytes shorter than the
  -- bytes following the header whenever children are present.
  local declared = #child_blob + #own - (#children > 0 and 2 or 0)
  return p16(wire_name) .. string.char(tag.type) .. p32(declared)
       .. child_blob .. own
end

function M.packet(opcode, tags)
  tags = tags or {}
  local body = { string.char(opcode), p16(#tags) }
  for i = 1, #tags do body[#body + 1] = encode_tag(tags[i]) end
  body = table.concat(body)
  return p32(M.FLAG_BASE) .. p32(#body) .. body
end

local parse_tag
parse_tag = function(data, pos, limit)
  local wire_name, next_pos, err = u16(data, pos)
  if not wire_name then return nil, pos, err end
  pos = next_pos
  local kind = string.byte(data, pos)
  if not kind then return nil, pos, "short tag type" end
  pos = pos + 1
  local declared
  declared, pos, err = u32(data, pos)
  if not declared then return nil, pos, err end
  local count_len = wire_name % 2 == 1 and 2 or 0
  if declared + count_len > limit - pos + 1 then
    return nil, pos, "tag length exceeds packet"
  end
  local payload_start = pos
  local children_start = pos
  local children = {}
  if wire_name % 2 == 1 then
    local count
    count, pos, err = u16(data, pos)
    if not count then return nil, pos, err end
    children_start = pos
    if count > 65534 then return nil, pos, "unsupported extended tag count" end
    for i = 1, count do
      local child
      child, pos, err = parse_tag(data, pos,
                                 payload_start + declared + count_len - 1)
      if not child then return nil, pos, err end
      children[#children + 1] = child
    end
  end
  local consumed = pos - children_start
  local own_len = declared - consumed
  if own_len < 0 or pos + own_len - 1 > limit then
    return nil, pos, "invalid tag payload length"
  end
  local raw = string.sub(data, pos, pos + own_len - 1)
  pos = pos + own_len
  local value = raw
  if kind >= M.TYPE.UINT8 and kind <= M.TYPE.UINT64 then
    value = uint_value(raw)
  elseif kind == M.TYPE.STRING then
    value = string.byte(raw, -1) == 0 and string.sub(raw, 1, -2) or raw
  elseif kind == M.TYPE.HASH16 then
    value = bytes_to_hex(raw)
  end
  return { name = floor(wire_name / 2), type = kind, value = value,
           integer_hex = kind >= M.TYPE.UINT8 and kind <= M.TYPE.UINT64
                         and integer_hex(raw) or nil,
           raw = raw, children = children }, pos
end

function M.decode_body(body)
  if type(body) ~= "string" or #body < 3 then return nil, "short EC body" end
  local opcode = string.byte(body, 1)
  local count, pos, err = u16(body, 2)
  if not count then return nil, err end
  local tags = {}
  for i = 1, count do
    local tag
    tag, pos, err = parse_tag(body, pos, #body)
    if not tag then return nil, err end
    tags[#tags + 1] = tag
  end
  if pos ~= #body + 1 then return nil, "trailing EC packet data" end
  return { opcode = opcode, tags = tags }
end

-- Extract as many complete frames as possible from a TCP receive buffer.
function M.frames(buffer, max_size)
  buffer = buffer or ""
  max_size = max_size or 64 * 1024 * 1024
  local packets, pos = {}, 1
  while #buffer - pos + 1 >= 8 do
    local flags, p, err = u32(buffer, pos)
    if not flags then return packets, string.sub(buffer, pos), err end
    local length
    length, p, err = u32(buffer, p)
    if not length then return packets, string.sub(buffer, pos), err end
    if length > max_size then return packets, "", "EC frame too large" end
    if #buffer - p + 1 < length then break end
    if flags ~= M.FLAG_BASE then
      return packets, "", string.format("unsupported EC flags 0x%x", flags)
    end
    local packet
    packet, err = M.decode_body(string.sub(buffer, p, p + length - 1))
    if not packet then return packets, "", err end
    packet.flags = flags
    packets[#packets + 1] = packet
    pos = p + length
  end
  return packets, string.sub(buffer, pos)
end

function M.child(container, name)
  local children = container and (container.children or container.tags) or nil
  for i = 1, #(children or {}) do
    if children[i].name == name then return children[i] end
  end
  return nil
end

function M.children(container, name)
  local out = {}
  local children = container and (container.children or container.tags) or nil
  for i = 1, #(children or {}) do
    if children[i].name == name then out[#out + 1] = children[i] end
  end
  return out
end

function M.auth_request()
  return M.packet(M.OP.AUTH_REQ, {
    M.string(M.TAG.CLIENT_NAME, "PowerVLC"),
    M.string(M.TAG.CLIENT_VERSION, "1.0"),
    M.integer(M.TAG.PROTOCOL_VERSION, M.PROTOCOL_VERSION),
  })
end

function M.auth_password(ec_password_hash, salt, md5)
  local salt_text
  if type(salt) == "table" and salt.integer_hex then salt_text = salt.integer_hex
  elseif type(salt) == "string" then salt_text = salt
  else salt_text = string.format("%X", salt) end
  local salt_hash = md5(salt_text)
  local challenge = md5(string.lower(ec_password_hash) .. salt_hash)
  return M.packet(M.OP.AUTH_PASSWD, { M.hash(M.TAG.PASSWD_HASH, challenge) })
end

return M
