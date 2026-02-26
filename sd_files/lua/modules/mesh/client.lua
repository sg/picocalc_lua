--[[

  mesh/client.lua - MeshCore Binary Protocol Client

  Handles TCP connection to a MeshCore companion radio node,
  binary frame encoding/decoding, contact storage, and event emission.

  Sync orchestration is handled by the caller (mesh.lua), not here.
  This module only sends frames and emits events.

]]

local Client = {}
Client.__index = Client

-- Protocol constants
local FRAME_OUT     = 0x3C  -- '<' outbound frame marker
local FRAME_IN      = 0x3E  -- '>' inbound frame marker
local MAX_PAYLOAD   = 300

-- Outbound command bytes
local CMD_APP_START       = 0x01
local CMD_SEND_TXT_MSG    = 0x02
local CMD_SEND_CHAN_MSG   = 0x03
local CMD_GET_CONTACTS    = 0x04
local CMD_GET_DEVICE_TIME = 0x05
local CMD_SYNC_NEXT_MSG   = 0x0A
local CMD_GET_BATT        = 0x14
local CMD_SEND_LOGIN      = 0x1A
local CMD_LOGOUT          = 0x1D
local CMD_GET_CHANNEL     = 0x1F

-- Inbound response bytes
local RSP_OK              = 0x00
local RSP_ERR             = 0x01
local RSP_CONTACT_START   = 0x02
local RSP_CONTACT         = 0x03
local RSP_CONTACT_END     = 0x04
local RSP_SELF_INFO       = 0x05
local RSP_MSG_SENT        = 0x06
local RSP_CONTACT_MSG_V1  = 0x07
local RSP_CHANNEL_MSG_V1  = 0x08
local RSP_CURR_TIME       = 0x09
local RSP_NO_MORE_MSGS    = 0x0A
local RSP_BATTERY         = 0x0C
local RSP_CONTACT_MSG_V3  = 0x10
local RSP_CHANNEL_MSG_V3  = 0x11
local RSP_CHANNEL_INFO    = 0x12

-- Push notification bytes
local PUSH_ADVERT         = 0x80
local PUSH_PATH_UPDATED   = 0x81
local PUSH_ACK            = 0x82
local PUSH_MSGS_WAITING   = 0x83
local PUSH_RAW_DATA       = 0x84
local PUSH_LOGIN_SUCCESS  = 0x85
local PUSH_LOGIN_FAILED   = 0x86
local PUSH_STATUS_RESP    = 0x87
local PUSH_LOG_RX_DATA    = 0x88
local PUSH_TRACE_DATA     = 0x89
local PUSH_NEW_ADVERT     = 0x8A
local PUSH_TELEMETRY      = 0x8B
local PUSH_BINARY_RESP    = 0x8C
local PUSH_CONTROL_DATA   = 0x8E

-- Packet name table for debug output
local PACKET_NAMES = {
  [RSP_OK]             = "OK",
  [RSP_ERR]            = "ERR",
  [RSP_CONTACT_START]  = "CONTACT_START",
  [RSP_CONTACT]        = "CONTACT",
  [RSP_CONTACT_END]    = "CONTACT_END",
  [RSP_SELF_INFO]      = "SELF_INFO",
  [RSP_MSG_SENT]       = "MSG_SENT",
  [RSP_CONTACT_MSG_V1] = "CONTACT_MSG_V1",
  [RSP_CHANNEL_MSG_V1] = "CHANNEL_MSG_V1",
  [RSP_CURR_TIME]      = "CURR_TIME",
  [RSP_NO_MORE_MSGS]   = "NO_MORE_MSGS",
  [RSP_BATTERY]        = "BATTERY",
  [RSP_CONTACT_MSG_V3] = "CONTACT_MSG_V3",
  [RSP_CHANNEL_MSG_V3] = "CHANNEL_MSG_V3",
  [RSP_CHANNEL_INFO]   = "CHANNEL_INFO",
  [PUSH_ADVERT]        = "ADVERT",
  [PUSH_PATH_UPDATED]  = "PATH_UPDATED",
  [PUSH_ACK]           = "ACK",
  [PUSH_MSGS_WAITING]  = "MSGS_WAITING",
  [PUSH_RAW_DATA]      = "RAW_DATA",
  [PUSH_LOGIN_SUCCESS]  = "LOGIN_OK",
  [PUSH_LOGIN_FAILED]   = "LOGIN_FAIL",
  [PUSH_LOG_RX_DATA]   = "LOG_RX_DATA",
  [PUSH_STATUS_RESP]   = "STATUS_RESP",
  [PUSH_TRACE_DATA]    = "TRACE_DATA",
  [PUSH_NEW_ADVERT]    = "NEW_ADVERT",
  [PUSH_TELEMETRY]     = "TELEMETRY",
  [PUSH_BINARY_RESP]   = "BINARY_RESP",
  [PUSH_CONTROL_DATA]  = "CONTROL_DATA",
}

-- Max contacts to store
local MAX_CONTACTS = 200

function Client.new(config)
  config = config or {}
  local self = setmetatable({
    host = config.host or "192.168.77.222",
    port = config.port or 5000,

    sock = nil,
    recv_buf = "",
    connected = false,

    -- Self info from node
    self_name = nil,
    self_pubkey = nil,
    self_prefix = nil,

    -- Contact storage (prefix only, no full pubkey)
    contacts = {},        -- array of {prefix, name, type, flags, lastmod}
    prefix_map = {},      -- 6-byte prefix string -> contact index
    contacts_lastmod = 0, -- for incremental sync

    -- Login state
    logged_in = false,
    login_prefix = nil,
    login_perms = 0,

    -- Channel names
    channel_names = {},       -- index -> name string

    -- Battery
    battery_pct = nil,

    -- Time sync: store node's epoch and os.clock() at sync moment
    time_synced = false,
    node_time_base = 0,    -- node's epoch seconds when synced
    clock_base = 0,         -- os.clock() value when synced
    picocalc_clock_offset = 0, -- node_epoch - os.time() at sync

    -- Debug mode (log file present) and verbose mode (-v flag)
    debug = config.debug or false,
    verbose = config.verbose or false,

    -- Event callbacks
    callbacks = {},

    -- Socket timeout for non-blocking reads
    recv_timeout = 0.05,
    connect_timeout = 10000,
  }, Client)

  return self
end

-- Event system
function Client:on(event, callback)
  if not self.callbacks[event] then
    self.callbacks[event] = {}
  end
  table.insert(self.callbacks[event], callback)
end

function Client:emit(event, ...)
  local cbs = self.callbacks[event]
  if cbs then
    for _, cb in ipairs(cbs) do
      cb(...)
    end
  end
end

-- Connect to the MeshCore node
function Client:connect()
  if self.connected then
    return false, "already connected"
  end

  collectgarbage("collect")

  local sock, err = socket.tcp()
  if not sock then
    return false, "failed to create socket: " .. (err or "unknown")
  end

  self.sock = sock

  local ok, conn_err = sock:connect(self.host, self.port, self.connect_timeout)
  if not ok then
    sock:close()
    self.sock = nil
    return false, "connection failed: " .. (conn_err or "unknown")
  end

  self.connected = true
  self.recv_buf = ""

  self:emit("connecting")

  -- Send APP_START: cmd, app_ver, reserved(6), app_name
  local payload = string.pack("BB", CMD_APP_START, 0x03) .. "\0\0\0\0\0\0" .. "mccli\0"
  self:send_frame(payload)

  self:emit("connected")

  -- Request device time (for timestamps), contacts, and battery
  -- Channel names are fetched after contacts load (by caller) to avoid OOM
  self:get_device_time()
  self:get_contacts()
  self:get_battery()

  return true
end

-- Disconnect from the node
function Client:disconnect()
  if not self.connected then
    return
  end

  if self.sock then
    self.sock:close()
    self.sock = nil
  end

  self.connected = false
  self.recv_buf = ""

  self:emit("disconnected", "disconnected")
  collectgarbage("collect")
end

-- Send a framed payload: [0x3C][size:2 LE][payload]
function Client:send_frame(payload)
  if not self.sock or not self.connected then
    return false
  end

  local size = #payload
  if size > MAX_PAYLOAD then
    self:emit("error", "payload too large: " .. size)
    return false
  end

  local frame = string.pack("<BI2", FRAME_OUT, size) .. payload
  local sent, err = self.sock:send(frame)
  if not sent then
    self:emit("error", "send failed: " .. (err or "unknown"))
    return false
  end

  return true
end

-- Try to receive one complete frame (non-blocking)
-- Returns payload string or nil
function Client:recv_frame()
  -- Check if buffer already contains a complete frame before reading more.
  -- Without this guard, each call reads 303 bytes but only extracts ~151,
  -- causing recv_buf to grow unboundedly during data floods (e.g. contacts).
  local have_frame = false
  if #self.recv_buf >= 3 then
    local m = string.byte(self.recv_buf, 1)
    if m == FRAME_IN then
      local sz = string.unpack("<I2", self.recv_buf, 2)
      if sz <= MAX_PAYLOAD and #self.recv_buf >= 3 + sz then
        have_frame = true
      end
    end
  end

  if not have_frame and self.sock then
    self.sock:settimeout(self.recv_timeout)
    local chunk, err = self.sock:receive(303)
    if chunk then
      self.recv_buf = self.recv_buf .. chunk
    elseif err == "closed" or err == "connection closed" then
      self.connected = false
      self:emit("disconnected", "connection closed by node")
      return nil
    end
  end

  -- Need at least 3 bytes for header
  if #self.recv_buf < 3 then
    return nil
  end

  local marker = string.byte(self.recv_buf, 1)
  if marker ~= FRAME_IN then
    -- Try to find next frame marker
    local pos = self.recv_buf:find(string.char(FRAME_IN), 2, true)
    if pos then
      self.recv_buf = self.recv_buf:sub(pos)
    else
      self.recv_buf = ""
    end
    return nil
  end

  local size = string.unpack("<I2", self.recv_buf, 2)
  if size > MAX_PAYLOAD then
    -- Bad frame, skip marker
    self.recv_buf = self.recv_buf:sub(2)
    return nil
  end

  -- Check if we have the full payload
  if #self.recv_buf < 3 + size then
    return nil
  end

  local payload = self.recv_buf:sub(4, 3 + size)
  self.recv_buf = self.recv_buf:sub(4 + size)

  return payload
end

-- Poll for incoming frames (non-blocking)
function Client:poll()
  if not self.connected then
    return false
  end

  local frame = self:recv_frame()
  local count = 0
  while frame do
    self:handle_packet(frame)
    count = count + 1
    collectgarbage("collect")
    if count >= 3 then break end
    frame = self:recv_frame()
  end

  return self.connected
end

-- Format raw data as hex string
function Client:hex_dump(data)
  local hex = {}
  for i = 2, #data do
    table.insert(hex, string.format("%02X", string.byte(data, i)))
  end
  return table.concat(hex, " ")
end

-- Dispatch a received packet by its first byte
function Client:handle_packet(data)
  if #data < 1 then return end

  local cmd = string.byte(data, 1)

  -- Debug: emit raw packet hex for all packets
  if self.debug then
    local name = PACKET_NAMES[cmd] or string.format("0x%02X", cmd)
    self:emit("debug_packet", name, cmd, data)
  end

  if cmd == RSP_OK then
    self:emit("resp_ok")
  elseif cmd == RSP_ERR then
    self:emit("error", "node returned error")
  elseif cmd == RSP_SELF_INFO then
    self:handle_self_info(data)
  elseif cmd == RSP_CONTACT_START then
    self:handle_contact_start(data)
  elseif cmd == RSP_CONTACT then
    self:handle_contact(data)
  elseif cmd == RSP_CONTACT_END then
    self:handle_contact_end(data)
  elseif cmd == RSP_MSG_SENT then
    self:handle_msg_sent(data)
  elseif cmd == RSP_CONTACT_MSG_V1 then
    self:handle_contact_msg(data, false)
  elseif cmd == RSP_CONTACT_MSG_V3 then
    self:handle_contact_msg(data, true)
  elseif cmd == RSP_CHANNEL_MSG_V1 then
    self:handle_channel_msg(data, false)
  elseif cmd == RSP_CHANNEL_MSG_V3 then
    self:handle_channel_msg(data, true)
  elseif cmd == RSP_CHANNEL_INFO then
    self:handle_channel_info(data)
  elseif cmd == RSP_CURR_TIME then
    self:handle_curr_time(data)
  elseif cmd == RSP_NO_MORE_MSGS then
    self:emit("no_more_msgs")
  elseif cmd == RSP_BATTERY then
    self:handle_battery(data)
  elseif cmd == PUSH_ACK then
    self:handle_ack(data)
  elseif cmd == PUSH_MSGS_WAITING then
    self:emit("msgs_waiting")
  elseif cmd == PUSH_LOGIN_SUCCESS then
    self:handle_login_success(data)
  elseif cmd == PUSH_LOGIN_FAILED then
    self:emit("login_failed")
  elseif cmd == PUSH_NEW_ADVERT then
    self:handle_new_advert(data)
  elseif cmd == PUSH_ADVERT then
    self:handle_advert(data)
  elseif self.debug or self.verbose then
    -- All remaining push types only need processing when debug or verbose.
    -- Skip entirely in default mode to avoid string allocation garbage.
    if cmd == PUSH_PATH_UPDATED then
      self:handle_path_updated(data)
    elseif cmd == PUSH_LOG_RX_DATA then
      self:handle_log_rx_data(data)
    elseif cmd == PUSH_STATUS_RESP then
      self:handle_status_resp(data)
    elseif cmd == PUSH_TELEMETRY then
      self:handle_telemetry(data)
    elseif cmd == PUSH_RAW_DATA then
      self:handle_raw_data(data)
    elseif cmd == PUSH_TRACE_DATA then
      self:handle_trace_data(data)
    elseif cmd == PUSH_CONTROL_DATA then
      self:handle_control_data(data)
    else
      self:emit("unknown_packet", cmd, data)
    end
  end
end

-- Handle SELF_INFO response
-- Layout: code(1) type(1) tx_power(1) max_tx(1) pubkey(32) lat(4) lon(4)
--         multi_acks(1) loc_policy(1) telemetry(1) manual_add(1)
--         freq(4) bw(4) sf(1) cr(1) name(var, null-terminated)
function Client:handle_self_info(data)
  if #data < 58 then return end

  self.self_pubkey = data:sub(5, 36)
  self.self_prefix = data:sub(5, 10)

  -- Name starts at byte 59 (offset 58)
  local name_start = 59
  if #data >= name_start then
    local name = data:sub(name_start)
    local null_pos = name:find("\0")
    if null_pos then
      name = name:sub(1, null_pos - 1)
    end
    self.self_name = name
  else
    self.self_name = "node"
  end

  self:emit("self_info", self.self_name, self.self_pubkey)
end

-- Handle CONTACT_START
function Client:handle_contact_start(data)
  self.contacts = {}
  self.prefix_map = {}
  collectgarbage("collect")
end

-- Handle CONTACT
function Client:handle_contact(data)
  if #data < 136 then return end
  if #self.contacts >= MAX_CONTACTS then return end

  local prefix = data:sub(2, 7)
  local ctype = string.byte(data, 34)
  local flags = string.byte(data, 35)
  local raw_name = data:sub(101, 132)
  local null_pos = raw_name:find("\0")
  if null_pos then
    raw_name = raw_name:sub(1, null_pos - 1)
  end
  raw_name = raw_name:gsub("%s+$", "")

  local lastmod = 0
  if #data >= 148 then
    lastmod = string.unpack("<I4", data, 145)
  end

  local idx = #self.contacts + 1
  self.contacts[idx] = {
    prefix = prefix,
    name = raw_name,
    type = ctype,
    flags = flags,
    lastmod = lastmod,
  }
  self.prefix_map[prefix] = idx

  collectgarbage("collect")
end

-- Handle CONTACT_END
function Client:handle_contact_end(data)
  if #data >= 5 then
    self.contacts_lastmod = string.unpack("<I4", data, 2)
  end
  -- Fallback time sync from contact lastmod timestamps
  self:sync_time_from_contacts()
  collectgarbage("collect")
  self:emit("contacts_loaded", #self.contacts)
end

-- Handle contact message (DM) - V1 and V3
function Client:handle_contact_msg(data, is_v3)
  local offset = 2
  if is_v3 then
    offset = offset + 3
  end

  if #data < offset + 12 then return end

  local prefix = data:sub(offset, offset + 5)
  offset = offset + 6
  local path_len = string.byte(data, offset)
  offset = offset + 1
  local txt_type = string.byte(data, offset)
  offset = offset + 1
  local ts = string.unpack("<I4", data, offset)
  offset = offset + 4
  local text = data:sub(offset)
  local null_pos = text:find("\0")
  if null_pos then
    text = text:sub(1, null_pos - 1)
  end
  text = text:gsub("[\r\n]+", " ")

  local sender = self:lookup_name(prefix)
  self:emit("dm_recv", sender, text, prefix, ts, path_len, txt_type)
end

-- Handle channel message - V1 and V3
function Client:handle_channel_msg(data, is_v3)
  local offset = 2
  if is_v3 then
    offset = offset + 3
  end

  if #data < offset + 7 then return end

  local ch_idx = string.byte(data, offset)
  offset = offset + 1
  local path_len = string.byte(data, offset)
  offset = offset + 1
  local txt_type = string.byte(data, offset)
  offset = offset + 1
  local ts = string.unpack("<I4", data, offset)
  offset = offset + 4
  local text = data:sub(offset)
  local null_pos = text:find("\0")
  if null_pos then
    text = text:sub(1, null_pos - 1)
  end
  text = text:gsub("[\r\n]+", " ")

  self:emit("channel_recv", ch_idx, text, ts, path_len, txt_type)
end

-- Handle MSG_SENT
function Client:handle_msg_sent(data)
  if #data < 2 then return end
  local msg_type = string.byte(data, 2)
  local expected_ack = 0
  local suggested_timeout = 0
  if #data >= 6 then
    expected_ack = string.unpack("<I4", data, 3)
  end
  if #data >= 10 then
    suggested_timeout = string.unpack("<I4", data, 7)
  end
  self:emit("msg_sent", msg_type, expected_ack, suggested_timeout)
end

-- Handle BATTERY
-- Layout: code(1) milli_volts(uint16 LE) used_kb(uint32) total_kb(uint32)
function Client:handle_battery(data)
  if #data >= 3 then
    local mv = string.unpack("<I2", data, 2)
    -- Convert millivolts to voltage string (e.g. 3850 -> "3.85v")
    self.battery_mv = mv
    self.battery_display = string.format("%.2fv", mv / 1000)
    self:emit("battery", mv)
  end
end

-- Handle ACK
function Client:handle_ack(data)
  if #data >= 5 then
    local ack_code = string.unpack("<I4", data, 2)
    self:emit("ack", ack_code)
  end
end

-- Handle LOGIN_SUCCESS
function Client:handle_login_success(data)
  if #data >= 8 then
    self.login_perms = string.byte(data, 2)
    self.login_prefix = data:sub(3, 8)
    self.logged_in = true
    self:emit("login_success", self.login_perms)
  end
end

-- Handle PUSH_ADVERT: code + pubkey(32)
-- Update lastmod on existing contacts; emit event in debug/verbose mode
function Client:handle_advert(data)
  if #data < 33 then return end
  local prefix = data:sub(2, 7)
  local idx = self.prefix_map[prefix]
  if idx and self.contacts[idx] then
    local ts = self:get_timestamp()
    if ts > 0 then
      self.contacts[idx].lastmod = ts
    end
  end
  if self.debug or self.verbose then
    local name = self:lookup_name(prefix)
    self:emit("advert", name)
  end
end

-- Handle PUSH_PATH_UPDATED: code + pubkey(32)
function Client:handle_path_updated(data)
  if #data < 33 then return end
  local prefix = data:sub(2, 7)
  local name = self:lookup_name(prefix)
  self:emit("path_updated", name)
end

-- Handle PUSH_NEW_ADVERT: same format as CONTACT
-- Add new contacts or update existing ones from full contact data
function Client:handle_new_advert(data)
  if #data < 136 then return end

  local prefix = data:sub(2, 7)
  local ctype = string.byte(data, 34)
  local flags = string.byte(data, 35)
  local raw_name = data:sub(101, 132)
  local null_pos = raw_name:find("\0")
  if null_pos then
    raw_name = raw_name:sub(1, null_pos - 1)
  end
  local name = raw_name:gsub("%s+$", "")

  local lastmod = 0
  if #data >= 148 then
    lastmod = string.unpack("<I4", data, 145)
  end
  -- Use current time if packet has no lastmod
  if lastmod == 0 then
    local ts = self:get_timestamp()
    if ts > 0 then lastmod = ts end
  end

  local idx = self.prefix_map[prefix]
  if idx and self.contacts[idx] then
    -- Update existing contact
    self.contacts[idx].name = name
    self.contacts[idx].type = ctype
    self.contacts[idx].flags = flags
    if lastmod > 0 then
      self.contacts[idx].lastmod = lastmod
    end
  elseif #self.contacts < MAX_CONTACTS then
    -- Add new contact
    idx = #self.contacts + 1
    self.contacts[idx] = {
      prefix = prefix,
      name = name,
      type = ctype,
      flags = flags,
      lastmod = lastmod,
    }
    self.prefix_map[prefix] = idx
  end

  -- Emit event for display
  local type_str = ""
  if ctype == 1 then type_str = " [C]"
  elseif ctype == 2 then type_str = " [R]"
  end
  self:emit("new_advert", name .. type_str)
end

-- Handle PUSH_STATUS_RESP: code + reserved + prefix(6) + data
function Client:handle_status_resp(data)
  if #data < 9 then return end
  local prefix = data:sub(3, 8)
  local name = self:lookup_name(prefix)
  local status = ""
  if #data > 8 then
    status = data:sub(9)
    local null_pos = status:find("\0")
    if null_pos then status = status:sub(1, null_pos - 1) end
  end
  self:emit("status_resp", name, status)
end

-- Handle PUSH_TELEMETRY: code + reserved + prefix(6) + LPP data
function Client:handle_telemetry(data)
  if #data < 9 then return end
  local prefix = data:sub(3, 8)
  local name = self:lookup_name(prefix)
  self:emit("telemetry_resp", name, #data - 8)
end

-- Handle PUSH_RAW_DATA: code + SNR + RSSI + reserved + payload
function Client:handle_raw_data(data)
  if #data < 4 then return end
  local snr = string.byte(data, 2)
  if snr > 127 then snr = snr - 256 end  -- signed
  local rssi = string.byte(data, 3)
  if rssi > 127 then rssi = rssi - 256 end  -- signed
  self:emit("raw_data", snr / 4.0, rssi, #data - 4)
end

-- Handle PUSH_TRACE_DATA: code + reserved + path_len + flags + tag(4) + auth(4)
function Client:handle_trace_data(data)
  if #data < 10 then return end
  local path_len = string.byte(data, 3)
  local flags = string.byte(data, 4)
  self:emit("trace_data", path_len, flags)
end

-- Handle PUSH_CONTROL_DATA: code + SNR + RSSI + path_len + [path] + payload
function Client:handle_control_data(data)
  if #data < 4 then return end
  local snr = string.byte(data, 2)
  if snr > 127 then snr = snr - 256 end
  local rssi = string.byte(data, 3)
  if rssi > 127 then rssi = rssi - 256 end
  local path_len = string.byte(data, 4)
  self:emit("control_data", snr / 4.0, rssi, path_len, #data)
end

-- Mesh on-wire payload type names (header bits 5-2)
local MESH_TYPES = {
  [0] = "REQ", [1] = "RESP", [2] = "TXT", [3] = "ACK",
  [4] = "ADVERT", [5] = "GRP_TXT", [6] = "RAW",
  [7] = "GRP_DATA", [8] = "PATH",
}

-- Handle PUSH_LOG_RX_DATA: code + SNR + RSSI + raw mesh packet
function Client:handle_log_rx_data(data)
  if #data < 4 then return end

  local snr = string.byte(data, 2)
  if snr > 127 then snr = snr - 256 end
  local rssi = string.byte(data, 3)
  if rssi > 127 then rssi = rssi - 256 end

  -- Parse mesh header byte
  local header = string.byte(data, 4)
  local payload_type = (header >> 2) & 0x0F
  local type_name = MESH_TYPES[payload_type] or string.format("T%d", payload_type)

  -- path_len follows header
  local path_len = 0
  if #data >= 5 then
    path_len = string.byte(data, 5)
  end

  -- Build path hash string
  local path_str = ""
  if path_len > 0 and #data >= 5 + path_len then
    local hashes = {}
    for i = 1, path_len do
      table.insert(hashes, string.format("%02X", string.byte(data, 5 + i)))
    end
    path_str = table.concat(hashes, ">")
  end

  -- Payload starts after header(1) + path_len(1) + path(path_len)
  local payload_start = 6 + path_len
  local payload_size = math.max(0, #data - payload_start + 1)

  -- For ADVERT, extract node name (follows 0xFA marker near end)
  local name = nil
  if payload_type == 4 and #data > payload_start + 10 then
    for i = #data - 2, payload_start, -1 do
      if string.byte(data, i) == 0xFA then
        local raw = data:sub(i + 1)
        local null_pos = raw:find("\0")
        if null_pos then raw = raw:sub(1, null_pos - 1) end
        if #raw >= 2 then name = raw end
        break
      end
    end
  end

  self:emit("log_rx_data", snr / 4.0, rssi, type_name, path_len, path_str, payload_size, name)
end

-- Handle CURR_TIME response
function Client:handle_curr_time(data)
  if #data >= 5 then
    local node_epoch = string.unpack("<I4", data, 2)
    if node_epoch > 1000000000 then  -- sanity check: after ~2001
      self.node_time_base = node_epoch
      self.clock_base = os.clock()
      self.picocalc_clock_offset = node_epoch - os.time()
      self.time_synced = true
      self:emit("time_synced", node_epoch)
    end
  end
end

-- Sync time from contacts lastmod as fallback
function Client:sync_time_from_contacts()
  if self.time_synced then return end
  local max_lastmod = 0
  for _, contact in ipairs(self.contacts) do
    if contact.lastmod > max_lastmod then
      max_lastmod = contact.lastmod
    end
  end
  if max_lastmod > 1000000000 then  -- sanity check
    self.node_time_base = max_lastmod
    self.clock_base = os.clock()
    self.picocalc_clock_offset = max_lastmod - os.time()
    self.time_synced = true
    self:emit("time_synced", max_lastmod)
  end
end

-- Get current timestamp using node's clock + elapsed time
function Client:get_timestamp()
  if self.time_synced then
    local elapsed = os.clock() - self.clock_base
    return math.floor(self.node_time_base + elapsed)
  end
  return 0
end

-- Estimate current epoch using os.time() + offset from node sync
function Client:estimated_time()
  if self.time_synced then
    return os.time() + self.picocalc_clock_offset
  end
  return 0
end

-- Request device time from node
function Client:get_device_time()
  local payload = string.pack("B", CMD_GET_DEVICE_TIME)
  return self:send_frame(payload)
end

-- Send a direct message to a contact
function Client:send_dm(contact_idx, text)
  local contact = self.contacts[contact_idx]
  if not contact then
    self:emit("error", "invalid contact index")
    return false
  end

  local ts = self:get_timestamp()
  local prefix = contact.prefix
  local payload = string.pack("<BBB I4", CMD_SEND_TXT_MSG, 0x00, 0x00, ts) .. prefix .. text
  return self:send_frame(payload)
end

-- Send a channel message
function Client:send_channel_msg(ch_idx, text)
  local ts = self:get_timestamp()
  local payload = string.pack("<BBB I4", CMD_SEND_CHAN_MSG, 0x00, ch_idx, ts) .. text
  return self:send_frame(payload)
end

-- Send SYNC_NEXT_MESSAGE request
function Client:sync_next_message()
  local payload = string.pack("B", CMD_SYNC_NEXT_MSG)
  return self:send_frame(payload)
end

-- Request contact list
function Client:get_contacts()
  local payload = string.pack("<B I4", CMD_GET_CONTACTS, self.contacts_lastmod)
  return self:send_frame(payload)
end

-- Request battery status
function Client:get_battery()
  local payload = string.pack("B", CMD_GET_BATT)
  return self:send_frame(payload)
end

-- Request a single channel's info
function Client:get_channel(idx)
  local payload = string.pack("BB", CMD_GET_CHANNEL, idx)
  return self:send_frame(payload)
end

-- Request all 8 channels
function Client:get_all_channels()
  for i = 0, 7 do
    self:get_channel(i)
  end
end

-- Handle RSP_CHANNEL_INFO: code(1) + channel_idx(1) + name(32, null-padded) + secret(16)
function Client:handle_channel_info(data)
  if #data < 34 then return end
  local idx = string.byte(data, 2)
  local raw_name = data:sub(3, 34)
  local null_pos = raw_name:find("\0")
  if null_pos then raw_name = raw_name:sub(1, null_pos - 1) end
  raw_name = raw_name:gsub("%s+$", "")
  if raw_name ~= "" then
    self.channel_names[idx] = raw_name
  end
  self:emit("channel_info", idx, raw_name)
end

-- Return a display label for a channel: "0:Public" or just "3"
function Client:channel_label(idx)
  local name = self.channel_names[idx]
  if name then
    return idx .. ":" .. name
  end
  return tostring(idx)
end

-- Login with password (uses self_pubkey from SELF_INFO)
function Client:login(password)
  if not self.self_pubkey then
    self:emit("error", "no self info yet, cannot login")
    return false
  end
  local payload = string.pack("B", CMD_SEND_LOGIN) .. self.self_pubkey .. password
  return self:send_frame(payload)
end

-- Logout
function Client:logout()
  if not self.self_pubkey then
    return false
  end
  self.logged_in = false
  local payload = string.pack("B", CMD_LOGOUT) .. self.self_pubkey
  return self:send_frame(payload)
end

-- Look up contact name by 6-byte prefix
function Client:lookup_name(prefix6)
  local idx = self.prefix_map[prefix6]
  if idx and self.contacts[idx] then
    return self.contacts[idx].name
  end
  return string.format("%02x%02x%02x%02x%02x%02x",
    string.byte(prefix6, 1), string.byte(prefix6, 2),
    string.byte(prefix6, 3), string.byte(prefix6, 4),
    string.byte(prefix6, 5), string.byte(prefix6, 6))
end

-- Find a contact index by 6-byte prefix
function Client:find_by_prefix(prefix6)
  return self.prefix_map[prefix6]
end

return Client
