--[[

  mesh.lua - MeshCore Radio Client for PicoCalc

  A terminal-based mesh radio client that connects to a MeshCore
  companion radio node via TCP for messaging over LoRa mesh networks.

  Usage:
    dofile("lua/mesh.lua")

  Or from shell:
    mesh [host] [port]

  Commands:
    /connect [host] [port]  - Connect to node
    /disconnect             - Disconnect
    /quit                   - Exit client (or press Esc)
    /contacts               - Browse contact list
    /msg <name> <text>      - Send DM to contact
    /ch [idx] [text]        - Send channel msg or switch channel
    /target <name>          - Set default DM target
    /login <password>       - Authenticate with node
    /logout                 - Deauthenticate
    /battery                - Request battery status
    /sync                   - Manually fetch pending messages
    /clear                  - Clear message buffer
    /help                   - List commands

]]

local Client = require("lua/modules/mesh/client")
local UI = require("lua/modules/mesh/ui")
local emoji

-- Default configuration
local config = {
  host = "192.168.77.222",
  port = 5000,
  verbose = false,
}

-- Command handlers
local commands = {}

-- Help text
local help = {
  connect    = "/connect [host] [port] - Connect to MeshCore node",
  disconnect = "/disconnect - Disconnect from node",
  quit       = "/quit - Exit mesh client",
  contacts   = "/contacts - Browse contact list",
  msg        = "/msg <name> <text> - Send DM to contact by name or number",
  ch         = "/ch [idx] [text] - Send channel msg or switch channel",
  target     = "/target <name> - Set default DM target",
  login      = "/login <password> - Authenticate with node",
  logout     = "/logout - Deauthenticate",
  battery    = "/battery - Request battery status",
  sync       = "/sync - Manually fetch pending messages",
  clear      = "/clear - Clear message buffer",
  tz         = "/tz [hours] - Set timezone offset from UTC (e.g. -5 for EST)",
  help       = "/help [command] - Show help",
  buffer     = "/buffer [on|off] - Toggle PSRAM buffer mode for screenshots",
  export     = "/export <filename> - Export contacts to CSV file",
}

-- Sync drain state (managed here, not in client)
-- sync_draining: we want to pull all queued messages
-- sync_sent: we sent a SYNC and are waiting for the response
-- sync_got_msg: at least one message arrived since last SYNC was sent
local sync_draining = false
local sync_sent = false
local sync_got_msg = false

-- Track last sent message type for ACK/repeat display
-- msg_type: 0 = direct, 1 = flood
local last_msg_type = nil
local repeat_count = 0
local pending_channel_send = false

-- Parse command line arguments
local function parse_args(args)
  if not args then return end
  local positional = {}
  for _, v in ipairs(args) do
    if v == "-v" then
      config.verbose = true
    else
      table.insert(positional, v)
    end
  end
  if positional[1] then config.host = positional[1] end
  if positional[2] then config.port = tonumber(positional[2]) or config.port end
  if positional[3] then config.logfile = positional[3] end
end

-- Lazy-load emoji module and encode shortcodes to UTF-8
local function emoji_encode(text)
  if not emoji then
    emoji = require("lua/modules/mesh/emoji")
    collectgarbage("collect")
  end
  return emoji.encode(text)
end

-- Find a contact by name substring or numeric index
local function find_contact(client, query)
  local num = tonumber(query)
  if num and num >= 1 and num <= #client.contacts then
    return num
  end

  local query_lower = query:lower()
  for i, contact in ipairs(client.contacts) do
    if contact.name:lower():find(query_lower, 1, true) then
      return i
    end
  end

  return nil
end

-- Find a channel by number or name substring
local function find_channel(client, query)
  local num = tonumber(query)
  if num then return num end
  local q = query:lower()
  for idx, name in pairs(client.channel_names) do
    if name:lower():find(q, 1, true) then return idx end
  end
  return nil
end

-- Write a line to the log file only (never to console)
local logfh  -- forward declaration; set in main()
local function log_write(text)
  if logfh then
    logfh:writeLine(text)
    logfh:flush()
  end
end

-- Start a sync drain
local function start_sync()
  sync_draining = true
  sync_sent = false
  sync_got_msg = false
end

-- Stop syncing
local function stop_sync()
  sync_draining = false
  sync_sent = false
  sync_got_msg = false
end

-- Command implementations
commands.connect = function(client, ui, args)
  if client.connected then
    ui:add_error("Already connected. Use /disconnect first.")
    return
  end

  if args[1] then config.host = args[1] end
  if args[2] then config.port = tonumber(args[2]) or config.port end

  client.host = config.host
  client.port = config.port

  ui:add_system("Connecting to " .. config.host .. ":" .. config.port .. "...")
  ui:refresh()
  collectgarbage("collect")

  local ok, err = client:connect()
  if not ok then
    ui:add_error("Connection failed: " .. (err or "unknown"))
  end
  collectgarbage("collect")
end

commands.disconnect = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  stop_sync()
  client:disconnect()
  ui:add_system("Disconnected.")
end

commands.quit = function(client, ui, args)
  stop_sync()
  if client.connected then
    client:disconnect()
  end
  return "quit"
end

commands.contacts = function(client, ui, args)
  if #client.contacts == 0 then
    ui:add_system("No contacts loaded.")
    if client.connected then
      ui:add_system("Requesting contacts...")
      client:get_contacts()
    end
    return
  end
  ui:show_contacts()
end

commands.msg = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args < 2 then
    ui:add_error("Usage: /msg <name|number> <text>")
    return
  end

  local idx = find_contact(client, args[1])
  if not idx then
    ui:add_error("Contact not found: " .. args[1])
    return
  end

  local text = table.concat(args, " ", 2)
  local contact = client.contacts[idx]

  client:send_dm(idx, emoji_encode(text))
  ui:add_message(contact.name, text, "dm_out", nil, client:get_timestamp())
end

commands.ch = function(client, ui, args)
  if #args == 0 then
    ui:add_system("Current channel: " .. client:channel_label(ui.current_channel))
    return
  end

  local ch_idx = find_channel(client, args[1])
  if not ch_idx then
    ui:add_error("Unknown channel: " .. args[1])
    return
  end

  if #args == 1 then
    ui.current_channel = ch_idx
    ui:add_system("Switched to channel " .. client:channel_label(ch_idx))
    ui:invalidate()
    return
  end

  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  local text = table.concat(args, " ", 2)
  pending_channel_send = true
  client:send_channel_msg(ch_idx, emoji_encode(text))
  ui:add_message("", text, "chan_out", tostring(ch_idx), client:get_timestamp())
end

commands.target = function(client, ui, args)
  if #args == 0 then
    if ui.current_target_name then
      ui:add_system("Current target: " .. ui.current_target_name)
    else
      ui:add_system("No DM target set. Use /target <name> or /contacts")
    end
    return
  end

  local query = table.concat(args, " ")
  local idx = find_contact(client, query)
  if not idx then
    ui:add_error("Contact not found: " .. query)
    return
  end

  ui.current_target = idx
  ui.current_target_name = client.contacts[idx].name
  ui:add_system("DM target set to: " .. ui.current_target_name)
  ui:invalidate()
end

commands.login = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  if #args == 0 then
    ui:add_error("Usage: /login <password>")
    return
  end

  local password = table.concat(args, " ")
  client:login(password)
  ui:add_system("Logging in...")
end

commands.logout = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  client:logout()
  ui:add_system("Logged out.")
end

commands.battery = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  client:get_battery()
end

commands.sync = function(client, ui, args)
  if not client.connected then
    ui:add_error("Not connected.")
    return
  end

  start_sync()
  ui:add_system("Syncing messages...")
end

commands.tz = function(client, ui, args)
  if #args == 0 then
    local off = ui.tz_offset
    ui:add_system("Timezone: UTC" .. (off >= 0 and "+" or "") .. off)
    return
  end
  local offset = tonumber(args[1])
  if not offset then
    ui:add_error("Usage: /tz <hours> (e.g. /tz -5 for EST)")
    return
  end
  ui.tz_offset = offset
  ui:add_system("Timezone set to UTC" .. (offset >= 0 and "+" or "") .. offset)
  ui:invalidate()
end

commands.clear = function(client, ui, args)
  ui:clear_messages()
  ui:add_system("Message buffer cleared.")
end

commands.export = function(client, ui, args)
  if #args == 0 then
    ui:add_error("Usage: /export <filename>")
    return
  end

  if #client.contacts == 0 then
    ui:add_error("No contacts to export.")
    return
  end

  local path = "lua/modules/mesh/" .. args[1]
  local fh = fs.open(path, "w")
  if not fh then
    ui:add_error("Failed to open: " .. path)
    return
  end

  fh:writeLine("index,name,type,flags,prefix,lastmod")
  for i, c in ipairs(client.contacts) do
    local prefix_hex = string.format("%02x%02x%02x%02x%02x%02x",
      string.byte(c.prefix, 1), string.byte(c.prefix, 2),
      string.byte(c.prefix, 3), string.byte(c.prefix, 4),
      string.byte(c.prefix, 5), string.byte(c.prefix, 6))
    local name = c.name:gsub('"', '""')
    fh:writeLine(string.format('%d,"%s",%d,%d,%s,%d',
      i, name, c.type, c.flags, prefix_hex, c.lastmod))
  end
  fh:close()

  ui:add_system("Exported " .. #client.contacts .. " contacts to " .. path)
  collectgarbage("collect")
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

-- Process user input
local function process_input(client, ui, input)
  if not input or input == "" then
    return nil
  end

  if input:sub(1, 1) == "/" then
    local parts = {}
    for part in input:gmatch("%S+") do
      table.insert(parts, part)
    end

    local cmd = parts[1]:sub(2):lower()
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
    if not client.connected then
      ui:add_error("Not connected.")
      return nil
    end

    if ui.current_target then
      local contact = client.contacts[ui.current_target]
      if contact then
        client:send_dm(ui.current_target, emoji_encode(input))
        ui:add_message(contact.name, input, "dm_out", nil, client:get_timestamp())
      else
        ui:add_error("Target contact no longer valid.")
        ui.current_target = nil
        ui.current_target_name = nil
      end
    else
      pending_channel_send = true
      client:send_channel_msg(ui.current_channel, emoji_encode(input))
      ui:add_message("", input, "chan_out", tostring(ui.current_channel), client:get_timestamp())
    end
  end

  return nil
end

-- Setup event handlers
local function setup_handlers(client, ui)
  client:on("connecting", function()
    ui:add_system("Connecting...")
  end)

  client:on("connected", function()
    ui:add_system("Connected to " .. client.host .. ":" .. client.port, client:estimated_time())
  end)

  client:on("disconnected", function(reason)
    stop_sync()
    ui:add_system("Disconnected" .. (reason and (": " .. reason) or ""), client:estimated_time())
    ui:invalidate()
  end)

  client:on("self_info", function(name, pubkey)
    ui:add_system("Node: " .. name, client:estimated_time())
    ui:invalidate()
  end)

  client:on("contacts_loaded", function(count)
    ui:add_system(count .. " contacts loaded.", client:estimated_time())
    collectgarbage("collect")
    -- Fetch channel names now that contacts are done and memory is freed
    client:get_all_channels()
    -- Auto-sync pending messages after contacts load
    start_sync()
  end)

  client:on("dm_recv", function(sender, text, prefix, ts, path_len, txt_type)
    ui:add_message(sender, text, "dm_in", nil, ts)
    -- Mark that we got a message in this sync round
    if sync_draining then
      sync_got_msg = true
      sync_sent = false  -- ready to send next SYNC
    end
  end)

  client:on("channel_recv", function(ch_idx, text, ts, path_len, txt_type)
    ui:add_message("", text, "chan_in", tostring(ch_idx), ts)
    if sync_draining then
      sync_got_msg = true
      sync_sent = false
    end
  end)

  client:on("resp_ok", function()
    if pending_channel_send then
      pending_channel_send = false
      last_msg_type = 1  -- flood
      repeat_count = 0
      ui:add_message("", "sent", "ack", nil, client:estimated_time())
    end
  end)

  client:on("msg_sent", function(msg_type, expected_ack, suggested_timeout)
    pending_channel_send = false
    last_msg_type = msg_type
    repeat_count = 0
    if msg_type == 1 then
      ui:add_message("", "sent", "ack", nil, client:estimated_time())
    else
      ui:add_message("", "sent (waiting for ack)", "ack", nil, client:estimated_time())
    end
  end)

  client:on("ack", function(ack_code)
    local now = client:estimated_time()
    if last_msg_type == 1 then
      repeat_count = repeat_count + 1
      local s = repeat_count == 1 and "repeat" or "repeats"
      ui:add_message("", "heard " .. repeat_count .. " " .. s, "ack", nil, now)
    else
      local status = (ack_code ~= 0) and "delivered" or "no ack"
      ui:add_message("", status, "ack", nil, now)
    end
  end)

  client:on("no_more_msgs", function()
    if sync_draining then
      if sync_got_msg then
        -- Got messages this round; there may be more. Send another SYNC
        -- on the next main loop iteration.
        sync_got_msg = false
        sync_sent = false
      else
        -- Empty round: queue is fully drained.
        stop_sync()
      end
    end
  end)

  client:on("msgs_waiting", function()
    start_sync()
  end)

  client:on("time_synced", function(epoch)
    ui:add_system("Time synced: " .. epoch, client:estimated_time())
  end)

  client:on("battery", function(mv)
    log_write("battery: " .. mv .. "mV")
    ui:invalidate()
  end)

  client:on("login_success", function(perms)
    ui:add_system("Login successful (perms=" .. perms .. ")", client:estimated_time())
  end)

  client:on("login_failed", function()
    ui:add_error("Login failed.", client:estimated_time())
  end)

  client:on("error", function(msg)
    ui:add_error(msg, client:estimated_time())
  end)

  -- Push notification handlers

  -- Verbose tier: advert pings from existing contacts
  client:on("advert", function(name)
    if config.verbose then
      ui:add_system("advert from " .. name, client:estimated_time())
    elseif logfh then
      log_write("advert from " .. name)
    end
  end)

  -- Verbose tier: path updates
  client:on("path_updated", function(name)
    if config.verbose then
      ui:add_system("path updated: " .. name, client:estimated_time())
    elseif logfh then
      log_write("path updated: " .. name)
    end
  end)

  -- Always tier: new adverts (new nodes discovered)
  client:on("new_advert", function(desc)
    ui:add_system("new node: " .. desc, client:estimated_time())
  end)

  -- Log-only tier: only register these handlers when we have a log file
  if logfh then
    client:on("status_resp", function(name, status)
      log_write("status from " .. name .. ": " .. status)
    end)

    client:on("telemetry_resp", function(name, len)
      log_write("telemetry from " .. name .. " (" .. len .. "B)")
    end)

    client:on("raw_data", function(snr, rssi, len)
      log_write(string.format("raw data: SNR=%.1f RSSI=%d (%dB)", snr, rssi, len))
    end)

    client:on("trace_data", function(path_len, flags)
      log_write(string.format("trace: path_len=%d flags=0x%02X", path_len, flags))
    end)

    client:on("control_data", function(snr, rssi, path_len, total)
      log_write(string.format("control: SNR=%.1f RSSI=%d path=%d (%dB)", snr, rssi, path_len, total))
    end)
  end

  -- Verbose tier: decoded LOG_RX mesh packets
  client:on("log_rx_data", function(snr, rssi, type_name, path_len, path_str, payload_size, name)
    if not config.verbose and not logfh then return end
    local msg = string.format("%s SNR=%.1f RSSI=%d hops=%d",
      type_name, snr, rssi, path_len)
    if path_str ~= "" then
      msg = msg .. " [" .. path_str .. "]"
    end
    if name then
      msg = msg .. ' "' .. name .. '"'
    else
      msg = msg .. string.format(" (%dB)", payload_size)
    end
    log_write(msg)
    if config.verbose then
      ui:add_system(msg, client:estimated_time())
    end
  end)

  -- Log-only tier: hex dump of all received packets
  if logfh then
    client:on("debug_packet", function(name, cmd, data)
      if cmd ~= 0x88 then
        log_write(string.format("[%s] (%dB): %s",
          name, #data, client:hex_dump(data)))
      end
    end)

    client:on("unknown_packet", function(cmd, data)
      log_write(string.format("unk 0x%02X (%dB): %s",
        cmd, #data, client:hex_dump(data)))
    end)
  end

  -- Channel info: verbose shows each channel, default is silent
  client:on("channel_info", function(idx, name)
    if name and name ~= "" then
      if config.verbose then
        ui:add_system("channel " .. idx .. ": " .. name, client:estimated_time())
      elseif logfh then
        log_write("channel " .. idx .. ": " .. name)
      end
    end
  end)
end

-- Main function
local function main(args)
  parse_args(args)

  collectgarbage("collect")

  -- Open log file if requested
  logfh = nil
  if config.logfile then
    local path = "lua/modules/mesh/" .. config.logfile
    logfh = fs.open(path, "a")
    if logfh then
      logfh:writeLine("")
      logfh:writeLine("--- MeshCore session ---")
    end
  end

  -- Create client and UI
  local client = Client.new(config)
  client.debug = (logfh ~= nil)
  client.verbose = config.verbose
  local ui = UI.new(client)
  ui.logfh = logfh

  -- Pre-load emoji module while memory is unfragmented (before contacts load)
  require("lua/modules/mesh/emoji")
  collectgarbage("collect")

  -- Setup handlers
  setup_handlers(client, ui)

  -- Initialize UI
  ui:init()
  ui:add_system("PicoCalc MeshCore Client")
  ui:add_system("Type /help for commands, /quit to exit.")
  ui:add_system("")

  -- Auto-connect
  ui:add_system("Connecting to " .. config.host .. ":" .. config.port .. "...")
  ui:refresh()

  -- Free startup garbage (closures, handler setup, UI init) before connect
  collectgarbage("collect")

  local ok, err = client:connect()
  if not ok then
    ui:add_error("Connection failed: " .. (err or "unknown"))
    ui:add_system("Use /connect to try again.")
  end

  -- Free connect() temporaries before the response flood
  collectgarbage("collect")

  -- Main loop
  local running = true
  local batt_counter = 0
  while running do
    ui:refresh()

    -- Receive and dispatch incoming packets
    if client.connected then
      client:poll()
    end

    -- Sync drain: send one SYNC_NEXT_MESSAGE per loop iteration.
    -- Sending happens here (never inside packet handlers) so that
    -- GC and UI refresh run between each request.
    if sync_draining and not sync_sent and client.connected then
      client:sync_next_message()
      sync_sent = true
      collectgarbage("collect")
    end

    -- Check for user input (non-blocking)
    local input = ui:check_input()
    if input then
      if input == "quit" then
        running = false
      elseif input == "contact_selected" then
        if ui.current_target_name then
          ui:add_system("DM target: " .. ui.current_target_name)
        end
      elseif input ~= "scroll_up" and input ~= "scroll_down" then
        local result = process_input(client, ui, input)
        if result == "quit" then
          running = false
        end
      end
    end

    collectgarbage("collect")

    -- Poll battery every ~600 iterations (~30s)
    batt_counter = batt_counter + 1
    if batt_counter >= 600 and client.connected then
      client:get_battery()
      batt_counter = 0
    end
  end

  -- Cleanup
  if client.connected then
    client:disconnect()
  end
  ui:cleanup()

  if logfh then
    logfh:close()
  end

  -- Free up resources
  package.loaded["lua/modules/mesh/client"] = nil
  package.loaded["lua/modules/mesh/ui"] = nil
  collectgarbage()
  print("MeshCore client closed.")
end

-- Run
if arg then
  main(arg)
else
  main({})
end

