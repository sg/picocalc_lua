--[[

  gravity.lua - 2D N-body gravity simulation for PicoCalc

  Reads initial state from lua/gravity.conf.
  Bodies are drawn as filled circles with configurable diameter.

  Controls:
    +/Up     Speed up (increase dt)
    -/Down   Slow down (decrease dt)
    Space    Pause / unpause
    t        Toggle trails
    r        Reset to initial config
    q/Esc    Quit

]]

local WIDTH = 320
local HEIGHT = 320
local DEFAULT_DIAM = 5    -- default body diameter in pixels
local FRAME_MS = 0.02     -- target ~50 FPS
local CONF_PATH = "lua/gravity.conf"

local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt
local rad = math.rad
local floor = math.floor
local abs = math.abs

local PRESSED = keys.states.pressed
local IDLE = keys.states.idle

local bg = colors.black
local hud_fg = colors.white
local hud_bg = colors.black

----------------------------------------------------------------------
-- Load config
----------------------------------------------------------------------
local function load_config()
  local ok, conf = pcall(dofile, CONF_PATH)
  if not ok or type(conf) ~= "table" then
    return nil, "Failed to load " .. CONF_PATH
  end
  if not conf.bodies or #conf.bodies == 0 then
    return nil, "No bodies defined in config"
  end
  conf.dt = conf.dt or 0.5
  conf.G = conf.G or 80.0
  conf.soften = conf.soften or 4.0
  conf.trail = conf.trail or false
  if conf.merge == nil then conf.merge = true end
  return conf
end

----------------------------------------------------------------------
-- Build body table from config
----------------------------------------------------------------------
local function init_bodies(conf)
  local bodies = {}
  for i, def in ipairs(conf.bodies) do
    local angle = rad(def.dir or 0)
    -- dir: 0=up(-y), 90=right(+x), 180=down(+y), 270=left(-x)
    local vx = (def.speed or 0) * sin(angle)
    local vy = -(def.speed or 0) * cos(angle)
    local c = def.color or {255, 255, 255}
    local diam = def.diameter or DEFAULT_DIAM
    bodies[#bodies + 1] = {
      name = def.name or ("B" .. i),
      mass = def.mass or 1,
      x = def.x or WIDTH / 2,
      y = def.y or HEIGHT / 2,
      vx = vx,
      vy = vy,
      color = colors.fromRGB(c[1], c[2], c[3]),
      fixed = def.fixed or false,
      alive = true,
      escaped = false,
      diameter = diam,
      radius = floor(diam / 2),
    }
  end
  return bodies
end

----------------------------------------------------------------------
-- Physics: compute gravitational accelerations and integrate
----------------------------------------------------------------------
local function physics_step(bodies, G, dt, soften)
  local n = #bodies

  -- accumulate acceleration
  for i = 1, n do
    local a = bodies[i]
    if a.alive and not a.fixed and not a.escaped then
      local ax, ay = 0, 0
      for j = 1, n do
        if i ~= j then
          local b = bodies[j]
          if b.alive then
            local dx = b.x - a.x
            local dy = b.y - a.y
            local dist_sq = dx * dx + dy * dy + soften * soften
            local dist = sqrt(dist_sq)
            local force = G * b.mass / dist_sq
            ax = ax + force * dx / dist
            ay = ay + force * dy / dist
          end
        end
      end
      a.vx = a.vx + ax * dt
      a.vy = a.vy + ay * dt
    end
  end

  -- integrate positions
  for i = 1, n do
    local a = bodies[i]
    if a.alive and not a.fixed and not a.escaped then
      a.x = a.x + a.vx * dt
      a.y = a.y + a.vy * dt
    end
  end
end

----------------------------------------------------------------------
-- Check escape condition: body has exceeded max distance or its
-- speed exceeds escape velocity from all other bodies combined.
-- Escape velocity: v_esc = sqrt(2 * G * M_total / r)
----------------------------------------------------------------------
local MAX_DIST = 20000

local function check_escape(bodies, G)
  local n = #bodies
  for i = 1, n do
    local a = bodies[i]
    if a.alive and not a.fixed and not a.escaped then
      -- distance from center of mass of all other bodies
      local total_mass = 0
      local cmx, cmy = 0, 0
      for j = 1, n do
        local b = bodies[j]
        if j ~= i and b.alive then
          total_mass = total_mass + b.mass
          cmx = cmx + b.x * b.mass
          cmy = cmy + b.y * b.mass
        end
      end
      if total_mass <= 0 then goto continue end
      cmx = cmx / total_mass
      cmy = cmy / total_mass

      local dx = a.x - cmx
      local dy = a.y - cmy
      local dist = sqrt(dx * dx + dy * dy)

      -- hard cap
      if dist >= MAX_DIST then
        a.escaped = true
        goto continue
      end

      -- only check escape velocity if off screen
      if dist > WIDTH then
        local speed_sq = a.vx * a.vx + a.vy * a.vy
        local v_esc_sq = 2 * G * total_mass / dist
        -- also check body is moving away from center of mass
        local radial_v = (dx * a.vx + dy * a.vy) / dist  -- dot product
        if speed_sq > v_esc_sq and radial_v > 0 then
          a.escaped = true
        end
      end
      ::continue::
    end
  end
end

----------------------------------------------------------------------
-- Check if a body is within the visible screen area
----------------------------------------------------------------------
local function on_screen(b)
  local r = b.radius
  return b.x >= -r and b.x <= WIDTH - 1 + r
     and b.y >= -r and b.y <= HEIGHT - 1 + r
end

----------------------------------------------------------------------
-- Draw an off-screen indicator: a 10px arrow at the screen edge
-- pointing toward the body, with 5px barbs.
----------------------------------------------------------------------
local CX = WIDTH / 2
local CY = HEIGHT / 2
local MARGIN = 12  -- keep arrow away from screen edge
local ARROW_LEN = 10
local BARB_LEN = 5

local function draw_offscreen_indicator(b)
  local dx = b.x - CX
  local dy = b.y - CY
  local adx = abs(dx)
  local ady = abs(dy)
  if adx < 1 and ady < 1 then return end

  -- project direction onto screen edge to find arrow tip position
  local sx = adx > 0 and (WIDTH / 2 - MARGIN) / adx or 1e6
  local sy = ady > 0 and (HEIGHT / 2 - MARGIN) / ady or 1e6
  local s = math.min(sx, sy)
  local tx = floor(CX + dx * s + 0.5)
  local ty = floor(CY + dy * s + 0.5)

  -- clamp tip to screen
  if tx < MARGIN then tx = MARGIN end
  if tx > WIDTH - 1 - MARGIN then tx = WIDTH - 1 - MARGIN end
  if ty < MARGIN then ty = MARGIN end
  if ty > HEIGHT - 1 - MARGIN then ty = HEIGHT - 1 - MARGIN end

  -- unit vector pointing toward the body (outward from center)
  local dist = sqrt(dx * dx + dy * dy)
  local ux = dx / dist
  local uy = dy / dist

  -- arrow shaft: from tail to tip, tip points outward
  local tailx = floor(tx - ux * ARROW_LEN + 0.5)
  local taily = floor(ty - uy * ARROW_LEN + 0.5)
  draw.line(tailx, taily, tx, ty, b.color)

  -- barbs: two lines from tip angled back 135 degrees from shaft
  -- perpendicular to the direction vector
  local px = -uy  -- perpendicular
  local py = ux
  -- barb endpoints: back along shaft + sideways
  local bx1 = floor(tx - ux * BARB_LEN + px * BARB_LEN * 0.5 + 0.5)
  local by1 = floor(ty - uy * BARB_LEN + py * BARB_LEN * 0.5 + 0.5)
  local bx2 = floor(tx - ux * BARB_LEN - px * BARB_LEN * 0.5 + 0.5)
  local by2 = floor(ty - uy * BARB_LEN - py * BARB_LEN * 0.5 + 0.5)
  draw.line(tx, ty, bx1, by1, b.color)
  draw.line(tx, ty, bx2, by2, b.color)

  -- distance label next to the arrow tail
  local label = b.escaped and "Esc" or tostring(floor(dist + 0.5))
  -- offset text to the inward side of the arrow so it doesn't clip edge
  local lx = tailx - floor(ux * 2 + 0.5)
  local ly = taily - floor(uy * 2 + 0.5)
  -- center the text on the point
  lx = lx - #label * 3  -- approximate half-width of text
  ly = ly - 4            -- approximate half-height of text
  draw.text(lx, ly, label, b.color, bg)
end

----------------------------------------------------------------------
-- Collision: merge overlapping bodies
----------------------------------------------------------------------
local function handle_collisions(bodies)
  local n = #bodies
  for i = 1, n do
    local a = bodies[i]
    if a.alive then
      for j = i + 1, n do
        local b = bodies[j]
        if b.alive then
          local dx = b.x - a.x
          local dy = b.y - a.y
          local dist = sqrt(dx * dx + dy * dy)
          if dist < a.radius + b.radius + 1 then
            -- merge b into a (conserve momentum)
            local total = a.mass + b.mass
            if not a.fixed then
              a.vx = (a.mass * a.vx + b.mass * b.vx) / total
              a.vy = (a.mass * a.vy + b.mass * b.vy) / total
              -- center of mass position
              a.x = (a.mass * a.x + b.mass * b.x) / total
              a.y = (a.mass * a.y + b.mass * b.y) / total
            end
            -- keep the heavier body's color
            if b.mass > a.mass then
              a.color = b.color
              a.name = b.name
            end
            a.mass = total
            -- grow diameter (area-based: new area = sum of areas)
            local new_diam = floor(sqrt(a.diameter * a.diameter + b.diameter * b.diameter) + 0.5)
            if new_diam < DEFAULT_DIAM then new_diam = DEFAULT_DIAM end
            a.diameter = new_diam
            a.radius = floor(new_diam / 2)
            b.alive = false
          end
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Render
----------------------------------------------------------------------
local function render(bodies, conf, paused, ticks)
  -- count alive bodies
  local alive = 0
  for i = 1, #bodies do
    if bodies[i].alive then alive = alive + 1 end
  end

  -- draw bodies
  for i = 1, #bodies do
    local b = bodies[i]
    if b.alive then
      if on_screen(b) then
        local px = floor(b.x + 0.5)
        local py = floor(b.y + 0.5)
        draw.circleFill(px, py, b.radius, b.color)
      else
        draw_offscreen_indicator(b)
      end
    end
  end

  -- HUD
  local fmem = floor(collectgarbage("count"))
  local status = "dt=" .. string.format("%.2f", conf.dt)
    .. " n=" .. alive
    .. " t=" .. ticks
    .. " mem=" .. fmem .. "k"
  if paused then status = status .. " [PAUSED]" end
  if conf.trail then status = status .. " [TRAIL]" end
  draw.text(2, 2, status, hud_fg, hud_bg)
  draw.text(2, 12, "+/- speed  spc=pause  t=trail  r=reset  q=quit",
    colors.cyan, hud_bg)
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------
local function main()
  local conf, err = load_config()
  if not conf then
    print(err or "Config error")
    return
  end

  local bodies = init_bodies(conf)
  local paused = false
  local ticks = 0

  -- enable buffer mode
  if not draw.enableBuffer(1) then
    if not draw.enableBuffer(2) then
      print("Buffer mode unavailable")
      return
    end
  end

  draw.clear()
  draw.blitBuffer()

  local last_frame = os.clock()
  local running = true

  local function on_key(code)
    if code == "q" or code == "Q" or code == keys.esc then
      running = false
    elseif code == " " then
      paused = not paused
    elseif code == "t" or code == "T" then
      conf.trail = not conf.trail
    elseif code == "r" or code == "R" then
      local new_conf = load_config()
      if new_conf then
        conf = new_conf
        bodies = init_bodies(conf)
        ticks = 0
        paused = false
      end
    elseif code == "+" or code == "=" or code == keys.up then
      conf.dt = conf.dt * 1.25
      if conf.dt > 10.0 then conf.dt = 10.0 end
    elseif code == "-" or code == "_" or code == keys.down then
      conf.dt = conf.dt * 0.8
      if conf.dt < 0.01 then conf.dt = 0.01 end
    end
  end

  while running do
    -- frame timing: wait for next frame
    local now = os.clock()
    if now >= last_frame + FRAME_MS then
      last_frame = now

      -- the keyboard queues a hold and a release after every press, so
      -- only the press may act or one keystroke toggles several times
      local state, _, code = keys.poll()
      while state ~= IDLE do
        if state == PRESSED then on_key(code) end
        state, _, code = keys.poll()
      end
      if not running then break end

      -- physics
      if not paused then
        physics_step(bodies, conf.G, conf.dt, conf.soften)
        if conf.merge then
          handle_collisions(bodies)
        end
        check_escape(bodies, conf.G)
        ticks = ticks + 1
      end

      -- render
      if not conf.trail then
        draw.clear()
      end
      render(bodies, conf, paused, ticks)
      draw.blitBuffer()
      collectgarbage()
    end
  end

  -- cleanup
  draw.enableBuffer(0)
  draw.clear()
  term.clear()
  term.setCursorPos(1, 1)
end

-- Run with error protection so buffer mode is always restored
local cursor_blink = term.getCursorBlink()
term.setCursorBlink(false)
local ok, err = pcall(main)
draw.enableBuffer(0)  -- always restore direct mode
term.setCursorBlink(cursor_blink)
if not ok then
  draw.clear()
  term.clear()
  term.setCursorPos(1, 1)
  print("gravity.lua error: " .. tostring(err))
end
collectgarbage()
