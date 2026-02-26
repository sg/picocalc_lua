--[[

  ss.lua - Screenshot command
  Saves the current display to a BMP file.
  Requires buffer mode (PSRAM or RAM) to be enabled.

]]

local c = require("lua/modules/simple-colors")

return {
  name = "ss",
  category = "util",
  aliases = {"screenshot"},
  help = c.cyan.."ss"..c.yellow.." [filename]"..c.white.." - save screenshot to BMP file",
  run = function(args, sh)
    local filename = args[1]

    -- Auto-generate filename if not provided
    if not filename then
      local i = 1
      repeat
        filename = string.format("screen%03d.bmp", i)
        i = i + 1
      until not fs.exists(sh:fs_path(sh:resolve_path(filename)))
    end

    -- Add .bmp extension if not present
    if not filename:match("%.bmp$") then
      filename = filename .. ".bmp"
    end

    local path = sh:fs_path(sh:resolve_path(filename))
    local ok, err = draw.screenshot(path)

    if ok then
      sh:success("Saved " .. path)
    else
      sh:error(err or "Screenshot failed")
    end
  end
}
