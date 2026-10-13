--[[

  dns.lua - DNS lookup command

]]

return {
  name = "dns",
  category = "net",
  aliases = {"host", "nslookup"},
  usage = "<hostname>",
  desc = "DNS lookup for given hostname",
  args = "string",
  needs = {"wifi"},
  run = function(args)
    local host = args[1]
    print("Looking up IP for " .. host .. "...")
    local result = socket.dns.resolve(host)
    if result ~= nil then
      print(result)
    end
  end
}
