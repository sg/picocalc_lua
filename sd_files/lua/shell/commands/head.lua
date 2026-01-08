--[[

  head.lua - display first few lines of a file

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
  name = "head",
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

    local content = f:readAll()
    f:close()

    if not content or content == "" then
      print("(empty file)")
      return
    end

    local count = 0
    for line in content:gmatch("[^\n]*") do
      if count >= num_lines then
        break
      end
      print(line)
      count = count + 1
    end
  end
}
