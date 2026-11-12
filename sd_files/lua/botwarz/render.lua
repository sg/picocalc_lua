-- BotWarz drawing: shared geometry, the frame's display list, the bars and the effects

local M = {}

local config = nil
local state = nil

local sin, cos, floor, ceil, sqrt, atan, random = math.sin, math.cos, math.floor, math.ceil, math.sqrt, math.atan, math.random
local RAD = math.pi / 180

local AX, AY, AW, AH = 0, 0, 0, 0
local buffered = false

function M.normalize_angle(a)
    a = a % 360
    -- a tiny negative angle rounds up to 360 itself
    if a >= 360 then a = 0 end
    return a
end
local normalize_angle = M.normalize_angle

-- the shorter way round from one angle to another, -180 to 180
function M.angle_diff(from, to)
    local d = (to - from) % 360
    if d > 180 then d = d - 360 end
    return d
end

function M.clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

function M.get_memory_kb()
    return floor(collectgarbage("count"))
end

function M.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return sqrt(dx * dx + dy * dy)
end

-- 0 is up and angles grow clockwise, as headings do
function M.angle_to(x1, y1, x2, y2)
    return normalize_angle(atan(x2 - x1, y1 - y2) / RAD)
end

-- Everything in the arena is drawn through a display list, so that with a framebuffer the frame is
-- drawn whole and shown at once, and without one the last frame's list is what gets erased.
local function new_frame()
    return {lines = {}, nl = 0, dots = {}, nd = 0, polys = {}, np = 0}
end
local cur, prev = new_frame(), new_frame()
local texts, nt = {}, 0

-- Sparks and wreckage are flat lists of numbers, a fixed count for each one, which take a fifth of
-- the memory that a table for each would.
local DOT, PIECE = 6, 8    -- x, y, vx, vy, life, color; x1, y1, x2, y2, vx, vy, life, color
local dots, wreckage, rings = {}, {}, {}
local shown_status = {}
local shown_info, shown_info_color

function M.init(cfg, game_state)
    config = cfg
    state = game_state
    AX, AY, AW, AH = config.ARENA_X, config.ARENA_Y, config.ARENA_WIDTH, config.ARENA_HEIGHT
    for i = 1, config.MAX_DOTS * DOT do dots[i] = 0 end
    for i = 1, config.MAX_WRECKAGE * PIECE do wreckage[i] = 0 end
    for i = 1, config.MAX_RINGS do
        rings[i] = {x = 0, y = 0, r = 0, max = 0, c = 0}
    end
end

local function clip_axis(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return nil end
    else
        local r = q / p
        if p < 0 then
            if r > t1 then return nil end
            if r > t0 then t0 = r end
        else
            if r < t0 then return nil end
            if r < t1 then t1 = r end
        end
    end
    return t0, t1
end

-- a line in arena coordinates, cut off at the walls so that nothing is drawn on the border or the bars
function M.line(x1, y1, x2, y2, c)
    local xmax, ymax = AW - 1, AH - 1
    if x1 < 0 or x1 > xmax or x2 < 0 or x2 > xmax or y1 < 0 or y1 > ymax or y2 < 0 or y2 > ymax then
        local dx, dy = x2 - x1, y2 - y1
        local t0, t1 = clip_axis(-dx, x1, 0, 1)
        if not t0 then return end
        t0, t1 = clip_axis(dx, xmax - x1, t0, t1)
        if not t0 then return end
        t0, t1 = clip_axis(-dy, y1, t0, t1)
        if not t0 then return end
        t0, t1 = clip_axis(dy, ymax - y1, t0, t1)
        if not t0 then return end
        x2, y2 = x1 + t1 * dx, y1 + t1 * dy
        x1, y1 = x1 + t0 * dx, y1 + t0 * dy
    end
    local l, n = cur.lines, cur.nl
    l[n + 1], l[n + 2], l[n + 3], l[n + 4], l[n + 5] =
        AX + floor(x1 + 0.5), AY + floor(y1 + 0.5), AX + floor(x2 + 0.5), AY + floor(y2 + 0.5), c
    cur.nl = n + 5
end
local line = M.line

-- a square of whole pixels in arena coordinates, left out if any of it is outside
function M.dot(x, y, size, c)
    if x < 0 or y < 0 or x > AW - size or y > AH - size then return end
    local d, n = cur.dots, cur.nd
    d[n + 1], d[n + 2], d[n + 3], d[n + 4] = AX + x, AY + y, size, c
    cur.nd = n + 4
end

function M.text(x, y, text, c)
    texts[nt + 1], texts[nt + 2], texts[nt + 3], texts[nt + 4] = x, y, text, c
    nt = nt + 4
end

local function paint(frame, erase)
    local l = frame.lines
    for i = 1, frame.nl, 5 do
        draw.line(l[i], l[i + 1], l[i + 2], l[i + 3], erase or l[i + 4])
    end
    local d = frame.dots
    for i = 1, frame.nd, 4 do
        if d[i + 2] == 1 then
            draw.point(d[i], d[i + 1], erase or d[i + 3])
        else
            draw.rectFill(d[i], d[i + 1], d[i + 2], d[i + 2], erase or d[i + 3])
        end
    end
    local p = frame.polys
    for i = 1, frame.np, 2 do
        draw.polygon(p[i], erase or p[i + 1])
    end
end

function M.begin()
    cur.nl, cur.nd, cur.np = 0, 0, 0
    nt = 0
end

function M.finish()
    if buffered then
        draw.rectFill(AX, AY, AW, AH, config.COLOR_ARENA_BG)
    else
        paint(prev, config.COLOR_ARENA_BG)
    end
    paint(cur)
    for i = 1, nt, 4 do
        draw.text(texts[i], texts[i + 1], texts[i + 2], texts[i + 3], config.COLOR_ARENA_BG, draw.align_center)
    end
    if buffered then
        draw.blitBuffer()
    else
        cur, prev = prev, cur
    end
end

-- QSPI PSRAM is mapped into memory, so a framebuffer there is quick and takes no heap; one in RAM is
-- risked only with far more memory free than it needs.
local function enable_buffer()
    if psram and psram.stats and psram.stats().qspi and draw.enableBuffer(1) then return true end
    collectgarbage()
    return sys.freeMemory() >= 256 * 1024 and draw.enableBuffer(2)
end

function M.start_match()
    buffered = config.USE_FRAMEBUFFER and enable_buffer() and true or false
    cur.nl, cur.nd, cur.np = 0, 0, 0
    prev.nl, prev.nd, prev.np = 0, 0, 0
    for i = 1, #dots do dots[i] = 0 end
    for i = 1, #wreckage do wreckage[i] = 0 end
    for i = 1, #rings do rings[i].r = 0 end
    shown_status[1], shown_status[2], shown_info = nil, nil, nil
    draw.clear()
    draw.rectFill(AX, AY, AW, AH, config.COLOR_ARENA_BG)
    draw.rect(AX - 1, AY - 1, AW + 2, AH + 2, config.COLOR_ARENA_BORDER)
end

function M.stop_match()
    if buffered then
        draw.enableBuffer(0)
        buffered = false
    end
end

-- Both bars are drawn only when what they show has changed; redrawn every tick they were most of a frame's drawing.
function M.draw_status_bar()
    for i = 1, 2 do
        local b = state.bots[i]
        local key = b.health * 2 + (b.script_error and 1 or 0)
        if shown_status[i] ~= key then
            shown_status[i] = key
            local x = (i - 1) * 160
            draw.rectFill(x, 0, 160, config.ARENA_MARGIN_TOP - 1, config.COLOR_BG)
            draw.text(x + 5, 2, b.label, b.color, config.COLOR_BG)
            draw.rectFill(x + 50, 4, 52, 8, config.COLOR_ARENA_BORDER)
            local width = floor(b.health * 50 / config.BOT_MAX_HEALTH)
            if width > 0 then
                draw.rectFill(x + 51, 5, width, 6, b.color)
            end
            draw.text(x + 105, 2, tostring(b.health), config.COLOR_TEXT, config.COLOR_BG)
            if b.script_error then
                draw.text(x + 130, 2, "ERR", colors.red, config.COLOR_BG)
            end
        end
    end
end

function M.draw_info_bar(text, color)
    if text == shown_info and color == shown_info_color then return end
    shown_info, shown_info_color = text, color
    local y = config.SCREEN_HEIGHT - config.ARENA_MARGIN_BOTTOM + 1
    draw.rectFill(0, y, config.SCREEN_WIDTH, config.ARENA_MARGIN_BOTTOM - 1, config.COLOR_BG)
    draw.text(5, y + 5, text, color, config.COLOR_BG)
end

local function ray(x, y, ang, r0, r1, c)
    local dx, dy = sin(ang * RAD), -cos(ang * RAD)
    line(x + dx * r0, y + dy * r0, x + dx * r1, y + dy * r1, c)
end

local function arc(x, y, r, a1, a2, c)
    local n = ceil((a2 - a1) / (r < 40 and 30 or 15))
    if n < 1 then n = 1 end
    local a, step = a1 * RAD, (a2 - a1) / n * RAD
    local x1, y1 = x + sin(a) * r, y - cos(a) * r
    for _ = 1, n do
        a = a + step
        local x2, y2 = x + sin(a) * r, y - cos(a) * r
        line(x1, y1, x2, y2, c)
        x1, y1 = x2, y2
    end
end

local function brackets(x, y, c)
    local r, k = config.BOT_RADIUS + 3, 5
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            local cx, cy = x + sx * r, y + sy * r
            line(cx, cy, cx - sx * k, cy, c)
            line(cx, cy, cx, cy - sy * k, c)
        end
    end
end

function M.draw_scan(b, mode)
    if mode == "off" then return end
    local scanned = b.scan_tick == state.game_tick
    if mode == "pulse" then
        if b.pulse_r > 0 then
            local half = b.pulse_arc / 2
            arc(b.pulse_x, b.pulse_y, b.pulse_r, b.pulse_ang - half, b.pulse_ang + half, b.dim)
        end
    elseif scanned then
        local half = b.scan_arc / 2
        local near, far = config.BOT_RADIUS + 2, config.BOT_SCAN_RANGE
        if mode == "wedge" then
            ray(b.x, b.y, b.scan_ang - half, near, far, b.dim)
            ray(b.x, b.y, b.scan_ang + half, near, far, b.dim)
            arc(b.x, b.y, far, b.scan_ang - half, b.scan_ang + half, b.dim)
        else
            ray(b.x, b.y, b.scan_ang + half * b.sweep, near, far, b.dim)
        end
    end
    local found = b.scan_hit
    if scanned and found and config.SCAN_LOCK then
        brackets(found.x, found.y, b.color)
    end
end

function M.draw_bot(b)
    local s, c = sin(b.heading * RAD), cos(b.heading * RAD)
    -- the list of the frame before still holds the other table, which is erased from when there is no framebuffer
    b.pts, b.pts_old = b.pts_old, b.pts
    local pts, shape = b.pts, b.shape
    local x, y = AX + b.x + 0.5, AY + b.y + 0.5
    for i = 1, #shape, 2 do
        local px, py = shape[i], shape[i + 1]
        pts[i] = floor(x + px * c - py * s)
        pts[i + 1] = floor(y + px * s + py * c)
    end
    local p, n = cur.polys, cur.np
    p[n + 1], p[n + 2] = pts, b.flash > 0 and colors.white or b.color
    cur.np = n + 2
    ray(b.x, b.y, b.aim or b.heading, 3, config.BARREL_LENGTH, b.color)
end

function M.draw_projectile(p)
    if p.ptype == config.PROJ_TYPE_CANNON then
        local x, y = floor(p.x + 0.5) - 1, floor(p.y + 0.5) - 1
        if x < 0 then x = 0 elseif x > AW - 2 then x = AW - 2 end
        if y < 0 then y = 0 elseif y > AH - 2 then y = AH - 2 end
        M.dot(x, y, 2, p.color)
    else
        line(p.x - p.ux * 4, p.y - p.uy * 4, p.x + p.ux * 4, p.y + p.uy * 4, p.color)
    end
end

function M.draw_fx()
    for i = 1, #rings do
        local r = rings[i]
        if r.r > 0 then arc(r.x, r.y, r.r, 0, 360, r.c) end
    end
    local w = wreckage
    for i = 1, #w, PIECE do
        if w[i + 6] > 0 then line(w[i], w[i + 1], w[i + 2], w[i + 3], w[i + 7]) end
    end
    local d = dots
    for i = 1, #d, DOT do
        if d[i + 4] > 0 then M.dot(floor(d[i]), floor(d[i + 1]), 1, d[i + 5]) end
    end
end

-- Sparks, wreckage and rings are made once and reused, so that an explosion costs the collector nothing.
function M.burst(x, y, n, power, c)
    local d = dots
    for i = 1, #d, DOT do
        if d[i + 4] == 0 then
            local a, v = random() * 6.2832, (0.6 + random() * 1.4) * power
            d[i], d[i + 1], d[i + 2], d[i + 3] = x, y, sin(a) * v, cos(a) * v
            d[i + 4], d[i + 5] = 8 + random(0, 6), c
            n = n - 1
            if n <= 0 then return end
        end
    end
end

function M.ring(x, y, max, c)
    for i = 1, #rings do
        local r = rings[i]
        if r.r == 0 then
            r.x, r.y, r.r, r.max, r.c = x, y, 2, max, c
            return
        end
    end
end

-- each piece drifts off the way its middle lies from the bot's centre
local function add_piece(b, x1, y1, x2, y2)
    local w = wreckage
    for i = 1, #w, PIECE do
        if w[i + 6] == 0 then
            local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            local m = sqrt(mx * mx + my * my)
            local v = (0.4 + random() * 0.5) / (m > 0.5 and m or 0.5)
            w[i], w[i + 1], w[i + 2], w[i + 3] = b.x + x1, b.y + y1, b.x + x2, b.y + y2
            w[i + 4], w[i + 5] = mx * v, my * v
            w[i + 6], w[i + 7] = 14 + random(0, config.FINALE_TICKS - 16), b.color
            return
        end
    end
end

-- the bot's outline comes apart into its edges, as the ship does in Asteroids, and the gun goes with them
function M.wreck(b)
    local s, c = sin(b.heading * RAD), cos(b.heading * RAD)
    local shape = b.shape
    local px, py = shape[1] * c - shape[2] * s, shape[1] * s + shape[2] * c
    for i = 3, #shape, 2 do
        local qx, qy = shape[i] * c - shape[i + 1] * s, shape[i] * s + shape[i + 1] * c
        add_piece(b, px, py, qx, qy)
        px, py = qx, qy
    end
    local a = (b.aim or b.heading) * RAD
    local dx, dy = sin(a), -cos(a)
    add_piece(b, dx * 3, dy * 3, dx * config.BARREL_LENGTH, dy * config.BARREL_LENGTH)
end

function M.update_fx()
    local d = dots
    for i = 1, #d, DOT do
        if d[i + 4] > 0 then
            local x, y = d[i] + d[i + 2], d[i + 1] + d[i + 3]
            d[i], d[i + 1] = x, y
            d[i + 4] = (x < 0 or x >= AW or y < 0 or y >= AH) and 0 or d[i + 4] - 1
        end
    end
    local w = wreckage
    for i = 1, #w, PIECE do
        if w[i + 6] > 0 then
            local vx, vy = w[i + 4], w[i + 5]
            w[i], w[i + 1], w[i + 2], w[i + 3] = w[i] + vx, w[i + 1] + vy, w[i + 2] + vx, w[i + 3] + vy
            w[i + 6] = w[i + 6] - 1
        end
    end
    for i = 1, #rings do
        local r = rings[i]
        if r.r > 0 then
            r.r = r.r + 6
            if r.r > r.max then r.r = 0 end
        end
    end
    local tick = state.game_tick
    for i = 1, #state.bots do
        local b = state.bots[i]
        if b.flash > 0 then b.flash = b.flash - 1 end
        if b.pulse_r > 0 then
            b.pulse_r = b.pulse_r + config.SCAN_PULSE_SPEED
            if b.pulse_r > config.BOT_SCAN_RANGE then b.pulse_r = 0 end
        end
        -- one pulse at a time: a bot that scans every tick sends the next as the last one dies out
        if b.pulse_r == 0 and b.scan_tick == tick then
            b.pulse_r = config.BOT_RADIUS + 2
            b.pulse_x, b.pulse_y, b.pulse_ang, b.pulse_arc = b.x, b.y, b.scan_ang, b.scan_arc
        end
        b.sweep = b.sweep + b.sweep_dir * 0.4
        if b.sweep >= 1 then
            b.sweep, b.sweep_dir = 1, -1
        elseif b.sweep <= -1 then
            b.sweep, b.sweep_dir = -1, 1
        end
    end
end

return M
