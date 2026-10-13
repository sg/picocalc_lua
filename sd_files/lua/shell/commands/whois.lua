--[[
  whois.lua - simple WHOIS command
  (requires the whois.lua module in shell/modules)
]]

return {
  name = "whois",
  category = "net",
  aliases = {"who"},
  usage = "<domain|ip> [file]",
  desc = "get WHOIS info [to file]",
  args = "string path?",
  needs = {"wifi"},
  pager = true,
  run = function(args, sh)
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
      local f <close> = fs.open(args.v[2], "w")
      f:write(response)
      sh:success(string.format("Saved %d bytes to %s", #response, output_file))
    else
      print("")
      print(response)
    end
  end
}
