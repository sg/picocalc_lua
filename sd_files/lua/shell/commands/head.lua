--[[

  head.lua - display first few lines of a file

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "head",
  category = "util",
  help = c.cyan.."head"..c.yellow.." <file> [n]"..c.white.." - print top n lines of a file",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: head <file> [num_lines]")
    end

    local path = sh:resolve_path(args[1])
    local fspath = sh:fs_path(path)
    local num_lines = tonumber(args[2]) or 10

    if not fs.exists(fspath) then
      return sh:error("'" .. args[1] .. "' not found")
    end

    if fs.isDir(fspath) then
      return sh:error("'" .. args[1] .. "' is a directory")
    end

    local f = fs.open(fspath, "r")
    if not f then
      return sh:error("Cannot open '" .. args[1] .. "'")
    end

    local count = 0
    while count < num_lines do
      local line = f:readLine()
      if not line then
        break
      else
        print(line)
        count = count + 1
      end    
    end
    f:close()

  end
}
