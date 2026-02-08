--------------------------------------------
-- packs.lua - list package.loaded
--------------------------------------------

print("")
term.setTextColor(colors.lime)
print("Loaded modules:")
term.setTextColor(colors.lightBlue)
for name, module_table in pairs(package.loaded) do
  --print("--> " .. name)
  term.write(name.." ")
end
term.setTextColor(colors.white)
term.write("\n\n")


