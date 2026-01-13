local x = require("lua/modules/xor")
local b64 = require("lua/modules/base64")
local c = require("lua/modules/simple-colors")
--local secret = "Hack the Planet!"
local secret = term.read(c.green .. "Enter secret: " .. c.white)
local xval = x.xor(secret, "mykey")

term.write(c.cyan .. "xor'ed secret = " .. c.white)
for i = 1, #xval do
  local byte = string.byte(xval, i)
  term.write(string.format("%02x", byte))
end
term.write("\n")

local b64val = b64.encode(xval)
term.write(c.cyan .. "b64val = " .. c.white .. b64val .. "\n")

local xval2 = b64.decode(b64val)
secret = x.xor(xval2, "mykey")
term.write(c.cyan .. "secret = " .. c.white .. secret .. "\n")
