--
-- xor encoder/decoder
--
-- xor data with supplied key
--
-- based on:
-- https://github.com/Braayy/xor-lua
--
-- example:
--
--  local x = require("xor")
--  local xored_msg = x.xor("message", "key")
--
local x = {}

function x.repeat_key(key, length)
  if #key >= length then
    return key:sub(1, length)
  end

  local times = math.floor(length / #key)
  local remain = length % #key

  local result = ''

  for i = 1, times do
    result = result .. key
  end

  if remain > 0 then
    result = result .. key:sub(1, remain)
  end

  return result

end


function x.xor(message, key)
  
  local rkey = x.repeat_key(key, #message)

  local result = ''

  for i = 1, #message do

    local k_char = rkey:sub(i, i)
    local m_char = message:sub(i, i)

    local k_byte = k_char:byte()
    local m_byte = m_char:byte()

    xor_byte = m_byte ~ k_byte

    xor_char = string.char(xor_byte)

    result = result .. xor_char

   end

   return result

end

return x
