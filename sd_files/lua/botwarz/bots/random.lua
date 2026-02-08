-- Random Bot
-- Moves randomly, fires when it sees something

bot.name = "Random"
bot.color = colors.fromRGB(255, 255, 0)  -- Yellow

local change_timer = 0
local turn_amount = 0

function bot.init()
    bot.drive(2)
    turn_amount = math.random(-5, 5)
end

function bot.tick()
    -- Change direction periodically
    change_timer = change_timer + 1
    if change_timer > 30 + math.random(0, 30) then
        change_timer = 0
        turn_amount = math.random(-8, 8)
        bot.drive(math.random(1, 4))
    end

    bot.turn(turn_amount)

    -- Scan and fire if we see something
    local dist, ang = bot.scan(60)
    if dist and bot.canFire() then
        bot.fire()
    end
end

function bot.onWall()
    -- Turn randomly away from wall
    bot.turn(90 + math.random(-45, 45))
    change_timer = 0
end

function bot.onHit(direction, damage)
    -- Randomly decide to fight or flee
    if math.random() > 0.5 then
        -- Fight
        bot.turnTo(direction)
        if bot.canFire() then
            bot.fire()
        end
    else
        -- Flee
        bot.turnTo(direction + 180)
        bot.drive(5)
    end
end
