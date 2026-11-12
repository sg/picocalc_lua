-- Spinner Bot
-- Simple strategy: spin in place and fire at anything detected

bot.name = "Spinner"
bot.color = colors.fromRGB(0, 255, 128)  -- Cyan-green
bot.shape = "saucer"

local spin_dir = 1
local fire_cooldown = 0

function bot.init()
    -- Start moving slowly
    bot.drive(1)
end

function bot.tick()
    -- Spin continuously
    bot.turn(8 * spin_dir)

    -- Decrease fire cooldown
    if fire_cooldown > 0 then
        fire_cooldown = fire_cooldown - 1
    end

    -- Scan forward with a wide arc
    local dist, ang = bot.scan(45)

    -- Fire if enemy detected and cooldown ready
    if dist and fire_cooldown == 0 and bot.canFire() then
        bot.fireAt(ang)
        fire_cooldown = 15
    end

    -- Keep moving slowly to avoid being a sitting target
    if bot.getSpeed() < 1 then
        bot.drive(1)
    end
end

function bot.onWall()
    -- Reverse spin direction and back up
    spin_dir = -spin_dir
    bot.turn(90 * spin_dir)
    bot.drive(2)
end

function bot.onHit(direction, damage)
    -- Turn toward attacker and fire back
    bot.turnTo(direction)
    if bot.canFire() then
        bot.fire()
    end
    -- Speed up to evade
    bot.drive(3)
end
