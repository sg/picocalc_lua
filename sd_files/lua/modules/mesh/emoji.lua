--[[
  mesh/emoji.lua - Emoji to ASCII shortcode conversion

  Single bidirectional table: UTF-8 bytes -> shortcode AND
  shortcode -> UTF-8 bytes, to minimise memory usage.
]]

local M = {}

-- Single bidirectional lookup table
-- Keys are both raw UTF-8 byte sequences and :shortcode: strings
local map = {}

local function add(bytes, code)
  map[bytes] = code
  map[code] = bytes
end

-- Smileys
add("\xF0\x9F\x98\x80", ":grinning:")
add("\xF0\x9F\x98\x82", ":joy:")
add("\xF0\x9F\x98\x84", ":smile:")
add("\xF0\x9F\x98\x86", ":laughing:")
add("\xF0\x9F\x98\x89", ":wink:")
add("\xF0\x9F\x98\x8A", ":blush:")
add("\xF0\x9F\x98\x8D", ":heart_eyes:")
add("\xF0\x9F\x98\x8E", ":sunglasses:")
add("\xF0\x9F\x98\xA0", ":angry:")
add("\xF0\x9F\x98\xA2", ":cry:")
add("\xF0\x9F\x98\xAD", ":sob:")
add("\xF0\x9F\x99\x82", ":slightly_smiling:")
add("\xF0\x9F\xA4\x94", ":thinking:")
add("\xF0\x9F\xA4\xA3", ":rofl:")
add("\xF0\x9F\xA4\xA6", ":facepalm:")
add("\xF0\x9F\xA4\xB7", ":shrug:")

-- Gestures
add("\xF0\x9F\x91\x8D", ":thumbsup:")
add("\xF0\x9F\x91\x8E", ":thumbsdown:")
add("\xF0\x9F\x91\x8B", ":wave:")
add("\xF0\x9F\x91\x8F", ":clap:")
add("\xF0\x9F\x91\x80", ":eyes:")
add("\xF0\x9F\x99\x8F", ":pray:")

-- Symbols and objects
add("\xF0\x9F\x94\xA5", ":fire:")
add("\xF0\x9F\x92\xAF", ":100:")
add("\xF0\x9F\x92\x80", ":skull:")
add("\xF0\x9F\x8E\x89", ":tada:")
add("\xF0\x9F\x92\xAA", ":muscle:")
add("\xF0\x9F\x9A\x80", ":rocket:")

-- 3-byte symbols
add("\xE2\x9D\xA4", ":heart:")
add("\xE2\x9C\x85", ":check:")
add("\xE2\x9D\x8C", ":x:")
add("\xE2\x9A\xA1", ":zap:")
add("\xE2\x9C\xA8", ":sparkles:")
add("\xE2\x98\x95", ":coffee:")

-- Replace :shortcode: with UTF-8 emoji bytes for sending
function M.encode(text)
  if not text or text == "" then return text end
  return text:gsub("(:[%w_]+:)", function(code)
    return map[code] or code
  end)
end

-- Common Unicode typography -> ASCII equivalents
-- These are auto-inserted by phone keyboards and can't render on PicoCalc
local typography = {
  ["\xE2\x80\x98"] = "'",   -- left single quote
  ["\xE2\x80\x99"] = "'",   -- right single quote
  ["\xE2\x80\x9C"] = '"',   -- left double quote
  ["\xE2\x80\x9D"] = '"',   -- right double quote
  ["\xE2\x80\x93"] = "-",   -- en dash
  ["\xE2\x80\x94"] = "--",  -- em dash
  ["\xE2\x80\xA6"] = "...", -- ellipsis
}

-- Replace emoji in text with shortcodes
function M.replace(text)
  if not text or text == "" then return text end

  -- Normalize smart quotes and other typography to ASCII first
  for utf8, ascii in pairs(typography) do
    text = text:gsub(utf8, ascii)
  end

  -- Replace 4-byte UTF-8 sequences (most emoji)
  text = text:gsub("([\xF0-\xF4][\x80-\xBF][\x80-\xBF][\x80-\xBF])", function(seq)
    return map[seq] or "[?]"
  end)

  -- Replace 3-byte symbols (E2 range = U+2000-2FFF, mostly symbols)
  text = text:gsub("(\xE2[\x80-\xBF][\x80-\xBF])", function(seq)
    return map[seq] or "[?]"
  end)
  -- Replace known 3-byte emoji in other ranges (leave unknown alone)
  text = text:gsub("([\xE3-\xEF][\x80-\xBF][\x80-\xBF])", function(seq)
    return map[seq] or seq
  end)

  -- Strip variation selectors (U+FE0E, U+FE0F)
  text = text:gsub("\xEF\xB8\x8E", "")
  text = text:gsub("\xEF\xB8\x8F", "")

  return text
end

return M
