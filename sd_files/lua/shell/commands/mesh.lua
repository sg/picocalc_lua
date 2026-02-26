--[[

  mesh - MeshCore radio client

  Usage:
    mesh [host] [port]              connect to MeshCore node
    mesh -v [host] [port]           connect with verbose output
    mesh [host] [port] [logfile]    log output to /lua/modules/mesh/<logfile>

]]

local c = require("lua/modules/simple-colors")

return {
  name = "mesh",
  help = c.cyan.."mesh"..c.yellow.." [-v] [host] [port] [logfile]"..c.white.." - MeshCore radio client",
  run = function(args, sh)
    if args then
      arg = args
    end
    term.loadFont("fonts/ProggyClean.fnt")
    dofile("lua/mesh.lua")
    term.loadFont("fonts/HP6x8.fnt")
  end
}
