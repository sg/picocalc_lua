-- Mechanics tests for BotWarz, run on the host through harness.lua with bots written for each case:
--
--   lua5.4 tools/botwarz/tests.lua
--
-- Each scenario writes two bot scripts to a temporary directory, points the game's BOTS_DIR and start
-- positions at what the case needs, plays a few ticks, and checks what the bots saw. The bots hand their
-- observations back through math.T, since the sandbox shares the real math table with the game.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local H = dofile(here .. "/harness.lua")
local DIR = io.popen("mktemp -d"):read("l")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function near(a, b, tol) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 1e-6) end
local function show(t) if type(t) ~= "table" then return tostring(t) end local o = {} for i = 1, (t.n or #t) do o[i] = tostring(t[i]) end return "{" .. table.concat(o, ", ") .. "}" end

local HEAD = 'local T = math.T\n'
local IDLE = 'bot.name = "B"\nfunction bot.tick() end\n'
local n = 0
local function scenario(o)
    n = n + 1
    local dir = DIR .. "/" .. n
    os.execute('mkdir -p "' .. dir .. '"')
    for i, name in ipairs{"a.lua", "b.lua"} do
        local f = assert(io.open(dir .. "/" .. name, "w"))
        f:write(o.raw and o.bots[i] or (HEAD .. o.bots[i]))
        f:close()
    end
    math.T = {}
    local r = H.run{plan = {{"a.lua", "b.lua"}}, maxticks = o.ticks or 40, quiet = true, on_frame = o.on_frame, psram = o.psram,
        patch = function(c)
            c.BOTS_DIR = dir .. "/"
            if o.starts then
                for i = 1, 2 do c.STARTS[i].x, c.STARTS[i].y, c.STARTS[i].heading = o.starts[i][1], o.starts[i][2], o.starts[i][3] end
            end
            if o.patch then o.patch(c) end
        end}
    check((o.name or ("scenario " .. n)) .. ": no harness problems", r.problems == 0, r.error)
    local T = math.T
    math.T = nil
    return T, r
end

-- 1: a shell across the arena; the victim is told the bearing back along its path
do
    local T, r = scenario{name = "hit", starts = {{50, 230, 0}, {230, 50, 0}}, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then T.fired = bot.fireAt(45) T.aim = bot.getAim() end end\n' ..
        'function bot.onShotHit(name, dmg) T.shot = {name, dmg, bot.getTick()} end\nfunction bot.onKill(name) T.kill = name end\n',
        'bot.name = "B"\nfunction bot.tick() end\nfunction bot.onHit(dir, dmg) T.hit = {dir, dmg, bot.getTick()} end\n'}}
    check("hit: fired", T.fired == true)
    check("hit: aim follows fireAt", T.aim == 45, T.aim)
    check("hit: onHit direction points back at the shooter", T.hit and near(T.hit[1], 225), show(T.hit))
    check("hit: damage 10 at tick 29", T.hit and T.hit[2] == 10 and T.hit[3] == 29, show(T.hit))
    check("hit: onShotHit", T.shot and T.shot[1] == "B" and T.shot[2] == 10 and T.shot[3] == 29, show(T.shot))
    check("hit: no kill", T.kill == nil)
    check("hit: health", r.state.bots[2].health == 90 and r.state.bots[1].health == 100)
    check("hit: ammo and cooldown", r.state.bots[1].ammo == 49)
end

-- 2: point-blank, bots touching
do
    local T, r = scenario{name = "point-blank", starts = {{100, 100, 90}, {124, 100, 0}}, ticks = 3, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then T.r = bot.fire() T.aim = bot.getAim() end end\n',
        'bot.name = "B"\nfunction bot.tick() end\nfunction bot.onHit(dir, dmg) T.hit = {dir, dmg, bot.getTick()} end\n'}}
    check("point-blank: hits on the tick it is fired", T.hit and T.hit[3] == 1 and near(T.hit[1], 270), show(T.hit))
    check("point-blank: fire() returns true and aims ahead", T.r == true and T.aim == 90)
end

-- 3: a shell passing 11.9 px from the centre must hit although its 8 px steps straddle the chord; 12.1 px must miss
for _, case in ipairs{{11.9, 90}, {12.1, 100}, {-11.9, 90}, {-12.1, 100}} do
    local T, r = scenario{name = "graze " .. case[1], starts = {{40, 140, 90}, {143, 140 + case[1], 0}}, ticks = 40, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then bot.fire() end end\n', IDLE}}
    check("graze at " .. case[1], r.state.bots[2].health == case[2], r.state.bots[2].health)
end

-- 4: missiles
do
    local T, r = scenario{name = "missile", starts = {{40, 140, 90}, {140, 140, 0}}, ticks = 40, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then T.r = bot.missile() end end\n',
        'bot.name = "B"\nfunction bot.tick() end\nfunction bot.onHit(dir, dmg) T.hit = {dir, dmg, bot.getTick()} end\n'}}
    check("missile: direct hit 25 from 270", T.hit and T.hit[2] == 25 and near(T.hit[1], 270), show(T.hit))
    -- muzzle at 52, circle edge at 128: 76 px at 4 a tick
    check("missile: arrives at tick 19", T.hit and T.hit[3] == 19, show(T.hit))
    check("missile: no splash on the far shooter", r.state.bots[1].health == 100 and r.state.bots[2].health == 75)
    check("missile: count", r.state.bots[1].missiles == 2)

    T, r = scenario{name = "missile point-blank", starts = {{100, 100, 90}, {124, 100, 0}}, ticks = 3, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then bot.missile() end end\n' ..
        'function bot.onHit(dir, dmg) T.self = {dir, dmg} end\nfunction bot.onShotHit(name, dmg) T.shot = (T.shot or 0) + 1 end\n', IDLE}}
    check("missile point-blank: target 75, shooter 95", r.state.bots[2].health == 75 and r.state.bots[1].health == 95, r.state.bots[1].health .. "/" .. r.state.bots[2].health)
    check("missile point-blank: own splash comes from the blast", T.self and near(T.self[1], 90) and T.self[2] == 5, show(T.self))
    check("missile point-blank: one onShotHit, none for itself", T.shot == 1, T.shot)

    T, r = scenario{name = "missile wall", starts = {{15, 140, 270}, {200, 140, 0}}, ticks = 3, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then bot.missile() end end\n' ..
        'function bot.onHit(dir, dmg) T.self = {dir, dmg} end\nfunction bot.onShotHit() T.shot = true end\nfunction bot.onKill() T.kill = true end\n', IDLE}}
    check("missile wall: splash 5 on the bot beside the wall", r.state.bots[1].health == 95 and T.self and near(T.self[1], 270), show(T.self))
    check("missile wall: no onShotHit for itself", T.shot == nil)

    T, r = scenario{name = "self kill", starts = {{15, 140, 270}, {200, 140, 0}}, ticks = 200, patch = function(c) c.MISSILE_SPLASH_DAMAGE = 100 end, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then bot.missile() end end\nfunction bot.onKill() T.kill = true end\n', IDLE}}
    check("self kill: the other bot wins", r.results[1].result == "B", r.results[1].result)
    check("self kill: no onKill", T.kill == nil)
    check("finale: a key before the prompt is ignored", r.results[1].finale >= r.config.FINALE_TICKS, r.results[1].finale)
    check("finale: texts", r.texts["B WINS!"] and r.texts["Press any key to continue"], "")
end

-- 5: both die on the same tick
do
    local T, r = scenario{name = "draw", starts = {{100, 100, 90}, {124, 100, 270}}, ticks = 200, patch = function(c) c.CANNON_DAMAGE = 100 end, bots = {
        'bot.name = "A"\nfunction bot.tick() bot.fire() end\nfunction bot.onKill() T.a = true end\n',
        'bot.name = "B"\nfunction bot.tick() bot.fire() end\nfunction bot.onKill() T.b = true end\n'}}
    check("draw: result", r.results[1].result == "draw" and r.texts["DRAW!"], r.results[1].result)
end

-- 6: scan geometry
do
    local T, r = scenario{name = "scan", starts = {{140, 200, 0}, {140, 140, 77}}, ticks = 3, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() ~= 1 then return end\n' ..
        'T.s1 = table.pack(bot.scanAt(0, 1)) T.s2 = table.pack(bot.scanAt(15, 10)) T.s3 = table.pack(bot.scanAt(17, 10))\n' ..
        'T.s4 = table.pack(bot.scanAt(345, 10)) T.s5 = table.pack(bot.scanAt(343, 10)) T.s6 = table.pack(bot.scan(90)) T.s7 = table.pack(bot.scanAt(180, 90))\n' ..
        'T.s8 = table.pack(bot.scanAt(-345, 400)) T.energy = bot.getEnergy() end\n',
        'bot.name = "B"\nfunction bot.tick() end\nfunction bot.onScanned(dir) T.scanned = {dir, bot.getTick()} T.count = (T.count or 0) + 1 end\n'}}
    check("scan: dead ahead gives dist, angle, heading, speed", near(T.s1[1], 60) and near(T.s1[2], 0) and T.s1[3] == 77 and T.s1[4] == 0, show(T.s1))
    check("scan: edge of the bot inside the arc is seen", near(T.s2[1], 60), show(T.s2))
    check("scan: just outside is not", T.s3[1] == nil, show(T.s3))
    check("scan: same on the other side", near(T.s4[1], 60) and T.s5[1] == nil, show(T.s4) .. show(T.s5))
    check("scan: scan(arc) looks along the heading", near(T.s6[1], 60), show(T.s6))
    check("scan: behind is not seen", T.s7[1] == nil, show(T.s7))
    check("scan: angle and arc are normalised and clamped", near(T.s8[1], 60), show(T.s8))
    check("scan: every scan costs 1", T.energy == 92, T.energy)
    check("scan: onScanned once a tick with the bearing to the scanner", T.scanned and near(T.scanned[1], 180) and T.count == 1, show(T.scanned))

    for _, case in ipairs{{161.5, true}, {162.5, false}} do
        T = scenario{name = "scan range", starts = {{20, 140, 90}, {20 + case[1], 140, 0}}, ticks = 2, bots = {
            'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then T.s = table.pack(bot.scan(30)) end end\n', IDLE}}
        check("scan: range at " .. case[1], (T.s[1] ~= nil) == case[2], show(T.s))
    end

    T = scenario{name = "scan energy", starts = {{140, 200, 0}, {140, 140, 0}}, ticks = 5, bots = {
        'bot.name = "A"\nT.ok = {}\nfunction bot.tick() local n = 0 for i = 1, 30 do if bot.scan(30) then n = n + 1 end end T.ok[bot.getTick()] = n end\n', IDLE}}
    check("scan: energy runs out", T.ok[1] == 30 and T.ok[2] == 30 and T.ok[3] == 30 and T.ok[4] == 16 and T.ok[5] == 2, show(T.ok))
end

-- 7: turning
do
    local T, r = scenario{name = "turn", starts = {{140, 140, 0}, {140, 40, 0}}, ticks = 12, bots = {
        'bot.name = "A"\nT.h = {}\nfunction bot.tick() local t = bot.getTick() T.h[t] = bot.getHeading()\n' ..
        'if t == 1 then bot.turn(100) elseif t == 3 then bot.turn(4) bot.turn(3) elseif t == 4 then bot.turn(50) bot.turnTo(15)\n' ..
        'elseif t == 5 then bot.turnTo(350) elseif t >= 7 then bot.turn(10) end end\n' ..
        'function bot.onScanned() bot.turn(10) end\n',
        'bot.name = "B"\nfunction bot.tick() if bot.getTick() >= 7 then bot.scanAt(180, 20) end end\n'}}
    check("turn: 10 a tick, and a request is not carried on", T.h[2] == 10 and T.h[3] == 10, show(T.h))
    check("turn: turn() adds", T.h[4] == 17, show(T.h))
    check("turn: turnTo() replaces", near(T.h[5], 15), show(T.h))
    check("turn: turnTo() takes the short way", near(T.h[6], 5) and near(T.h[7], 5), show(T.h))
    check("turn: a handler and tick() share one allowance", near(T.h[9] - T.h[8], 10) and near(T.h[11] - T.h[10], 10), show(T.h))
end

-- 8: pressing on a wall halves the turn rate
do
    local T, r = scenario{name = "wall", starts = {{140, 13, 0}, {140, 200, 0}}, ticks = 30, bots = {
        'bot.name = "A"\nT.h = {} T.walls = 0\nfunction bot.tick() T.h[bot.getTick()] = bot.getHeading() bot.drive(5) bot.turn(10) end\n' ..
        'function bot.onWall() T.walls = T.walls + 1 T.speed = bot.getSpeed() bot.turn(10) end\n', IDLE}}
    check("wall: first turn is full, then 5 a tick while pressing", T.h[2] == 10 and T.h[3] == 15 and T.h[4] == 20 and T.h[10] == 50, show(T.h))
    -- at 90 the bot runs along the wall without pressing on it
    check("wall: full rate again once clear", T.h[18] == 90 and T.h[19] == 100 and T.h[20] == 110, show(T.h))
    check("wall: onWall each tick it presses, with speed zeroed", T.walls == 16 and T.speed == 0, T.walls)
end

-- 9: collisions
do
    local min = 1e9
    local function watch(st) local a, b = st.bots[1], st.bots[2] local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) if d < min then min = d end end
    local T, r = scenario{name = "collide", starts = {{100, 140, 90}, {180, 140, 270}}, ticks = 30, on_frame = watch, bots = {
        'bot.name = "A"\nfunction bot.tick() bot.drive(5) end\nfunction bot.onCollision(dir) T.a = {dir, bot.getSpeed(), bot.getTick()} T.an = (T.an or 0) + 1 end\n',
        'bot.name = "B"\nfunction bot.tick() bot.drive(5) end\nfunction bot.onCollision(dir) T.b = {dir, bot.getSpeed()} end\n'}}
    check("collide: bots never overlap", min >= 24 - 1e-9, min)
    check("collide: onCollision gives the bearing to the other bot", T.a and near(T.a[1], 90) and T.b and near(T.b[1], 270), show(T.a) .. show(T.b))
    check("collide: both are stopped", T.a and T.a[2] == 0 and T.b[2] == 0)
    check("collide: every tick they press", T.an == 25, T.an)

    min = 1e9
    T, r = scenario{name = "corner pin", starts = {{12, 12, 0}, {70, 70, 315}}, ticks = 60, on_frame = watch, bots = {
        'bot.name = "A"\nfunction bot.tick() end\n', 'bot.name = "B"\nfunction bot.tick() bot.drive(5) end\n'}}
    check("corner pin: the free bot gives way for both", min >= 24 - 1e-6 and r.max_overlap < 1e-6, min)
    check("corner pin: the cornered bot stays put", near(r.state.bots[1].x, 12) and near(r.state.bots[1].y, 12))
end

-- 10: reverse, wall distance, state queries
do
    local T, r = scenario{name = "reverse", starts = {{50, 230, 315}, {230, 50, 0}}, ticks = 6, bots = {
        'bot.name = "A"\nfunction bot.tick() local t = bot.getTick() if t == 1 then T.w = {bot.wallDistance(), bot.wallDistance(90), bot.wallDistance(180), bot.wallDistance(0)}\n' ..
        'T.c = {bot.MAX_SPEED, bot.MAX_REVERSE, bot.RADIUS, bot.SCAN_RANGE, bot.CANNON_SPEED, bot.MISSILE_SPEED, bot.TURN_RATE}\n' ..
        'T.d = {bot.angleDiff(350, 10), bot.angleDiff(10, 350), bot.angleTo(50, 0), bot.distanceTo(50, 200)} T.cd = {bot.getCooldown()} end\n' ..
        'if t == 2 then bot.fire() T.cd2 = {bot.getCooldown()} end bot.drive(-5) T.s = bot.getSpeed() end\n', IDLE}}
    check("wallDistance", near(T.w[1], 50 / math.sin(math.rad(45)), 1e-6) and near(T.w[2], 230) and near(T.w[3], 50) and near(T.w[4], 230), show(T.w))
    check("constants", T.c[1] == 5 and T.c[2] == 2 and T.c[3] == 12 and T.c[4] == 150 and T.c[5] == 8 and T.c[6] == 4 and T.c[7] == 10, show(T.c))
    check("angle helpers", T.d[1] == 20 and T.d[2] == -20 and near(T.d[3], 0) and near(T.d[4], 30), show(T.d))
    check("cooldowns", T.cd[1] == 0 and T.cd[2] == 0 and T.cd2[1] == 10, show(T.cd2))
    check("reverse: speed is held to -2", T.s == -2, T.s)
    local b = r.state.bots[1]
    local back = 2 * 6 * math.sin(math.rad(45))
    check("reverse: moves backwards", near(b.x, 50 + back, 1e-6) and near(b.y, 230 + back, 1e-6), b.x .. "," .. b.y)
end

-- 11: detectShot
do
    local T, r = scenario{name = "detectShot", starts = {{40, 140, 90}, {200, 140, 0}}, ticks = 4, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then bot.fire() else T.own = table.pack(bot.detectShot()) end end\n',
        'bot.name = "B"\nT.d = {}\nfunction bot.tick() T.d[bot.getTick()] = table.pack(bot.detectShot()) end\n'}}
    check("detectShot: sees the shell the tick it is fired", near(T.d[1][1], 148) and near(T.d[1][2], 270) and T.d[1][3] == 90 and T.d[1][4] == "cannon", show(T.d[1]))
    check("detectShot: closing 8 a tick", near(T.d[2][1], 140) and near(T.d[3][1], 132), show(T.d[2]))
    check("detectShot: a bot's own shots are not reported", T.own and T.own[1] == nil, show(T.own))
end

-- 12: instruction limit and script errors
do
    local T, r = scenario{name = "limit", ticks = 20, bots = {
        'bot.name = "A"\nfunction bot.tick() while true do end end\n',
        'bot.name = "B"\nT.n = 0\nfunction bot.tick() T.n = T.n + 1 local x = 0 for i = 1, 1000 do x = x + i end T.x = x end\n'}}
    check("limit: a runaway tick is stopped", r.state.bots[1].script_error == "tick: instruction limit exceeded", r.state.bots[1].script_error)
    check("limit: the other bot is untouched", T.n == 20 and T.x == 500500 and r.state.bots[2].script_error == nil, r.state.bots[2].script_error)
    check("limit: error goes to the log once", #r.logs == 1 and table.concat(r.logs[1]):find("ERROR: A tick: instruction limit exceeded", 1, true)
        and select(2, table.concat(r.logs[1]):gsub("ERROR", "")) == 1, r.logs[1] and table.concat(r.logs[1]))

    T, r = scenario{name = "limit size", ticks = 3, bots = {
        'bot.name = "A"\nfunction bot.tick() local x = 0 for i = 1, 4000 do x = x + i end end\n', IDLE}}
    check("limit: 4000 loop passes are over it", r.state.bots[1].script_error ~= nil)

    T, r = scenario{name = "runtime error", ticks = 5, bots = {
        'bot.name = "A"\nfunction bot.tick() local t = nil; t.x = 1 end\n', IDLE}}
    check("error: message names the file and line without its directory", r.state.bots[1].script_error and r.state.bots[1].script_error:match("^tick: a%.lua:%d+: attempt to index"), r.state.bots[1].script_error)
    check("error: shown in the info bar", r.state.error_text and r.state.error_text:match("^A tick: a%.lua"), r.state.error_text)
end

-- 12b: the allowance running out exactly as a script returns must not stop the game
do
    local bad, first, last = 0, nil, nil
    for limit = 20, 120 do
        local T, r = scenario{name = "limit edge " .. limit, ticks = 6, patch = function(c) c.BOT_INSTRUCTION_LIMIT = limit end, bots = {
            'bot.name = "A"\nfunction bot.tick() local x = 0 for i = 1, 12 do x = x + i end bot.turn(1) end\nfunction bot.onWall() local t = nil; t.x = 1 end\n', IDLE}}
        if r.error then bad = bad + 1 end
        local e = r.state.bots[1].script_error
        if e and not first then first = limit end
        if not e then last = last or limit end
    end
    check("limit edge: the game survives every limit from 20 to 120", bad == 0, bad)
    check("limit edge: the sweep crossed the bot's real cost", first == 20 and last and last > 20, tostring(first) .. " " .. tostring(last))
end

-- 13: values a script should never pass
do
    local T, r = scenario{name = "bad numbers", starts = {{140, 140, 30}, {140, 40, 0}}, ticks = 5, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() ~= 1 then return end local nan, inf = 0/0, 1/0\n' ..
        'bot.turn(nan) bot.turnTo(inf) bot.drive(nan) bot.drive(inf) bot.drive("5") bot.turn({})\n' ..
        'T.f = {bot.fireAt(nan), bot.missileAt(-inf), bot.fireAt("x")} T.s = table.pack(bot.scanAt(inf, 30)) T.s2 = table.pack(bot.scan(nan))\n' ..
        'T.w = bot.wallDistance(nan) T.a = bot.angleTo(nan, 1) T.d = bot.distanceTo(1, inf) T.g = bot.angleDiff(nan, 1)\n' ..
        'T.big = bot.fireAt(1e300) T.aim = bot.getAim() T.done = true end\n', IDLE}}
    local b = r.state.bots[1]
    check("bad numbers: script ran through", T.done == true and b.script_error == nil, b.script_error)
    check("bad numbers: nothing moved", b.heading == 30 and b.speed == 0 and b.x == 140, b.heading)
    check("bad numbers: shots refused", T.f[1] == false and T.f[2] == false and T.f[3] == false and b.missiles == 3)
    check("bad numbers: queries give defaults", T.s[1] == nil and T.s2[1] == nil and T.w == 0 and T.a == 0 and T.d == 0 and T.g == 0)
    check("bad numbers: a huge finite angle is just an angle", T.big == true and T.aim >= 0 and T.aim < 360, T.aim)
end

-- 14: script fields
do
    local T, r = scenario{name = "fields", ticks = 2, bots = {
        'bot.name = 42 bot.color = "red" bot.shape = "nope"\nfunction bot.tick() end\n',
        'bot.name = "ThisNameIsFarTooLong" bot.color = 0x1F bot.shape = 3 bot.onHit = 5\nfunction bot.tick() end\n'}}
    local a, b, c = r.state.bots[1], r.state.bots[2], r.config
    check("fields: bad values fall back", a.name == "Unnamed" and a.color == c.COLOR_BOT1 and a.shape == c.SHAPES.dart, a.name)
    check("fields: name cut, color and numbered shape taken", b.name == "ThisNameIsFa" and b.label == "ThisNam" and b.color == 0x1F and b.shape == c.SHAPES.saucer, b.name)
    check("fields: a handler that is not a function is dropped", b.script.onHit == nil)
    for _, name in ipairs(c.SHAPE_NAMES) do
        local s, maxr = c.SHAPES[name], 0
        for i = 1, #s, 2 do maxr = math.max(maxr, math.sqrt(s[i] ^ 2 + s[i + 1] ^ 2)) end
        check("shape " .. name .. " is closed and inside the collision circle", s[1] == s[#s - 1] and s[2] == s[#s] and maxr < c.BOT_RADIUS - 0.5, maxr)
    end
end

-- 15: scripts that do not load
do
    local T, r = scenario{name = "syntax error", ticks = 5, raw = true, bots = {'bot.name = "A"\nfunction bot.tick( end\n', IDLE}}
    check("load: syntax error is reported and the match still runs", r.state.bots[1].script_error and r.state.bots[1].script_error:match("^Load error"), r.state.bots[1].script_error)
    T, r = scenario{name = "no tick", ticks = 5, raw = true, bots = {'bot.name = "A"\n', IDLE}}
    check("load: no tick()", r.state.bots[1].script_error == "Bot must define bot.tick() function", r.state.bots[1].script_error)
    T, r = scenario{name = "load loop", ticks = 5, raw = true, bots = {'while true do end\n', IDLE}}
    check("load: runaway script body", r.state.bots[1].script_error and r.state.bots[1].script_error:match("instruction limit"), r.state.bots[1].script_error)
end

-- 16: debug log, and print() from a script
do
    local T, r = scenario{name = "log", starts = {{140, 200, 0}, {140, 140, 0}}, ticks = 30, patch = function(c) c.DEBUG_LOG = true end, bots = {
        'bot.name = "A"\nfunction bot.tick() if bot.getTick() == 1 then print("hello", 42, nil) end if bot.scan(10) then bot.fire() end end\n', IDLE}}
    local log = r.logs[1] and table.concat(r.logs[1]) or ""
    check("log: scans, shots, hits and print", log:find("A scan%(0, arc=10%): found B at dist=60 ang=0") and log:find("A fires at 0") and log:find("HIT: B takes 10 from A")
        and log:find("A: hello 42 nil", 1, true) and log:find("Match started"), log:sub(1, 600))
end

-- 17: geometry helpers
do
    local r = H.run{plan = {}, quiet = true}
    local R = r.render
    check("angle_to", R.angle_to(0, 0, 0, -1) == 0 and R.angle_to(0, 0, 1, 0) == 90 and R.angle_to(0, 0, 0, 1) == 180 and R.angle_to(0, 0, -1, 0) == 270)
    check("angle_diff", R.angle_diff(350, 10) == 20 and R.angle_diff(10, 350) == -20 and R.angle_diff(0, 180) == 180 and R.angle_diff(90, 90) == 0)
    check("normalize_angle", R.normalize_angle(725) == 5 and R.normalize_angle(-90) == 270 and R.normalize_angle(-1e-15) == 0 and R.normalize_angle(360) == 0)
end

os.execute('rm -rf "' .. DIR .. '"')
print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
