--[[

  ntp.lua - NTP time sync command

  Usage:
    ntp              - show last synced and current estimated time
    ntp -s           - sync time from pool.ntp.org
    ntp -s <server>  - sync time from a specific NTP server

]]

local c = require("lua/modules/simple-colors")

local function show_time(ntp, label, epoch)
  term.write(c.cyan .. label .. c.white .. "\n")
  term.write(c.cyan .. "  Epoch: " .. c.white .. ntp.fmt(epoch) .. "\n")
  term.write(c.cyan .. "    UTC: " .. c.white .. ntp.iso(epoch) .. "\n")
  if _G.time_zone then
    term.write(c.cyan .. "  Local: " .. c.white .. ntp.local_iso(epoch) .. "\n")
  end
end

return {
  name = "ntp",
  category = "net",
  usage = "[-s [server]]",
  desc = "show or sync NTP time",
  long = "  ntp             show last synced and current time\n"
    .. "  ntp -s          sync time from pool.ntp.org\n"
    .. "  ntp -s <server> sync time from a specific server",
  flags = "s",
  args = "string?",
  run = function(args, sh)
    -- a server only makes sense together with -s
    if args[1] and not args.flags.s then
      return sh:usage("ntp")
    end

    local ntp = require("lua/modules/ntp")

    if args.flags.s then
      if not wifi.isConnected() then
        return sh:error("Wi-Fi not connected")
      end

      local server = args[1]
      term.write("Syncing from " .. c.cyan
        .. (server or "pool.ntp.org") .. c.white .. "...\n")

      local epoch, err = ntp.sync(server)
      if not epoch then
        return sh:error("NTP sync failed: " .. (err or "unknown"))
      end

      term.write(c.green .. "Synced!" .. c.white .. "\n")
      show_time(ntp, "Time:", epoch)
      return
    end

    if not _G.epoch_boot then
      term.write(c.yellow .. "No NTP sync yet." .. c.white .. "\n")
      term.write("Run " .. c.cyan .. "ntp -s" .. c.white .. " to sync.\n")
      return
    end

    show_time(ntp, "Last sync:", _G.epoch_time)
    show_time(ntp, "Current:", ntp.time())
  end,
}
