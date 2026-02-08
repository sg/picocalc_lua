-- BotWarz - Programmable Robot Arena Battle
-- A game where Lua-scripted bots fight in an arena

-- =============================================================================
-- MODULE LOADING
-- =============================================================================

local config = require("lua.botwarz.config")
local render = require("lua.botwarz.render")
local bot_module = require("lua.botwarz.bot")
local screens = require("lua.botwarz.screens")

-- =============================================================================
-- DEBUG LOGGING
-- =============================================================================

local DEBUG_LOG_ENABLED = true
local log_handle = nil
local state = nil  -- Forward declaration for log function

local function log_open()
    if not DEBUG_LOG_ENABLED then return end
    log_handle = fs.open(config.LOG_FILE, "w")
    if log_handle then
        log_handle:write("=== BotWarz Debug Log ===\n")
        log_handle:flush()
    end
end

local function log_close()
    if log_handle then
        log_handle:close()
        log_handle = nil
    end
end

local function log(msg)
    if not log_handle then return end
    local tick = (state and state.game_tick) or 0
    log_handle:write(string.format("[%04d] %s\n", tick, msg))
    log_handle:flush()
end

-- =============================================================================
-- SHARED GAME STATE
-- =============================================================================

state = {
    game_state = "menu",
    last_tick = 0,
    game_tick = 0,
    quit_game = false,

    -- Bots
    bots = {
        {
            x = 0, y = 0,
            heading = 0,
            speed = 0,
            health = 100,
            energy = 100,
            ammo = 50,
            missiles = 3,
            color = config.COLOR_BOT1,
            name = "Bot1",
            prev_x = 0, prev_y = 0, prev_heading = 0,
            hit_wall = false,
            cannon_cooldown = 0,
            missile_cooldown = 0,
            script = nil,
            script_error = nil,
            pending_turn = 0,
            pending_speed = nil,
        },
        {
            x = 0, y = 0,
            heading = 180,
            speed = 0,
            health = 100,
            energy = 100,
            ammo = 50,
            missiles = 3,
            color = config.COLOR_BOT2,
            name = "Bot2",
            prev_x = 0, prev_y = 0, prev_heading = 180,
            hit_wall = false,
            cannon_cooldown = 0,
            missile_cooldown = 0,
            script = nil,
            script_error = nil,
            pending_turn = 0,
            pending_speed = nil,
        }
    },

    -- Menu state
    menu_selection = 1,
    menu_items = {"Start Match", "How to Play", "Quit"},

    -- Bot selection state
    available_bots = {},
    selected_bots = {1, 2},
    select_slot = 1,

    -- Results state
    winner_name = "",

    -- Functions exposed to other modules
    log = log,
    spawn_projectile = nil,  -- Set below
    scan_bot_files = nil,    -- Set below
    init_match = nil,        -- Set below
}

-- =============================================================================
-- PROJECTILE POOL
-- =============================================================================

local projectiles = {}
for i = 1, config.MAX_PROJECTILES do
    projectiles[i] = {
        active = false,
        x = 0, y = 0,
        vx = 0, vy = 0,
        prev_x = 0, prev_y = 0,
        ptype = 0,
        owner = 0,
        color = colors.white,
    }
end

local function spawn_projectile(x, y, angle, speed, ptype, owner, color)
    for i = 1, config.MAX_PROJECTILES do
        if not projectiles[i].active then
            local p = projectiles[i]
            local rad = render.deg_to_rad(angle)
            p.active = true
            p.x = x
            p.y = y
            p.prev_x = x
            p.prev_y = y
            p.vx = math.sin(rad) * speed
            p.vy = -math.cos(rad) * speed
            p.ptype = ptype
            p.owner = owner
            p.color = color
            return true
        end
    end
    return false
end

local function clear_projectiles()
    for i = 1, config.MAX_PROJECTILES do
        projectiles[i].active = false
    end
end

-- Expose to state for bot module
state.spawn_projectile = spawn_projectile

-- =============================================================================
-- INITIALIZE MODULES
-- =============================================================================

-- Wrapper for scan_bot_files
state.scan_bot_files = function()
    return bot_module.scan_bot_files()
end

render.init(config, state)
bot_module.init(config, render, state)
screens.init(config, render, state)

-- =============================================================================
-- MATCH INITIALIZATION
-- =============================================================================

local function init_match()
    state.game_tick = 0
    clear_projectiles()

    -- Reset bot 1
    state.bots[1].x = 50
    state.bots[1].y = config.ARENA_HEIGHT - 50
    state.bots[1].heading = 315
    state.bots[1].speed = 0
    state.bots[1].health = 100
    state.bots[1].energy = config.BOT_MAX_ENERGY
    state.bots[1].ammo = 50
    state.bots[1].missiles = 3
    state.bots[1].prev_x = state.bots[1].x
    state.bots[1].prev_y = state.bots[1].y
    state.bots[1].prev_heading = state.bots[1].heading
    state.bots[1].hit_wall = false
    state.bots[1].cannon_cooldown = 0
    state.bots[1].missile_cooldown = 0
    state.bots[1].script = nil
    state.bots[1].script_error = nil
    state.bots[1].color = config.COLOR_BOT1
    state.bots[1].last_canfire_fail = nil
    state.bots[1].last_canmissile_fail = nil

    -- Reset bot 2
    state.bots[2].x = config.ARENA_WIDTH - 50
    state.bots[2].y = 50
    state.bots[2].heading = 135
    state.bots[2].speed = 0
    state.bots[2].health = 100
    state.bots[2].energy = config.BOT_MAX_ENERGY
    state.bots[2].ammo = 50
    state.bots[2].missiles = 3
    state.bots[2].prev_x = state.bots[2].x
    state.bots[2].prev_y = state.bots[2].y
    state.bots[2].prev_heading = state.bots[2].heading
    state.bots[2].hit_wall = false
    state.bots[2].cannon_cooldown = 0
    state.bots[2].missile_cooldown = 0
    state.bots[2].script = nil
    state.bots[2].script_error = nil
    state.bots[2].color = config.COLOR_BOT2
    state.bots[2].last_canfire_fail = nil
    state.bots[2].last_canmissile_fail = nil

    -- Load bot scripts
    term.clear()
    draw.text(config.SCREEN_WIDTH/2, 100, "Loading bots...", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)

    for i = 1, 2 do
        local filename = state.available_bots[state.selected_bots[i]]
        draw.text(config.SCREEN_WIDTH/2, 120 + i * 20, "Loading " .. filename, config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)

        local script, err = bot_module.load_bot_script(filename, state.bots[i])
        if script then
            state.bots[i].script = script
            state.bots[i].name = script.name
            if script.color then
                state.bots[i].color = script.color
            end
        else
            state.bots[i].script_error = err
            state.bots[i].name = "ERROR"
            draw.text(config.SCREEN_WIDTH/2, 140 + i * 20, err, colors.red, config.COLOR_BG, draw.align_center)
        end
    end

    -- Call init functions
    for i = 1, 2 do
        if state.bots[i].script and state.bots[i].script.init then
            bot_module.execute_bot_event(state.bots[i], "init")
        end
    end

    -- Small delay to see loading
    local start = os.clock()
    while os.clock() - start < 0.5 do end

    collectgarbage()

    log_open()
    log("Match started")
    log(string.format("Bot1: %s at (%.0f,%.0f) heading %.0f, ammo=%d energy=%d",
        state.bots[1].name, state.bots[1].x, state.bots[1].y, state.bots[1].heading, state.bots[1].ammo, state.bots[1].energy))
    log(string.format("Bot2: %s at (%.0f,%.0f) heading %.0f, ammo=%d energy=%d",
        state.bots[2].name, state.bots[2].x, state.bots[2].y, state.bots[2].heading, state.bots[2].ammo, state.bots[2].energy))

    term.clear()
    term.setCursorBlink(false)
    render.draw_arena()
    render.draw_status_bar()
    render.draw_info_bar()

    for _, b in ipairs(state.bots) do
        render.draw_bot(b)
    end

    state.last_tick = os.clock()
end

-- Expose to state for screens module
state.init_match = init_match

-- =============================================================================
-- GAME UPDATE
-- =============================================================================

local function update_bot_position(b)
    b.hit_wall = false

    if b.speed ~= 0 then
        local rad = render.deg_to_rad(b.heading)
        local dx = math.sin(rad) * b.speed
        local dy = -math.cos(rad) * b.speed

        local new_x = b.x + dx
        local new_y = b.y + dy

        if new_x < config.BOT_RADIUS then
            new_x = config.BOT_RADIUS
            b.hit_wall = true
        elseif new_x > config.ARENA_WIDTH - config.BOT_RADIUS then
            new_x = config.ARENA_WIDTH - config.BOT_RADIUS
            b.hit_wall = true
        end

        if new_y < config.BOT_RADIUS then
            new_y = config.BOT_RADIUS
            b.hit_wall = true
        elseif new_y > config.ARENA_HEIGHT - config.BOT_RADIUS then
            new_y = config.ARENA_HEIGHT - config.BOT_RADIUS
            b.hit_wall = true
        end

        if b.hit_wall then
            b.speed = 0
        end

        b.x = new_x
        b.y = new_y
    end
end

local function update_projectiles()
    for i = 1, config.MAX_PROJECTILES do
        local p = projectiles[i]
        if p.active then
            p.prev_x = p.x
            p.prev_y = p.y

            p.x = p.x + p.vx
            p.y = p.y + p.vy

            if p.x < 0 or p.x >= config.ARENA_WIDTH or p.y < 0 or p.y >= config.ARENA_HEIGHT then
                if p.ptype == config.PROJ_TYPE_MISSILE then
                    for j, b in ipairs(state.bots) do
                        if b.health > 0 then
                            local dist = render.distance(p.x, p.y, b.x, b.y)
                            if dist <= config.MISSILE_SPLASH_RADIUS then
                                local was_alive = b.health > 0
                                b.health = b.health - config.MISSILE_SPLASH_DAMAGE
                                if b.health < 0 then b.health = 0 end
                                local hit_dir = render.angle_to(p.x, p.y, b.x, b.y)
                                bot_module.execute_bot_event(b, "onHit", hit_dir, config.MISSILE_SPLASH_DAMAGE)
                                if was_alive and b.health == 0 then
                                    local killer = state.bots[p.owner]
                                    local victim_name = b.script and b.script.name or b.name
                                    bot_module.execute_bot_event(killer, "onKill", victim_name)
                                end
                            end
                        end
                    end
                    sound.playPitch(0, 0.3, sound.drums.kick1)
                end
                p.active = false
            else
                for j, b in ipairs(state.bots) do
                    if j ~= p.owner and b.health > 0 then
                        local dist = render.distance(p.x, p.y, b.x, b.y)
                        if dist <= config.BOT_RADIUS then
                            local damage = (p.ptype == config.PROJ_TYPE_CANNON) and config.CANNON_DAMAGE or config.MISSILE_DAMAGE
                            local hit_dir = render.angle_to(p.x, p.y, b.x, b.y)
                            local was_alive = b.health > 0
                            local proj_type = (p.ptype == config.PROJ_TYPE_CANNON) and "cannon" or "missile"
                            local shooter_name = state.bots[p.owner].name or ("Bot" .. p.owner)
                            local victim_name = b.name or ("Bot" .. j)
                            log(string.format("HIT: %s's %s hit %s for %d dmg (health: %d->%d)",
                                shooter_name, proj_type, victim_name, damage, b.health, math.max(0, b.health - damage)))

                            b.health = b.health - damage
                            if b.health < 0 then b.health = 0 end

                            bot_module.execute_bot_event(b, "onHit", hit_dir, damage)

                            if was_alive and b.health == 0 then
                                local killer = state.bots[p.owner]
                                local victim_name2 = b.script and b.script.name or b.name
                                bot_module.execute_bot_event(killer, "onKill", victim_name2)
                                sound.playPitch(0, 0.2, sound.drums.kick1)
                            else
                                sound.playPitch(0, 0.6, sound.drums.snare2)
                            end

                            if p.ptype == config.PROJ_TYPE_MISSILE then
                                for k, other_bot in ipairs(state.bots) do
                                    if k ~= j and other_bot.health > 0 then
                                        local splash_dist = render.distance(p.x, p.y, other_bot.x, other_bot.y)
                                        if splash_dist <= config.MISSILE_SPLASH_RADIUS then
                                            local splash_was_alive = other_bot.health > 0
                                            other_bot.health = other_bot.health - config.MISSILE_SPLASH_DAMAGE
                                            if other_bot.health < 0 then other_bot.health = 0 end
                                            local splash_dir = render.angle_to(p.x, p.y, other_bot.x, other_bot.y)
                                            bot_module.execute_bot_event(other_bot, "onHit", splash_dir, config.MISSILE_SPLASH_DAMAGE)
                                            if splash_was_alive and other_bot.health == 0 then
                                                local killer = state.bots[p.owner]
                                                local victim_name3 = other_bot.script and other_bot.script.name or other_bot.name
                                                bot_module.execute_bot_event(killer, "onKill", victim_name3)
                                            end
                                        end
                                    end
                                end
                                sound.playPitch(0, 0.3, sound.drums.kick1)
                            end

                            p.active = false
                            break
                        end
                    end
                end
            end
        end
    end
end

local function update_playing()
    state.game_tick = state.game_tick + 1

    -- Periodic status logging
    if state.game_tick % 100 == 0 then
        for i, b in ipairs(state.bots) do
            if b.health > 0 then
                log(string.format("STATUS %s: HP=%d ammo=%d missiles=%d energy=%d pos=(%.0f,%.0f)",
                    b.name or ("Bot"..i), b.health, b.ammo, b.missiles, b.energy, b.x, b.y))
            end
        end
    end

    -- Store previous positions
    for _, b in ipairs(state.bots) do
        b.prev_x = b.x
        b.prev_y = b.y
        b.prev_heading = b.heading
    end

    -- Regenerate energy and decrement cooldowns
    for _, b in ipairs(state.bots) do
        b.energy = math.min(b.energy + config.BOT_ENERGY_REGEN, config.BOT_MAX_ENERGY)
        if b.cannon_cooldown > 0 then
            b.cannon_cooldown = b.cannon_cooldown - 1
        end
        if b.missile_cooldown > 0 then
            b.missile_cooldown = b.missile_cooldown - 1
        end
    end

    -- Execute bot tick functions
    for _, b in ipairs(state.bots) do
        if b.health > 0 then
            bot_module.execute_bot_tick(b)
        end
    end

    -- Update positions
    for _, b in ipairs(state.bots) do
        update_bot_position(b)
    end

    -- Check wall collisions
    for _, b in ipairs(state.bots) do
        if b.hit_wall then
            bot_module.execute_bot_event(b, "onWall")
        end
    end

    -- Update projectiles
    update_projectiles()

    -- Erase projectiles at old positions
    for i = 1, config.MAX_PROJECTILES do
        local p = projectiles[i]
        if p.active or (p.prev_x ~= p.x or p.prev_y ~= p.y) then
            render.erase_projectile(p, p.prev_x, p.prev_y)
        end
    end

    -- Erase bots at old positions
    for _, b in ipairs(state.bots) do
        render.erase_bot(b, b.prev_x, b.prev_y, b.prev_heading)
    end

    -- Draw bots at new positions
    for _, b in ipairs(state.bots) do
        if b.health > 0 then
            render.draw_bot(b)
        end
    end

    -- Draw projectiles at new positions
    for i = 1, config.MAX_PROJECTILES do
        local p = projectiles[i]
        if p.active then
            render.draw_projectile(p)
        end
    end

    render.draw_status_bar()
    render.draw_info_bar()

    -- Periodic garbage collection
    if state.game_tick % 50 == 0 then
        collectgarbage("step", 10)
    end

    -- Check win condition
    local alive_count = 0
    local last_alive = nil
    for _, b in ipairs(state.bots) do
        if b.health > 0 then
            alive_count = alive_count + 1
            last_alive = b
        end
    end

    if alive_count <= 1 then
        if last_alive then
            state.winner_name = last_alive.script and last_alive.script.name or last_alive.name
        else
            state.winner_name = "Nobody"
        end
        log(string.format("MATCH OVER: %s wins! (tick %d)", state.winner_name, state.game_tick))
        log_close()
        state.game_state = "results"
        screens.draw_results()
    end
end

local function playing_input()
    local key_state, _, code = keys.poll()
    if key_state == keys.states.pressed then
        if code == keys.esc then
            log("Match aborted by user (ESC)")
            log_close()
            state.game_state = "menu"
            term.setCursorBlink(false)
            screens.draw_menu()
        end
    end
end

-- =============================================================================
-- CLEANUP
-- =============================================================================

local function cleanup()
    log_close()
    package.loaded["lua.botwarz.config"] = nil
    package.loaded["lua.botwarz.render"] = nil
    package.loaded["lua.botwarz.bot"] = nil
    package.loaded["lua.botwarz.screens"] = nil
    collectgarbage()
end

-- =============================================================================
-- MAIN GAME LOOP
-- =============================================================================

local function main()
    term.setCursorBlink(false)
    collectgarbage()
    local initial_mem = render.get_memory_kb()

    screens.draw_menu()

    while not state.quit_game do
        if state.game_state == "menu" then
            screens.menu_input()

        elseif state.game_state == "select" then
            screens.select_input()

        elseif state.game_state == "playing" then
            playing_input()

            local now = os.clock()
            if now >= state.last_tick + config.TICK_INTERVAL then
                state.last_tick = now
                update_playing()
            end

        elseif state.game_state == "results" then
            screens.results_input()
        end
    end

    term.setCursorBlink(true)
    term.clear()
    print("Thanks for playing BotWarz!")
    print("Final memory: " .. render.get_memory_kb() .. "KB")
    print("Initial memory: " .. initial_mem .. "KB")

    cleanup()
end

-- Run the game
main()
