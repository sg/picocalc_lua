-- BotWarz Bot Module
-- Bot sandbox, loading, and execution

local M = {}

-- Module-local references (set via init)
local config = nil
local render = nil
local state = nil  -- shared game state with bots, projectiles, log, spawn_projectile

-- Instruction counter for limiting bot execution
local instruction_count = 0

local function instruction_hook()
    instruction_count = instruction_count + 1
    if instruction_count > config.BOT_INSTRUCTION_LIMIT then
        error("Instruction limit exceeded")
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function M.init(cfg, rnd, game_state)
    config = cfg
    render = rnd
    state = game_state
end

-- =============================================================================
-- BOT SANDBOX
-- =============================================================================

-- Create a restricted environment for bot scripts
function M.create_bot_sandbox(bot_state)
    -- The bot API object that scripts interact with
    local bot = {
        name = "Unnamed",
        color = nil,
    }

    -- Movement commands
    function bot.drive(speed)
        if type(speed) ~= "number" then return end
        bot_state.pending_speed = render.clamp(speed, 0, config.BOT_MAX_SPEED)
    end

    function bot.turn(degrees)
        if type(degrees) ~= "number" then return end
        bot_state.pending_turn = bot_state.pending_turn + degrees
    end

    function bot.turnTo(angle)
        if type(angle) ~= "number" then return end
        local current = bot_state.heading
        local target = render.normalize_angle(angle)
        local diff = target - current
        if diff > 180 then diff = diff - 360 end
        if diff < -180 then diff = diff + 360 end
        bot_state.pending_turn = bot_state.pending_turn + diff
    end

    function bot.stop()
        bot_state.pending_speed = 0
    end

    -- Sensing commands
    function bot.scan(arc)
        if type(arc) ~= "number" then return nil, nil end
        arc = render.clamp(arc, 1, 90)
        if bot_state.energy < config.BOT_SCAN_COST then
            return nil, nil
        end
        bot_state.energy = bot_state.energy - config.BOT_SCAN_COST
        return bot.scanAt(bot_state.heading, arc)
    end

    function bot.scanAt(angle, arc)
        if type(angle) ~= "number" or type(arc) ~= "number" then return nil, nil end
        arc = render.clamp(arc, 1, 90)
        angle = render.normalize_angle(angle)

        local owner_idx = 1
        for i, b in ipairs(state.bots) do
            if b == bot_state then owner_idx = i break end
        end
        local bot_name = bot_state.name or ("Bot" .. owner_idx)

        local closest_dist = nil
        local closest_angle = nil

        for i, other in ipairs(state.bots) do
            if other ~= bot_state and other.health > 0 then
                local dist = render.distance(bot_state.x, bot_state.y, other.x, other.y)
                if dist <= config.BOT_SCAN_RANGE then
                    local ang = render.angle_to(bot_state.x, bot_state.y, other.x, other.y)
                    local diff = ang - angle
                    if diff > 180 then diff = diff - 360 end
                    if diff < -180 then diff = diff + 360 end
                    if math.abs(diff) <= arc / 2 then
                        if closest_dist == nil or dist < closest_dist then
                            closest_dist = dist
                            closest_angle = ang
                        end
                    end
                end
            end
        end

        if closest_dist then
            state.log(string.format("%s scanAt(%.0f, arc=%d): FOUND at dist=%.0f ang=%.0f",
                bot_name, angle, arc, closest_dist, closest_angle))
        end

        return closest_dist, closest_angle
    end

    -- State queries
    function bot.getHeading() return bot_state.heading end
    function bot.getPosition() return bot_state.x, bot_state.y end
    function bot.getHealth() return bot_state.health end
    function bot.getEnergy() return bot_state.energy end
    function bot.getAmmo() return bot_state.ammo end
    function bot.getMissiles() return bot_state.missiles end
    function bot.getSpeed() return bot_state.speed end
    function bot.getArenaSize() return config.ARENA_WIDTH, config.ARENA_HEIGHT end
    function bot.getTick() return state.game_tick end

    -- Utility functions
    function bot.angleTo(x, y)
        if type(x) ~= "number" or type(y) ~= "number" then return 0 end
        return render.angle_to(bot_state.x, bot_state.y, x, y)
    end

    function bot.distanceTo(x, y)
        if type(x) ~= "number" or type(y) ~= "number" then return 0 end
        return render.distance(bot_state.x, bot_state.y, x, y)
    end

    -- Combat commands
    function bot.fire()
        bot.fireAt(bot_state.heading)
    end

    function bot.fireAt(angle)
        local owner_idx = 1
        for i, b in ipairs(state.bots) do
            if b == bot_state then owner_idx = i break end
        end
        local bot_name = bot_state.name or ("Bot" .. owner_idx)

        if type(angle) ~= "number" then
            state.log(string.format("%s fireAt: FAIL - angle not a number", bot_name))
            return false
        end
        if bot_state.ammo <= 0 then
            state.log(string.format("%s fireAt: FAIL - no ammo (ammo=%d)", bot_name, bot_state.ammo))
            return false
        end
        if bot_state.cannon_cooldown > 0 then
            state.log(string.format("%s fireAt: FAIL - cooldown active (cd=%d)", bot_name, bot_state.cannon_cooldown))
            return false
        end
        if bot_state.energy < config.CANNON_ENERGY then
            state.log(string.format("%s fireAt: FAIL - low energy (energy=%d need=%d)", bot_name, bot_state.energy, config.CANNON_ENERGY))
            return false
        end

        angle = render.normalize_angle(angle)
        local rad = render.deg_to_rad(angle)
        local spawn_x = bot_state.x + math.sin(rad) * 16
        local spawn_y = bot_state.y - math.cos(rad) * 16

        if state.spawn_projectile(spawn_x, spawn_y, angle, config.CANNON_SPEED, config.PROJ_TYPE_CANNON, owner_idx, bot_state.color) then
            bot_state.ammo = bot_state.ammo - 1
            bot_state.cannon_cooldown = config.CANNON_COOLDOWN
            bot_state.energy = bot_state.energy - config.CANNON_ENERGY
            state.log(string.format("%s fireAt: SUCCESS at angle %.0f from (%.0f,%.0f)", bot_name, angle, spawn_x, spawn_y))
            sound.playPitch(0, 0.8, sound.drums.tom)
            return true
        end
        state.log(string.format("%s fireAt: FAIL - projectile pool exhausted", bot_name))
        return false
    end

    function bot.missile()
        bot.missileAt(bot_state.heading)
    end

    function bot.missileAt(angle)
        if type(angle) ~= "number" then return false end
        if bot_state.missiles <= 0 then return false end
        if bot_state.missile_cooldown > 0 then return false end
        if bot_state.energy < config.MISSILE_ENERGY then return false end

        angle = render.normalize_angle(angle)
        local rad = render.deg_to_rad(angle)
        local spawn_x = bot_state.x + math.sin(rad) * 16
        local spawn_y = bot_state.y - math.cos(rad) * 16

        local owner_idx = 1
        for i, b in ipairs(state.bots) do
            if b == bot_state then owner_idx = i break end
        end

        if state.spawn_projectile(spawn_x, spawn_y, angle, config.MISSILE_SPEED, config.PROJ_TYPE_MISSILE, owner_idx, bot_state.color) then
            bot_state.missiles = bot_state.missiles - 1
            bot_state.missile_cooldown = config.MISSILE_COOLDOWN
            bot_state.energy = bot_state.energy - config.MISSILE_ENERGY
            sound.playPitch(0, 0.5, sound.drums.kick1)
            return true
        end
        return false
    end

    function bot.canFire()
        local can = bot_state.ammo > 0 and bot_state.cannon_cooldown == 0 and bot_state.energy >= config.CANNON_ENERGY
        if not can then
            local reason = ""
            if bot_state.ammo <= 0 then reason = "no_ammo"
            elseif bot_state.cannon_cooldown > 0 then reason = "cooldown"
            else reason = "low_energy" end
            if bot_state.last_canfire_fail ~= reason then
                bot_state.last_canfire_fail = reason
                local owner_idx = 1
                for i, b in ipairs(state.bots) do if b == bot_state then owner_idx = i break end end
                local bot_name = bot_state.name or ("Bot" .. owner_idx)
                if reason == "no_ammo" then
                    state.log(string.format("%s canFire: NO - out of ammo", bot_name))
                elseif reason == "cooldown" then
                    state.log(string.format("%s canFire: NO - cooldown (%d ticks)", bot_name, bot_state.cannon_cooldown))
                else
                    state.log(string.format("%s canFire: NO - low energy (%d/%d)", bot_name, bot_state.energy, config.CANNON_ENERGY))
                end
            end
        else
            bot_state.last_canfire_fail = nil
        end
        return can
    end

    function bot.canMissile()
        local can = bot_state.missiles > 0 and bot_state.missile_cooldown == 0 and bot_state.energy >= config.MISSILE_ENERGY
        if not can and bot_state.last_canmissile_fail ~= true then
            bot_state.last_canmissile_fail = true
            local owner_idx = 1
            for i, b in ipairs(state.bots) do if b == bot_state then owner_idx = i break end end
            local bot_name = bot_state.name or ("Bot" .. owner_idx)
            local reason = ""
            if bot_state.missiles <= 0 then reason = "no missiles"
            elseif bot_state.missile_cooldown > 0 then reason = "cooldown"
            else reason = "low energy" end
            state.log(string.format("%s canMissile: NO - %s", bot_name, reason))
        elseif can then
            bot_state.last_canmissile_fail = nil
        end
        return can
    end

    -- Create the sandbox environment
    local sandbox = {
        bot = bot,
        math = math,
        string = string,
        table = table,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        print = print,
        colors = {
            fromRGB = colors.fromRGB,
            white = colors.white,
            black = colors.black,
            red = colors.red,
            green = colors.green,
            blue = colors.blue,
            yellow = colors.yellow,
            cyan = colors.cyan,
            magenta = colors.magenta,
            orange = colors.orange,
        },
    }

    return sandbox, bot
end

-- =============================================================================
-- BOT LOADING
-- =============================================================================

function M.load_bot_script(filename, bot_state)
    local filepath = config.BOTS_DIR .. filename

    if not fs.exists(filepath) then
        return nil, "File not found: " .. filepath
    end

    local sandbox, bot_api = M.create_bot_sandbox(bot_state)

    local chunk, err = loadfile(filepath, "t", sandbox)
    if not chunk then
        return nil, "Load error: " .. tostring(err)
    end

    instruction_count = 0
    debug.sethook(instruction_hook, "", 100)

    local ok, run_err = pcall(chunk)

    debug.sethook()

    if not ok then
        return nil, "Run error: " .. tostring(run_err)
    end

    local script = {
        name = bot_api.name or "Unnamed",
        color = bot_api.color,
        init = bot_api.init,
        tick = bot_api.tick,
        onHit = bot_api.onHit,
        onWall = bot_api.onWall,
        onCollision = bot_api.onCollision,
        onKill = bot_api.onKill,
    }

    if type(script.tick) ~= "function" then
        return nil, "Bot must define bot.tick() function"
    end

    return script, nil
end

-- =============================================================================
-- BOT EXECUTION
-- =============================================================================

function M.execute_bot_tick(bot_state)
    if not bot_state.script or not bot_state.script.tick then
        return
    end

    bot_state.pending_turn = 0
    bot_state.pending_speed = nil

    instruction_count = 0
    debug.sethook(instruction_hook, "", 50)

    local ok, err = pcall(bot_state.script.tick)

    debug.sethook()

    if not ok then
        bot_state.script_error = "tick error: " .. tostring(err)
        state.log(string.format("ERROR: %s tick() failed: %s", bot_state.name or "Bot", tostring(err)))
    end

    if bot_state.pending_turn ~= 0 then
        local turn = render.clamp(bot_state.pending_turn, -config.BOT_TURN_RATE, config.BOT_TURN_RATE)
        bot_state.heading = render.normalize_angle(bot_state.heading + turn)
    end
    if bot_state.pending_speed ~= nil then
        bot_state.speed = bot_state.pending_speed
    end
end

function M.execute_bot_event(bot_state, event_name, ...)
    if not bot_state.script then return end
    local handler = bot_state.script[event_name]
    if type(handler) ~= "function" then return end

    bot_state.pending_turn = 0
    bot_state.pending_speed = nil

    instruction_count = 0
    debug.sethook(instruction_hook, "", 50)

    local ok, err = pcall(handler, ...)

    debug.sethook()

    if not ok then
        bot_state.script_error = event_name .. " error: " .. tostring(err)
    end

    if bot_state.pending_turn ~= 0 then
        local max_turn = config.BOT_TURN_RATE
        if event_name == "onWall" then
            max_turn = config.BOT_TURN_RATE * config.BOT_WALL_TURN_PENALTY
        end
        local turn = render.clamp(bot_state.pending_turn, -max_turn, max_turn)
        bot_state.heading = render.normalize_angle(bot_state.heading + turn)
    end
    if bot_state.pending_speed ~= nil then
        bot_state.speed = bot_state.pending_speed
    end
end

-- =============================================================================
-- BOT FILE SCANNING
-- =============================================================================

function M.scan_bot_files()
    local available_bots = {}

    if not fs.exists(config.BOTS_DIR) or not fs.isDir(config.BOTS_DIR) then
        return available_bots
    end

    local files = fs.list(config.BOTS_DIR)
    if not files then
        return available_bots
    end

    for _, entry in ipairs(files) do
        if not entry.isDir and string.sub(entry.name, -4) == ".lua" then
            table.insert(available_bots, entry.name)
        end
    end

    table.sort(available_bots)
    return available_bots
end

return M
