--[[

  wifi.lua - Wi-Fi shell command

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "wifi",
  aliases = {"wf","wlan"},
  help = c.cyan.."wifi"..c.yellow.." [status|on|off|scan]"..c.white.." - manage Wi-Fi connection",
  run = function(args, sh)
    local action = args[1] or "status"

    if action == "status" then
      if not wifi.isInitialized() then
        print("Wi-Fi: " .. sh:color("yellow", "not initialized"))
        return
      end

      if wifi.isConnected() then
        print("Wi-Fi: " .. sh:color("green", "connected"))
        local info = wifi.getInfo()
        if info then
          if info.ssid then
            print(" SSID: " .. info.ssid)
          end
          print("   IP: " .. info.ip)
          --print("  Gateway: " .. info.gateway)
          --print("  Netmask: " .. info.netmask)
        end
      else
        print("Wi-Fi: " .. sh:color("yellow", "disconnected"))
      end

    elseif action == "on" or action == "start" or action == "connect" then
      -- Run the wifi-start script
      local ok, err = pcall(dofile, "/lua/wifi-start.lua")
      if not ok then
        sh:error(tostring(err))
      end

    elseif action == "off" or action == "stop" or action == "disconnect" then
      if not wifi.isInitialized() then
        return sh:error("Wi-Fi not initialized")
      end

      if wifi.isConnected() then
        wifi.disconnect()
        sh:success("Disconnected from Wi-Fi")
      else
        print("Wi-Fi already disconnected")
      end

    elseif action == "scan" then
      if not wifi.isInitialized() then
        print("Initializing Wi-Fi...")
        if not wifi.init("US") then
          return sh:error("Failed to initialize Wi-Fi")
        end
      end

      print("Scanning...")
      local networks, err = wifi.scan()

      if not networks then
        return sh:error("Scan failed: " .. (err or "unknown"))
      end

      if #networks == 0 then
        print("No networks found")
        return
      end

      -- Sort by signal strength
      table.sort(networks, function(a, b)
        return a.rssi > b.rssi
        end)

      print(sh:color("green", "Found " .. #networks .. " networks:"))
      for i, net in ipairs(networks) do
        local security = net.secure and "*" or " "
        local signal
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
        print(string.format("  %s %s %s (%ddBm)", security, signal, net.ssid, net.rssi))
      end
      print("  * = secured")

    else
      sh:error("Unknown action: " .. action)
      print("Usage: wifi [status|on|off|scan]")
    end
  end
}
