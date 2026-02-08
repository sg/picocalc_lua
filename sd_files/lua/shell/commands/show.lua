--[[

  show.lua - Display BMP image on screen
  Supports 16-bit RGB565, 24-bit BGR, and 32-bit BGRA formats.
  Streams row-by-row for minimal memory usage.

]]

local c = require("lua/modules/simple-colors")

return {
  name = "show",
  aliases = {"view", "display"},
  help = c.cyan.."show"..c.yellow.." <file.bmp>"..c.white.." - display BMP image on screen",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: show <file.bmp>")
    end

    local path = sh:fs_path(sh:resolve_path(args[1]))
    if not fs.exists(path) then
      return sh:error("File not found: " .. args[1])
    end

    local ok, err = draw.showBMP(path)
    if not ok then
      return sh:error(err or "Failed to display image")
    end

    -- Image displayed, wait for keypress to return to shell
    term.read("Press Enter to continue...")
    term.clear()
  end
}
