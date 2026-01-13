--------------------------------------------
-- main.lua - startup file for picocalc_lua
--------------------------------------------

print("")
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

--if term.read("Init Wifi? [Y]/n: ") ~= "n" then
--  dofile("lua/wifi-start.lua")
--end

if term.read("Start command shell? [Y]/n: ") ~= "n" then
  dofile("shell.lua")
end

