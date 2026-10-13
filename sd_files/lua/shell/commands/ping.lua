--[[
  ping.lua - 
  ICMP ping (using socket.ping)
]]

return {
  name = "ping",
  category = "net",
  usage = "<host> [count]",
  desc = "ICMP ping host",
  args = "string number?",
  needs = {"wifi"},
  run = function(args)
    local host = args[1]
    local count = args.v[2] or 4

    print(string.format("PING %s", host))

    local successes = 0
    local total_time = 0
    local resolved_ip = nil
    for i = 1, count do
      local result, err = socket.ping(host, 3000)

      if result then
        resolved_ip = result.ip
        if result.success then
          successes = successes + 1
          total_time = total_time + result.time
          print(string.format("  Reply from %s: time=%dms TTL=%d",
          result.ip, result.time, result.ttl))
        else
          print(string.format("  #%d: No reply", i))
        end
      else
        print(string.format("  #%d: %s", i, err or "failed"))
      end
    end

    print("")
    print(string.format("--- %s ping statistics ---", resolved_ip or host))
    print(string.format("%d packets transmitted, %d received, %.0f%% loss", count, successes, ((count - successes) / count) * 100))

    if successes > 0 then
      print(string.format("avg time: %.0fms", total_time / successes))
    end
  end
}
