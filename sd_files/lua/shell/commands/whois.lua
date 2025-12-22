--[[
    whois.lua - Simple WHOIS command
    External command for shell.lua
]]

return {
    name = "whois",
    aliases = {"who"},
    help = "'whois <domain|ip address> [file]' - retrieve WHOIS info (optionally save to file)",
    run = function(args, sh)
        if not args[1] then
            return sh:error("Usage: whois <domain|ip address> [output_file]")
        end

        if not wifi.isConnected() then
            return sh:error("Wi-Fi not connected")
        end

        local target = args[1]
        local output_file = args[2]

        -- Load whois module
        local ok, whois = pcall(require, "lua/whois")
        if not ok then
            return sh:error("WHOIS module not available")
        end

        print("Looking up " .. target .. "...")

        local response, err = whois(target)

        if not response then
            return sh:error(err or "lookup failed")
        end

        if output_file then
            -- Save to file
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
            -- Print to console
            print("")
            print(response)
        end
    end
}
