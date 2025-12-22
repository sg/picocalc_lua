--[[
    nc.lua - netcat command
    External command for shell.lua
]]

return {
    name = "nc",
    aliases = {"netcat"},
    help = "'nc <host> <port>' - tcp connect to host and port",
    run = function(args, sh)
        if #args < 2 then
            return sh:error("Usage: nc <host> <port>")
        end

        if not wifi.isConnected() then
            return sh:error("Wi-Fi not connected")
        end

        local host = args[1]
        local port = args[2]

        -- Load netcat module
        local ok, nc = pcall(require, "lua/nc")
        if not ok then
            return sh:error("netcat (nc) module not available")
        end

        print("Connecting to " .. host .. "...")

        local response, err = nc(host, port)

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
