--[[

  irc - internet relay chat

  Usage:
    irc <host> <port>   connect to host:port

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "irc",
  help = c.cyan.."irc"..c.yellow.." [server] [port]"..c.white.." - internet relay chat",
  run = function(args, sh)
    local ok, irc = pcall(require, "lua/irc")
    if not ok then
      return sh:error("Failed to load irc: " .. tostring(irc))
    end
    if args then
      irc.main(args)
    else
      irc.main()
    end
  end
}
