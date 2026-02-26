--[[
  nc - Netcat shell command

  Usage:
    nc <host> <port>    TCP connect to host:port
    nc -l <port>        TCP server - listen on port
    nc -u <host> <port> UDP send to host:port
    nc -lu <port>       UDP server - listen on port
    nc -h               Show help
]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "nc",
  category = "net",
  aliases = {"netcat"},
  help = c.cyan.."nc"..c.yellow.." [-l] [-u] <host> <port>"..c.white.." - netcat network utility",
  run = function(args, sh)
    -- load the nc module
    local ok, nc = pcall(require, "lua/shell/modules/nc")
    if not ok then
      return sh:error("Failed to load nc module: " .. tostring(nc))
    end

    -- pass all arguments directly to nc module
    -- lua/shell/modules/nc.lua handles: wifi check,
    -- argument parsing, mode selection
    nc(table.unpack(args))
  end
}
