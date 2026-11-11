-- asteroids game
-- written by maple "mavica" syrup <maple@maple.pet>

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

-- The game moves in fixed steps whatever the frame rate, and every speed below is per step.
local step_time = 0.05
local max_shots = 5
local shot_speed = 7
local rock_speed = 0.6
local rock_size = 30
local rock_step = 10
local ship_size = 10
local turn_speed = 0.15
local fire_held = 8
local fire_tapped = 2

local sin, cos, floor, random = math.sin, math.cos, math.floor, math.random
local PRESSED, IDLE = keys.states.pressed, keys.states.idle

local player = {
	x=width/2,
	y=height/2,
	accel = 0.06,
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
local lives = 3
local game_over = false
local quit = false

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

-- A frame drawn in a RAM framebuffer and sent whole is never seen half erased; without the 100 KB
-- that needs, each shape is erased and redrawn alone so that it vanishes only briefly.
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
	for i=1,4 do
		rock_create(random(30,width-30), random(30,height-30), random()*6.28, rock_size)
	end
	player.inv = 50
end

local function player_hit()
	sound.playPitch(1, 0.4, sound.drums.snare1)
	if lives == 0 then game_over = true return end
	lives = lives - 1
	player.x = width/2
	player.y = height/2
	player.vx = 0
	player.vy = 0
	player.ang = 0
	player.inv = 50
end

local function rock_hit(k, shot)
	local rock = rocks[k]
	sound.playPitch(1, 0.5, sound.drums.snare2)
	score = score + ((rock_size + rock_step) - rock.scale)
	rock_speed = rock_speed + 0.06
	table.remove(rocks, k)
	gone[#gone+1] = rock
	if rock.scale > rock_step then
		rock_create(rock.x, rock.y, shot.ang - random()*3.14, rock.scale-rock_step)
		rock_create(rock.x, rock.y, shot.ang + random()*3.14, rock.scale-rock_step)
	end
	if #rocks == 0 then
		rock_speed = rock_speed - 0.6
		score = score + 500
		level_init()
	end
end

local function fire()
	sound.playPitch(1, 2, sound.drums.tom)
	shots[#shots+1] = {
		x = player.x,
		y = player.y,
		ang = player.ang,
		vx = sin(player.ang) * shot_speed,
		vy = -cos(player.ang) * shot_speed,
	}
	player.cdown = fire_held
end

local function player_update()
	local p = player
	p.ang = p.ang + ((down(keys.right) and turn_speed or 0) - (down(keys.left) and turn_speed or 0))
	if down(keys.up) then
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
	player_update()

	for k = #shots, 1, -1 do
		local shot = shots[k]
		shot.x = shot.x + shot.vx
		shot.y = shot.y + shot.vy
		local hit = false
		if shot.x > width or shot.x < 0 or shot.y > height or shot.y < 0 then
			hit = true
		else
			for r = #rocks, 1, -1 do
				local rock = rocks[r]
				local dx, dy = shot.x - rock.x, shot.y - rock.y
				if dx * dx + dy * dy < rock.scale * rock.scale then
					rock_hit(r, shot)
					hit = true
					break
				end
			end
		end
		if hit then
			table.remove(shots, k)
			gone[#gone+1] = shot
		end
	end

	for k = 1, #rocks do
		local rock = rocks[k]
		rock.x = (rock.x + rock.vx) % width
		rock.y = (rock.y + rock.vy) % height
		local dx, dy = player.x - rock.x, player.y - rock.y
		if player.inv == 0 and dx * dx + dy * dy < rock.scale * rock.scale then
			player_hit()
		end
	end
end

local hud_score, hud_text
local function hud_draw()
	if score ~= hud_score then
		hud_score = score
		hud_text = string.format("%-7d", score)
	end
	draw.text(15, 15, hud_text, fg, bg)
	for i = 0, 3 do
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
	local visible = floor(p.inv / 3) % 2 == 0
	sprite(p.ship, poly_ship, p.x, p.y, p.ang, 1, ship_size, visible)
	sprite(p.flame, poly_thrust, p.x, p.y, p.ang, 1, ship_size, visible and keys.getState(keys.up))
	for _, shot in ipairs(shots) do sprite(shot, poly_shot, shot.x, shot.y, shot.ang, 1, 0, true) end
	for _, rock in ipairs(rocks) do sprite(rock, poly_rock, rock.x, rock.y, rock.ang, rock.scale, rock.scale, true) end

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

local blink = term.getCursorBlink()
term.setCursorBlink(false)
term.clear()
buffered = draw.enableBuffer(2)
-- Even when stopped with Break, the terminal gets its cursor back and the keys held in the game stay out of the shell.
local ok, err = pcall(main)
draw.enableBuffer(0)
keys.flush()
term.setCursorBlink(blink)
term.clear()
if not ok then error(err, 0) end
if game_over then
	print("game over!")
	print("final score: "..score)
end
