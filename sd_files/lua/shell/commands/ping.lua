--[[
    ping.lua - Simple connectivity check
    External command for shell.lua

    Note: This is a TCP connect test since ICMP ping requires raw sockets
    which aren't available. It tests if a host is reachable on a given port.
]]

return {
    name = "ping",
    aliases = {"tcping"},
    help = "'ping <host> [port]' - test connectivity to host (TCP)",
    run = function(args, sh)
        if not args[1] then
            return sh:error("Usage: ping <host> [port]")
        end

        if not wifi.isConnected() then
            return sh:error("Wi-Fi not connected")
        end

        local host = args[1]
        local port = tonumber(args[2]) or 80
        local count = 4

        print(string.format("PING %s:%d (TCP connect test)", host, port))

        local successes = 0
        local total_time = 0

        for i = 1, count do
            local sock, err = socket.tcp()
            if not sock then
                print(string.format("  #%d: Failed to create socket", i))
            else
                local start = os.clock()
                local ok, conn_err = sock:connect(host, port, 5000)
                local elapsed = (os.clock() - start) * 1000

                if ok then
                    successes = successes + 1
                    total_time = total_time + elapsed
                    print(string.format("  #%d: Connected - %.0fms", i, elapsed))
                else
                    print(string.format("  #%d: %s", i, conn_err or "timeout"))
                end

                sock:close()
            end

            -- Small delay between attempts
            if i < count then
                for j = 1, 50000 do end
            end
        end

        print("")
        print(string.format("--- %s ping statistics ---", host))
        print(string.format("%d packets transmitted, %d received, %.0f%% loss",
            count, successes, ((count - successes) / count) * 100))

        if successes > 0 then
            print(string.format("avg time: %.0fms", total_time / successes))
        end
    end
}
