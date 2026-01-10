--[[

nc.lua - Netcat for PicoCalc
  
Usage:
  nc(host, port)       -- Connect to host:port (TCP)
  nc("-l", port)       -- Listen on port (TCP server)
  nc("-u", host, port) -- UDP client mode
  nc("-lu", port)      -- UDP server mode
  nc("-h")             -- Show help

Interactive commands (during session):
  Ctrl+C or type /quit  -- Exit session
  /status               -- Show connection status
]]

local nc = {}

-- Configuration
nc.TIMEOUT = 30       -- Connection timeout (seconds)
nc.RECV_TIMEOUT = 0.1 -- Receive timeout (seconds)
nc.BUFFER_SIZE = 1024 -- Receive buffer size

-- Show help
local function show_help()
  print("nc.lua - Netcat for PicoCalc")
  print("")
  print("Usage:")
  print("  nc(host, port)        TCP client - connect to host:port")
  print("  nc('-l', port)        TCP server - listen on port")
  print("  nc('-u', host, port)  UDP client - send to host:port")
  print("  nc('-lu', port)       UDP server - listen on port (UDP)")
  print("  nc('-h')              Show this help")
  print("")
  print("Interactive commands:")
  print("  /quit                 Exit the session")
  print("  /status               Show connection info")
  print("")
  print("Examples:")
  print("  nc('example.com', 80)     -- Connect to web server")
  print("  nc('-l', 8080)            -- Listen on port 8080")
  print("  nc('-u', '192.168.1.1', 5000)  -- UDP to host")
end

-- Check if user wants to quit
local function check_quit(input)
  if not input then return false end
  local lower = input:lower()
  return lower == "/quit" or lower == "/exit" or lower == "/q"
end

-- Check for status command
local function check_status(input)
  if not input then return false end
  return input:lower() == "/status"
end

-- TCP Client mode
local function tcp_client(host, port)
  print(string.format("Connecting to %s:%d...", host, port))

  local sock, err = socket.tcp()
  if not sock then
    print("Failed to create socket: " .. (err or "unknown"))
    return
  end

  local ok, conn_err = sock:connect(host, port, nc.TIMEOUT * 1000)
  if not ok then
    print("Connection failed: " .. (conn_err or "unknown"))
    sock:close()
    return
  end

  print("Connected! Type '/quit' to exit.")
  print("---")

  sock:settimeout(nc.RECV_TIMEOUT)

  -- Main loop
  while sock:isconnected() do
    -- Check for incoming data
    local avail = sock:available()
    if avail and avail > 0 then
      local data, recv_err = sock:receive(nc.BUFFER_SIZE)
      if data then
        term.write(data)
        --io.flush()
      elseif recv_err and recv_err ~= "timeout" then
        print("\n[Connection closed by remote]")
        break
      end
    end

    -- Check for user input (non-blocking)
    local input = term.read("", 0)  -- 0 timeout for non-blocking
    if input then
      if check_quit(input) then
        print("[Closing connection]")
        break
      elseif check_status(input) then
        print(string.format("[Connected to %s:%d]", host, port))
      else
        -- Send data with newline
        local sent, send_err = sock:send(input .. "\n")
        if not sent then
          print("[Send failed: " .. (send_err or "unknown") .. "]")
          break
        end
      end
    end

    -- Small delay to prevent busy loop
    for i = 1, 100 do end
  end

  sock:close()
  print("[Disconnected]")
end

-- TCP Server mode
local function tcp_server(port)
  print(string.format("Listening on port %d...", port))

  local server, err = socket.tcp()
  if not server then
    print("Failed to create socket: " .. (err or "unknown"))
    return
  end

  local ok, bind_err = server:bind("0.0.0.0", port)
  if not ok then
    print("Bind failed: " .. (bind_err or "unknown"))
    server:close()
    return
  end

  ok, err = server:listen(1)
  if not ok then
    print("Listen failed: " .. (err or "unknown"))
    server:close()
    return
  end
  
  print("Waiting for connection... (Ctrl+C to cancel)")
  
  -- Wait for connection
  local client, accept_err = server:accept(0)  -- 0 = wait indefinitely
  if not client then
    print("Accept failed: " .. (accept_err or "unknown"))
    server:close()
    return
  end
  
  print("Client connected! Type '/quit' to exit.")
  print("---")
  
  client:settimeout(nc.RECV_TIMEOUT)

  -- Main loop
  while client:isconnected() do
    -- Check for incoming data
    local avail = client:available()
    if avail and avail > 0 then
      local data, recv_err = client:receive(nc.BUFFER_SIZE)
      if data then
        term.write(data)
        --io.flush()
      elseif recv_err and recv_err ~= "timeout" then
        print("\n[Client disconnected]")
        break
      end
    end

    -- Check for user input
    local input = term.read("", 0)
    if input then
      if check_quit(input) then
        print("[Closing connection]")
        break
      elseif check_status(input) then
        print("[Client connected on port " .. port .. "]")
      else
        local sent, send_err = client:send(input .. "\n")
        if not sent then
          print("[Send failed: " .. (send_err or "unknown") .. "]")
          break
        end
      end
    end

    for i = 1, 100 do end
  end

  client:close()
  server:close()
  print("[Server stopped]")
end

-- UDP Client mode
local function udp_client(host, port)
  print(string.format("UDP mode to %s:%d", host, port))
  print("Type '/quit' to exit.")
  print("---")

  local sock, err = socket.udp()
  if not sock then
    print("Failed to create socket: " .. (err or "unknown"))
    return
  end

  sock:settimeout(nc.RECV_TIMEOUT)

  -- Main loop
  local running = true
  while running do
    -- Check for incoming data
    local data, sender_ip, sender_port = sock:receivefrom(nc.BUFFER_SIZE)
    if data then
      term.write(string.format("[%s:%d] %s", sender_ip or "?", sender_port or 0, data))
      if not data:match("\n$") then
        term.write("\n")
      end
    end

    -- Check for user input
    local input = term.read("", 0)
    if input then
      if check_quit(input) then
        print("[Closing]")
        running = false
      elseif check_status(input) then
        print(string.format("[UDP target: %s:%d]", host, port))
      else
        local sent, send_err = sock:sendto(input .. "\n", host, port)
        if not sent then
          print("[Send failed: " .. (send_err or "unknown") .. "]")
        end
      end
    end

    for i = 1, 100 do end
  end

  sock:close()
  print("[Closed]")
end

-- UDP Server mode
local function udp_server(port)
  print(string.format("UDP listening on port %d", port))
  print("Type '/quit' to exit.")
  print("---")

  local sock, err = socket.udp()
  if not sock then
    print("Failed to create socket: " .. (err or "unknown"))
    return
  end

  local ok, bind_err = sock:bind("0.0.0.0", port)
  if not ok then
    print("Bind failed: " .. (bind_err or "unknown"))
    sock:close()
    return
  end

  sock:settimeout(nc.RECV_TIMEOUT)

  -- Track last sender for replies
  local last_sender_ip = nil
  local last_sender_port = nil

  -- Main loop
  local running = true
  while running do
    -- Check for incoming data
    local data, sender_ip, sender_port = sock:receivefrom(nc.BUFFER_SIZE)
    if data then
      last_sender_ip = sender_ip
      last_sender_port = sender_port
      term.write(string.format("[%s:%d] %s", sender_ip or "?", sender_port or 0, data))
      if not data:match("\n$") then
        term.write("\n")
      end
    end

    -- Check for user input
    local input = term.read("", 0)
    if input then
      if check_quit(input) then
        print("[Closing]")
        running = false
      elseif check_status(input) then
        if last_sender_ip then
          print(string.format("[Last sender: %s:%d]", last_sender_ip, last_sender_port))
        else
          print("[No messages received yet]")
        end
      else
        if last_sender_ip then
          local sent, send_err = sock:sendto(input .. "\n", last_sender_ip, last_sender_port)
          if not sent then
            print("[Send failed: " .. (send_err or "unknown") .. "]")
          end
        else
          print("[No target - wait for incoming message first]")
        end
      end
    end

    for i = 1, 100 do end
  end

  sock:close()
  print("[Closed]")
end

-- Main entry point
local function main(...)
  local args = {...}

  if #args == 0 then
    show_help()
    return
  end

  local arg1 = args[1]

  -- Help
  if arg1 == "-h" or arg1 == "--help" or arg1 == "help" then
    show_help()
    return
  end

  -- Check Wi-Fi connection
  if not wifi.isConnected() then
    print("Error: Wi-Fi not connected")
    print("Run: dofile('lua/wifi-start.lua')")
    return
  end

  -- Parse options
  if arg1 == "-l" then
    -- TCP server
    local port = tonumber(args[2])
    if not port then
      print("Error: port required")
      print("Usage: nc('-l', port)")
      return
    end
    tcp_server(port)

  elseif arg1 == "-lu" or arg1 == "-ul" then
    -- UDP server
    local port = tonumber(args[2])
    if not port then
      print("Error: port required")
      print("Usage: nc('-lu', port)")
      return
    end
    udp_server(port)

  elseif arg1 == "-u" then
    -- UDP client
    local host = args[2]
    local port = tonumber(args[3])
    if not host or not port then
      print("Error: host and port required")
      print("Usage: nc('-u', host, port)")
      return
    end
    udp_client(host, port)

  else
    -- TCP client (default)
    local host = arg1
    local port = tonumber(args[2])
    if not port then
      print("Error: port required")
      print("Usage: nc(host, port)")
      return
    end
    tcp_client(host, port)
  end
end

-- Allow calling as function
setmetatable(nc, {
  __call = function(_, ...)
    main(...)
  end
})

-- If run directly, check for global args
if arg and #arg > 0 then
  main(table.unpack(arg))
end

return nc
