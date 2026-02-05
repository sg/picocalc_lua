--[[

  wifi-start.lua

  Load wifi details from pre-existing config file or
  scan for networks and connect to one selected.

  The wifi password is encrypted before saving it to
  the config file on the SD card. It is only using
  rc4 with symetric key, but might prevent a non-tech
  person from immediately joining your network if your
  SD card is lost. Anyone else, of course, will figure
  it out in about 2 minutes ¯\_(ツ)_/¯ 

]]

local rc4 = require("lua/modules/rc4")
local b64 = require("lua/modules/base64")
local serialize = require("lua/modules/serialize")

local wifi_country_code = ""
local wifi_config_path = "lua/wifi.conf"
local wifi_config = {}
local using_config = false
local selected = {}
local password = ""
local auth = wifi.AUTH_OPEN
local xkey = "x92@.g"

local function encrypt(val, key)
  return b64.encode(rc4(key,val))
end

local function decrypt(val, key)
  return rc4(key, b64.decode(val))
end

-- load wifi_config from file 
local function loadWifiConfig(filename)
  local func, err = loadfile(filename)
  if func then
    local success, wifi_conf = pcall(func)
    if success then
      return wifi_conf
    else
      print("Error loading wifi config values: " .. wifi_conf)
      return nil
    end
  else
    print("Error reading wifi config file: " .. err)
    return nil
  end
end 

-- save wifi_config to file 
local function saveWifiConfig(filename, data_table)
  local file = fs.open(filename, "w")
  if file then
    serialize.toFile(data_table, file)
    file:close()
    return true
  else
    print("Error: Could not open file for writing.")
    return false
  end
end

-- function to scan for SSIDs
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

-- wait for connection status to settle and return actual status
local function awaitFinalConnectionState(timeout_seconds)
  local start = os.clock()
  while (os.clock() - start) < timeout_seconds do
    local status = wifi.status()
    if status == wifi.STATUS_UP then
      return true, nil
    elseif status == wifi.STATUS_FAIL then
      return false, "connection failed"
    elseif status == wifi.STATUS_NONET then
      return false, "network not found"
    elseif status == wifi.STATUS_BADAUTH then
      return false, "authentication failed"
    end
    -- STATUS_DOWN, JOIN, or NOIP - keep waiting for definitive result
    for i = 1, 5000 do end
  end
  -- timeout - check final status
  if wifi.isConnected() then
    return true, nil
  end
  return false, "connection timed out"
end

-- connect
print("Connecting...")
local ok, conn_err
if using_config then
  --print("debug: using ssid: " .. wifi_config.ssid .. " pass: " .. wifi_config.pass .. " auth: " .. wifi_config.auth)
  ok, conn_err = wifi.connect(wifi_config.ssid, decrypt(wifi_config.pass, xkey), wifi_config.auth, 15000)
  -- unloading modules to save memory
  package.loaded["lua/modules/rc4"] = nil
  package.loaded["lua/modules/base64"] = nil
  collectgarbage()
else
  ok, conn_err = wifi.connect(selected.ssid, password, auth, 30000)
end

-- if connect returned an ambiguous err, wait for status to
-- settle to get the real error status code.
-- (handles spurious errors like -7/ERR_WOULDBLOCK
-- and delayed auth failures)
if not ok then
  local status = wifi.status()
  if status == wifi.STATUS_UP then
    -- actually connected despite error
    ok = true
  elseif status == wifi.STATUS_BADAUTH then
    conn_err = "authentication failed"
  elseif status == wifi.STATUS_NONET then
    conn_err = "network not found"
  elseif status == wifi.STATUS_FAIL then
    conn_err = "connection failed"
  else
    -- status not definitive yet, wait for it to settle
    --print("debug: awaiting connection status...")
    ok, conn_err = awaitFinalConnectionState(5)
  end
end

if not ok then
  print("Connection failed: " .. (conn_err or "unknown error"))
  return
end

-- wait for DHCP to assign IP (if not already connected)
if not wifi.isConnected() then
  --print("debug: waiting for IP address...")
  ok, conn_err = awaitFinalConnectionState(10)
  if not ok then
    print(conn_err or "Connection timed out waiting for IP")
    return
  end
end

-- display connection info
if wifi.isConnected() then
  local info = wifi.getInfo()
  print("\nConnected successfully!")
  if info then
    print("Network SSID: " .. info.ssid)
    print("  IP Address: " .. info.ip)
    --print("     Gateway:    " .. info.gateway)
    --print("     Netmask:    " .. info.netmask)
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
    wifi_config.pass = encrypt(password, xkey)
    wifi_config.auth = auth
    saveWifiConfig(wifi_config_path, wifi_config)
    -- unloading modules to save memory
    package.loaded["lua/modules/rc4"] = nil
    package.loaded["lua/modules/base64"] = nil
    collectgarbage()    
  end
end
  
