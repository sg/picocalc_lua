-- asteroids game
-- written by maple "mavica" syrup <maple@maple.pet>
-- its settings are in lua/asteroids.conf, and asteroids-sound-tune.lua sets the sounds among them by ear

local conf = require("lua/modules/asteroids-conf")
local snd = require("lua/modules/asteroids-sound")
local set = conf.load(true)
snd.apply()

local poly_ship = {{0, -10}, {5, 5}, {0, 0}, {-5, 5}, {0, -10}}
local poly_thrust = {{-2.5, 2.5}, {0, 4}, {2.5, 2.5}}
local poly_shot = {{0, 0}, {0, -5}}
local poly_rock = {{-1,0},{-0.8,-0.6},{-0.4,-0.5},
{0,-1},{0.5,-0.9},{0.3,-0.4},{0.8,-0.5},
{1,0},{0.7,0.4},{0.7,0.6},{0.3,0.8},{0,0.7},
{-0.3,0.9},{-0.7,0.8},{-0.7,0.5},{-1,0}}

local bg = colors.fromRGB(0,0,0)
local fg = colors.fromRGB(0,255,0)
local width = 320
local height = 320

-- The game moves in fixed steps whatever the frame rate, so the settings, which are by the second, are
-- turned here into amounts per step.
local step_time = 0.05
local function steps(seconds)
	return math.max(1, math.floor(seconds / step_time + 0.5))
end
local max_shots = set.shots
local shot_speed = set.shot_speed * step_time
local shot_overshoot = set.shot_reach
local rock_start = set.rock_speed * step_time
local rock_speed = rock_start
local rock_faster = set.rock_faster * step_time
local rock_slower = set.rock_slower * step_time
local rock_size = 30
local rock_step = 10
local ship_size = 10
local turn_speed = math.rad(set.ship_turn) * step_time
local fire_held = steps(set.fire_repeat)
local fire_tapped = math.min(fire_held, steps(set.fire_tap))
local shield = set.ship_shield > 0 and steps(set.ship_shield) or 0
local burst_dots = 8
local burst_time = 12
local wreck_time = 40
local wreck_lives = {16, 6, 10, 28}

local sin, cos, floor, random = math.sin, math.cos, math.floor, math.random
local PRESSED, IDLE = keys.states.pressed, keys.states.idle

-- The heartbeat keeps the arcade board's timing, which counted in frames of 1/62.5 s.
local frame = 1 / 62.5
local thump_on, thump_gap, thump_gap_min, thump_faster = 4, 48, 8, 64

local player = {
	x=width/2,
	y=height/2,
	accel = set.ship_thrust * step_time * step_time,
	vx=0,
	vy=0,
	ang=0,
	cdown=0,
	inv=0,
	ship = {},
	flame = {},
}

local shots = {}
local rocks = {}
local gone = {}
local score = 0
local lives = set.lives
local game_over = false
local quit = false
local dead = 0
local last_ship = false
local wave_start, next_thump, thump_is_high = 0, false, true

-- Dots and wreckage are made once and reused, so that a burst costs the collector nothing.
local dots = {}
for i = 1, burst_dots * 3 do
	dots[i] = {x = 0, y = 0, vx = 0, vy = 0, life = 0, sx = false, sy = 0}
end
local wreck = {}
for i = 1, #poly_ship - 1 do
	wreck[i] = {shape = {poly_ship[i], poly_ship[i + 1]}, x = 0, y = 0, vx = 0, vy = 0, ang = 0, life = 0}
end

-- Keys pressed since the last step, so that a tap shorter than a step still counts.
local tapped = {}

local function read_keys()
	local state, _, code = keys.poll()
	while state ~= IDLE do
		if state == PRESSED then tapped[code] = true end
		state, _, code = keys.poll()
	end
end

local function down(code)
	return tapped[code] or keys.getState(code)
end

-- Point lists are refilled in place rather than built anew, which leaves the collector little to do.
local function transform(shape, x, y, ang, scale, out)
	local s, c = sin(ang) * scale, cos(ang) * scale
	local n = #shape
	for i = 1, n do
		local v = shape[i]
		out[2*i-1] = floor(x + v[1] * c - v[2] * s + 0.5)
		out[2*i] = floor(y + v[1] * s + v[2] * c + 0.5)
	end
	for i = #out, 2*n + 1, -1 do out[i] = nil end
	return out
end

-- A frame drawn in a framebuffer and sent whole is never seen half erased; without one, each shape
-- is erased and redrawn alone so that it vanishes only briefly.
local buffered = false
local scratch = {}

local function same(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

-- Drawing straight to the LCD is slow, so a shape is redrawn only when its points have moved.
local function show(o, pts)
	local old = o.shown
	if pts and old and same(pts, old) then return end
	if old then draw.polygon(old, bg) end
	if pts then
		draw.polygon(pts, fg)
		o.shown, o.spare = pts, old or {}
	else
		o.shown, o.spare = nil, old or o.spare
	end
end

-- Something across an edge shows on the opposite one as well, as it wraps around to there.
local function draw_wrapped(shape, x, y, ang, scale, r)
	local xs = (x < r and width) or (x > width - r and -width) or 0
	local ys = (y < r and height) or (y > height - r and -height) or 0
	draw.polygon(transform(shape, x, y, ang, scale, scratch), fg)
	if xs ~= 0 then draw.polygon(transform(shape, x + xs, y, ang, scale, scratch), fg) end
	if ys ~= 0 then draw.polygon(transform(shape, x, y + ys, ang, scale, scratch), fg) end
	if xs ~= 0 and ys ~= 0 then draw.polygon(transform(shape, x + xs, y + ys, ang, scale, scratch), fg) end
end

local function sprite(o, shape, x, y, ang, scale, r, visible)
	if buffered then
		if visible then draw_wrapped(shape, x, y, ang, scale, r) end
	else
		o.spare = o.spare or {}
		show(o, visible and transform(shape, x, y, ang, scale, o.spare) or nil)
	end
end

-- Without a framebuffer a dot is erased and redrawn only when it has moved to another pixel.
local function draw_dots()
	for i = 1, #dots do
		local d = dots[i]
		if buffered then
			if d.life > 0 then draw.point(floor(d.x), floor(d.y), fg) end
		else
			local x, y = false, 0
			if d.life > 0 then x, y = floor(d.x), floor(d.y) end
			if x ~= d.sx or y ~= d.sy then
				if d.sx then draw.point(d.sx, d.sy, bg) end
				if x then draw.point(x, y, fg) end
				d.sx, d.sy = x, y
			end
		end
	end
end

-- The thump quickens with the time spent on a wave, not with the rocks left, and rests while there is no ship.
local function heartbeat(now)
	if #rocks == 0 or dead > 0 then next_thump = false return end
	local gap = thump_gap - floor((now - wave_start) / (thump_faster * frame))
	if gap < thump_gap_min then gap = thump_gap_min end
	if not next_thump then next_thump = now + gap * frame end
	if now >= next_thump then
		thump_is_high = not thump_is_high
		snd.thump(thump_is_high)
		-- A beat that comes a little late keeps to its schedule, but one held up by a stall starts it afresh.
		if now - next_thump > step_time then next_thump = now end
		next_thump = next_thump + (thump_on + gap) * frame
	end
end

local function burst(x, y)
	local n = burst_dots
	for i = 1, #dots do
		local d = dots[i]
		if d.life == 0 then
			local a, v = random() * 6.28, 0.6 + random() * 1.4
			d.x, d.y, d.vx, d.vy = x, y, sin(a) * v, cos(a) * v
			d.life = burst_time - random(0, 4)
			n = n - 1
			if n == 0 then return end
		end
	end
end

-- Each piece of the ship's outline drifts off the way its middle lies from the ship's centre.
local function wreck_ship()
	local p = player
	local s, c = sin(p.ang), cos(p.ang)
	for i = 1, #wreck do
		local w = wreck[i]
		local a, b = w.shape[1], w.shape[2]
		local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		local v = (0.4 + random() * 0.5) / math.sqrt(mx * mx + my * my)
		w.x, w.y, w.ang = p.x, p.y, p.ang
		w.vx, w.vy = (mx * c - my * s) * v, (mx * s + my * c) * v
		w.life = wreck_lives[i]
	end
end

local function rock_create(x, y, ang, size)
	rocks[#rocks+1] = {
		x = x,
		y = y,
		ang = ang,
		vx = sin(ang) * rock_speed,
		vy = -cos(ang) * rock_speed,
		scale = size
	}
end

local function level_init()
	for i = 1, set.rocks do
		rock_create(random(30,width-30), random(30,height-30), random()*6.28, rock_size)
	end
	player.inv = shield
	wave_start = os.clock()
end

-- The ship is gone while its wreckage drifts, and the game ends only once the last ship's has.
local function player_hit()
	snd.bang()
	wreck_ship()
	dead = wreck_time
	if lives == 0 then last_ship = true else lives = lives - 1 end
end

local function player_return()
	if last_ship then game_over = true return end
	local p = player
	p.x, p.y, p.vx, p.vy = width/2, height/2, 0, 0
	p.ang, p.cdown, p.inv = 0, 0, shield
end

local function rock_hit(k, shot)
	local rock = rocks[k]
	snd.bang(rock.scale // rock_step)
	score = score + ((rock_size + rock_step) - rock.scale)
	rock_speed = rock_speed + rock_faster
	table.remove(rocks, k)
	gone[#gone+1] = rock
	if rock.scale > rock_step then
		rock_create(rock.x, rock.y, shot.ang - random()*3.14, rock.scale-rock_step)
		rock_create(rock.x, rock.y, shot.ang + random()*3.14, rock.scale-rock_step)
	else
		burst(rock.x, rock.y)
	end
	if #rocks == 0 then
		rock_speed = math.max(rock_start, rock_speed - rock_slower)
		score = score + 500
		level_init()
	end
end

local function fire()
	snd.fire()
	shots[#shots+1] = {
		x = player.x,
		y = player.y,
		ang = player.ang,
		vx = sin(player.ang) * shot_speed,
		vy = -cos(player.ang) * shot_speed,
		left = false,
	}
	player.cdown = fire_held
end

local function player_update()
	local p = player
	p.ang = p.ang + ((down(keys.right) and turn_speed or 0) - (down(keys.left) and turn_speed or 0))
	local thrust = down(keys.up)
	snd.thrust(thrust)
	if thrust then
		p.vx = p.vx + sin(p.ang) * p.accel
		p.vy = p.vy - cos(p.ang) * p.accel
	elseif down(keys.down) then
		local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
		local slower = speed > p.accel and (speed - p.accel) / speed or 0
		p.vx = p.vx * slower
		p.vy = p.vy * slower
	end
	p.x = (p.x + p.vx) % width
	p.y = (p.y + p.vy) % height

	if p.cdown > 0 then p.cdown = p.cdown - 1 end
	-- Held, fire repeats slowly; pressed again, it fires at once, limited only by the shots in flight.
	local tap = tapped[keys.enter] or tapped[" "]
	local held = keys.getState(keys.enter) or keys.getState(" ")
	if #shots < max_shots and ((tap and p.cdown <= fire_held - fire_tapped) or (held and p.cdown == 0)) then
		fire()
	end

	if p.inv > 0 then p.inv = p.inv - 1 end
end

local function step()
	if down(keys.esc) then quit = true return end
	if dead == 0 then
		player_update()
	else
		snd.thrust(false)
		dead = dead - 1
		if dead == 0 then player_return() end
		if game_over then return end
	end

	for k = #shots, 1, -1 do
		local shot = shots[k]
		local x, y = shot.x + shot.vx, shot.y + shot.vy
		-- A shot comes back in at the opposite edge, but from there has only a little further to go.
		if shot.left then
			shot.left = shot.left - shot_speed
		elseif x < 0 or x >= width or y < 0 or y >= height then
			shot.left = shot_overshoot
		end
		x, y = x % width, y % height
		shot.x, shot.y = x, y
		local hit = false
		for r = #rocks, 1, -1 do
			local rock = rocks[r]
			local dx, dy = x - rock.x, y - rock.y
			if dx * dx + dy * dy < rock.scale * rock.scale then
				rock_hit(r, shot)
				hit = true
				break
			end
		end
		if hit or (shot.left and shot.left <= 0) then
			table.remove(shots, k)
			gone[#gone+1] = shot
		end
	end

	for k = 1, #rocks do
		local rock = rocks[k]
		rock.x = (rock.x + rock.vx) % width
		rock.y = (rock.y + rock.vy) % height
		local dx, dy = player.x - rock.x, player.y - rock.y
		if dead == 0 and player.inv == 0 and dx * dx + dy * dy < rock.scale * rock.scale then
			player_hit()
		end
	end

	for i = 1, #dots do
		local d = dots[i]
		if d.life > 0 then
			d.x, d.y, d.life = d.x + d.vx, d.y + d.vy, d.life - 1
			if d.x < 0 or d.x >= width or d.y < 0 or d.y >= height then d.life = 0 end
		end
	end
	for i = 1, #wreck do
		local w = wreck[i]
		if w.life > 0 then w.x, w.y, w.life = w.x + w.vx, w.y + w.vy, w.life - 1 end
	end
end

local hud_score, hud_text
local function hud_draw()
	if score ~= hud_score then
		hud_score = score
		hud_text = string.format("%-7d", score)
	end
	draw.text(15, 15, hud_text, fg, bg)
	for i = 0, set.lives - 1 do
		if i < lives or not buffered then
			draw.polygon(transform(poly_ship, width - 20 - 20*i, 20, 0, 1, scratch), i < lives and fg or bg)
		end
	end
end

local function render()
	if buffered then
		draw.clear()
		hud_draw()
	else
		for i = 1, #gone do show(gone[i], nil) end
	end
	for i = #gone, 1, -1 do gone[i] = nil end

	local p = player
	local visible = dead == 0 and floor(p.inv / 3) % 2 == 0
	sprite(p.ship, poly_ship, p.x, p.y, p.ang, 1, ship_size, visible)
	sprite(p.flame, poly_thrust, p.x, p.y, p.ang, 1, ship_size, visible and keys.getState(keys.up))
	for _, w in ipairs(wreck) do sprite(w, w.shape, w.x, w.y, w.ang, 1, ship_size, w.life > 0) end
	for _, shot in ipairs(shots) do sprite(shot, poly_shot, shot.x, shot.y, shot.ang, 1, 5, true) end
	for _, rock in ipairs(rocks) do sprite(rock, poly_rock, rock.x, rock.y, rock.ang, rock.scale, rock.scale, true) end
	draw_dots()

	if buffered then
		draw.blitBuffer()
	else
		hud_draw()
	end
end

local function main()
	level_init()
	local next_step = os.clock()
	while not (quit or game_over) do
		read_keys()
		local now = os.clock()
		heartbeat(now)
		if now >= next_step then
			-- Steps that fell behind run before the next frame so the game keeps its pace, but time
			-- lost to a long stall is dropped rather than raced through.
			if now - next_step > 5 * step_time then next_step = now end
			while now >= next_step and not (quit or game_over) do
				next_step = next_step + step_time
				step()
				for code in pairs(tapped) do tapped[code] = nil end
			end
			render()
		end
	end
end

-- QSPI PSRAM is mapped into memory, so a framebuffer there is quick and takes no heap; picolua
-- panics when an allocation fails, so one in RAM is risked only with far more memory free than it needs.
local function enable_buffer()
	if psram and psram.stats and psram.stats().qspi and draw.enableBuffer(1) then return true end
	collectgarbage()
	return sys.freeMemory() >= 256 * 1024 and draw.enableBuffer(2)
end

local blink = term.getCursorBlink()
term.setCursorBlink(false)
term.clear()
buffered = enable_buffer()
-- Even when stopped with Break, the terminal gets its cursor back and the keys held in the game stay out of the shell.
local ok, err = pcall(main)
snd.hush()
draw.enableBuffer(0)
keys.flush()
term.setCursorBlink(blink)
term.clear()
if not ok then error(err, 0) end
if conf.problem then print(conf.problem) end
if game_over then
	print("game over!")
	print("final score: "..score)
end
