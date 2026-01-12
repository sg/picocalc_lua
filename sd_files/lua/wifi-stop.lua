--[[
  
wifi-stop.lua
  Disconnect from Wi-Fi network

]]

-- check current state
if not wifi.isInitialized() then
    print("Wi-Fi is not initialized")
    return
end

if not wifi.isConnected() then
    print("Wi-Fi is not connected")
    -- ask if user wants to deinitialize anyway
    --local answer = term.read("Deinitialize Wi-Fi? (y/n): ")
    --if answer and (answer:lower() == "y" or answer:lower() == "yes") then
    --    wifi.deinit()
    --    print("Wi-Fi deinitialized")
    --end
    return
end

-- show current connection info
local info = wifi.getInfo()
if info then
    print("Currently connected:")
    print("  SSID: " .. (info.ssid or "unknown"))
    print("  IP:   " .. info.ip)
end

-- disconnect
print("\nDisconnecting...")
wifi.disconnect()
-- delay
for i = 1, 10000 do end

-- verify disconnection
if not wifi.isConnected() then
    print("Disconnected successfully")
else
    print("Wi-Fi still appears connected.")
    print("Wait a few seconds and try again.")
end

-- deinitialize?
--local answer = term.read("\nDeinitialize Wi-Fi? (y/n): ")
--if answer and (answer:lower() == "y" or answer:lower() == "yes") then
--    wifi.deinit()
--    print("Wi-Fi deinitialized")
--else
--    print("Wi-Fi remains initialized (can reconnect faster)")
--end
