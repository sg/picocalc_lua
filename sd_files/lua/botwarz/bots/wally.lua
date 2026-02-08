-- Wally
-- Hugs the walls while scanning/shoting

bot.name = "Wally"
bot.color = colors.fromRGB(128, 128, 255) --Light blue

local scan_angle = 90
local dest_wall_dir = 0
local at_wall = false

function bot.init()
    -- Head toward top wall
    bot.turnTo(top_wall_dir)
    bot.drive(4)
end

function bot.tick()
    while true do
        -- Keep moving toward wall
        bot.drive(4)

        -- Check if we're at the wall
        local x, y = bot.getPosition()
        local w, h = bot.getArenaSize()

        local near_x_edge = (x < 40) or (x > w - 40)
        local near_y_edge = (y < 40) or (y > h - 40)

        if near_x_edge or near_y_edge then
            bot.stop()
            -- Face toward center
            --bot.turnTo(bot.angleTo(w/2, h/2))
            if dest_wall_dir >= 270 then
              dest_wall_dir = 0
            else
              dest_wall_dir = dest_wall_dir + 90
            end 
            if scan_angle >= 270 then
              scan_angle = 0
            else
              scan_angle = scan_angle + 90
            end
            bot.turnTo(dest_wall_dir)
        else
            local dist, ang = bot.scanAt(scan_angle, 45)
            if dist and bot.canFire() then
                bot.fireAt(ang)
            end
        end
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
    if bot.canFire() then
        bot.fireAt(direction)
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
