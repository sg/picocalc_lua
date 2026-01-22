--[[

  wifi-start.lua
  Load wifi details from pre-existing config file or
  scan for Wi-Fi networks and connect to one selected by the user
]]

local x = require("lua/modules/xor")
local b64 = require("lua/modules/base64")

local wifi_country_code = ""
local wifi_config_path = "lua/wifi.conf"
local wifi_config = {}
local using_config = false
local selected = {}
local password = ""
local auth = wifi.AUTH_OPEN
local xkey = "x92@.gPa3{dO0B88B80O0-s"

-- funcs to encode/decode
local function encode(val, key)
  return b64.encode(x.xor(val, key))
end

local function decode(val, key)
  return x.xor(b64.decode(val), key)
end

-- funcs to load/save wifi_config from/to file 
local function loadWifiConfig(filename)
  local func, err = loadfile(filename)
  if func then
    local success, wifi_conf = pcall(func)
    if success then
      return wifi_conf
    else
      print("Error loading wifi config values: " .. wifi_config)
      return nil
    end
  else
    print("Error reading wifi config file: " .. err)
    return nil
  end
end 

local function saveWifiConfig(filename, data_table)
  local file = fs.open(filename, "w")
  if file then
    -- serialize the table into Lua code and write to a file.
    -- in the future can be read and loaded into a table with pcall.
    file:write("return ")
    local serialized_data = "{\n"
    for k, v in pairs(data_table) do
      local key_str = type(k) == "string" and string.format('"%s"', k) or tostring(k)
      local val_str = type(v) == "string" and string.format('"%s"', v) or tostring(v)
      serialized_data = serialized_data .. string.format('    [%s] = %s,\n', key_str, val_str)
    end
    serialized_data = serialized_data .. "}\n"

    file:write(serialized_data)
    file:close()
    return true
  else
    print("Error: Could not open file for writing.")
    return false
  end
end

-- func to scan for SSIDs
local function scanForSSIDsAndConnect()
  print("Scanning for networks...")
  local networks, err = wifi.scan()

  if not networks then
    print("Scan failed: " .. (err or "unknown error"))
    return false
  end

  if #networks == 0 then
    print("No networks found")
    return false
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
    return false
  end

  selected = networks[idx]
  print("\nConnecting to: " .. selected.ssid)

  -- get password if network is secured
  if selected.secure then
    password = term.read("Password: ")
    if not password or password == "" then
      print("Password required for secured network")
      return false
    end
  end
  return true
end

-- check if already connected
if wifi.isInitialized() and wifi.isConnected() then
  local info = wifi.getInfo()
  print("Already connected to Wi-Fi")
  if info then
    print("IP: " .. info.ip)
  end
  return
end



-- check for existing wifi config file
if fs.exists(wifi_config_path) then
  wifi_config = loadWifiConfig(wifi_config_path)
  print("Wifi config found for SSID: " .. wifi_config.ssid)
  if term.read("Connect to this SSID? [Y]/n: ") ~= "n" then
    -- connect using existing config
    using_config = true
  end
  -- init wi-fi if needed
  if not wifi.isInitialized() then  
    print("Initializing Wi-Fi using stored country code (".. wifi_config.country ..")")
    if not wifi.init(wifi_config.country) then
      print("Failed to initialize Wi-Fi")
      return
    end
  end
end


if not using_config then
  -- init wi-fi if needed
  if not wifi.isInitialized() then
    wifi_country_code = term.read("Set Wi-Fi two-letter country code [US]: ")  
    if wifi_country_code == "" then
      wifi_country_code = "US"
    end
    if #wifi_country_code ~= 2 then
      print("Country code must be a two-letter code")
      print("(e.g., GB, US, CA, DE, FR, etc.")
      return
    end
    print("Initializing Wi-Fi...")
    if not wifi.init(wifi_country_code) then
      print("Failed to initialize Wi-Fi")
      return
    end
  end
  -- scan for / connect to available networks
  if not scanForSSIDsAndConnect() then
    print("Scan and select network failed.")
    return
  end
end

-- set auth mode to WPA2 for now
if selected.secure then
  auth = wifi.AUTH_WPA2  
end

-- connect
print("Connecting...")
if using_config then
  --print("debug: using ssid: " .. wifi_config.ssid .. " pass: " .. wifi_config.pass .. " auth: " .. wifi_config.auth)
  local ok, conn_err = wifi.connect(wifi_config.ssid, decode(wifi_config.pass, xkey), wifi_config.auth, 30000)
  package.loaded["lua/modules/xor"] = nil
  package.loaded["lua/modules/base64"] = nil
  collectgarbage()
    
  if not ok then
    print("Connection failed: " .. (conn_err or "unknown error"))
    return
  end
else
  local ok, conn_err = wifi.connect(selected.ssid, password, auth, 30000)
  if not ok then
    print("Connection failed: " .. (conn_err or "unknown error"))
    return
  end
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

-- if we manually configured wifi info then offer to save
-- for future use
if not using_config then
  if term.read("Save Wifi connection info to config file? [Y]/n: ") ~= n then
    wifi_config.country = wifi_country_code
    wifi_config.ssid = selected.ssid
    wifi_config.pass = encode(password, xkey)
    wifi_config.auth = auth
    saveWifiConfig(wifi_config_path, wifi_config)
    package.loaded["lua/modules/xor"] = nil
    package.loaded["lua/modules/base64"] = nil
    collectgarbage()    
  end
end
  
