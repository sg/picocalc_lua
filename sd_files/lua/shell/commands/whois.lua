--[[
  whois.lua - simple WHOIS command
  (requires the whois.lua module in shell/modules)
]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "whois",
  category = "net",
  aliases = {"who"},
  help = c.cyan.."whois"..c.yellow.." <domain|ip> [file]"..c.white.." - get WHOIS info [to file]",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: whois <domain|ip address> [output_file]")
    end

    local target = args[1]
    local output_file = args[2]

    -- load whois module
    local ok, whois = pcall(require, "lua/shell/modules/whois")
    if not ok then
      return sh:error("WHOIS module not available")
    end

    print("Looking up " .. target .. "...")

    local response, err = whois(target)

    if not response then
      return sh:error(err or "lookup failed")
    end

    if output_file then
      -- save to file
      local path = sh:resolve_path(output_file)
      local fspath = sh:fs_path(path)
      local f = fs.open(fspath, "w")
      if not f then
        return sh:error("Cannot write to " .. output_file)
      end
      f:write(response)
      f:close()
      sh:success(string.format("Saved %d bytes to %s", #response, output_file))
    else
      -- print to console
      print("")
      print(response)
    end
  end
}
