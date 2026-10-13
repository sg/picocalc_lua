--[[

  module-list.lua - print the names of currenly loaded modules

]]

return {
  name = "modules",
  category = "core",
  aliases = {"packages"},
  usage = "",
  desc = "print the names of loaded modules",
  run = function(args)
    term.write("\n")
    term.setTextColor(colors.lime)
    print("Loaded modules:")
    for name, module_table in pairs(package.loaded) do
      term.setTextColor(colors.white)
      term.write("--> ")
      term.setTextColor(colors.lightBlue)
      term.write(name.."\n")
    end
    term.setTextColor(colors.white)
    term.write("\n")
  end
}
