--[[
    fetch.lua - Simple HTTP fetch command
    External command for shell.lua
]]

return {
    name = "fetch",
    aliases = {"wget", "get"},
    help = "'fetch <url> [file]' - download URL (optionally save to file)",
    run = function(args, sh)
        if not args[1] then
            return sh:error("Usage: fetch <url> [output_file]")
        end

        if not wifi.isConnected() then
            return sh:error("Wi-Fi not connected")
        end

        local url = args[1]
        local output_file = args[2]

        -- Load http module
        local ok, http = pcall(require, "lua/http")
        if not ok then
            return sh:error("HTTP module not available")
        end

        print("Fetching " .. url .. "...")

        local response, err = http.get(url)

        if not response then
            return sh:error(err or "request failed")
        end

        print(string.format("Status: %d %s", response.status, response.reason or ""))

        if response.status >= 400 then
            return sh:error("Request failed with status " .. response.status)
        end

        local body = response.body or ""

        if output_file then
            -- Save to file
            local path = sh:resolve_path(output_file)
            local fspath = sh:fs_path(path)
            local f = fs.open(fspath, "w")
            if not f then
                return sh:error("Cannot write to " .. output_file)
            end
            f:write(body)
            f:close()
            sh:success(string.format("Saved %d bytes to %s", #body, output_file))
        else
            -- Print to console
            print("")
            print(body)
        end
    end
}
