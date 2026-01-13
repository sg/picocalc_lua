--[[

  simple-colors.lua

  - can be 'required' into any script to allow
    easy color code usage

]]
-- ANSI color codes
local c = {
  black   = "\27[90m",
  red     = "\27[91m",
  green   = "\27[92m",
  yellow  = "\27[93m",
  blue    = "\27[94m",
  magenta = "\27[95m",
  cyan    = "\27[96m",
  white   = "\27[97m",
  reset   = "\27[0m",
}

return c
