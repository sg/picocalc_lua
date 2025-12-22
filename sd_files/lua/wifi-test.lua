--
-- wifi test
--
--

if wifi.isConnected() then
  print("Already connected. IP:" .. wifi.getIP())
  return
end
 
if wifi.isInitialized() then
  print("wifi is already initialized.")
else
  if wifi.init("US") then
    print("wifi initialized!")
  else
    print("failed to init wifi :(")
    return
  end
end

print("Scanning for networks...")
local networks = wifi.scan()
if networks then
  print("Found " .. #networks .. " networks:")
  for i, net in ipairs(networks) do
    local security = net.secure and "Secured" or "Open"
    print(string.format("%d. %-20s Ch:%2d RSSI:%4d %s", i, net.ssid, net.channel, net.rssi, security))
  end
else
  print("Scan failed")
  return
end

local ok, err = wifi.connect("vonlane944", "Welcome!")
if ok then
  print("Conncted succssfully!")
else
  print("Connection failed.")
  return
end

local info = wifi.getInfo()
if info then
  print("IP:      " .. info.ip)
  print("Gateway: " .. info.gateway)
  print("Netmask: " .. info.netmask)
end

