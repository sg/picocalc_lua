--[[

  tz.lua - View or set timezone

  Usage:
    tz          - show current timezone
    tz <offset> - set timezone (e.g. -5, 0, 5.5)

]]

local c = require("lua/modules/simple-colors")

return {
  name = "tz",
  category = "util",
  usage = "[offset]",
  desc = "view or set UTC timezone offset",
  args = "number?",
  run = function(args, sh)
    local offset = args.v[1]

    if not offset then
      -- display current timezone
      local tz = _G.time_zone
      if tz then
        local sign = tz >= 0 and "+" or ""
        term.write(c.cyan .. "Timezone: " .. c.white
          .. "UTC" .. sign .. tostring(tz) .. "\n")
      else
        term.write(c.yellow .. "No timezone set" .. c.white
          .. " (assuming UTC)\n")
        term.write("Set with: " .. c.cyan .. "tz <offset>"
          .. c.white .. " (e.g. tz -5)\n")
      end
      return
    end

    if offset < -12 or offset > 14 then
      return sh:error("Offset out of range (-12 to +14)")
    end

    -- update _G
    _G.time_zone = offset

    -- update picolua.conf
    local conf_path = "lua/picolua.conf"
    local conf = {}
    if fs.exists(conf_path) then
      local ok, existing = pcall(dofile, conf_path)
      if ok and type(existing) == "table" then
        conf = existing
      end
    end
    conf.time_zone = offset

    local serialize = require("lua/modules/serialize")
    local f <close> = fs.open(conf_path, "w")
    serialize.toFile(conf, f)
    f:write("\n")
    f:flush()

    local sign = offset >= 0 and "+" or ""
    sh:success("Timezone set to UTC" .. sign .. tostring(offset))
  end,
}
