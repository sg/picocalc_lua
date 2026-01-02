--[[

  wifi-start.lua
  Scan for Wi-Fi networks and connect to one selected by the user
]]

-- check if already connected
if wifi.isInitialized() and wifi.isConnected() then
  local info = wifi.getInfo()
  print("Already connected to Wi-Fi")
  if info then
    print("IP: " .. info.ip)
  end
  return
end

-- init wi-fi if needed
if not wifi.isInitialized() then
  print("Initializing Wi-Fi...")
  if not wifi.init("US") then
    print("Failed to initialize Wi-Fi")
    return
  end
end

-- scan for ssids
print("Scanning for networks...")
local networks, err = wifi.scan()

if not networks then
  print("Scan failed: " .. (err or "unknown error"))
  return
end

if #networks == 0 then
  print("No networks found")
  return
end

-- sort by signal strength
table.sort(networks, function(a, b)
  return a.rssi > b.rssi
end)

-- display networks
print("\nAvailable networks:")
print("-------------------")
for i, net in ipairs(networks) do
  local security = net.secure and "*" or " "
  local signal = ""
  if net.rssi >= -50 then
    signal = "[====]"
  elseif net.rssi >= -60 then
    signal = "[=== ]"
  elseif net.rssi >= -70 then
    signal = "[==  ]"
  elseif net.rssi >= -80 then
    signal = "[=   ]"
  else
    signal = "[    ]"
  end
  print(string.format("%2d. %s %s %s", i, security, signal, net.ssid))
end
print("\n* = secured network")

-- select a network
print("")
local selection = term.read("Enter number (1-" .. #networks .. "): ")
local idx = tonumber(selection)

if not idx or idx < 1 or idx > #networks then
  print("Invalid selection")
  return
end

local selected = networks[idx]
print("\nConnecting to: " .. selected.ssid)

-- get password if network is secured
local password = ""
if selected.secure then
  password = term.read("Password: ")
  if not password or password == "" then
    print("Password required for secured network")
    return
  end
end

-- set auth mode to WPA2 for now
local auth = wifi.AUTH_OPEN
if selected.secure then
  auth = wifi.AUTH_WPA2  
end

-- connect
print("Connecting...")
local ok, conn_err = wifi.connect(selected.ssid, password, auth, 30000)

if not ok then
  print("Connection failed: " .. (conn_err or "unknown error"))
  return
end

-- wait for DHCP to assign IP
print("Waiting for IP address...")
local timeout = 10 -- seconds
local start = os.clock()
while not wifi.isConnected() and (os.clock() - start) < timeout do
  -- delay
  for i = 1, 1000 do end
end

-- display connection info
if wifi.isConnected() then
  local info = wifi.getInfo()
  print("\nConnected successfully!")
  if info then
    print("IP Address: " .. info.ip)
    --print("Gateway:    " .. info.gateway)
    --print("Netmask:    " .. info.netmask)
  end
else
  print("\nConnection timed out waiting for IP")
end
