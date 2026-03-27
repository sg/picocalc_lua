--[[

  ntp.lua - NTP client module for PicoCalc Lua

  Queries an NTP server via UDP and returns the current
  Unix epoch time. Sets two globals on success:

    _G.epoch_boot  - epoch time when the device booted
                     (computed as ntp_epoch - os.time())
    _G.epoch_time  - epoch time at the moment of sync

  Any script can get the approximate current time with:
    os.time() + _G.epoch_boot

  Usage:
    local ntp = require("lua/modules/ntp")
    local epoch = ntp.sync()            -- uses default server
    local epoch = ntp.sync("time.google.com")
    local epoch = ntp.time()            -- current epoch (no network)
    print(ntp.iso(ntp.time()))          -- "2026-03-15T14:30:00Z"

  NTP timestamp parsing uses byte-level subtraction of the
  NTP epoch offset so the result stays within 32-bit integer
  range, avoiding float precision loss on this platform.

]]

local ntp = {}

local NTP_PORT = 123
local NTP_PACKET_SIZE = 48
local DEFAULT_SERVER = "pool.ntp.org"
local TIMEOUT = 5  -- seconds

-- NTP epoch offset 2208988800 = 0x83AA7E80
-- Split into bytes for subtraction without overflow
local OFF1, OFF2, OFF3, OFF4 = 0x83, 0xAA, 0x7E, 0x80

-- Minimal SNTPv3 request: LI=0, VN=3, Mode=3 -> 0x1B, rest zeros
local NTP_REQUEST = string.char(0x1B) .. string.rep("\0", 47)

-- Days in each month (non-leap)
local MDAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

-- Read 4 bytes from an NTP timestamp and subtract the NTP epoch
-- offset (2208988800) using byte-level arithmetic. Returns the
-- Unix epoch as an integer (fits in int32 until 2038).
local function read_epoch(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  if b1 == 0 and b2 == 0 and b3 == 0 and b4 == 0 then
    return nil
  end
  local d4 = b4 - OFF4
  local d3 = b3 - OFF3
  local d2 = b2 - OFF2
  local d1 = b1 - OFF1
  if d4 < 0 then d4 = d4 + 256; d3 = d3 - 1 end
  if d3 < 0 then d3 = d3 + 256; d2 = d2 - 1 end
  if d2 < 0 then d2 = d2 + 256; d1 = d1 - 1 end
  return d1 * 16777216 + d2 * 65536 + d3 * 256 + d4
end

--- Convert a Unix epoch integer to an ISO 8601 UTC string.
-- @param epoch Unix timestamp (integer)
-- @return string like "2026-03-15T14:30:00Z"
function ntp.iso(epoch)
  if not epoch then return "nil" end
  local s = epoch
  local sec = s % 60; s = s // 60
  local min = s % 60; s = s // 60
  local hour = s % 24; s = s // 24
  -- s is now days since 1970-01-01
  local year = 1970
  while true do
    local dy = 365
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
      dy = 366
    end
    if s < dy then break end
    s = s - dy
    year = year + 1
  end
  local leap = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0))
  local month = 1
  while month <= 12 do
    local dm = MDAYS[month]
    if month == 2 and leap then dm = 29 end
    if s < dm then break end
    s = s - dm
    month = month + 1
  end
  local day = s + 1
  return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
    year, month, day, hour, min, sec)
end

--- Convert a Unix epoch to a local ISO 8601 string using _G.time_zone.
-- @param epoch Unix timestamp (integer)
-- @return string like "2026-03-15T11:30:00-05:00" or UTC if no timezone set
function ntp.local_iso(epoch)
  if not epoch then return "nil" end
  local tz = _G.time_zone
  if not tz then return ntp.iso(epoch) end
  local local_epoch = epoch + tz * 3600
  local s = local_epoch
  local sec = s % 60; s = s // 60
  local min = s % 60; s = s // 60
  local hour = s % 24; s = s // 24
  local year = 1970
  while true do
    local dy = 365
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
      dy = 366
    end
    if s < dy then break end
    s = s - dy
    year = year + 1
  end
  local leap = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0))
  local month = 1
  while month <= 12 do
    local dm = MDAYS[month]
    if month == 2 and leap then dm = 29 end
    if s < dm then break end
    s = s - dm
    month = month + 1
  end
  local day = s + 1
  local sign = tz >= 0 and "+" or "-"
  local abs_tz = math.abs(tz)
  local tz_h = abs_tz // 1
  local tz_m = (abs_tz % 1) * 60
  return string.format("%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d",
    year, month, day, hour, min, sec, sign, tz_h, tz_m)
end

--- Format an epoch as a plain integer string (no scientific notation).
-- @param epoch Unix timestamp (number)
-- @return string like "1742054400"
function ntp.fmt(epoch)
  if not epoch then return "nil" end
  return string.format("%d", epoch)
end

--- Query an NTP server and return the Unix epoch time.
-- On success, sets _G.epoch_boot and _G.epoch_time.
-- @param server NTP server hostname (default: "pool.ntp.org")
-- @return epoch_time (integer) on success, or nil + error string
function ntp.sync(server)
  server = server or DEFAULT_SERVER

  -- resolve hostname
  local ip, err = socket.dns.resolve(server)
  if not ip then
    return nil, "DNS failed: " .. (err or server)
  end

  -- create UDP socket
  local sock
  sock, err = socket.udp()
  if not sock then
    return nil, "UDP socket failed: " .. (err or "unknown")
  end
  sock:settimeout(TIMEOUT)

  -- send NTP request
  local sent, send_err = sock:sendto(NTP_REQUEST, ip, NTP_PORT)
  if not sent then
    sock:close()
    return nil, "Send failed: " .. (send_err or "unknown")
  end

  -- receive response
  local data, recv_ip, recv_port = sock:receivefrom(512)
  sock:close()

  if not data then
    return nil, "No response (timeout)"
  end

  if #data < NTP_PACKET_SIZE then
    return nil, "Short response: " .. #data .. " bytes"
  end

  -- Extract transmit timestamp (bytes 41-44) and convert to Unix epoch
  local epoch = read_epoch(data, 41)

  if not epoch then
    return nil, "Server returned empty timestamp"
  end

  if epoch < 0 then
    return nil, "Timestamp before Unix epoch"
  end

  -- Store boot epoch: subtract uptime so any script can compute
  -- current time as os.time() + _G.epoch_boot
  _G.epoch_boot = epoch - os.time()
  _G.epoch_time = epoch

  return epoch
end

--- Return the current estimated epoch time using the boot offset.
-- Does not make a network request. Returns nil if no sync has occurred.
-- @return epoch_time (integer) or nil
function ntp.time()
  if not _G.epoch_boot then return nil end
  local epoch = os.time() + _G.epoch_boot
  _G.epoch_time = epoch
  return epoch
end

return ntp
