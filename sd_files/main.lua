--------------------------------------------
-- main.lua - startup file for picocalc_lua
--------------------------------------------

-- load user config into _G
local conf_path = "lua/picolua.conf"
if fs.exists(conf_path) then
  local ok, conf = pcall(dofile, conf_path)
  if ok and type(conf) == "table" then
    local count = 0
    for k, v in pairs(conf) do
      _G[k] = v
      count = count + 1
    end
    if count > 0 then
      term.write("\27[92mConfig:\27[97m " .. conf_path .. "\n")
      for k, v in pairs(conf) do
        term.write("  \27[96m" .. tostring(k) .. "\27[97m = " .. tostring(v) .. "\n")
      end
    else
      term.write("\27[93mConfig:\27[97m " .. conf_path .. " (no values set, time_zone = UTC)\n")
    end
  else
    term.write("\27[91mConfig:\27[97m " .. conf_path .. " failed to load\n")
  end
else
  -- create placeholder config
  local f = fs.open(conf_path, "w")
  if f then
    f:write("--[[\n")
    f:write("\n")
    f:write("  picolua.conf - PicoCalc Lua configuration\n")
    f:write("\n")
    f:write("  All key/value pairs in this table are loaded into _G\n")
    f:write("  at startup and available to all scripts.\n")
    f:write("\n")
    f:write("  Example:\n")
    f:write("    return {\n")
    f:write("      time_zone = -5,   -- UTC offset (-5=CDT, 0=UTC, 1=CET, 5.5=IST)\n")
    f:write("      my_setting = \"value\",\n")
    f:write("    }\n")
    f:write("\n")
    f:write("]]\n")
    f:write("\n")
    f:write("return {\n")
    f:write("  time_zone = 0,\n")
    f:write("}\n")
    f:flush()
    f:close()
    _G.time_zone = 0
    term.write("\27[93mConfig:\27[97m created " .. conf_path .. " (time_zone = UTC)\n")
    term.write("  Edit to set your timezone: \27[96medit /" .. conf_path .. "\27[97m\n")
  end
end

print("")
term.setTextColor(colors.lime)
print("Loaded modules:")
term.setTextColor(colors.lightBlue)
for name, module_table in pairs(package.loaded) do
  term.write(name.." ")
end
term.setTextColor(colors.white)
term.write("\n\n")

--browser = loadfile("lua/browser.lua")
--if browser then print("File browser available at: browser()") end
if package.loaded["wifi"] then
  if term.read("\27[93mConnect to Wifi? \27[97m[\27[92mY\27[97m]/n: ") ~= "n" then
    dofile("lua/wifi-start.lua")
  end
end

if fs.exists("shell.lua") then
  if term.read("\n\27[93mStart command shell? \27[97m[\27[92mY\27[97m]/n: ") ~= "n" then
    dofile("shell.lua")
  end
end

