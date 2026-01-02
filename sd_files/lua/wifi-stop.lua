--[[
  wifi-stop.lua
  Disconnect from Wi-Fi network and optionally deinitialize.
]]

-- Check current state
if not wifi.isInitialized() then
    print("Wi-Fi is not initialized")
    return
end

if not wifi.isConnected() then
    print("Wi-Fi is not connected")
    -- Ask if user wants to deinitialize anyway
    local answer = term.read("Deinitialize Wi-Fi? (y/n): ")
    if answer and (answer:lower() == "y" or answer:lower() == "yes") then
        wifi.deinit()
        print("Wi-Fi deinitialized")
    end
    return
end

-- Show current connection info
local info = wifi.getInfo()
if info then
    print("Currently connected:")
    print("  SSID: " .. (info.ssid or "unknown"))
    print("  IP:   " .. info.ip)
end

-- Disconnect
print("\nDisconnecting...")
wifi.disconnect()

-- Verify disconnection
if not wifi.isConnected() then
    print("Disconnected successfully")
else
    print("Warning: Still appears connected")
end

-- Ask about deinitializing
local answer = term.read("\nDeinitialize Wi-Fi? (y/n): ")
if answer and (answer:lower() == "y" or answer:lower() == "yes") then
    wifi.deinit()
    print("Wi-Fi deinitialized")
else
    print("Wi-Fi remains initialized (can reconnect faster)")
end
