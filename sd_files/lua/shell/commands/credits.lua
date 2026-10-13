--[[

  credits.lua - print the compiled-in credits screen

]]

return {
  name = "credits",
  category = "core",
  aliases = {"about"},
  usage = "",
  desc = "print the credits screen",
  run = function(args)
    credits()
  end
}
