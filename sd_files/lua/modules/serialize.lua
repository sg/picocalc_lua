--[[

  serialize.lua -

  Serialize a Lua table to a string that can be
  written to a file. The string can be subsequently
  read from the file and deserialized back to table
  format. 

]]--

local serialize = {}

local function _serialize(o)
  local sz = ""
  if type(o) == "number" then
    sz = sz .. o
    --print("debug: num sz = " .. sz)
  elseif type(o) == "string" then
    sz = sz .. string.format("%q", o)
    --print("debug: str sz = " .. sz)
  elseif type(o) == "table" then
    sz = sz .. "{\n"
    for k,v in pairs(o) do
      sz = sz .. "  [" .. k .. "] = "
      sz = sz .. _serialize(v)
      sz = sz .. ",\n"
    end
    sz = sz .. "}"
    --print("debug: table sz = " .. sz)
  
  else
    error("cannot serialize a " .. type(o))
  end
  return sz
end
 
function serialize.toString(o)
  local sz = "return "
  --print("debug: sz = " .. sz)
  sz = sz .. _serialize(o)
  return sz
end

return serialize

