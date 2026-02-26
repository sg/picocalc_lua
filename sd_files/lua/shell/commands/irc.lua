--[[

  irc - internet relay chat

  Usage:
    irc <host> <port>   connect to host:port

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "irc",
  category = "net",
  help = c.cyan.."irc"..c.yellow.." [server] [port]"..c.white.." - internet relay chat",
  run = function(args, sh)
    if args then
      arg = args
    end
    dofile("lua/irc.lua")
  end
}
