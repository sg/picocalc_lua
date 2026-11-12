-- BotWarz bot scripts: the sandbox and API a script sees, loading it, and running its handlers

local M = {}

local config = nil
local render = nil
local state = nil

local sin, cos, sqrt, asin, abs, huge = math.sin, math.cos, math.sqrt, math.asin, math.abs, math.huge
local RAD = math.pi / 180

function M.init(cfg, rnd, game_state)
    config = cfg
    render = rnd
    state = game_state
end

-- inf and nan are numbers too, and one of them in a heading or a coordinate would stop the game
local function finite(v)
    return type(v) == "number" and v - v == 0
end

local guarded_call

-- The allowance can run out in the few instructions after a script has returned, where nothing would catch the error.
local function over_limit()
    if debug.getinfo(2, "f").func ~= guarded_call then
        error("instruction limit exceeded", 0)
    end
end

-- The count hook fires once, when the allowance is used up, so a script within it pays nothing for the limit.
function guarded_call(limit, fn, a1, a2)
    debug.sethook(over_limit, "", limit)
    local ok, err = pcall(fn, a1, a2)
    debug.sethook()
    return ok, err
end

local function report(b, what, err)
    local msg = what .. ": " .. (tostring(err):gsub("^[^:]*/", ""))
    -- a script that fails usually fails the same way every tick
    if b.script_error ~= msg then
        b.script_error = msg
        state.error_text = (b.name .. " " .. msg):sub(1, 52)
        state.error_tick = state.game_tick
        state.log_error(b.name .. " " .. msg)
    end
end

function M.create_bot_sandbox(b)
    local bot = {
        name = "Unnamed",
        color = nil,
        shape = nil,
        MAX_SPEED = config.BOT_MAX_SPEED,
        MAX_REVERSE = config.BOT_MAX_REVERSE,
        TURN_RATE = config.BOT_TURN_RATE,
        RADIUS = config.BOT_RADIUS,
        SCAN_RANGE = config.BOT_SCAN_RANGE,
        CANNON_SPEED = config.CANNON_SPEED,
        MISSILE_SPEED = config.MISSILE_SPEED,
    }

    -- What a script asks for with these is carried out once a tick, after its tick() has run, so a
    -- handler that runs between ticks adds to the same turn allowance instead of getting one of its own.
    function bot.drive(speed)
        if not finite(speed) then return end
        b.pending_speed = render.clamp(speed, -config.BOT_MAX_REVERSE, config.BOT_MAX_SPEED)
    end

    function bot.turn(degrees)
        if not finite(degrees) then return end
        b.pending_turn = b.pending_turn + degrees
    end

    function bot.turnTo(angle)
        if not finite(angle) then return end
        b.pending_turn = render.angle_diff(b.heading, angle)
    end

    function bot.stop()
        b.pending_speed = 0
    end

    local function scan(angle, arc)
        if b.energy < config.BOT_SCAN_COST then return nil end
        b.energy = b.energy - config.BOT_SCAN_COST
        arc = render.clamp(arc, 1, 90)
        angle = render.normalize_angle(angle)

        local radius, range = config.BOT_RADIUS, config.BOT_SCAN_RANGE
        local found, found_dist
        local bots = state.bots
        for i = 1, #bots do
            local other = bots[i]
            if other ~= b and other.health > 0 then
                local dist = render.distance(b.x, b.y, other.x, other.y)
                if dist - radius <= range and (not found or dist < found_dist) then
                    -- a bot is seen when any of it is inside the arc, which is what the arc drawn on screen shows
                    local seen = dist <= radius
                    if not seen then
                        local off = abs(render.angle_diff(angle, render.angle_to(b.x, b.y, other.x, other.y)))
                        seen = off <= arc / 2 + asin(radius / dist) / RAD
                    end
                    if seen then found, found_dist = other, dist end
                end
            end
        end

        -- of several scans in a tick the screen shows one, and that is one which found something if any did
        if b.scan_tick ~= state.game_tick or not b.scan_hit then
            b.scan_tick, b.scan_ang, b.scan_arc, b.scan_hit = state.game_tick, angle, arc, found
        end
        if not found then return nil end

        local bearing = render.angle_to(b.x, b.y, found.x, found.y)
        found.scanned_from = render.normalize_angle(bearing + 180)
        if state.logging then
            state.log("%s scan(%.0f, arc=%.0f): found %s at dist=%.0f ang=%.0f", b.name, angle, arc, found.name, found_dist, bearing)
        end
        return found_dist, bearing, found.heading, found.speed
    end

    function bot.scan(arc)
        if not finite(arc) then return nil end
        return scan(b.heading, arc)
    end

    function bot.scanAt(angle, arc)
        if not finite(angle) or not finite(arc) then return nil end
        return scan(angle, arc)
    end

    -- the nearest enemy shot within scan range that is closing on this bot
    function bot.detectShot()
        if b.energy < config.BOT_SCAN_COST then return nil end
        b.energy = b.energy - config.BOT_SCAN_COST
        local best, best_d2 = nil, config.BOT_SCAN_RANGE * config.BOT_SCAN_RANGE
        local shots = state.projectiles
        for i = 1, #shots do
            local p = shots[i]
            if p.active and p.owner ~= b.index then
                local dx, dy = p.x - b.x, p.y - b.y
                local d2 = dx * dx + dy * dy
                if d2 <= best_d2 and dx * p.vx + dy * p.vy < 0 then
                    best, best_d2 = p, d2
                end
            end
        end
        if not best then return nil end
        return sqrt(best_d2), render.angle_to(b.x, b.y, best.x, best.y), best.heading,
            best.ptype == config.PROJ_TYPE_MISSILE and "missile" or "cannon"
    end

    -- from the bot's centre, which stops RADIUS short of the wall
    function bot.wallDistance(angle)
        if angle == nil then
            angle = b.heading
        elseif not finite(angle) then
            return 0
        end
        local dx, dy = sin(angle * RAD), -cos(angle * RAD)
        local t = huge
        if dx > 1e-9 then t = (config.ARENA_WIDTH - b.x) / dx elseif dx < -1e-9 then t = -b.x / dx end
        if dy > 1e-9 then
            t = math.min(t, (config.ARENA_HEIGHT - b.y) / dy)
        elseif dy < -1e-9 then
            t = math.min(t, -b.y / dy)
        end
        return t
    end

    function bot.getHeading() return b.heading end
    function bot.getPosition() return b.x, b.y end
    function bot.getHealth() return b.health end
    function bot.getEnergy() return b.energy end
    function bot.getAmmo() return b.ammo end
    function bot.getMissiles() return b.missiles end
    function bot.getSpeed() return b.speed end
    function bot.getAim() return b.aim or b.heading end
    function bot.getCooldown() return b.cannon_cooldown, b.missile_cooldown end
    function bot.getArenaSize() return config.ARENA_WIDTH, config.ARENA_HEIGHT end
    function bot.getTick() return state.game_tick end

    function bot.angleTo(x, y)
        if not finite(x) or not finite(y) then return 0 end
        return render.angle_to(b.x, b.y, x, y)
    end

    function bot.distanceTo(x, y)
        if not finite(x) or not finite(y) then return 0 end
        return render.distance(b.x, b.y, x, y)
    end

    function bot.angleDiff(from, to)
        if not finite(from) or not finite(to) then return 0 end
        return render.angle_diff(from, to)
    end

    local function launch(angle, ptype, speed)
        local dx, dy = sin(angle * RAD), -cos(angle * RAD)
        local reach = config.BARREL_LENGTH
        return state.spawn_projectile(b.x + dx * reach, b.y + dy * reach, angle, speed, ptype, b.index, b.color)
    end

    function bot.canFire()
        return b.ammo > 0 and b.cannon_cooldown == 0 and b.energy >= config.CANNON_ENERGY
    end

    function bot.canMissile()
        return b.missiles > 0 and b.missile_cooldown == 0 and b.energy >= config.MISSILE_ENERGY
    end

    local function fire_cannon(angle)
        if not bot.canFire() or not launch(angle, config.PROJ_TYPE_CANNON, config.CANNON_SPEED) then return false end
        b.ammo = b.ammo - 1
        b.cannon_cooldown = config.CANNON_COOLDOWN
        b.energy = b.energy - config.CANNON_ENERGY
        sound.playPitch(0, 0.8, sound.drums.tom)
        if state.logging then state.log("%s fires at %.0f", b.name, angle) end
        return true
    end

    local function fire_missile(angle)
        if not bot.canMissile() or not launch(angle, config.PROJ_TYPE_MISSILE, config.MISSILE_SPEED) then return false end
        b.missiles = b.missiles - 1
        b.missile_cooldown = config.MISSILE_COOLDOWN
        b.energy = b.energy - config.MISSILE_ENERGY
        sound.playPitch(0, 0.5, sound.drums.kick1)
        if state.logging then state.log("%s launches a missile at %.0f", b.name, angle) end
        return true
    end

    -- The gun points wherever the bot last aimed: straight ahead, turning with the bot, after fire() or
    -- missile(), and at a fixed bearing after fireAt() or missileAt(), even when the shot was not ready.
    function bot.fire()
        b.aim = nil
        return fire_cannon(b.heading)
    end

    function bot.fireAt(angle)
        if not finite(angle) then return false end
        b.aim = render.normalize_angle(angle)
        return fire_cannon(b.aim)
    end

    function bot.missile()
        b.aim = nil
        return fire_missile(b.heading)
    end

    function bot.missileAt(angle)
        if not finite(angle) then return false end
        b.aim = render.normalize_angle(angle)
        return fire_missile(b.aim)
    end

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
        -- printing on the screen would write over the arena
        print = function(...)
            if not state.logging then return end
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring((select(i, ...)))
            end
            state.log("%s: %s", b.name, table.concat(parts, " "))
        end,
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

local function handler(f)
    return type(f) == "function" and f or nil
end

function M.load_bot_script(filename, b)
    local filepath = config.BOTS_DIR .. filename

    if not fs.exists(filepath) then
        return nil, "File not found: " .. filepath
    end

    local sandbox, api = M.create_bot_sandbox(b)

    local chunk, err = loadfile(filepath, "t", sandbox)
    if not chunk then
        return nil, "Load error: " .. tostring(err)
    end

    local ok, run_err = guarded_call(config.BOT_LOAD_INSTRUCTION_LIMIT, chunk)

    if not ok then
        return nil, "Run error: " .. tostring(run_err)
    end
    if type(api.tick) ~= "function" then
        return nil, "Bot must define bot.tick() function"
    end

    local name = type(api.name) == "string" and api.name ~= "" and api.name or "Unnamed"
    local color = api.color
    if math.type(color) ~= "integer" or color < 0 or color > 0xFFFF then color = nil end

    return {
        name = name:sub(1, 12),
        color = color,
        shape = config.SHAPES[config.SHAPE_NAMES[api.shape] or api.shape],
        init = handler(api.init),
        tick = api.tick,
        onHit = handler(api.onHit),
        onWall = handler(api.onWall),
        onCollision = handler(api.onCollision),
        onKill = handler(api.onKill),
        onScanned = handler(api.onScanned),
        onShotHit = handler(api.onShotHit),
    }
end

local function run(b, fn, what, a1, a2)
    local ok, err = guarded_call(config.BOT_INSTRUCTION_LIMIT, fn, a1, a2)
    if not ok then report(b, what, err) end
end

function M.execute_bot_tick(b)
    if not b.script then return end
    run(b, b.script.tick, "tick")

    local rate = config.BOT_TURN_RATE
    -- hit_wall is from the move before, so a bot pressing on a wall turns slowly until it stops pressing
    if b.hit_wall then rate = rate * config.BOT_WALL_TURN_PENALTY end
    local turn = render.clamp(b.pending_turn, -rate, rate)
    if turn ~= 0 then
        b.heading = render.normalize_angle(b.heading + turn)
    end
    b.pending_turn = 0
    if b.pending_speed then
        b.speed = b.pending_speed
        b.pending_speed = nil
    end
end

function M.execute_bot_event(b, event_name, a1, a2)
    if not b.script or b.health <= 0 then return end
    local fn = b.script[event_name]
    if fn then run(b, fn, event_name, a1, a2) end
end

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
