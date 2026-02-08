--[[

  simple-colors.lua

  - can be 'required' into any script to allow
    easy color code usage

]]

-- ANSI color codes
local ESC = "\27["
local RESET = ESC .. "0m"
local BOLD = ESC .. "1m"
local DIM = ESC .. "2m"
local ITALIC = ESC .. "3m"
local REVERSE = ESC .. "7m"
local CLEAR_LINE = ESC .. "K"

local c = {
  black   = ESC .. "90m",
  red     = ESC .. "91m",
  green   = ESC .. "92m",
  yellow  = ESC .. "93m",
  blue    = ESC .. "94m",
  magenta = ESC .. "95m",
  cyan    = ESC .. "96m",
  white   = ESC .. "97m",
  reset   = RESET,
  bold    = BOLD,
  dim     = DIM,
  italic  = ITALIC,
  reverse = REVERSE,
  clrline = CLEAR_LINE,
}

return c
