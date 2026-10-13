--[[

  show.lua - Display BMP image on screen
  Supports 16-bit RGB565, 24-bit BGR, and 32-bit BGRA formats.
  Streams row-by-row for minimal memory usage.

]]

return {
  name = "show",
  category = "util",
  aliases = {"view", "display"},
  usage = "<file.bmp>",
  desc = "display BMP image on screen",
  args = "file",
  run = function(args, sh)
    local ok, err = draw.showBMP(args.v[1])
    if not ok then
      return sh:error(err or "Failed to display image")
    end

    -- Image displayed, wait for keypress to return to shell
    term.read("Press Enter to continue...")
    term.clear()
  end
}
