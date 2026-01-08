--[[
  tail.lua - display the last few lines of a file
]]

-- ANSI color codes
local c = {
  black   = "\27[90m",
  red     = "\27[91m",
  green   = "\27[92m",
  yellow  = "\27[93m",
  blue    = "\27[94m",
  magenta = "\27[95m",
  cyan    = "\27[96m",
  white   = "\27[97m",
  reset   = "\27[0m",
}

return {
  name = "tail",
  help = c.cyan.."tail"..c.yellow.." <file> [n]"..c.white.." - print last n lines (default 10)",
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

    -- reading the whole file for now, but should change
    -- this to be smarter so it doesn't cause an out of
    -- memory panic if the file is larger than available
    -- memory. Down below it loads the content as lines
    -- into a table, which doubles the memory footprint.
    local content = f:readAll()
    f:close()

    if not content or content == "" then
      print("(empty file)")
      return
    end

    -- load all lines into a table... yes, terrible
    local lines = {}
    for line in content:gmatch("[^\n]*") do
      table.insert(lines, line)
    end

    -- remove any empty lines 
    if lines[#lines] == "" then
      table.remove(lines)
    end

    -- prrint last n lines
    local start = math.max(1, #lines - num_lines + 1)
    for i = start, #lines do
      print(lines[i])
    end
  end
}
