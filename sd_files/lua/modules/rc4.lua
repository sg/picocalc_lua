--[[
-- RC4 encryption / decryption
--
--]]

-- key scheduling algorithm (KSA)
local function ksa(key)
    local keylen = #key
    local S = {}
    for i = 0, 255 do
        S[i] = i
    end

    local j = 0
    for i = 0, 255 do
        j = (j + S[i] + string.byte(key, (i % keylen) + 1)) % 256
        S[i], S[j] = S[j], S[i]
    end
    return S
end

-- pseudo random generation algorithm (PRGA) – produces keystream
local function rc4_crypt(S, data)
    local i, j = 0, 0
    local out = {}
    local out_len = #data

    for k = 1, out_len do
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        local K = S[(S[i] + S[j]) % 256]
        out[k] = string.byte(data, k) ~ K
    end

    -- convert byte array back to string
    return string.char(table.unpack(out))
end

-- public interface 
-- encrypt(key, plaintext)  -> ciphertext
-- decrypt(key, ciphertext) -> plaintext 
local function rc4(key, data)
    local S = ksa(key)
    return rc4_crypt(S, data)
end

-- example usage 
--[[
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
--]]

return rc4

