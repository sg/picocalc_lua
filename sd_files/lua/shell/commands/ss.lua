--[[

  ss.lua - Screenshot command
  Saves the current display to a BMP file.

]]

local c = require("lua/modules/simple-colors")

local DIRECT, PSRAM, RAM = 0, 1, 2
local FRAMEBUFFER_BYTES = 320 * 320 * 2

-- the panel cannot be read back, so in direct mode the terminal is
-- rebuilt from its shadow inside a temporary framebuffer
local function capture(path)
  if draw.getBufferMode() ~= DIRECT then
    return draw.screenshot(path)
  end

  -- a PSRAM framebuffer would overwrite buffers allocated below it
  local mode = PSRAM
  for _, a in ipairs(psram and psram.list() or {}) do
    if a.addr < FRAMEBUFFER_BYTES then mode = RAM end
  end

  local blink = term.getCursorBlink()
  term.setCursorBlink(false)
  local ok, err
  if not draw.enableBuffer(mode) then
    err = "Could not enable a framebuffer for the capture"
  elseif not term.redraw() then
    err = "Terminal shadow unavailable"
  else
    ok, err = draw.screenshot(path)
  end
  draw.enableBuffer(DIRECT)
  term.setCursorBlink(blink)

  if ok and mode == RAM then
    return true, "PSRAM is in use, so colours were reduced to 8 bits"
  end
  return ok, err
end

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
    local ok, note = capture(path)

    if ok then
      sh:success("Saved " .. path)
      if note then sh:warn(note) end
    else
      sh:error(note or "Screenshot failed")
    end
  end
}
