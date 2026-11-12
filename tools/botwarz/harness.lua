-- Headless host harness for BotWarz: plays whole matches under host Lua with the device's APIs stubbed,
-- and checks after every tick that the bots, shots and drawing stay within the rules.
--
--   lua5.4 tools/botwarz/harness.lua          every bot against every other
--
-- Environment: PAIRS="a.lua,b.lua;c.lua,d.lua" to play only those, MAXTICKS (default 6000), SEED,
-- PSRAM=0 for the path without a framebuffer, CYCLE=1 to press S through the scan displays, QUIET=1 for
-- the summary line alone, VERBOSE=1 to print the debug log, SDROOT for a card other than the repo's sd_files.
--
-- tests.lua uses this as a module: H.run{...} returns the game's state and modules for a test to inspect.
local H = {}
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local real_open, real_loadfile, real_clock, real_load = io.open, loadfile, os.clock, load
local SD = os.getenv("SDROOT") or (here .. "/../../sd_files")
package.path = SD .. "/?.lua;" .. package.path
package.searchers[2] = (function(orig)
    return function(name) return orig((name:gsub("%.", "/"))) end
end)(package.searchers[2])
-- the card's root is SD; test bots live at real absolute paths
local function full(p)
    if p:sub(1, 5) == "/lua/" then return SD .. p end
    if p:sub(1, 1) == "/" then return p end
    return SD .. "/" .. p
end

-- opts: plan = {{"a.lua","b.lua"},...} (default all pairs), maxticks, psram (default true), seed, cycle,
--       patch = function(config), on_frame = function(state, config), quiet
function H.run(opts)
opts = opts or {}
local PSRAM = opts.psram ~= false
local MAXTICKS = opts.maxticks or 6000
local CYCLE = opts.cycle
math.randomseed(opts.seed or 1)

local function rgb(r, g, b) return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3) end
colors = {
    fromRGB = function(r, g, b) return rgb(math.tointeger(r) or r // 1, math.tointeger(g) or g // 1, math.tointeger(b) or b // 1) end,
    toRGB = function(c) return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31 end,
    white = 0xFFFF, black = 0, red = rgb(255, 0, 0), green = rgb(0, 255, 0), blue = rgb(0, 0, 255), yellow = rgb(255, 255, 0),
    cyan = rgb(0, 255, 255), magenta = rgb(255, 0, 255), orange = rgb(255, 165, 0),
}

local problems, nproblems = {}, 0
local function problem(fmt, ...)
    local msg = string.format(fmt, ...)
    if not problems[msg] then problems[msg] = true; nproblems = nproblems + 1; print("PROBLEM: " .. msg) end
end

local STATE, CONFIG, BOTMOD, RENDER
local in_match_draw = false
local stats = {line = 0, point = 0, rect = 0, poly = 0, text = 0, blit = 0}
local texts = {}
local function int(v, what) if math.type(v) ~= "integer" then problem("%s got non-integer %s", what, tostring(v)) end end
local function in_arena(x, y, what)
    if not in_match_draw or not CONFIG then return end
    if x < CONFIG.ARENA_X or x > CONFIG.ARENA_X + CONFIG.ARENA_WIDTH - 1 or y < CONFIG.ARENA_Y or y > CONFIG.ARENA_Y + CONFIG.ARENA_HEIGHT - 1 then
        problem("%s outside the arena at %d,%d", what, x, y)
    end
end
local buffer_mode = 0
draw = {
    align_left = 0, align_center = 1, align_right = 2,
    text = function(x, y, s, fg, bg, align) stats.text = stats.text + 1; assert(type(s) == "string", "draw.text needs a string"); texts[s] = (texts[s] or 0) + 1 end,
    clear = function() end,
    point = function(x, y, c) int(x, "point"); int(y, "point"); int(c, "point color"); in_arena(x, y, "point"); stats.point = stats.point + 1 end,
    rect = function() end,
    rectFill = function(x, y, w, h, c)
        int(x, "rectFill"); int(y, "rectFill"); int(c, "rectFill color"); stats.rect = stats.rect + 1
        if in_match_draw and w <= 2 then in_arena(x, y, "dot"); in_arena(x + w - 1, y + h - 1, "dot") end
    end,
    line = function(x1, y1, x2, y2, c)
        int(x1, "line"); int(y1, "line"); int(x2, "line"); int(y2, "line"); int(c, "line color")
        in_arena(x1, y1, "line"); in_arena(x2, y2, "line"); stats.line = stats.line + 1
    end,
    circle = function() end, circleFill = function() end,
    polygon = function(pts, c)
        int(c, "polygon color"); stats.poly = stats.poly + 1
        assert(#pts % 2 == 0, "odd polygon")
        for i = 1, #pts, 2 do int(pts[i], "polygon"); int(pts[i + 1], "polygon"); in_arena(pts[i], pts[i + 1], "polygon") end
    end,
    enableBuffer = function(mode)
        if mode == 1 and not PSRAM then return false end
        buffer_mode = mode; return true
    end,
    blitBuffer = function() stats.blit = stats.blit + 1 end,
    getBufferMode = function() return buffer_mode end,
}
term = { clear = function() end, setCursorBlink = function() end, getCursorBlink = function() return true end, write = function() end }
sound = { playPitch = function() end, drums = {kick1 = 1, kick2 = 2, snare1 = 3, snare2 = 4, hihat = 5, tom = 6, cowbell = 7}, presets = {} }
sys = { freeMemory = function() return 150 * 1024 end }
psram = { stats = function() return {qspi = PSRAM} end }

local LOGS = {}
fs = {
    exists = function(p) local f = real_open(full(p), "r"); if f then f:close() return true end; return os.execute('test -d "' .. full(p) .. '"') == true end,
    isDir = function(p) return os.execute('test -d "' .. full(p) .. '"') == true end,
    list = function(p)
        local out = {}
        local h = io.popen('ls -1 "' .. full(p) .. '"')
        for name in h:lines() do out[#out + 1] = {name = name, isDir = false} end
        h:close()
        return out
    end,
    open = function(p, mode)
        local log = {}
        LOGS[#LOGS + 1] = log
        return { write = function(_, s) log[#log + 1] = s end, flush = function() end, close = function() end }
    end,
}
loadfile = function(path, mode, env) return real_loadfile(full(path), mode, env) end

-- virtual time: every look at the clock moves it on one tick, so each pass of the game loop steps once
local vt = 0
os.clock = function() vt = vt + 0.05; return vt end

local files, index, plan = {}, {}, {}
local function prepare()
    if opts.patch then opts.patch(CONFIG) end
    local h = io.popen('ls -1 "' .. full(CONFIG.BOTS_DIR) .. '"')
    for n in h:lines() do if n:match("%.lua$") then files[#files + 1] = n end end
    h:close()
    table.sort(files)
    for i, n in ipairs(files) do index[n] = i end
    if opts.plan then
        for _, m in ipairs(opts.plan) do plan[#plan + 1] = {assert(index[m[1]], m[1]), assert(index[m[2]], m[2])} end
    else
        for i = 1, #files do for j = 1, #files do plan[#plan + 1] = {i, j} end end
    end
end
local stripped = 0
load = function(code, name, mode, ...)
    -- an explicit nil for env would become the chunk's _ENV
    local f, err = real_load(code, name, mode, ...)
    local short = f and type(name) == "string" and name:match("^=lua/botwarz/(%w+)$")
    if not short then return f, err end
    stripped = stripped + 1
    return function(...)
        local m = f(...)
        if short == "config" then CONFIG = m; prepare()
        elseif short == "bot" then BOTMOD = m
        elseif short == "render" then
            RENDER = m
            local rinit, rfinish = m.init, m.finish
            m.init = function(cfg, st) STATE = st; return rinit(cfg, st) end
            m.finish = function() H.frame(rfinish) end
        end
        return m
    end
end
local match_no, results = 0, {}
local pressed_for = nil

keys = {
    states = {idle = 0, pressed = 1, hold = 2, released = 3},
    enter = "\n", esc = "\27", up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", backspace = "\8",
    flush = function() end,
    wait = function() return 1, 0, "x" end,
    getState = function() return false end,
}
local last_gs, last_finale = nil, 0
function keys.poll()
    local gs = STATE.game_state
    local token = gs .. ":" .. STATE.game_tick .. ":" .. STATE.finale_ticks .. ":" .. match_no
    if pressed_for == token then return 0, 0, 0 end
    local code
    if gs == "menu" then
        if last_gs == "finale" or last_gs == "playing" then
            local r = results[#results]
            local w = STATE.winner
            r.result = last_gs == "playing" and "TIMEOUT" or (w and w.name or "draw")
            r.ticks = STATE.game_tick
            r.finale = last_finale
            r.hp = {STATE.bots[1].health, STATE.bots[2].health}
            r.err = {STATE.bots[1].script_error, STATE.bots[2].script_error}
        end
        if match_no < #plan then code = keys.enter else code = keys.esc end
    elseif gs == "select" then
        match_no = match_no + 1
        STATE.selected_bots = {plan[match_no][1], plan[match_no][2]}
        results[#results + 1] = {a = files[plan[match_no][1]], b = files[plan[match_no][2]]}
        code = keys.enter
    elseif gs == "playing" then
        if STATE.game_tick >= MAXTICKS then code = keys.esc
        elseif CYCLE and STATE.game_tick % 37 == 5 then code = "s" end
    elseif gs == "finale" then
        last_finale = STATE.finale_ticks
        if STATE.finale_ticks >= CONFIG.FINALE_TICKS + 2 then code = "x"
        elseif STATE.finale_ticks == 5 then code = "x" end   -- must be ignored this early
    end
    last_gs = gs
    if code then pressed_for = token; return 1, 0, code end
    return 0, 0, 0
end

local max_overlap = 0
local function check_state()
    local R, W, H = CONFIG.BOT_RADIUS, CONFIG.ARENA_WIDTH, CONFIG.ARENA_HEIGHT
    for i, b in ipairs(STATE.bots) do
        if b.health > 0 then
            if b.x < R - 1e-6 or b.x > W - R + 1e-6 or b.y < R - 1e-6 or b.y > H - R + 1e-6 then problem("bot %s outside the arena at %.2f,%.2f", b.name, b.x, b.y) end
            if not (b.heading >= 0 and b.heading < 360) then problem("heading out of range: %s", tostring(b.heading)) end
            if b.speed < -CONFIG.BOT_MAX_REVERSE or b.speed > CONFIG.BOT_MAX_SPEED then problem("speed out of range: %s", tostring(b.speed)) end
            if b.energy < 0 or b.energy > CONFIG.BOT_MAX_ENERGY then problem("energy out of range: %s", tostring(b.energy)) end
            if b.aim and not (b.aim >= 0 and b.aim < 360) then problem("aim out of range: %s", tostring(b.aim)) end
        end
        if b.health < 0 or b.health > 100 or math.type(b.health) ~= "integer" then problem("health %s", tostring(b.health)) end
    end
    local a, b = STATE.bots[1], STATE.bots[2]
    if a.health > 0 and b.health > 0 then
        local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
        if 2 * R - d > max_overlap then max_overlap = 2 * R - d end
    end
    for _, p in ipairs(STATE.projectiles) do
        if p.active and (p.x < -1e-6 or p.x > W + 1e-6 or p.y < -1e-6 or p.y > H + 1e-6) then problem("live shot outside the arena at %.2f,%.2f", p.x, p.y) end
    end
end

H.frame = function(rfinish)
    check_state()
    if opts.on_frame then opts.on_frame(STATE, CONFIG) end
    in_match_draw = true
    rfinish()
    in_match_draw = false
end

local t0 = real_clock()
local real_print = print
if opts.quiet then print = function(...) end end
local ok, err = pcall(dofile, SD .. "/lua/botwarz/main.lua")
print = real_print
os.clock = real_clock
loadfile = real_loadfile
load = real_load
if stripped ~= 4 then problem("expected 4 stripped modules, saw %d", stripped) end
if not ok then print("GAME ERROR: " .. tostring(err)) nproblems = nproblems + 1 end
return {state = STATE, config = CONFIG, bot = BOTMOD, render = RENDER, problems = nproblems, results = results, logs = LOGS,
    stats = stats, texts = texts, max_overlap = max_overlap, seconds = real_clock() - t0, error = not ok and err or nil}
end

if arg and arg[0] and arg[0]:match("harness%.lua$") then
    local plan
    if os.getenv("PAIRS") then
        plan = {}
        for a, b in os.getenv("PAIRS"):gmatch("([^,;]+),([^,;]+)") do plan[#plan + 1] = {a, b} end
    end
    local r = H.run{plan = plan, psram = os.getenv("PSRAM") ~= "0", maxticks = tonumber(os.getenv("MAXTICKS") or "6000"),
        seed = tonumber(os.getenv("SEED") or "1"), cycle = os.getenv("CYCLE") == "1"}
    if os.getenv("QUIET") ~= "1" then
        for _, m in ipairs(r.results) do
            print(string.format("%-12s vs %-12s -> %-8s %5d ticks  hp %3d/%3d%s%s", m.a, m.b, tostring(m.result), m.ticks or -1, m.hp and m.hp[1] or -1, m.hp and m.hp[2] or -1,
                m.err and m.err[1] and ("  [1] " .. m.err[1]) or "", m.err and m.err[2] and ("  [2] " .. m.err[2]) or ""))
        end
    end
    local s = r.stats
    print(string.format("%d matches, %d problems, draw calls: line %d point %d rect %d poly %d text %d blit %d, max overlap %.3f, %.1fs",
        #r.results, r.problems, s.line, s.point, s.rect, s.poly, s.text, s.blit, r.max_overlap, r.seconds))
    if os.getenv("VERBOSE") == "1" then for _, log in ipairs(r.logs) do io.write(table.concat(log)) end end
end
return H
