--[[

  wx.lua - fetch weather forecast using open-meteo
           API.

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")
local json = require("lua/modules/json")
-- Load http module
local http = require("lua/modules/http")


return {
  name = "wx",
  aliases = {"weather"},
  help = c.cyan.."wx"..c.yellow.." [lat][lon][file]"..c.white.." - download weather forecast",
  run = function(args, sh)
    local output_file = nil
    local lat = "30.31"
    local lon = "-97.95"

    if args[1] then
      lat = args[1]
      if not args[2] then
        print("Usage: wx [lat] [lon] [file]")
      else
        lon = args[2]
      end
    end

    if args[3] then
      output_file = args[3]
    end

    if not wifi.isConnected() then
      return sh:error("Wi-Fi not connected")
    end


    local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. "&longitude=" .. lon .. "&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m&wind_speed_unit=mph&temperature_unit=fahrenheit&precipitation_unit=inch"
    print("Fetching current weather from api.open-meteo.com...")

    local response, err = http.get(url)

    if not response then
      return sh:error(err or "request failed")
    end

    print(string.format("Status: %d %s", response.status, response.reason or ""))

    if response.status >= 400 then
      return sh:error("Request failed with status " .. response.status)
    end

    local body = response.body:match('{.*}}') or ""

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
      local current_wx = response["current"]
      for k, v in pairs(current_wx) do
        print(c.cyan .. k .. c.white .. ": " .. c.green .. v .. c.white)
      end
      print("")
    end
  end
}
