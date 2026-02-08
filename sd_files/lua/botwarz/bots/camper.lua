-- Camper Bot
-- Finds a corner and defends it

bot.name = "Camper"
bot.color = colors.fromRGB(128, 128, 255)  -- Light blue

local settled = false
local scan_angle = 0
local corner_target = 45  -- Head toward top-right corner initially

function bot.init()
    -- Head toward a corner
    bot.turnTo(corner_target)
    bot.drive(4)
end

function bot.tick()
    if not settled then
        -- Keep moving toward corner
        bot.turnTo(corner_target)
        bot.drive(4)

        -- Check if we're in a corner
        local x, y = bot.getPosition()
        local w, h = bot.getArenaSize()

        local near_x_edge = (x < 40) or (x > w - 40)
        local near_y_edge = (y < 40) or (y > h - 40)

        if near_x_edge and near_y_edge then
            settled = true
            bot.stop()
            -- Face toward center
            --bot.turnTo(bot.angleTo(w/2, h/2))
            bot.turnTo(225)
        end
    else
        -- Settled: sweep scan and shoot
        scan_angle = scan_angle + 8
        if scan_angle > 270 then
            scan_angle = 175
        end

        local dist, ang = bot.scanAt(scan_angle, 45)
        if dist and bot.canFire() then
            bot.fireAt(ang)
        end

        -- Stay still
        bot.stop()
    end
end

function bot.onWall()
    if not settled then
        -- Turn toward corner and keep going
        corner_target = corner_target + 45
        bot.turnTo(corner_target)
    end
end

function bot.onHit(direction, damage)
    -- Return fire immediately
    bot.turnTo(direction)
    if bot.canFire() then
        bot.fire()
    end
    -- Use missile if we have one
    if bot.canMissile() then
        bot.missileAt(direction)
    end
end

function bot.onCollision()
    -- If something comes to us, fight back
    local dist, ang = bot.scan(90)
    if dist and bot.canFire() then
        bot.fireAt(ang)
    end
end
