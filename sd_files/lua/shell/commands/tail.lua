--[[
  tail.lua - display the last few lines of a file
]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "tail",
  help = c.cyan.."tail"..c.yellow.." <file> [n]"..c.white.." - print last n lines [default 10]",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: tail <file> [num_lines]")
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
    local pos = f:seek("end", (-80 * num_lines))
    --print("pos = " .. pos)
    local tail_table = {}
    while true do
      local line = f:readLine()
      if not line then
        break
      else
        table.insert(tail_table, line)
        count = count + 1
      end
    end
    --print("read " .. count .. " lines.")
    f:close()
    
    local extra_lines = count - num_lines
    for i = 1, count do
      if i > extra_lines then
        print(tail_table[i])
      end
    end
  end
}
