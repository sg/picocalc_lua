--------------------------------------------
-- main.lua - startup file for picocalc_lua
--------------------------------------------
-- open a file to write output to
--local f = fs.open("lua-out.txt", "w+")
--if f == nil then
--    print("filehandle couldn't be opened")
--    return
--end


print("Available modules:")
--f:writeLine("Available modules:")
for name, module_table in pairs(package.loaded) do
  print("--> " .. name)
--  f:writeLine("--> " .. name)
end
--f:close()

-- local batLvl,charging = sys.battery()
-- print("Battery:" .. batLvl)
-- if charging then
--   print("Charging: true")
-- else
--   print("Charging: false")
-- end

--browser = loadfile("lua/browser.lua")
--if browser then print("File browser available at: browser()") end

--term.write("Init Wifi? [Y]/n: ")
--if term.read() ~= "n" then
--  dofile("lua/wifi-start.lua")
--end
term.write("Start command shell? [Y]/n: ")
if term.read() ~= "n" then
  dofile("shell.lua")
end

