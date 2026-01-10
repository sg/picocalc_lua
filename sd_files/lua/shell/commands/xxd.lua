--[[

  xxd.lua - output hex and ascii byte values
                for a given file

]]

-- ANSI color codes
local c = require("lua/shell/modules/simple-colors")

return {
  name = "xxd",
  aliases = {"hexdump"},
  help = c.cyan.."xxd"..c.yellow.." <file> [count]"..c.white.." - print hex/ascii values of file",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: xxd <file> [count]")
    end

    local path = sh:resolve_path(args[1])
    local fspath = sh:fs_path(path)
    local max_bytes = tonumber(args[2]) or 256

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

    -- make sure file isn't larger than free memory
    local fattrib = fs.attributes(fspath)
    print("file size: " .. fattrib.size)
    local freemem = sys.freeMemory()
    if freemem < fattrib.size then
      return sh:error("File larger than free memory ("..freemem..")")
    end

    -- for now we lazily load the whole file into memory.
    -- this can cause an out of memory panic if the file is
    -- larger than free memory. ymmv...
    local content = f:readAll()
    f:close()

    if not content then
      print("(empty file)")
      return
    end

    local len = math.min(#content, max_bytes)
    local offset = 0

    while offset < len do
      -- offset address (hex)
      local hex_offset = string.format(c.yellow .. "%08x:" .. c.white, offset)

      -- hex bytes
      local hex_part = ""
      local ascii_part = ""

      for i = 0, 15 do
        local pos = offset + i + 1
        if pos <= len then
          local byte = string.byte(content, pos)
          hex_part = hex_part .. string.format("%02x", byte)

          -- ASCII representation
          if byte >= 32 and byte < 127 then
            ascii_part = ascii_part .. c.green .. " " .. string.char(byte) .. c.white
          else
            ascii_part = ascii_part .. c.cyan .. " ." .. c.white
          end
        else
          hex_part = hex_part .. "   "
          ascii_part = ascii_part .. "   "
        end

        -- add extra space in middle
        if i == 7 then
          hex_part = hex_part .. " "
          ascii_part = ascii_part .. " "
        end
      end
      print(hex_offset .. hex_part)
      --print(hex_part .. "|" .. ascii_part) 
      print("         " .. ascii_part)
      --print("---------")
      offset = offset + 16
    end

    if #content > max_bytes then
      print(string.format("... (%d more bytes)", #content - max_bytes))
    end

    print(string.format("\nTotal: %d bytes", #content))
  end
}
