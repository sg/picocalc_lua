--[[

  irc/client.lua - IRC Client Connection Manager

  Handles socket connection, message buffering, and command sending.

  Usage:
    local Client = require("lua/modules/irc/client")
    local client = Client.new({
      server = "irc.libera.chat",
      port = 6697,
      nick = "PicoUser",
      use_tls = true,
    })

    client:on("message", function(nick, channel, text)
      print(nick .. ": " .. text)
    end)

    client:connect()
    while client.connected do
      client:poll()
    end

]]

local protocol = require("lua/modules/irc/protocol")
-- base64 loaded on-demand for SASL to save memory
local base64 = nil
-- Debug logger (set externally)
local Debug = nil

local Client = {}
Client.__index = Client

-- Set debug logger (called from main irc.lua)
function Client.set_debug(debug_module)
  Debug = debug_module
end

-- Create a new IRC client instance
function Client.new(options)
  options = options or {}

  local self = setmetatable({
    -- Connection settings
    server = options.server or "irc.libera.chat",
    port = options.port or 6697,
    use_tls = options.use_tls ~= false,  -- default true

    -- User settings
    nick = options.nick or "PicoUser",
    user = options.user or "picocalc",
    realname = options.realname or "PicoCalc IRC Client",

    -- SASL settings
    sasl_user = options.sasl_user,
    sasl_pass = options.sasl_pass,

    -- State
    sock = nil,
    buffer = "",
    connected = false,
    registered = false,

    -- Current nick (may change if initial nick is taken)
    current_nick = options.nick or "PicoUser",

    -- Channel state: { ["#channel"] = { users = {}, topic = "", modes = "" } }
    channels = {},
    current_channel = nil,
    channel_list = {},  -- ordered list of channel names

    -- Event callbacks
    callbacks = {},

    -- Rate limiting
    last_send_time = 0,
    send_queue = {},
    rate_limit = 0.5,  -- seconds between messages

    -- SASL state
    sasl_in_progress = false,
    cap_negotiating = false,

    -- Connection timeout
    connect_timeout = 30000,  -- 30 seconds
    recv_timeout = 0.05,      -- 50ms for non-blocking receive
  }, Client)

  return self
end

-- Register event callback
function Client:on(event, callback)
  if not self.callbacks[event] then
    self.callbacks[event] = {}
  end
  table.insert(self.callbacks[event], callback)
end

-- Emit event to callbacks
function Client:emit(event, ...)
  local callbacks = self.callbacks[event]
  if callbacks then
    for _, callback in ipairs(callbacks) do
      callback(...)
    end
  end
end

-- Connect to the IRC server
function Client:connect()
  if self.connected then
    return false, "already connected"
  end

  if Debug then
    Debug.mem("pre_connect")
  end

  -- Create socket - collect garbage first to maximize available memory
  collectgarbage("collect")

  if Debug then
    Debug.mem("post_gc")
  end

  local sock, err

  if self.use_tls then
    sock, err = socket.tls()
  else
    sock, err = socket.tcp()
  end

  if not sock then
    return false, "failed to create socket: " .. (err or "unknown")
  end

  self.sock = sock

  if Debug then
    Debug.mem("post_socket")
    Debug.log("CONNECT", "connecting to " .. self.server .. ":" .. self.port)
  end

  -- Connect with timeout
  local ok, conn_err = sock:connect(self.server, self.port, self.connect_timeout)
  if not ok then
    sock:close()
    self.sock = nil
    return false, "connection failed: " .. (conn_err or "unknown")
  end

  if Debug then
    Debug.mem("post_connect")
  end

  self.connected = true
  self.buffer = ""
  self.current_nick = self.nick

  self:emit("connecting")

  -- Start registration
  if self.sasl_user and self.sasl_pass then
    -- Request SASL capability
    self:send_raw("CAP LS 302")
  else
    -- Direct registration
    self:send_raw(protocol.format("NICK", self.nick))
    self:send_raw(protocol.format("USER", self.user, "0", "*", self.realname))
  end

  return true
end

-- Disconnect from the server
function Client:disconnect(message)
  if not self.connected then
    return
  end

  message = message or "Goodbye"
  self:send_raw(protocol.format("QUIT", message))

  if self.sock then
    self.sock:close()
    self.sock = nil
  end

  self.connected = false
  self.registered = false
  self.channels = {}
  self.channel_list = {}
  self.current_channel = nil

  self:emit("disconnected", message)
  collectgarbage("collect")  -- free memory after disconnect
end

-- Send raw data to server
function Client:send_raw(data)
  if not self.sock or not self.connected then
    return false
  end

  -- Ensure data ends with CRLF
  if not data:match("\r\n$") then
    data = data .. "\r\n"
  end

  if Debug then
    Debug.irc_out(data)
    Debug.mem("send")
  end

  local sent, err = self.sock:send(data)
  if not sent then
    self:emit("error", "send failed: " .. (err or "unknown"))
    return false
  end

  self:emit("raw_send", data:gsub("\r\n$", ""))
  return true
end

-- Send command with rate limiting
function Client:send(command, ...)
  local msg = protocol.format(command, ...)

  local now = os.clock()
  if now - self.last_send_time < self.rate_limit then
    table.insert(self.send_queue, msg)
    return true
  end

  self.last_send_time = now
  return self:send_raw(msg)
end

-- Process send queue
function Client:process_queue()
  if #self.send_queue == 0 then
    return
  end

  local now = os.clock()
  if now - self.last_send_time >= self.rate_limit then
    local msg = table.remove(self.send_queue, 1)
    self.last_send_time = now
    self:send_raw(msg)
  end
end

-- Receive one complete line (handles fragmentation)
function Client:receive_line()
  -- Check buffer for complete line
  local crlf = self.buffer:find("\r\n")
  if crlf then
    local line = self.buffer:sub(1, crlf - 1)
    self.buffer = self.buffer:sub(crlf + 2)
    return line
  end

  -- Try to receive more data (non-blocking)
  if not self.sock then
    return nil
  end

  self.sock:settimeout(self.recv_timeout)
  local chunk, err = self.sock:receive(512)

  if chunk then
    self.buffer = self.buffer .. chunk
    -- Check again for complete line
    crlf = self.buffer:find("\r\n")
    if crlf then
      local line = self.buffer:sub(1, crlf - 1)
      self.buffer = self.buffer:sub(crlf + 2)
      return line
    end
  elseif err == "closed" or err == "connection closed" then
    self.connected = false
    self:emit("disconnected", "connection closed by server")
  end

  return nil
end

-- Poll for incoming messages (non-blocking)
function Client:poll()
  if not self.connected then
    return false
  end

  -- Process outgoing queue
  self:process_queue()

  -- Process incoming messages with memory management
  local line = self:receive_line()
  local msg_count = 0
  while line do
    self:handle_line(line)
    msg_count = msg_count + 1

    -- Run GC every 5 messages during heavy traffic to prevent OOM
    if msg_count % 5 == 0 then
      collectgarbage("collect")
      if Debug then
        Debug.mem("poll_gc_" .. msg_count)
      end
    end

    line = self:receive_line()
  end

  return self.connected
end

-- Handle a received line
function Client:handle_line(line)
  if Debug then
    Debug.irc_in(line)
    Debug.mem("recv")
  end

  self:emit("raw_recv", line)

  local msg = protocol.parse(line)
  if not msg then
    return
  end

  self:emit("raw", msg)

  -- Handle specific commands
  local handler = self["handle_" .. msg.command:lower()]
  if handler then
    handler(self, msg)
  elseif protocol.is_numeric(msg) then
    self:handle_numeric(msg)
  end
end

-- Handle PING
function Client:handle_ping(msg)
  local server = msg.trailing or (msg.params and msg.params[1])
  self:send_raw("PONG :" .. (server or ""))
  self:emit("ping", server)
end

-- Handle CAP (capability negotiation)
function Client:handle_cap(msg)
  local subcommand = msg.params[2]

  if subcommand == "LS" then
    local caps = msg.trailing or msg.params[3] or ""
    self.cap_negotiating = true

    if caps:find("sasl") and self.sasl_user and self.sasl_pass then
      self:send_raw("CAP REQ :sasl")
    else
      self:send_raw("CAP END")
      self.cap_negotiating = false
      -- Continue with registration
      self:send_raw(protocol.format("NICK", self.nick))
      self:send_raw(protocol.format("USER", self.user, "0", "*", self.realname))
    end

  elseif subcommand == "ACK" then
    local ack_caps = msg.trailing or msg.params[3] or ""
    if ack_caps:find("sasl") then
      self:send_raw("AUTHENTICATE PLAIN")
      self.sasl_in_progress = true
    end

  elseif subcommand == "NAK" then
    self:send_raw("CAP END")
    self.cap_negotiating = false
    self:send_raw(protocol.format("NICK", self.nick))
    self:send_raw(protocol.format("USER", self.user, "0", "*", self.realname))
  end
end

-- Handle AUTHENTICATE
function Client:handle_authenticate(msg)
  if msg.params[1] == "+" then
    -- Lazy-load base64 only when SASL is actually used
    if not base64 then
      base64 = require("lua/modules/base64")
    end
    -- Server is ready, send credentials
    local credentials = self.sasl_user .. "\0" .. self.sasl_user .. "\0" .. self.sasl_pass
    local encoded = base64.encode(credentials)
    self:send_raw("AUTHENTICATE " .. encoded)
  end
end

-- Handle PRIVMSG
function Client:handle_privmsg(msg)
  local target = msg.params[1]
  local text = msg.trailing
  local nick = msg.nick

  -- Check for CTCP
  if protocol.is_ctcp(text) then
    local ctcp_cmd, ctcp_text = protocol.ctcp_decode(text)
    if ctcp_cmd == "ACTION" then
      self:emit("action", nick, target, ctcp_text)
    else
      self:emit("ctcp", nick, ctcp_cmd, ctcp_text)
      -- Auto-respond to common CTCP
      if ctcp_cmd == "VERSION" then
        self:notice(nick, protocol.ctcp_encode("VERSION", "PicoCalc IRC Client 1.0"))
      elseif ctcp_cmd == "PING" then
        self:notice(nick, protocol.ctcp_encode("PING", ctcp_text))
      end
    end
  else
    -- Regular message
    if protocol.is_channel(target) then
      self:emit("message", nick, target, text)
    else
      self:emit("private", nick, text)
    end
  end
end

-- Handle NOTICE
function Client:handle_notice(msg)
  local target = msg.params[1]
  local text = msg.trailing
  local nick = msg.nick or msg.prefix

  self:emit("notice", nick, target, text)
end

-- Handle JOIN
function Client:handle_join(msg)
  local channel = msg.trailing or msg.params[1]
  local nick = msg.nick

  if nick == self.current_nick then
    -- We joined a channel
    if not self.channels[channel] then
      self.channels[channel] = { users = {}, topic = "", modes = "", user_count = 0 }
      table.insert(self.channel_list, channel)
    end
    if not self.current_channel then
      self.current_channel = channel
    end
  else
    -- Someone else joined
    if self.channels[channel] then
      self.channels[channel].users[nick] = ""
      -- Increment user count
      self.channels[channel].user_count = (self.channels[channel].user_count or 0) + 1
    end
  end

  self:emit("join", nick, channel)
end

-- Handle PART
function Client:handle_part(msg)
  local channel = msg.params[1]
  local nick = msg.nick
  local reason = msg.trailing or ""

  if nick == self.current_nick then
    -- We left a channel
    self.channels[channel] = nil
    for i, ch in ipairs(self.channel_list) do
      if ch == channel then
        table.remove(self.channel_list, i)
        break
      end
    end
    if self.current_channel == channel then
      self.current_channel = self.channel_list[1]
    end
  else
    -- Someone else left
    if self.channels[channel] then
      self.channels[channel].users[nick] = nil
      -- Decrement user count
      if self.channels[channel].user_count and self.channels[channel].user_count > 0 then
        self.channels[channel].user_count = self.channels[channel].user_count - 1
      end
    end
  end

  self:emit("part", nick, channel, reason)
end

-- Handle QUIT
function Client:handle_quit(msg)
  local nick = msg.nick
  local reason = msg.trailing or ""

  -- Remove user from all channels and decrement count
  for _, channel_data in pairs(self.channels) do
    if channel_data.users[nick] then
      channel_data.users[nick] = nil
      if channel_data.user_count and channel_data.user_count > 0 then
        channel_data.user_count = channel_data.user_count - 1
      end
    end
  end

  self:emit("quit", nick, reason)
end

-- Handle KICK
function Client:handle_kick(msg)
  local channel = msg.params[1]
  local target = msg.params[2]
  local kicker = msg.nick
  local reason = msg.trailing or ""

  if target == self.current_nick then
    -- We were kicked
    self.channels[channel] = nil
    for i, ch in ipairs(self.channel_list) do
      if ch == channel then
        table.remove(self.channel_list, i)
        break
      end
    end
    if self.current_channel == channel then
      self.current_channel = self.channel_list[1]
    end
  else
    -- Someone else was kicked
    if self.channels[channel] then
      self.channels[channel].users[target] = nil
      -- Decrement user count
      if self.channels[channel].user_count and self.channels[channel].user_count > 0 then
        self.channels[channel].user_count = self.channels[channel].user_count - 1
      end
    end
  end

  self:emit("kick", kicker, channel, target, reason)
end

-- Handle NICK change
function Client:handle_nick(msg)
  local old_nick = msg.nick
  local new_nick = msg.trailing or msg.params[1]

  if old_nick == self.current_nick then
    self.current_nick = new_nick
  end

  -- Update nick in all channels
  for _, channel_data in pairs(self.channels) do
    local mode = channel_data.users[old_nick]
    if mode then
      channel_data.users[old_nick] = nil
      channel_data.users[new_nick] = mode
    end
  end

  self:emit("nick", old_nick, new_nick)
end

-- Handle MODE
function Client:handle_mode(msg)
  local target = msg.params[1]
  local modes = msg.params[2]
  local params = {}
  for i = 3, #msg.params do
    table.insert(params, msg.params[i])
  end

  if protocol.is_channel(target) and self.channels[target] then
    local parsed = protocol.parse_modes(modes, params)
    for _, mode_change in ipairs(parsed) do
      if mode_change.param then
        -- User mode change (+o, +v, etc.)
        local user = self.channels[target].users[mode_change.param]
        if user ~= nil then
          if mode_change.mode:sub(1, 1) == "+" then
            -- Add mode prefix
            local prefix = ""
            if mode_change.mode:sub(2) == "o" then prefix = "@"
            elseif mode_change.mode:sub(2) == "v" then prefix = "+"
            elseif mode_change.mode:sub(2) == "h" then prefix = "%"
            end
            if prefix ~= "" and not user:find(prefix, 1, true) then
              self.channels[target].users[mode_change.param] = prefix .. user
            end
          else
            -- Remove mode prefix
            local prefix = ""
            if mode_change.mode:sub(2) == "o" then prefix = "@"
            elseif mode_change.mode:sub(2) == "v" then prefix = "+"
            elseif mode_change.mode:sub(2) == "h" then prefix = "%"
            end
            if prefix ~= "" then
              self.channels[target].users[mode_change.param] = user:gsub(prefix, "")
            end
          end
        end
      end
    end
  end

  self:emit("mode", msg.nick, target, modes, params)
end

-- Handle TOPIC
function Client:handle_topic(msg)
  local channel = msg.params[1]
  local topic = msg.trailing or ""

  if self.channels[channel] then
    self.channels[channel].topic = topic
  end

  self:emit("topic", msg.nick, channel, topic)
end

-- Handle numeric responses
function Client:handle_numeric(msg)
  local code = tonumber(msg.command)
  if not code then
    return
  end

  -- RPL_WELCOME (001) - registration complete
  if code == 1 then
    self.registered = true
    self:emit("registered")
    self:emit("connected")

  -- RPL_TOPIC (332)
  elseif code == 332 then
    local channel = msg.params[2]
    local topic = msg.trailing or ""
    if self.channels[channel] then
      self.channels[channel].topic = topic
    end
    self:emit("topic_reply", channel, topic)

  -- RPL_NAMREPLY (353)
  elseif code == 353 then
    -- Format: <nick> = <channel> :[@+]nick1 [@+]nick2 ...
    local channel = msg.params[3]
    local names = msg.trailing or ""

    if self.channels[channel] then
      -- Count users by counting spaces + 1 (much more memory efficient than gmatch)
      local user_count = 1
      for i = 1, #names do
        if names:sub(i, i) == " " then
          user_count = user_count + 1
        end
      end
      -- Handle empty names list
      if names == "" then user_count = 0 end

      -- Update actual user count (accumulate since NAMES can come in multiple messages)
      self.channels[channel].user_count = (self.channels[channel].user_count or 0) + user_count

      -- Only store first 50 users total (skip if we already have enough)
      local stored_count = 0
      for _ in pairs(self.channels[channel].users) do
        stored_count = stored_count + 1
      end

      if stored_count < 50 then
        local max_users = 50
        for name in names:gmatch("%S+") do
          if stored_count >= max_users then break end
          local mode = name:match("^([@%%+]+)") or ""
          local nick = name:gsub("^[@%%+]+", "")
          self.channels[channel].users[nick] = mode
          stored_count = stored_count + 1
        end
      end
    end

  -- RPL_ENDOFNAMES (366)
  elseif code == 366 then
    local channel = msg.params[2]
    self:emit("names_end", channel)

  -- SASL success (903)
  elseif code == 903 then
    self.sasl_in_progress = false
    self:send_raw("CAP END")
    self.cap_negotiating = false
    self:send_raw(protocol.format("NICK", self.nick))
    self:send_raw(protocol.format("USER", self.user, "0", "*", self.realname))
    self:emit("sasl_success")

  -- SASL failure (904)
  elseif code == 904 then
    self.sasl_in_progress = false
    self:send_raw("CAP END")
    self.cap_negotiating = false
    self:emit("sasl_fail", msg.trailing)
    -- Continue with registration anyway
    self:send_raw(protocol.format("NICK", self.nick))
    self:send_raw(protocol.format("USER", self.user, "0", "*", self.realname))

  -- ERR_NICKNAMEINUSE (433)
  elseif code == 433 then
    if not self.registered then
      -- Try alternate nick during registration
      self.current_nick = self.nick .. "_"
      self:send_raw(protocol.format("NICK", self.current_nick))
    end
    self:emit("nick_in_use", msg.params[2])

  -- ERR_ERRONEUSNICKNAME (432)
  elseif code == 432 then
    self:emit("error", "Invalid nickname: " .. (msg.params[2] or ""))
  end

  -- Emit generic numeric event
  self:emit("numeric", code, msg.params, msg.trailing)
end

-- High-level commands

function Client:join(channel, key)
  if key then
    return self:send("JOIN", channel, key)
  else
    return self:send("JOIN", channel)
  end
end

function Client:part(channel, message)
  channel = channel or self.current_channel
  if not channel then
    return false
  end
  if message then
    return self:send("PART", channel, message)
  else
    return self:send("PART", channel)
  end
end

function Client:privmsg(target, message)
  return self:send("PRIVMSG", target, message)
end

function Client:notice(target, message)
  return self:send("NOTICE", target, message)
end

function Client:action(target, message)
  return self:privmsg(target, protocol.ctcp_encode("ACTION", message))
end

function Client:change_nick(new_nick)
  return self:send("NICK", new_nick)
end

function Client:quit(message)
  self:disconnect(message)
end

function Client:topic(channel, new_topic)
  channel = channel or self.current_channel
  if not channel then
    return false
  end
  if new_topic then
    return self:send("TOPIC", channel, new_topic)
  else
    return self:send("TOPIC", channel)
  end
end

function Client:kick(channel, user, reason)
  channel = channel or self.current_channel
  if not channel or not user then
    return false
  end
  if reason then
    return self:send("KICK", channel, user, reason)
  else
    return self:send("KICK", channel, user)
  end
end

function Client:mode(target, modes, ...)
  if modes then
    return self:send("MODE", target, modes, ...)
  else
    return self:send("MODE", target)
  end
end

function Client:whois(nick)
  return self:send("WHOIS", nick)
end

function Client:who(mask)
  return self:send("WHO", mask)
end

function Client:names(channel)
  channel = channel or self.current_channel
  if channel then
    return self:send("NAMES", channel)
  end
  return false
end

function Client:list(pattern)
  if pattern then
    return self:send("LIST", pattern)
  else
    return self:send("LIST")
  end
end

function Client:invite(nick, channel)
  channel = channel or self.current_channel
  if not channel or not nick then
    return false
  end
  return self:send("INVITE", nick, channel)
end

function Client:away(message)
  if message then
    return self:send("AWAY", message)
  else
    return self:send("AWAY")
  end
end

function Client:ctcp(target, command, text)
  return self:privmsg(target, protocol.ctcp_encode(command, text))
end

-- Switch to a different channel
function Client:switch_channel(channel)
  if self.channels[channel] then
    self.current_channel = channel
    self:emit("channel_switched", channel)
    return true
  end
  return false
end

-- Get channel by index (1-based)
function Client:get_channel_by_index(index)
  return self.channel_list[index]
end

-- Get user count in current channel (returns actual count, not limited stored users)
function Client:get_user_count(channel)
  channel = channel or self.current_channel
  if not channel or not self.channels[channel] then
    return 0
  end
  -- Return the actual user count from NAMES reply
  return self.channels[channel].user_count or 0
end

-- Get topic of channel
function Client:get_topic(channel)
  channel = channel or self.current_channel
  if not channel or not self.channels[channel] then
    return ""
  end
  return self.channels[channel].topic
end

return Client
