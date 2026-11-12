-- test only: leave 4 KB allocations pinned every 12 KB through the free memory, the way programs that have run leave theirs
PINS = PINS or {}
local fill = {}
for i = 1, 40 do
    local ok, s = pcall(string.rep, string.pack("i8", i), 1500)
    if not ok then break end
    fill[i] = s
    local ok2, p = pcall(string.rep, string.pack("i8", -i), 512)
    if not ok2 then break end
    PINS[#PINS + 1] = p
end
print("pinned " .. #PINS .. " x 4k")
fill = nil
collectgarbage() collectgarbage()
