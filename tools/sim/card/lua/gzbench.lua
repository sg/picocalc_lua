-- test only: time decompressing the whole archive in 1 KB reads, as tar reads it
collectgarbage() collectgarbage()
local r <close> = gzip.open("/sd_files-test.tar.gz")
local t, n = os.clock(), 0
while true do
    local s = r:read(1024)
    if not s then break end
    n = n + #s
end
print(string.format("%d bytes in %.2f s, gzip.blockSize %s", n, os.clock() - t, tostring(gzip.blockSize)))
