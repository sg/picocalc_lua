--[[

  dns.lua - DNS lookup command

]]
-- ANSI color codes
local c = {
  black   = "\27[90m",
  red     = "\27[91m",
  green   = "\27[92m",
  yellow  = "\27[93m",
  blue    = "\27[94m",
  magenta = "\27[95m",
  cyan    = "\27[96m",
  white   = "\27[97m",
  reset   = "\27[0m",
}

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
