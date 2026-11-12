-- Shows which bots in sd_files/lua/botwarz/bots go over an instruction limit of each of several sizes,
-- and how low each bot's energy falls, by playing every pairing:
--
--   lua5.4 tools/botwarz/limits.lua
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local H = dofile(here .. "/harness.lua")
for _, limit in ipairs{150, 250, 400, 600, 1000} do
    local r = H.run{quiet = true, maxticks = 1500, patch = function(c) c.BOT_INSTRUCTION_LIMIT = limit end}
    local over = {}
    for _, m in ipairs(r.results) do
        for i = 1, 2 do
            local e = m.err and m.err[i]
            if e and e:find("instruction limit") then over[i == 1 and m.a or m.b] = true end
        end
    end
    local names = {}
    for k in pairs(over) do names[#names + 1] = k end
    table.sort(names)
    print(string.format("limit %5d: over it: %s", limit, table.concat(names, " ")))
end
-- energy low-water mark per stock bot
local low = {}
local r = H.run{quiet = true, maxticks = 3000, on_frame = function(st)
    for _, b in ipairs(st.bots) do if b.health > 0 and (not low[b.name] or b.energy < low[b.name]) then low[b.name] = b.energy end end
end}
local o = {}
for k, v in pairs(low) do o[#o + 1] = k .. "=" .. v end
table.sort(o)
print("lowest energy seen: " .. table.concat(o, " "))
