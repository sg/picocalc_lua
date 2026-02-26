--[[

  wx.lua - fetch weather forecast using open-meteo
           API.

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

local function free_mem()
  package.loaded["lua/modules/http"] = nil
  package.loaded["lua/modules/json"] = nil
  package.loaded["lua/modules/serialize"] = nil
  collectgarbage()
end

return {
  name = "wx",
  category = "net",
  aliases = {"weather"},
  help = c.cyan.."wx"..c.yellow..""..c.white.." - download weather forecast",
  run = function(args, sh)

    local ok, c = pcall(require,"lua/modules/simple-colors")
    if not ok then
      print("Can't find 'lua/modules/simple-colors.lua'")
      return
    end
    
    local ok, json = pcall(require,"lua/modules/json")
    if not ok then
      print("Can't find 'lua/modules/json.lua'")
      return
    end
   
    local ok, http = pcall(require,"lua/modules/http")
    if not ok then
      print("Can't find 'lua/modules/http.lua'")
      return
    end
    
    local ok, serialize = pcall(require,"lua/modules/serialize")
    
    if not ok then
      print("Can't find 'lua/modules/serialize.lua'")
      return
    end

    local default_lat = "30.25"
    local default_lon = "-97.75"
    local lat = ""
    local lon = ""
    local wx_conf_path = "lua/wx.conf"
    local wx_conf = {}
    local using_conf = false

    local function loadConfig()                               --
      local func, err = loadfile(wx_conf_path)
      if not func then
        print(c.red .. "Error: " .. c.white .. "failed to load wx.conf: " .. err)
	      return false
      end
      local success, conf = pcall(func)
      if not success then
        print(c.red .. "Error: " .. c.white .. "failed to pcall wx.conf code.")
        return false
      end
      wx_conf = conf
      print("wx.conf loaded...")
      return true
    end

    if fs.exists(wx_conf_path) then
      print("found " .. wx_conf_path)
      if loadConfig() then
        using_config = true
      end
    end

    if using_config then
      -- available locations in config
      local picker = {}
      for name, loc in pairs(wx_conf) do
        table.insert(picker, name)
      end
      -- sort alphabtically
      table.sort(picker, function(a, b)
        return a:lower() < b:lower()
      end)

      for i, name in ipairs(picker) do
        print(string.format("%2d. %s", i, name))
      end
    
      local selection = term.read("Choose location: [1] ")
      if selection == "" then selection = "1" end
      if tonumber(selection) > #picker then
        print(c.red .. "Error: " .. c.white .. "invalid selection.")
        free_mem()
        return
      end

      local loc_idx = tonumber(selection)
      lat = wx_conf[picker[loc_idx]]["lat"]
      lon = wx_conf[picker[loc_idx]]["lon"]
    else
      lat = term.read("Enter latitude: [" .. default_lat .. "] ")
      if lat == "" then lat = default_lat end
      lon = term.read("Enter longitude: [" .. default_lon .. "] ")
      if lon == "" then lon = default_lon end
    end

    local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. "&longitude=" .. lon .. "&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m&wind_speed_unit=mph&temperature_unit=fahrenheit&precipitation_unit=inch"
  
    if not wifi.isConnected() then
      print("Wi-Fi not connected")
      free_mem()
      return
    end

    print("Fetching current weather from api.open-meteocom...")
    local response, err = http.get(url)

    if not response then
      print("Request failed:" .. err)
      free_mem()
      return
    end

    print(string.format("Status: %d %s", response.status, response.reason or ""))

    if response.status >= 400 then
      print("Request failed with status " .. response.status)
      free_mem()
      return
    end

    local body = response.body:match('{.*}}') or ""
    --print("")
    --print(body)
    print("")
    local response_tbl = json.decode(body)
    local current_wx = response_tbl["current"]
    for k, v in pairs(current_wx) do
      print(c.cyan .. k .. c.white .. ": " .. c.green .. v .. c.white)
    end
    print("")
    free_mem()

  end
}
