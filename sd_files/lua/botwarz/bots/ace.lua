-- Ace Bot
-- Circles its target, leads its shots, and sidesteps incoming fire

bot.name = "Ace"
bot.color = colors.fromRGB(255, 96, 255)  -- Pink
bot.shape = "wing"

local target_ang = nil
local sweep = 0
local strafe = 1
local dodge = 0
local dodge_ang = 0

-- Where to shoot so that a shell and a target that keeps its course arrive together
local function lead(dist, ang, heading, speed)
    local a, h = math.rad(ang), math.rad(heading)
    local px, py = math.sin(a) * dist, -math.cos(a) * dist
    local vx, vy = math.sin(h) * speed, -math.cos(h) * speed
    local qa = vx * vx + vy * vy - bot.CANNON_SPEED * bot.CANNON_SPEED
    local qb = px * vx + py * vy
    local t = (-qb - math.sqrt(qb * qb - qa * dist * dist)) / qa
    return math.deg(math.atan(px + vx * t, -(py + vy * t))) % 360
end

function bot.tick()
    -- A shot on its way in: drive across its path. Looking for one costs energy, as a scan does,
    -- and looking every tick as well as scanning would use it faster than it comes back.
    if dodge == 0 and bot.getTick() % 3 == 0 then
        local shot_dist, _, shot_heading = bot.detectShot()
        if shot_dist and shot_dist < 90 then
            dodge = 8
            dodge_ang = shot_heading + 90 * strafe
        end
    end

    local dist, ang, heading, speed
    if target_ang then
        dist, ang, heading, speed = bot.scanAt(target_ang, 40)
    else
        -- Search: a quarter of the circle each tick
        sweep = (sweep + 90) % 360
        dist, ang, heading, speed = bot.scanAt(sweep, 90)
    end

    if dist then
        target_ang = ang
        if bot.canFire() then
            bot.fireAt(lead(dist, ang, heading, speed))
        end
        -- Circle the target, closing in from far away and backing off when close
        local offset = (dist > 110 and 50) or (dist < 60 and 125) or 90
        bot.turnTo(ang + offset * strafe)
        bot.drive(4)
    else
        target_ang = nil
        bot.drive(3)
    end

    if dodge > 0 then
        dodge = dodge - 1
        bot.turnTo(dodge_ang)
        bot.drive(bot.MAX_SPEED)
    end

    -- Turn back toward the middle before reaching a wall
    if bot.wallDistance() < bot.RADIUS + 20 then
        local w, h = bot.getArenaSize()
        bot.turnTo(bot.angleTo(w / 2, h / 2))
        strafe = -strafe
        dodge = 0
    end
end

function bot.onWall()
    strafe = -strafe
end

function bot.onHit(direction, damage)
    -- Whoever hit us is that way
    if not target_ang then target_ang = direction end
    strafe = -strafe
end

function bot.onScanned(direction)
    -- Being scanned gives the scanner away
    if not target_ang then target_ang = direction end
end

function bot.onCollision(direction)
    if bot.canMissile() then
        bot.missileAt(direction)
    end
end
