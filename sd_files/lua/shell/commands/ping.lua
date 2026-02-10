--[[
  ping.lua - 
  ICMP ping (using socket.ping)
]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "ping",
  aliases = {""},
  help = c.cyan.."ping"..c.yellow.." <host> [count]"..c.white.." - ICMP ping host",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: ping <host> [count]")
    end

    if not wifi.isConnected() then
      return sh:error("Wi-Fi not connected")
    end

    local host = args[1]
    local count = tonumber(args[2]) or 4

    print(string.format("PING %s", host))

    local successes = 0
    local total_time = 0
    local resolved_ip = nil
    local now = 0
    local later = 0
    for i = 1, count do
      local result, err = socket.ping(host, 3000)

      if result then
        resolved_ip = result.ip
        if result.success then
          successes = successes + 1
          total_time = total_time + result.time
          print(string.format("  Reply from %s: time=%dms TTL=%d",
          result.ip, result.time, result.ttl))
        else
          print(string.format("  #%d: No reply", i))
        end
      else
        print(string.format("  #%d: %s", i, err or "failed"))
      end

      -- short delay between pings
      --for j = 1, 100 do end 
      
    end

    print("")
    print(string.format("--- %s ping statistics ---", resolved_ip or host))
    print(string.format("%d packets transmitted, %d received, %.0f%% loss", count, successes, ((count - successes) / count) * 100))

    if successes > 0 then
      print(string.format("avg time: %.0fms", total_time / successes))
    end
  end
}
