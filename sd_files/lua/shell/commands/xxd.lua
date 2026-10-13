--[[

  xxd.lua - output hex and ascii byte values
            for a given file

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

local LINE = 16

-- rendered ascii cell for every byte value, keyed by the character
-- itself so gsub can use the table directly
local ascii_of = {}
local dot = c.cyan .. " ." .. c.white
for i = 0, 255 do
  local ch = string.char(i)
  if i >= 32 and i < 127 then
    ascii_of[ch] = c.green .. " " .. ch .. c.white
  else
    ascii_of[ch] = dot
  end
end

-- format string for a line of n bytes: pairs with a gap after the
-- seventh byte, missing bytes padded to keep the ascii row aligned
local function hex_format(n)
  local left = math.min(n, 7)
  local right = n - left
  return ("%02x"):rep(left) .. ("   "):rep(7 - left) .. " "
    .. ("%02x"):rep(right) .. ("   "):rep(LINE - 7 - right)
end

local function ascii_line(chunk, n)
  local left = math.min(n, 7)
  local right = n - left
  return (chunk:sub(1, 7):gsub(".", ascii_of)) .. ("   "):rep(7 - left) .. " "
    .. (chunk:sub(8):gsub(".", ascii_of)) .. ("   "):rep(LINE - 7 - right)
end

return {
  name = "xxd",
  category = "util",
  aliases = {"hexdump"},
  usage = "<file> [count]",
  desc = "print hex/ascii values of file",
  args = "file number?",
  pager = true,
  run = function(args)
    local fspath = args.v[1]
    local max_bytes = args.v[2] or 256

    local f <close> = fs.open(fspath, "r")
    local fattrib = fs.attributes(fspath)
    print("file size: " .. fattrib.size)

    local len = math.min(fattrib.size, max_bytes)
    local full_fmt = c.yellow .. "%08x:" .. c.white .. hex_format(LINE)
    local offset = 0

    while offset < len do
      local chunk = f:read(math.min(LINE, len - offset))
      if not chunk then break end
      local n = #chunk

      local fmt = full_fmt
      if n < LINE then
        fmt = c.yellow .. "%08x:" .. c.white .. hex_format(n)
      end
      print(fmt:format(offset, chunk:byte(1, n)))
      print("         " .. ascii_line(chunk, n))
      offset = offset + n
    end

    if fattrib.size > max_bytes then
      print(string.format("... (%d more bytes)", fattrib.size - max_bytes))
    end

    print(string.format("\nTotal: %d bytes", fattrib.size))
  end
}
