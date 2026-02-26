--------------------------------------------
-- main.lua - startup file for picocalc_lua
--------------------------------------------
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

