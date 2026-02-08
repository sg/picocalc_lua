--
--
--
local rc4 = require("lua/modules/rc4")

local key = "my secret key"
local plaintext = "Hello, world!\nThis is a test of RC4."
print("Plaintext: " .. plaintext)

local ciphertext = rc4(key, plaintext)
print("Ciphertext (hex):")
print(string.gsub(ciphertext, ".", function(c)
    return string.format("%02X ", string.byte(c))
end))

local recovered = rc4(key, ciphertext)
print("Recovered: " .. recovered)
