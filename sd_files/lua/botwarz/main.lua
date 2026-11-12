-- BotWarz - Programmable Robot Arena Battle
-- A game where Lua-scripted bots fight in an arena

-- Debug information is a quarter of the game's code, so the modules are loaded without it;
-- set the global BOTWARZ_DEBUG for line numbers in the game's own errors. Bot scripts always have theirs.
local function load_module(name)
    local path = "lua/botwarz/" .. name
    local chunk = assert(loadfile("/" .. path .. ".lua"))
    if not BOTWARZ_DEBUG then
        local code = string.dump(chunk, true)
        chunk = nil
        collectgarbage()
        chunk = assert(load(code, "=" .. path, "b"))
    end
    local module = chunk()
    collectgarbage()
    return module
end

local config = load_module("config")
local render = load_module("render")
local bot_module = load_module("bot")
local screens = load_module("screens")

local sin, cos, sqrt, floor = math.sin, math.cos, math.sqrt, math.floor
local RAD = math.pi / 180
local TICK = config.TICK_INTERVAL
local RADIUS = config.BOT_RADIUS
local ARENA_W, ARENA_H = config.ARENA_WIDTH, config.ARENA_HEIGHT

local state
local log_handle = nil
local next_step = 0
local info_seconds, info_text

local function log_open()
    if log_handle then return end
    log_handle = fs.open(config.LOG_FILE, "w")
    if log_handle then
        log_handle:write("=== BotWarz Debug Log ===\n")
    end
end

local function log_close()
    if log_handle then
        log_handle:close()
        log_handle = nil
    end
    state.logging = false
end

local function log(fmt, ...)
    if not log_handle then return end
    log_handle:write(string.format("[%04d] ", state.game_tick) .. string.format(fmt, ...) .. "\n")
end

-- a script's error is worth a file even when nothing else is being logged
local function log_error(msg)
    log_open()
    if log_handle then
        log_handle:write(string.format("[%04d] ERROR: %s\n", state.game_tick, msg))
        log_handle:flush()
    end
end

local function new_bot(i)
    return {
        index = i,
        x = 0, y = 0, heading = 0, speed = 0,
        health = 0, energy = 0, ammo = 0, missiles = 0,
        cannon_cooldown = 0, missile_cooldown = 0,
        pending_turn = 0, pending_speed = nil,
        hit_wall = false, bumped = nil, scanned_from = nil,
        aim = nil, flash = 0,
        scan_tick = -1, scan_ang = 0, scan_arc = 0, scan_hit = nil,
        pulse_r = 0, pulse_x = 0, pulse_y = 0, pulse_ang = 0, pulse_arc = 0,
        sweep = 0, sweep_dir = 1,
        name = "Bot" .. i, label = "Bot" .. i,
        color = config.STARTS[i].color, dim = 0,
        shape = config.SHAPES[config.DEFAULT_SHAPE],
        pts = {}, pts_old = {},
        script = nil, script_error = nil,
    }
end

state = {
    game_state = "menu",
    game_tick = 0,
    finale_ticks = 0,
    quit_game = false,
    logging = false,

    bots = {new_bot(1), new_bot(2)},
    projectiles = {},

    menu_selection = 1,
    menu_items = {"Start Match", "How to Play", "Quit"},

    available_bots = {},
    selected_bots = {1, 2},
    select_slot = 1,

    winner = nil,
    scan_mode = 1,
    error_text = nil,
    error_tick = 0,

    log = log,
    log_error = log_error,
}

for i, name in ipairs(config.SCAN_MODES) do
    if name == config.SCAN_DISPLAY then state.scan_mode = i end
end

local projectiles = state.projectiles
for i = 1, config.MAX_PROJECTILES do
    projectiles[i] = {
        active = false,
        x = 0, y = 0,
        vx = 0, vy = 0,
        ux = 0, uy = 0,
        heading = 0,
        ptype = 0,
        owner = 0,
        color = colors.white,
    }
end

function state.spawn_projectile(x, y, angle, speed, ptype, owner, color)
    for i = 1, config.MAX_PROJECTILES do
        local p = projectiles[i]
        if not p.active then
            p.active = true
            p.x, p.y = x, y
            p.ux, p.uy = sin(angle * RAD), -cos(angle * RAD)
            p.vx, p.vy = p.ux * speed, p.uy * speed
            p.heading = angle
            p.ptype = ptype
            p.owner = owner
            p.color = color
            return true
        end
    end
    return false
end

function state.scan_bot_files()
    return bot_module.scan_bot_files()
end

render.init(config, state)
bot_module.init(config, render, state)
screens.init(config, render, state)

local function reset_bot(b)
    local start = config.STARTS[b.index]
    b.x, b.y, b.heading, b.speed = start.x, start.y, start.heading, 0
    b.health = config.BOT_MAX_HEALTH
    b.energy = config.BOT_MAX_ENERGY
    b.ammo = config.BOT_START_AMMO
    b.missiles = config.BOT_START_MISSILES
    b.cannon_cooldown, b.missile_cooldown = 0, 0
    b.pending_turn, b.pending_speed = 0, nil
    b.hit_wall, b.bumped, b.scanned_from = false, nil, nil
    b.aim, b.flash = nil, 0
    b.scan_tick, b.scan_hit, b.pulse_r = -1, nil, 0
    b.sweep, b.sweep_dir = 0, 1
    b.name = "Bot" .. b.index
    b.color = start.color
    b.shape = config.SHAPES[config.DEFAULT_SHAPE]
    b.script, b.script_error = nil, nil
end

local function end_match()
    log_close()
    render.stop_match()
    state.game_state = "menu"
    term.setCursorBlink(false)
    screens.draw_menu()
end

local function init_match()
    state.game_tick = 0
    state.finale_ticks = 0
    state.winner = nil
    state.error_text = nil
    info_seconds = nil
    for i = 1, config.MAX_PROJECTILES do
        projectiles[i].active = false
    end
    if config.DEBUG_LOG then
        log_open()
        state.logging = log_handle ~= nil
    end

    term.clear()
    draw.text(config.SCREEN_WIDTH/2, 100, "Loading bots...", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)

    local failed = false
    for i = 1, 2 do
        local b = state.bots[i]
        reset_bot(b)
        local filename = state.available_bots[state.selected_bots[i]]
        local y = 80 + i * 50
        draw.text(config.SCREEN_WIDTH/2, y, "Loading " .. filename, config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)

        local script, err = bot_module.load_bot_script(filename, b)
        if script then
            b.script = script
            b.name = script.name
            b.color = script.color or b.color
            b.shape = script.shape or b.shape
        else
            failed = true
            b.script_error = err
            b.name = "ERROR"
            log_error(filename .. ": " .. err)
            err = err:gsub("^(%a+ error: )[^:]*/", "%1")
            for line = 0, 2 do
                local part = err:sub(line * 50 + 1, line * 50 + 50)
                if part ~= "" then
                    draw.text(5, y + 12 + line * 10, part, colors.red, config.COLOR_BG)
                end
            end
        end
        b.label = b.name:sub(1, 7)
        local r, g, bl = colors.toRGB(b.color)
        b.dim = colors.fromRGB(r * 2 // 5, g * 2 // 5, bl * 2 // 5)
        -- the outline's point lists are as long as the avatar's, which draw.polygon goes by
        b.pts, b.pts_old = {}, {}
    end

    for i = 1, 2 do
        bot_module.execute_bot_event(state.bots[i], "init")
    end

    if failed then
        draw.text(config.SCREEN_WIDTH/2, 250, "Press any key...", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)
        keys.flush()
        keys.wait(true)
    else
        local start = os.clock()
        while os.clock() - start < 0.5 do end
    end

    collectgarbage()

    log("Match started")
    for i = 1, 2 do
        local b = state.bots[i]
        log("Bot%d: %s at (%.0f,%.0f) heading %.0f", i, b.name, b.x, b.y, b.heading)
    end

    term.setCursorBlink(false)
    render.start_match()
    state.game_state = "playing"
    next_step = os.clock()
end

state.init_match = init_match

-- returns whether a wall had to stop the bot
local function clamp_to_arena(b)
    local hit = false
    if b.x < RADIUS then
        b.x = RADIUS
        hit = true
    elseif b.x > ARENA_W - RADIUS then
        b.x = ARENA_W - RADIUS
        hit = true
    end
    if b.y < RADIUS then
        b.y = RADIUS
        hit = true
    elseif b.y > ARENA_H - RADIUS then
        b.y = ARENA_H - RADIUS
        hit = true
    end
    return hit
end

local function move_bot(b)
    b.hit_wall = false
    if b.speed ~= 0 then
        b.x = b.x + sin(b.heading * RAD) * b.speed
        b.y = b.y - cos(b.heading * RAD) * b.speed
        if clamp_to_arena(b) then
            b.hit_wall = true
            b.speed = 0
        end
    end
end

local function collide(a, b)
    local reach = 2 * RADIUS
    local dx, dy = b.x - a.x, b.y - a.y
    local d2 = dx * dx + dy * dy
    if d2 >= reach * reach then return end
    local d = sqrt(d2)
    if d < 0.01 then dx, dy, d = 0, 1, 1 end
    local push = (reach - d) / 2
    a.x, a.y = a.x - dx / d * push, a.y - dy / d * push
    b.x, b.y = b.x + dx / d * push, b.y + dy / d * push
    local a_walled, b_walled = clamp_to_arena(a), clamp_to_arena(b)
    -- a wall has taken back one bot's share of the push, so the other gives way for both
    if a_walled ~= b_walled then
        dx, dy = b.x - a.x, b.y - a.y
        d = sqrt(dx * dx + dy * dy)
        if d < reach and d >= 0.01 then
            local rest = reach - d
            if a_walled then
                b.x, b.y = b.x + dx / d * rest, b.y + dy / d * rest
                clamp_to_arena(b)
            else
                a.x, a.y = a.x - dx / d * rest, a.y - dy / d * rest
                clamp_to_arena(a)
            end
        end
    end
    a.speed, b.speed = 0, 0
    a.bumped = render.angle_to(a.x, a.y, b.x, b.y)
    b.bumped = render.normalize_angle(a.bumped + 180)
end

local function hurt(victim, damage, from, owner, x, y)
    if victim.health <= 0 then return end
    if state.logging then
        log("HIT: %s takes %d from %s (health %d->%d)", victim.name, damage, owner.name, victim.health, math.max(0, victim.health - damage))
    end
    victim.health = math.max(0, victim.health - damage)
    victim.flash = 3
    render.burst(x, y, 3 + damage // 2, 0.7 + damage / 25, config.COLOR_SPARK)
    if victim.health > 0 then
        sound.playPitch(1, 0.6, sound.drums.snare2)
        bot_module.execute_bot_event(victim, "onHit", from, damage)
    else
        sound.playPitch(2, 0.2, sound.drums.kick1)
        render.wreck(victim)
        render.burst(victim.x, victim.y, 24, 1.8, victim.color)
    end
    if owner ~= victim then
        bot_module.execute_bot_event(owner, "onShotHit", victim.name, damage)
        if victim.health == 0 then
            bot_module.execute_bot_event(owner, "onKill", victim.name)
        end
    end
end

local function explode(p, direct_victim, harmless)
    render.ring(p.x, p.y, config.MISSILE_SPLASH_RADIUS, config.COLOR_SPARK)
    sound.playPitch(2, 0.3, sound.drums.kick1)
    if harmless then return end
    local owner = state.bots[p.owner]
    for i = 1, #state.bots do
        local b = state.bots[i]
        if b ~= direct_victim and b.health > 0 then
            local dist = render.distance(p.x, p.y, b.x, b.y)
            if dist <= config.MISSILE_SPLASH_RADIUS then
                local from = render.angle_to(b.x, b.y, p.x, p.y)
                -- the sparks fly from the side of the bot the blast was on
                local reach = math.min(dist, RADIUS)
                hurt(b, config.MISSILE_SPLASH_DAMAGE, from, owner, b.x + sin(from * RAD) * reach, b.y - cos(from * RAD) * reach)
            end
        end
    end
end

-- how far along this tick's flight, 0 to 1, a shot first touches a bot's circle
local function hit_time(ox, oy, vx, vy, b)
    local fx, fy = ox - b.x, oy - b.y
    local c = fx * fx + fy * fy - RADIUS * RADIUS
    if c <= 0 then return 0 end
    local approach = fx * vx + fy * vy
    if approach >= 0 then return nil end
    local a = vx * vx + vy * vy
    local disc = approach * approach - a * c
    if disc < 0 then return nil end
    local t = (-approach - sqrt(disc)) / a
    if t <= 1 then return t end
end

-- A shot is tested along the whole of its flight this tick, not just where it ends up: a shell covers
-- 8 pixels a tick, so it could otherwise step over the edge of a bot or start beyond one at point-blank range.
local function update_projectiles(harmless)
    local bots = state.bots
    for i = 1, config.MAX_PROJECTILES do
        local p = projectiles[i]
        if p.active then
            local ox, oy, vx, vy = p.x, p.y, p.vx, p.vy
            local nx, ny = ox + vx, oy + vy
            local t, wall = 1, false
            if nx < 0 then
                t, wall = -ox / vx, true
            elseif nx > ARENA_W then
                t, wall = (ARENA_W - ox) / vx, true
            end
            if ny < 0 then
                t, wall = math.min(t, -oy / vy), true
            elseif ny > ARENA_H then
                t, wall = math.min(t, (ARENA_H - oy) / vy), true
            end

            local victim = nil
            for j = 1, #bots do
                local b = bots[j]
                if j ~= p.owner and b.health > 0 then
                    local tb = hit_time(ox, oy, vx, vy, b)
                    if tb and tb <= t then
                        t, victim = tb, b
                    end
                end
            end

            p.x, p.y = ox + vx * t, oy + vy * t
            if victim then
                p.active = false
                local missile = p.ptype == config.PROJ_TYPE_MISSILE
                if harmless then
                    render.burst(p.x, p.y, 3, 1, config.COLOR_SPARK)
                else
                    -- a bot told where a shot came from looks back along the shot's path
                    hurt(victim, missile and config.MISSILE_DAMAGE or config.CANNON_DAMAGE,
                        render.normalize_angle(p.heading + 180), bots[p.owner], p.x, p.y)
                end
                if missile then explode(p, victim, harmless) end
            elseif wall then
                p.active = false
                if p.ptype == config.PROJ_TYPE_MISSILE then explode(p, nil, harmless) end
            end
        end
    end
end

local function step()
    local bots = state.bots
    state.game_tick = state.game_tick + 1

    if state.logging and state.game_tick % 100 == 0 then
        for i = 1, #bots do
            local b = bots[i]
            log("STATUS %s: HP=%d ammo=%d missiles=%d energy=%d pos=(%.0f,%.0f)", b.name, b.health, b.ammo, b.missiles, b.energy, b.x, b.y)
        end
    end

    for i = 1, #bots do
        local b = bots[i]
        b.energy = math.min(b.energy + config.BOT_ENERGY_REGEN, config.BOT_MAX_ENERGY)
        if b.cannon_cooldown > 0 then b.cannon_cooldown = b.cannon_cooldown - 1 end
        if b.missile_cooldown > 0 then b.missile_cooldown = b.missile_cooldown - 1 end
    end

    for i = 1, #bots do
        if bots[i].health > 0 then bot_module.execute_bot_tick(bots[i]) end
    end

    -- told after both have had their tick, so that a handler which scans back cannot set off the other's in turn
    for i = 1, #bots do
        local b = bots[i]
        local from = b.scanned_from
        if from then
            b.scanned_from = nil
            bot_module.execute_bot_event(b, "onScanned", from)
        end
    end

    for i = 1, #bots do
        if bots[i].health > 0 then move_bot(bots[i]) end
    end
    for i = 1, #bots - 1 do
        for j = i + 1, #bots do
            if bots[i].health > 0 and bots[j].health > 0 then collide(bots[i], bots[j]) end
        end
    end

    for i = 1, #bots do
        local b = bots[i]
        if b.hit_wall then
            bot_module.execute_bot_event(b, "onWall")
        end
        local toward = b.bumped
        if toward then
            b.bumped = nil
            bot_module.execute_bot_event(b, "onCollision", toward)
        end
    end

    update_projectiles(false)
    render.update_fx()

    local alive, last = 0, nil
    for i = 1, #bots do
        if bots[i].health > 0 then
            alive = alive + 1
            last = bots[i]
        end
    end
    if alive <= 1 then
        state.winner = last
        log("MATCH OVER: %s (tick %d)", last and (last.name .. " wins") or "draw", state.game_tick)
        log_close()
        for i = 1, #bots do
            bots[i].speed, bots[i].scan_tick, bots[i].pulse_r = 0, -1, 0
        end
        state.finale_ticks = 0
        state.game_state = "finale"
    end
end

-- the match is over, but shots still in the air fly on and the wreckage drifts
local function finale_step()
    update_projectiles(true)
    render.update_fx()
    state.finale_ticks = state.finale_ticks + 1
end

local function info_bar()
    if state.error_text and state.game_tick - state.error_tick < config.ERROR_SHOW_TICKS then
        return state.error_text, colors.red
    end
    local seconds = floor(state.game_tick * TICK)
    if seconds ~= info_seconds then
        info_seconds = seconds
        info_text = string.format("%d:%02d  ESC:quit  S:scan %-5s  Mem:%dK", seconds // 60, seconds % 60,
            config.SCAN_MODES[state.scan_mode], render.get_memory_kb())
    end
    return info_text, config.COLOR_TEXT
end

local function draw_frame()
    local bots = state.bots
    render.draw_status_bar()
    render.draw_info_bar(info_bar())

    render.begin()
    local mode = config.SCAN_MODES[state.scan_mode]
    for i = 1, #bots do
        if bots[i].health > 0 then render.draw_scan(bots[i], mode) end
    end
    for i = 1, config.MAX_PROJECTILES do
        if projectiles[i].active then render.draw_projectile(projectiles[i]) end
    end
    render.draw_fx()
    for i = 1, #bots do
        if bots[i].health > 0 then render.draw_bot(bots[i]) end
    end
    if state.game_state == "finale" then
        local x = config.SCREEN_WIDTH / 2
        local winner = state.winner
        render.text(x, config.ARENA_Y + 100, winner and (winner.name .. " WINS!") or "DRAW!", colors.yellow)
        if state.finale_ticks >= config.FINALE_TICKS then
            render.text(x, config.ARENA_Y + 120, "Press any key to continue", config.COLOR_TEXT)
        end
    end
    render.finish()
end

local function match_input()
    local key_state, _, code = keys.poll()
    while key_state ~= keys.states.idle do
        if key_state == keys.states.pressed then
            if code == keys.esc then
                log("Match left by user (ESC)")
                return end_match()
            elseif state.game_state == "finale" then
                if state.finale_ticks >= config.FINALE_TICKS then return end_match() end
            elseif code == "s" or code == "S" then
                state.scan_mode = state.scan_mode % #config.SCAN_MODES + 1
                info_seconds = nil
            end
        end
        key_state, _, code = keys.poll()
    end
end

local function match_frame()
    match_input()
    if state.game_state == "menu" then return end
    local now = os.clock()
    if now < next_step then return end
    -- ticks that fell behind run before the next frame is drawn, but time lost to a long stall is dropped
    if now - next_step > 5 * TICK then next_step = now end
    repeat
        next_step = next_step + TICK
        if state.game_state == "playing" then step() else finale_step() end
    until now < next_step
    draw_frame()
end

local function main()
    term.setCursorBlink(false)
    collectgarbage()
    screens.draw_menu()

    while not state.quit_game do
        if state.game_state == "menu" then
            screens.menu_input()
        elseif state.game_state == "select" then
            screens.select_input()
        else
            match_frame()
        end
    end
end

-- Even when stopped with Break, the screen goes back to the terminal.
local ok, err = pcall(main)
log_close()
draw.enableBuffer(0)
keys.flush()
term.setCursorBlink(true)
term.clear()
if not ok then error(err, 0) end
print("Thanks for playing BotWarz!")
