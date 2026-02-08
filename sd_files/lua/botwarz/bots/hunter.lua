-- Hunter Bot
-- Actively seeks out and pursues enemies

bot.name = "Hunter"
bot.color = colors.fromRGB(255, 128, 0)  -- Orange

local target_dist = nil
local target_ang = nil
local scan_offset = 0
local hunting = false
local evade_timer = 0

function bot.init()
    bot.drive(2)
end

function bot.tick()
    -- Handle evasion mode
    if evade_timer > 0 then
        evade_timer = evade_timer - 1
        bot.drive(4)
        return
    end

    if not hunting then
        -- Search mode: sweep scan across wide arc
        scan_offset = scan_offset + 30
        if scan_offset > 180 then
            scan_offset = -180
        end

        local heading = bot.getHeading()
        local dist, ang = bot.scanAt(heading + scan_offset, 60)

        if dist then
            target_dist = dist
            target_ang = ang
            hunting = true
        else
            -- Wander while searching
            bot.drive(2)
            bot.turn(2)
        end
    else
        -- Hunt mode: pursue target
        bot.turnTo(target_ang)

        -- Adjust speed based on distance
        if target_dist > 80 then
            bot.drive(4)
        else
            bot.drive(2)
        end

        -- Update target with narrower scan
        local dist, ang = bot.scan(30)
        if dist then
            target_dist = dist
            target_ang = ang

            -- Fire when close enough
            if dist < 120 and bot.canFire() then
                bot.fireAt(ang)
            end
        else
            -- Lost target
            hunting = false
        end
    end
end

function bot.onWall()
    -- Turn away from wall
    bot.turn(90)
    bot.drive(3)
    hunting = false  -- Reset hunting when hitting wall
end

function bot.onHit(direction, damage)
    -- Counter-attack!
    if bot.canFire() then
        bot.fireAt(direction)
    end
    bot.turnTo(direction)
    -- Evasive maneuver
    evade_timer = 20
    bot.turn(45)
end

function bot.onCollision()
    -- Back away and turn
    bot.drive(0)
    bot.turn(180)
end
