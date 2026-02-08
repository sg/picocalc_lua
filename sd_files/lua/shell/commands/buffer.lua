--[[

  buffer.lua - Toggle PSRAM display buffer mode
  Required for taking screenshots of the terminal.

]]

local c = require("lua/modules/simple-colors")

return {
  name = "buffer",
  help = c.cyan.."buffer"..c.yellow.." [on|off]"..c.white.." - PSRAM buffer mode for screenshots",
  run = function(args, sh)
    local mode = args[1]

    if mode == "on" or mode == "1" then
      if draw.enableBuffer(1) then  -- PSRAM mode
        -- Set global flag for readline auto-blit
        _G._buffer_mode_blit = true
        -- Clear and show the buffer
        term.clear()
        draw.blitBuffer()
        sh:success("PSRAM buffer mode enabled")
        term.write("Auto-blit active - display will update automatically\n")
        draw.blitBuffer()
      else
        sh:error("Failed to enable buffer mode")
      end
    elseif mode == "off" or mode == "0" then
      _G._buffer_mode_blit = false
      draw.enableBuffer(0)  -- Direct mode
      sh:success("Direct mode enabled")
    else
      -- Show usage and current status
      local status = _G._buffer_mode_blit and "ON (PSRAM)" or "OFF (Direct)"
      term.write("Buffer mode: " .. c.yellow .. status .. c.white .. "\n")
      term.write("\n")
      term.write("Usage: " .. c.cyan .. "buffer" .. c.yellow .. " [on|off]" .. c.white .. "\n")
      term.write("Enables PSRAM buffer mode for screenshots.\n")
      term.write("\n")
      term.write("Example workflow:\n")
      term.write("  " .. c.cyan .. "buffer on" .. c.white .. "   - Enable buffer mode\n")
      term.write("  " .. c.cyan .. "help" .. c.white .. "        - (use shell normally)\n")
      term.write("  " .. c.cyan .. "ss" .. c.white .. "          - Take screenshot\n")
      term.write("  " .. c.cyan .. "buffer off" .. c.white .. "  - Return to direct mode\n")
    end
  end
}
