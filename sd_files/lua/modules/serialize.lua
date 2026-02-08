--[[

  serialize.lua -

  Serialize a Lua table to a string that can be
  written to a file. The string can be subsequently
  read from the file and deserialized back to table
  format. 

]]--

local serialize = {}

local function _serializeToString(o)
  local sz = ""
  if type(o) == "number" then
    sz = sz .. o
    --print("debug: num sz = " .. sz)
  elseif type(o) == "string" then
    sz = sz .. string.format("%q", o)
    --print("debug: str sz = " .. sz)
  elseif type(o) == "boolean" then
    sz = sz .. (o and "true" or "false")
    --print("debug: boolean sz = " .. sz)
  elseif type(o) == "table" then
    sz = sz .. "{\n"
    for k,v in pairs(o) do
      sz = sz .. "  [\"" .. k .. "\"] = "
      sz = sz .. _serializeToString(v)
      sz = sz .. ",\n"
    end
    sz = sz .. "}"
    --print("debug: table sz = " .. sz)
  
  else
    error("cannot serialize a " .. type(o))
  end
  return sz
end
 
local function _serializeToFile(o, f)
  if type(o) == "number" then
    f:write(o)
    --print("debug: _serializeToFile: (number) = " .. o)
  elseif type(o) == "string" then
    f:write(string.format("%q", o))
    --print("debug: _serializeToFile: (string) = " .. string.format("%q", o))
  elseif type(o) == "boolean" then
    f:write((o and "true" or "false"))
    --print("debug: _serializeToFile: (boolean) = " .. (o and "true" or "false")
  elseif type(o) == "table" then
    --print("debug: _serializeToFile: recursing into another table")
    f:write("{\n")
    for k,v in pairs(o) do
      f:write("  [\"" .. k .. "\"] = ")
      _serializeToFile(v, f)
      f:write(",\n")
    end
    f:write("}")
  
  else
    error("cannot serialize a " .. type(o))
  end
end

function serialize.toString(o)
  local sz = "return "
  --print("debug: sz = " .. sz)
  sz = sz .. _serializeToString(o)
  return sz
end

function serialize.toFile(o, file_handle)
  file_handle:write("return ")
  _serializeToFile(o, file_handle)
end

return serialize

