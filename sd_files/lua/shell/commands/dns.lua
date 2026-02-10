--[[

  dns.lua - DNS lookup command

]]
-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "dns",
  aliases = {"host", "nslookup"},
  help = c.cyan.."dns"..c.yellow.." <hostname>"..c.white.." - DNS lookup for given hostname",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: dns <hostname>")
    end

    if not wifi.isConnected() then
      return sh:error("Wi-Fi not connected")
    end

    local host = args[1]
    print("Looking up IP for " .. host .. "...")
    result = socket.dns.resolve(host)
    if result ~= nil then
      print(result)
    end
  end
}
