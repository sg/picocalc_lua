--[[

  myip.lua - fetch device's external source IP as seen
             by sites connected to on the internet.
             also gets geo-location details.
]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "myip",
  category = "net",
  usage = "[file]",
  desc = "get ext. IP and geo-loc info [to file]",
  args = "path?",
  needs = {"wifi"},
  run = function(args, sh)
    local json = require("lua/modules/json")
    local http = require("lua/modules/http")

    local output_file = args[1]
    local url = "https://ipinfo.io"

    local response, err = http.get(url)

    if not response then
      return sh:error(err or "request failed")
    end

    print(string.format("Status: %d %s", response.status, response.reason or ""))

    if response.status >= 400 then
      return sh:error("Request failed with status " .. response.status)
    end

    local body = response.body

    if output_file then
      local f <close> = fs.open(args.v[1], "w")
      f:write(body)
      sh:success(string.format("Saved %d bytes to %s", #body, output_file))
    else
      print("")
      local info = json.decode(body)
      for k, v in pairs(info) do
        print(c.cyan .. k .. c.white .. ": " .. c.green .. v .. c.white)
      end
      print("")
    end
  end
}
