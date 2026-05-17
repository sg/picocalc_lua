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
  help = c.cyan.."myip"..c.yellow.." [file]"..c.white.." - get ext. IP and geo-loc info [to file]",
  run = function(args, sh)
    local json = require("lua/modules/json")
    local http = require("lua/modules/http")

    local output_file = nil

    if args[1] then
      output_file = args[1]
    end

    if not wifi.isConnected() then
      return sh:error("Wi-Fi not connected")
    end


    local url = "https://ipinfo.io"

    local response, err = http.get(url)

    if not response then
      return sh:error(err or "request failed")
    end

    print(string.format("Status: %d %s", response.status, response.reason or ""))

    if response.status >= 400 then
      return sh:error("Request failed with status " .. response.status)
    end

    --local body = response.body:match('{.*}}') or ""
    local body = response.body

    if output_file then
      -- Save to file
      local path = sh:resolve_path(output_file)
      local fspath = sh:fs_path(path)
      local f = fs.open(fspath, "w")
      if not f then
        return sh:error("Cannot write to " .. output_file)
      end
      f:write(body)
      f:close()
      sh:success(string.format("Saved %d bytes to %s", #body, output_file))
    else
      -- Print to console
      --print("")
      --print(body)
      print("")
      local response = json.decode(body)
      for k, v in pairs(response) do
        print(c.cyan .. k .. c.white .. ": " .. c.green .. v .. c.white)
      end
      print("")
    end

    -- unload modules to save memory
    package.loaded["lua/modules/http"] = nil
    package.loaded["lua/modules/json"] = nil
    collectgarbage()
    
  end
}
