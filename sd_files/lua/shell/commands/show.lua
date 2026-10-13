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
  desc = "display BMP image on screen, any key returns",
  args = "file",
  run = function(args, sh)
    local blink = term.getCursorBlink()
    term.setCursorBlink(false)
    -- the terminal scrolls the panel, so clearing resets that offset
    -- and the image lands where showBMP addresses it
    term.clear()
    local ok, err = draw.showBMP(args.v[1])
    if ok then
      if draw.getBufferMode() ~= 0 then draw.blitBuffer() end
      -- no prompt: a full-screen image leaves nothing to print it on
      keys.wait()
    end
    term.clear()
    term.setCursorBlink(blink)
    if not ok then
      return sh:error(err or "Failed to display image")
    end
  end
}
