--------------------------------------------
-- main.lua - startup file for picocalc_lua
--------------------------------------------

term.setTextColor(colors.lime)
print("Available modules:")
term.setTextColor(colors.lightBlue)
for name, module_table in pairs(package.loaded) do
  --print("--> " .. name)
  term.write(name.." ")
end
term.setTextColor(colors.white)
term.write("\n\n")

browser = loadfile("lua/browser.lua")
--if browser then print("File browser available at: browser()") end

--term.write("Init Wifi? [Y]/n: ")
--if term.read() ~= "n" then
--  dofile("lua/wifi-start.lua")
--end
term.write("Start command shell? [Y]/n: ")
if term.read() ~= "n" then
  dofile("shell.lua")
end

