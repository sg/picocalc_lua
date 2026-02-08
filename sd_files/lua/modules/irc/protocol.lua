--[[

  irc/protocol.lua - IRC Protocol Parser

  Handles IRC message parsing and formatting according to RFC 1459/2812.

  Message format: [:<prefix>] <command> [<params>] [:<trailing>]

  Usage:
    local protocol = require("lua/modules/irc/protocol")

    local msg = protocol.parse(":nick!user@host PRIVMSG #channel :Hello!")
    -- msg.prefix = "nick!user@host"
    -- msg.nick = "nick"
    -- msg.command = "PRIVMSG"
    -- msg.params = {"#channel"}
    -- msg.trailing = "Hello!"

    local line = protocol.format("PRIVMSG", "#channel", "Hello!")
    -- line = "PRIVMSG #channel :Hello!\r\n"

]]

local protocol = {}

protocol._VERSION = "1.0"

-- Note: Removed large numerics lookup table to save memory
-- Numeric codes are handled directly by code number where needed

-- Parse an IRC message line
-- Returns: { prefix, nick, user, host, command, params, trailing, raw }
function protocol.parse(line)
  if not line or line == "" then
    return nil
  end

  local msg = {
    prefix = nil,
    nick = nil,
    user = nil,
    host = nil,
    command = nil,
    params = {},
    trailing = nil,
    raw = line,
  }

  local pos = 1
  local len = #line

  -- Parse optional prefix (starts with :)
  if line:sub(1, 1) == ":" then
    local space = line:find(" ", 2)
    if not space then
      return nil  -- malformed
    end
    msg.prefix = line:sub(2, space - 1)
    pos = space + 1

    -- Parse nick!user@host from prefix
    local nick, user, host = msg.prefix:match("^([^!]+)!([^@]+)@(.+)$")
    if nick then
      msg.nick = nick
      msg.user = user
      msg.host = host
    else
      -- Try nick@host format
      nick, host = msg.prefix:match("^([^@]+)@(.+)$")
      if nick then
        msg.nick = nick
        msg.host = host
      else
        -- Just server name or nick
        msg.nick = msg.prefix
      end
    end
  end

  -- Skip leading spaces
  while pos <= len and line:sub(pos, pos) == " " do
    pos = pos + 1
  end

  -- Parse command
  local cmd_end = line:find(" ", pos)
  if cmd_end then
    msg.command = line:sub(pos, cmd_end - 1):upper()
    pos = cmd_end + 1
  else
    msg.command = line:sub(pos):upper()
    return msg
  end

  -- Parse parameters
  while pos <= len do
    -- Skip spaces
    while pos <= len and line:sub(pos, pos) == " " do
      pos = pos + 1
    end

    if pos > len then
      break
    end

    -- Check for trailing (starts with :)
    if line:sub(pos, pos) == ":" then
      msg.trailing = line:sub(pos + 1)
      break
    end

    -- Regular parameter
    local param_end = line:find(" ", pos)
    if param_end then
      table.insert(msg.params, line:sub(pos, param_end - 1))
      pos = param_end + 1
    else
      table.insert(msg.params, line:sub(pos))
      break
    end
  end

  return msg
end

-- Format an outgoing IRC command
-- Usage: protocol.format("PRIVMSG", "#channel", "Hello world")
-- Returns: "PRIVMSG #channel :Hello world\r\n"
function protocol.format(command, ...)
  local args = {...}
  local parts = {command:upper()}

  for i, arg in ipairs(args) do
    if arg and arg ~= "" then
      -- Last argument with spaces needs : prefix
      if i == #args and (arg:find(" ") or arg:sub(1, 1) == ":") then
        table.insert(parts, ":" .. arg)
      else
        table.insert(parts, arg)
      end
    end
  end

  return table.concat(parts, " ") .. "\r\n"
end

-- CTCP delimiter character
local CTCP_DELIM = "\001"

-- Encode a CTCP message
-- Usage: protocol.ctcp_encode("ACTION", "waves")
-- Returns: "\001ACTION waves\001"
function protocol.ctcp_encode(command, text)
  if text and text ~= "" then
    return CTCP_DELIM .. command:upper() .. " " .. text .. CTCP_DELIM
  else
    return CTCP_DELIM .. command:upper() .. CTCP_DELIM
  end
end

-- Decode a CTCP message
-- Returns: command, text (or nil if not CTCP)
function protocol.ctcp_decode(message)
  if not message then
    return nil
  end

  -- Check for CTCP delimiters
  if message:sub(1, 1) ~= CTCP_DELIM or message:sub(-1) ~= CTCP_DELIM then
    return nil
  end

  -- Extract content between delimiters
  local content = message:sub(2, -2)
  local space = content:find(" ")

  if space then
    return content:sub(1, space - 1):upper(), content:sub(space + 1)
  else
    return content:upper(), nil
  end
end

-- Check if a message is a CTCP message
function protocol.is_ctcp(message)
  if not message then
    return false
  end
  return message:sub(1, 1) == CTCP_DELIM and message:sub(-1) == CTCP_DELIM
end

-- Check if a target is a channel (starts with # or &)
function protocol.is_channel(target)
  if not target or target == "" then
    return false
  end
  local first = target:sub(1, 1)
  return first == "#" or first == "&" or first == "+" or first == "!"
end

-- Parse mode changes into individual mode operations
-- Returns: list of { mode="+o" or "-v", param="nick" or nil }
function protocol.parse_modes(modes, params)
  local result = {}
  local param_idx = 1
  local sign = "+"

  -- Mode types that take parameters
  local param_modes = {
    o = true, v = true, h = true,  -- user modes in channel
    k = true, l = true,            -- channel key/limit
    b = true, e = true, I = true,  -- ban/exception/invite
  }

  for i = 1, #modes do
    local char = modes:sub(i, i)
    if char == "+" or char == "-" then
      sign = char
    else
      local entry = { mode = sign .. char }
      if param_modes[char] then
        if params and param_idx <= #params then
          entry.param = params[param_idx]
          param_idx = param_idx + 1
        end
      end
      table.insert(result, entry)
    end
  end

  return result
end

-- Extract channel from params (for channel messages)
function protocol.get_target(msg)
  if msg.params and #msg.params > 0 then
    return msg.params[1]
  end
  return nil
end

-- Get the text content from a message
function protocol.get_text(msg)
  return msg.trailing or (msg.params and msg.params[#msg.params])
end

-- Check if message is an error numeric
function protocol.is_error(msg)
  local code = tonumber(msg.command)
  if not code then
    return false
  end
  return code >= 400 and code < 600
end

-- Check if message is a reply numeric
function protocol.is_numeric(msg)
  return tonumber(msg.command) ~= nil
end

return protocol
