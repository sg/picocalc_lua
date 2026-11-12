-- test only: the largest single block, and how much can be had at once in 4 KB blocks
collectgarbage() collectgarbage()
local lo, hi = 0, 400 * 1024
while hi - lo > 512 do
    local mid = (lo + hi) // 2
    local ok, s = pcall(string.rep, "\0", mid)
    s = nil
    collectgarbage()
    if ok then lo = mid else hi = mid end
end
collectgarbage() collectgarbage()
local held = {}
for i = 1, 100 do held[i] = false end
local n = 0
while n < 100 do
    local ok, s = pcall(string.rep, string.pack("i8", n), 512)
    if not ok then break end
    n = n + 1
    held[n] = s
end
held = nil
collectgarbage() collectgarbage()
print(string.format("largest %.1fk; in 4k blocks %dk; free %.1fk", lo / 1024, n * 4, sys.freeMemory() / 1024))
