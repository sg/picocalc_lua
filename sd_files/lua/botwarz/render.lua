-- BotWarz Rendering Module
-- Drawing primitives and rendering functions

local M = {}

-- Module-local references (set via init)
local config = nil
local state = nil  -- shared game state

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function M.deg_to_rad(deg)
    return deg * math.pi / 180
end

function M.rad_to_deg(rad)
    return rad * 180 / math.pi
end

-- Normalize angle to 0-359
function M.normalize_angle(ang)
    while ang < 0 do ang = ang + 360 end
    while ang >= 360 do ang = ang - 360 end
    return ang
end

-- Clamp value between min and max
function M.clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

-- Get memory usage in KB
function M.get_memory_kb()
    return math.floor(collectgarbage("count"))
end

-- Distance between two points
function M.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Angle from point 1 to point 2 (in degrees, 0 = up)
function M.angle_to(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local rad = math.atan(dx, -dy)
    return M.normalize_angle(M.rad_to_deg(rad))
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Pre-allocated polygon table for draw_rotated (avoids allocation during gameplay)
local draw_poly = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

function M.init(cfg, game_state)
    config = cfg
    state = game_state
end

-- =============================================================================
-- DRAWING PRIMITIVES
-- =============================================================================

-- Draw a rotated polygon (reuses pre-allocated draw_poly table)
function M.draw_rotated(shape, x, y, ang, scale, color)
    local rad = M.deg_to_rad(ang)
    local sin_a = math.sin(rad) * scale
    local cos_a = math.cos(rad) * scale

    for i = 1, #shape do
        local px = shape[i][1]
        local py = shape[i][2]
        local rx = px * cos_a - py * sin_a
        local ry = px * sin_a + py * cos_a
        local idx = (i - 1) * 2 + 1
        draw_poly[idx] = math.floor(x + rx + 0.5)
        draw_poly[idx + 1] = math.floor(y + ry + 0.5)
    end

    draw.polygon(draw_poly, color)
end

-- Draw a line (for turret barrel)
function M.draw_line_rotated(shape, x, y, ang, scale, color)
    local rad = M.deg_to_rad(ang)
    local sin_a = math.sin(rad) * scale
    local cos_a = math.cos(rad) * scale

    local x1 = math.floor(x + shape[1][1] * cos_a - shape[1][2] * sin_a + 0.5)
    local y1 = math.floor(y + shape[1][1] * sin_a + shape[1][2] * cos_a + 0.5)
    local x2 = math.floor(x + shape[2][1] * cos_a - shape[2][2] * sin_a + 0.5)
    local y2 = math.floor(y + shape[2][1] * sin_a + shape[2][2] * cos_a + 0.5)

    draw.line(x1, y1, x2, y2, color)
end

-- =============================================================================
-- ARENA RENDERING
-- =============================================================================

function M.draw_arena()
    draw.rectFill(config.ARENA_X, config.ARENA_Y, config.ARENA_WIDTH, config.ARENA_HEIGHT, config.COLOR_ARENA_BG)
    draw.rect(config.ARENA_X - 1, config.ARENA_Y - 1, config.ARENA_WIDTH + 2, config.ARENA_HEIGHT + 2, config.COLOR_ARENA_BORDER)
end

-- =============================================================================
-- BOT RENDERING
-- =============================================================================

function M.draw_bot(bot)
    local screen_x = config.ARENA_X + bot.x
    local screen_y = config.ARENA_Y + bot.y
    M.draw_rotated(config.POLY_BODY, screen_x, screen_y, bot.heading, 1, bot.color)
    M.draw_line_rotated(config.POLY_TURRET, screen_x, screen_y, bot.heading, 1, bot.color)
end

function M.erase_bot(bot, x, y, heading)
    local screen_x = config.ARENA_X + x
    local screen_y = config.ARENA_Y + y
    M.draw_rotated(config.POLY_BODY, screen_x, screen_y, heading, 1, config.COLOR_ARENA_BG)
    M.draw_line_rotated(config.POLY_TURRET, screen_x, screen_y, heading, 1, config.COLOR_ARENA_BG)
end

-- =============================================================================
-- PROJECTILE RENDERING
-- =============================================================================

function M.draw_projectile(p)
    local screen_x = config.ARENA_X + math.floor(p.x + 0.5)
    local screen_y = config.ARENA_Y + math.floor(p.y + 0.5)
    if p.ptype == config.PROJ_TYPE_CANNON then
        draw.rectFill(screen_x - 1, screen_y - 1, 2, 2, p.color)
    else
        local angle = math.atan(p.vx, -p.vy)
        local dx = math.sin(angle) * 4
        local dy = -math.cos(angle) * 4
        draw.line(
            math.floor(screen_x - dx + 0.5), math.floor(screen_y - dy + 0.5),
            math.floor(screen_x + dx + 0.5), math.floor(screen_y + dy + 0.5),
            p.color
        )
    end
end

function M.erase_projectile(p, x, y)
    local screen_x = config.ARENA_X + math.floor(x + 0.5)
    local screen_y = config.ARENA_Y + math.floor(y + 0.5)
    if p.ptype == config.PROJ_TYPE_CANNON then
        draw.rectFill(screen_x - 1, screen_y - 1, 2, 2, config.COLOR_ARENA_BG)
    else
        local angle = math.atan(p.vx, -p.vy)
        local dx = math.sin(angle) * 4
        local dy = -math.cos(angle) * 4
        draw.line(
            math.floor(screen_x - dx + 0.5), math.floor(screen_y - dy + 0.5),
            math.floor(screen_x + dx + 0.5), math.floor(screen_y + dy + 0.5),
            config.COLOR_ARENA_BG
        )
    end
end

-- =============================================================================
-- STATUS BARS
-- =============================================================================

function M.draw_status_bar()
    draw.rectFill(0, 0, config.SCREEN_WIDTH, config.ARENA_MARGIN_TOP, config.COLOR_BG)

    local b1 = state.bots[1]
    local name1 = b1.script and b1.script.name or b1.name
    draw.text(5, 2, string.sub(name1, 1, 8), b1.color, config.COLOR_BG)
    draw.rectFill(50, 4, 52, 8, config.COLOR_ARENA_BORDER)
    local health_width = math.floor(b1.health / 2)
    if health_width > 0 then
        draw.rectFill(51, 5, health_width, 6, b1.color)
    end
    draw.text(105, 2, tostring(b1.health), config.COLOR_TEXT, config.COLOR_BG)

    local b2 = state.bots[2]
    local name2 = b2.script and b2.script.name or b2.name
    draw.text(165, 2, string.sub(name2, 1, 8), b2.color, config.COLOR_BG)
    draw.rectFill(210, 4, 52, 8, config.COLOR_ARENA_BORDER)
    local health_width2 = math.floor(b2.health / 2)
    if health_width2 > 0 then
        draw.rectFill(211, 5, health_width2, 6, b2.color)
    end
    draw.text(265, 2, tostring(b2.health), config.COLOR_TEXT, config.COLOR_BG)
end

function M.draw_info_bar()
    draw.rectFill(0, config.SCREEN_HEIGHT - config.ARENA_MARGIN_BOTTOM, config.SCREEN_WIDTH, config.ARENA_MARGIN_BOTTOM, config.COLOR_BG)
    draw.text(5, config.SCREEN_HEIGHT - 16, "Tick: " .. state.game_tick .. "  ESC: Quit", config.COLOR_TEXT, config.COLOR_BG)
    draw.text(200, config.SCREEN_HEIGHT - 16, "Mem:" .. M.get_memory_kb() .. "KB", config.COLOR_DIM_TEXT, config.COLOR_BG)
end

return M
