--[[

  irc.lua - IRC Client for PicoCalc

  A terminal-based IRC client with TLS support, SASL authentication,
  and multi-channel management.

  Usage:
    dofile("lua/irc.lua")

  Or from shell:
    irc [server] [port] [nick]

  Commands:
    /connect [server] [port]  - Connect to server
    /disconnect [message]     - Disconnect from server
    /quit [message]           - Exit IRC client
    /join <channel> [key]     - Join a channel
    /part [channel] [message] - Leave a channel
    /msg <target> <message>   - Send private message
    /me <action>              - Send action message
    /nick <newnick>           - Change nickname
    /topic [channel] [topic]  - View/set topic
    /names [channel]          - List users in channel
    /whois <nick>             - Get user info
    /list [pattern]           - List channels
    /switch <channel>         - Switch to channel
    /w <channel>              - Alias for /switch
    /1, /2, ...               - Switch to channel by number
    /clear                    - Clear message buffer
    /raw <command>            - Send raw IRC command
    /help [command]           - Show help
    /away [message]           - Set away status
    /back                     - Clear away status

]]

local Client = require("lua/modules/irc/client")
local UI = require("lua/modules/irc/ui")

-- Debug logging (set to true to enable debug log file)
local DEBUG_ENABLED = true
local Debug = nil
if DEBUG_ENABLED then
  Debug = require("lua/modules/irc/debug")
  Debug.init("irc_debug.log")
  Client.set_debug(Debug)
  UI.set_debug(Debug)
end

-- Default configuration
local config = {
  server = "irc.libera.chat",
  port = 6697,
  nick = "SteveG",
  user = "steveg",
  realname = "PicoCalc IRC Client",
  use_tls = true,
  sasl_user = nil,
  sasl_pass = nil,
}

-- Command handlers
local commands = {}

-- Help text for commands
local help = {
  connect = "/connect [server] [port] - Connect to IRC server",
  disconnect = "/disconnect [message] - Disconnect from server",
  quit = "/quit [message] - Exit IRC client",
  join = "/join <channel> [key] - Join a channel",
  part = "/part [channel] [message] - Leave current or specified channel",
  msg = "/msg <target> <message> - Send private message",
  me = "/me <action> - Send action message (e.g., /me waves)",
  nick = "/nick <newnick> - Change your nickname",
  topic = "/topic [channel] [topic] - View or set channel topic",
  names = "/names [channel] - List users in channel",
  whois = "/whois <nick> - Get information about a user",
  list = "/list [pattern] - List available channels",
  switch = "/switch <channel> - Switch to a joined channel",
  w = "/w <channel> - Alias for /switch",
  clear = "/clear - Clear message buffer",
  raw = "/raw <command> - Send raw IRC command",
  away = "/away [message] - Set away status",
  back = "/back - Clear away status",
  kick = "/kick <user> [reason] - Kick user from channel",
  ban = "/ban <mask> - Ban user from channel",
  unban = "/unban <mask> - Remove ban",
  op = "/op <nick> - Give operator status",
  deop = "/deop <nick> - Remove operator status",
  voice = "/voice <nick> - Give voice status",
  devoice = "/devoice <nick> - Remove voice status",
  mode = "/mode <modes> [args] - Set channel/user modes",
  invite = "/invite <nick> [channel] - Invite user to channel",
  ctcp = "/ctcp <nick> <command> - Send CTCP query",
  ping = "/ping <nick> - Ping a user",
  version = "/version <nick> - Request client version",
  help = "/help [command] - Show help for command",
  buffer = "/buffer [on|off] - Toggle PSRAM buffer mode for screenshots",
}

-- Parse command line arguments
local function parse_args(args)
  if args and #args > 0 then
    config.server = args[1] or config.server
    config.port = tonumber(args[2]) or config.port
    config.nick = args[3] or config.nick
  end
end

-- Command implementations
commands.connect = function(client, ui, args)
  if client.connected then
    ui:add_error("Already connected. Use /disconnect first.")
    return
  end

  if args[1] then
    config.server = args[1]
  end
  if args[2] then
    config.port = tonumber(args[2]) or config.port
  end

  client.server = config.server
  client.port = config.port

  ui:add_system("Connecting to " .. config.server .. ":" .. config.port .. "...")

  local ok, err = client:connect()
  if not ok then
    ui:add_error("Connection failed: " .. (err or "unknown"))
  end
end

commands.disconnect = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local message = table.concat(args, " ")
  if message == "" then
    message = "Leaving"
  end

  client:disconnect(message)
  ui:add_system("Disconnected.")
end

commands.quit = function(client, ui, args)
  local message = table.concat(args, " ")
  if message == "" then
    message = "Goodbye"
  end

  if client.connected then
    client:disconnect(message)
  end

  return "quit"
end

commands.join = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /join <channel> [key]")
    return
  end

  local channel = args[1]
  if not channel:match("^[#&]") then
    channel = "#" .. channel
  end

  local key = args[2]
  client:join(channel, key)
end

commands.part = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local channel = args[1]
  local message

  if channel and channel:match("^[#&]") then
    message = table.concat(args, " ", 2)
  else
    channel = client.current_channel
    message = table.concat(args, " ")
  end

  if not channel then
    ui:add_error("No channel to part.")
    return
  end

  client:part(channel, message ~= "" and message or nil)
end

commands.msg = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args < 2 then
    ui:add_error("Usage: /msg <target> <message>")
    return
  end

  local target = args[1]
  local message = table.concat(args, " ", 2)
  client:privmsg(target, message)

  -- Show in UI
  ui:add_message(client.current_nick, message, "private", target)
end

commands.notice = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args < 2 then
    ui:add_error("Usage: /notice <target> <message>")
    return
  end

  local target = args[1]
  local message = table.concat(args, " ", 2)
  client:notice(target, message)
end

commands.me = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  local message = table.concat(args, " ")
  if message == "" then
    ui:add_error("Usage: /me <action>")
    return
  end

  client:action(client.current_channel, message)
  ui:add_message(client.current_nick, message, "action", client.current_channel)
end

commands.nick = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /nick <newnick>")
    return
  end

  client:change_nick(args[1])
end

commands.topic = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local channel = args[1]
  local topic

  if channel and channel:match("^[#&]") then
    topic = table.concat(args, " ", 2)
    if topic == "" then topic = nil end
  else
    channel = client.current_channel
    topic = table.concat(args, " ")
    if topic == "" then topic = nil end
  end

  if not channel then
    ui:add_error("No channel specified.")
    return
  end

  client:topic(channel, topic)
end

commands.names = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local channel = args[1] or client.current_channel
  if not channel then
    ui:add_error("No channel specified.")
    return
  end

  client:names(channel)
end

commands.whois = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /whois <nick>")
    return
  end

  client:whois(args[1])
end

commands.list = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local pattern = args[1]
  client:list(pattern)
end

commands.switch = function(client, ui, args)
  if #args == 0 then
    -- List channels
    if #client.channel_list == 0 then
      ui:add_system("No channels joined.")
    else
      ui:add_system("Joined channels:")
      for i, ch in ipairs(client.channel_list) do
        local marker = (ch == client.current_channel) and " *" or ""
        ui:add_system("  " .. i .. ". " .. ch .. marker)
      end
    end
    return
  end

  local channel = args[1]
  if not channel:match("^[#&]") then
    channel = "#" .. channel
  end

  if client:switch_channel(channel) then
    ui:add_system("Switched to " .. channel)
  else
    ui:add_error("Not in channel: " .. channel)
  end
end

commands.w = commands.switch

commands.clear = function(client, ui, args)
  ui:clear_messages()
  ui:add_system("Message buffer cleared.")
end

commands.raw = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local raw_cmd = table.concat(args, " ")
  if raw_cmd == "" then
    ui:add_error("Usage: /raw <command>")
    return
  end

  client:send_raw(raw_cmd .. "\r\n")
  ui:add_system("Sent: " .. raw_cmd)
end

commands.away = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local message = table.concat(args, " ")
  client:away(message ~= "" and message or nil)

  if message ~= "" then
    ui:add_system("You are now marked as away.")
  else
    ui:add_system("You are no longer marked as away.")
  end
end

commands.back = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  client:away()
  ui:add_system("You are no longer marked as away.")
end

commands.kick = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /kick <user> [reason]")
    return
  end

  local user = args[1]
  local reason = table.concat(args, " ", 2)
  client:kick(client.current_channel, user, reason ~= "" and reason or nil)
end

commands.ban = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /ban <mask>")
    return
  end

  client:mode(client.current_channel, "+b", args[1])
end

commands.unban = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /unban <mask>")
    return
  end

  client:mode(client.current_channel, "-b", args[1])
end

commands.op = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /op <nick>")
    return
  end

  client:mode(client.current_channel, "+o", args[1])
end

commands.deop = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /deop <nick>")
    return
  end

  client:mode(client.current_channel, "-o", args[1])
end

commands.voice = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /voice <nick>")
    return
  end

  client:mode(client.current_channel, "+v", args[1])
end

commands.devoice = function(client, ui, args)
  if not client.connected or not client.current_channel then
    ui:add_error("Not in a channel.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /devoice <nick>")
    return
  end

  client:mode(client.current_channel, "-v", args[1])
end

commands.mode = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /mode <modes> [args]")
    return
  end

  local target = client.current_channel or client.current_nick
  client:mode(target, table.unpack(args))
end

commands.invite = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /invite <nick> [channel]")
    return
  end

  local nick = args[1]
  local channel = args[2] or client.current_channel

  if not channel then
    ui:add_error("No channel specified.")
    return
  end

  client:invite(nick, channel)
  ui:add_system("Invited " .. nick .. " to " .. channel)
end

commands.ctcp = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args < 2 then
    ui:add_error("Usage: /ctcp <nick> <command> [args]")
    return
  end

  local nick = args[1]
  local cmd = args[2]:upper()
  local text = table.concat(args, " ", 3)
  client:ctcp(nick, cmd, text ~= "" and text or nil)
  ui:add_system("CTCP " .. cmd .. " sent to " .. nick)
end

commands.ping = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /ping <nick>")
    return
  end

  local timestamp = tostring(os.time())
  client:ctcp(args[1], "PING", timestamp)
  ui:add_system("PING sent to " .. args[1])
end

commands.version = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /version <nick>")
    return
  end

  client:ctcp(args[1], "VERSION", nil)
end

commands.buffer = function(client, ui, args)
  local mode = args[1]
  if mode == "on" or mode == "1" then
    if draw.enableBuffer(1) then
      _G._buffer_mode_blit = true
      term.clear()
      ui:invalidate()
      ui:add_system("PSRAM buffer mode enabled")
    else
      ui:add_error("Failed to enable buffer mode")
    end
  elseif mode == "off" or mode == "0" then
    _G._buffer_mode_blit = false
    draw.enableBuffer(0)
    ui:add_system("Direct mode enabled")
    ui:invalidate()
  else
    local status = _G._buffer_mode_blit and "ON (PSRAM)" or "OFF (Direct)"
    ui:add_system("Buffer mode: " .. status .. " - Usage: /buffer [on|off]")
  end
end

commands.help = function(client, ui, args)
  if #args == 0 then
    ui:add_system("Available commands:")
    local cmd_list = {}
    for cmd, _ in pairs(help) do
      table.insert(cmd_list, "/" .. cmd)
    end
    table.sort(cmd_list)
    ui:add_system(table.concat(cmd_list, ", "))
    ui:add_system("Use /help <command> for details.")
  else
    local cmd = args[1]:gsub("^/", "")
    if help[cmd] then
      ui:add_system(help[cmd])
    else
      ui:add_error("Unknown command: " .. cmd)
    end
  end
end

-- Handle channel switch by number
for i = 1, 9 do
  commands[tostring(i)] = function(client, ui, args)
    local channel = client:get_channel_by_index(i)
    if channel then
      client:switch_channel(channel)
      ui:add_system("Switched to " .. channel)
    else
      ui:add_error("No channel at position " .. i)
    end
  end
end

-- Process user input
local function process_input(client, ui, input)
  if not input or input == "" then
    return nil
  end

  -- Check for command
  if input:sub(1, 1) == "/" then
    local parts = {}
    for part in input:gmatch("%S+") do
      table.insert(parts, part)
    end

    local cmd = parts[1]:sub(2):lower()  -- remove leading /
    local args = {}
    for i = 2, #parts do
      table.insert(args, parts[i])
    end

    if commands[cmd] then
      return commands[cmd](client, ui, args)
    else
      ui:add_error("Unknown command: /" .. cmd .. ". Type /help for commands.")
    end
  else
    -- Regular message to current channel
    if not client.connected then
      ui:add_error("Not connected.")
      return nil
    end

    if not client.current_channel then
      ui:add_error("No channel selected. Use /join <channel>")
      return nil
    end

    client:privmsg(client.current_channel, input)
    ui:add_message(client.current_nick, input, "msg", client.current_channel)
  end

  return nil
end

-- Setup event handlers
local function setup_handlers(client, ui)
  client:on("connecting", function()
    ui:add_system("Connecting...")
  end)

  client:on("connected", function()
    ui:add_system("Connected to " .. client.server)
  end)

  client:on("registered", function()
    ui:add_system("Registered as " .. client.current_nick)
  end)

  client:on("disconnected", function(reason)
    ui:add_system("Disconnected: " .. (reason or ""))
  end)

  client:on("message", function(nick, channel, text)
    ui:add_message(nick, text, "msg", channel)
  end)

  client:on("private", function(nick, text)
    ui:add_message(nick, text, "private", nil)
  end)

  client:on("action", function(nick, channel, text)
    ui:add_message(nick, text, "action", channel)
  end)

  client:on("notice", function(nick, target, text)
    ui:add_message(nick, text, "notice", nil)
  end)

  client:on("join", function(nick, channel)
    if nick == client.current_nick then
      ui:add_system("You have joined " .. channel)
    else
      ui:add_message(nick, "", "join", channel)
    end
  end)

  client:on("part", function(nick, channel, reason)
    if nick == client.current_nick then
      ui:add_system("You have left " .. channel)
    else
      ui:add_message(nick, reason or "", "part", channel)
    end
  end)

  client:on("quit", function(nick, reason)
    ui:add_message(nick, reason or "", "quit", nil)
  end)

  client:on("kick", function(kicker, channel, target, reason)
    local msg = target .. " was kicked by " .. kicker
    if reason and reason ~= "" then
      msg = msg .. " (" .. reason .. ")"
    end
    ui:add_message("", msg, "kick", channel)
  end)

  client:on("nick", function(old_nick, new_nick)
    ui:add_message(old_nick, new_nick, "nick", nil)
  end)

  client:on("topic", function(nick, channel, topic)
    if nick and nick ~= "" then
      ui:add_system(nick .. " changed the topic to: " .. topic)
    end
  end)

  client:on("topic_reply", function(channel, topic)
    ui:add_message("", topic, "topic", channel)
  end)

  client:on("channel_switched", function(channel)
    ui:invalidate()
  end)

  client:on("nick_in_use", function(nick)
    ui:add_error("Nickname " .. nick .. " is already in use.")
  end)

  client:on("sasl_success", function()
    ui:add_system("SASL authentication successful.")
  end)

  client:on("sasl_fail", function(reason)
    ui:add_error("SASL authentication failed: " .. (reason or "unknown"))
  end)

  client:on("ctcp", function(nick, command, text)
    ui:add_system("CTCP " .. command .. " from " .. nick .. (text and (": " .. text) or ""))
  end)

  client:on("error", function(msg)
    ui:add_error(msg)
  end)

  client:on("numeric", function(code, params, trailing)
    -- Show some informational numerics
    -- Note: MOTD (372, 375, 376) skipped to save memory
    -- Note: NAMES list (353) skipped - too much data, would cause OOM
    -- We display a summary when NAMES ends (366) instead
    if code == 366 then
      -- End of NAMES list - show summary
      local channel = params[2]
      local count = client:get_user_count(channel)
      if count > 0 then
        ui:add_system(channel .. ": " .. count .. " users")
      end
    elseif code >= 400 and code < 600 then
      -- Error numerics
      ui:add_error("[" .. code .. "] " .. (trailing or table.concat(params, " ")))
    end
  end)
end

-- Main function
local function main(args)
  parse_args(args)

  if Debug then
    Debug.mem("main_start")
  end

  -- Create client and UI
  local client = Client.new(config)

  if Debug then
    Debug.mem("post_client_new")
  end

  local ui = UI.new(client)

  if Debug then
    Debug.mem("post_ui_new")
  end

  -- Setup handlers
  setup_handlers(client, ui)

  if Debug then
    Debug.mem("post_handlers")
  end

  -- Initialize UI
  ui:init()
  ui:add_system("PicoCalc IRC Client")
  ui:add_system("Type /help for commands, /quit to exit.")
  ui:add_system("")

  -- Auto-connect
  ui:add_system("Connecting to " .. config.server .. ":" .. config.port .. "...")

  -- IMPORTANT: Refresh UI before connect to show initial messages
  -- This fixes the blocking display issue (Option C)
  ui:refresh()

  local ok, err = client:connect()
  if not ok then
    ui:add_error("Connection failed: " .. (err or "unknown"))
    ui:add_system("Use /connect to try again.")
  end

  if Debug then
    Debug.mem("entering_main_loop")
  end

  -- Main loop
  local running = true
  local gc_counter = 0
  while running do
    -- IMPORTANT: Refresh UI BEFORE checking input (Option C fix)
    -- This ensures screen updates are visible before we potentially block
    ui:refresh()

    -- Poll for IRC messages
    if client.connected then
      client:poll()
    end

    -- Check for user input (non-blocking)
    local input = ui:check_input()
    if input then
      if input == "quit" then
        running = false
      elseif input ~= "scroll_up" and input ~= "scroll_down" then
        local result = process_input(client, ui, input)
        if result == "quit" then
          running = false
        end
      end
    end

    gc_counter = gc_counter + 1
    if gc_counter >= 20 then
      collectgarbage()
      if Debug then
        Debug.mem("gc_cycle")
      end
      gc_counter = 0
    end
  end

  -- Cleanup
  if client.connected then
    client:disconnect("Goodbye")
  end
  ui:cleanup()

  -- Close debug log
  if Debug then
    Debug.mem("cleanup")
    Debug.close()
  end

  -- Final cleanup to free memory
  collectgarbage()
  print("IRC client closed.")
end

-- Check for command line arguments or run directly
if arg then
  main(arg)
else
  main({})
end
