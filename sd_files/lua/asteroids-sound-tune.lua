--[[

  asteroids-sound-tune.lua - set the sounds of asteroids.lua by ear

  Plays each sound as the game does, lets its settings be changed
  while listening, and saves them in lua/asteroids.conf.

]]

local conf = require("lua/modules/asteroids-conf")
local snd = require("lua/modules/asteroids-sound")
local set = conf.load(true)
snd.apply()

if not snd.has_thrust then
	print("These sounds need newer firmware than")
	print("this: flash the latest UF2 first.")
	return
end

local rows = {
	{title = "Heartbeat", key = "H"},
	{"thump_low", "low note", "Hz"},
	{"thump_high", "high note", "Hz"},
	{"thump_length", "length", "ms"},
	{"thump_lowpass", "low-pass", "Hz"},
	{"thump_volume", "volume"},
	{title = "Shot", key = "F"},
	{"fire_from", "starts at", "Hz"},
	{"fire_to", "slides to", "Hz"},
	{"fire_length", "length", "ms"},
	{"fire_volume", "volume"},
	{title = "Explosion", key = "1 2 3 4"},
	{"bang_large", "1 large rock", "Hz"},
	{"bang_medium", "2 medium rock", "Hz"},
	{"bang_small", "3 small rock", "Hz"},
	{"bang_ship", "4 ship", "Hz"},
	{"bang_length", "length", "ms"},
	{"bang_lowpass", "low-pass", "Hz"},
	{"bang_volume", "volume"},
	{title = "Thrust", key = "T"},
	{"thrust_rate", "noise rate", "Hz"},
	{"thrust_band", "band centre", "Hz"},
	{"thrust_resonance", "resonance"},
	{"thrust_lowpass", "low-pass", "Hz"},
	{"thrust_volume", "volume"},
}
local top = 2
local status_line = top + #rows + 7

local selected = 2
local thrust_on, high, dirty, leaving = false, false, false, false
local PRESSED, IDLE = keys.states.pressed, keys.states.idle

-- numbers here are 32-bit floats, so a value stepped back to its default may not be its equal to the last bit
local function is_default(name)
	return math.abs(set[name] - conf.default(name)) < 0.001
end

local function value_text(row)
	local name = row[1]
	local v, step = set[name], conf.info[name][5]
	if v == 0 and conf.info[name].off then return "off" end
	local text = string.format(step >= 1 and "%d" or step < 0.1 and "%.2f" or "%.1f", v)
	return row[3] and text .. " " .. row[3] or text
end

local function draw_row(i)
	local row = rows[i]
	term.setCursorPos(1, top + i)
	term.clearLine()
	if row.title then
		term.setTextColor(colors.cyan)
		term.write(string.format(" %-28s plays with %s", row.title, row.key))
	else
		-- a setting moved from its default stands out, as the one to look at when a sound seems wrong
		local changed = not is_default(row[1])
		term.setTextColor(i == selected and colors.white or changed and colors.yellow or colors.lightGray)
		term.write(string.format(" %s %-16s %s%s", i == selected and ">" or " ", row[2], value_text(row), changed and " *" or ""))
	end
end

local function status(text)
	term.setCursorPos(1, status_line)
	term.clearLine()
	term.setTextColor(dirty and colors.yellow or colors.lime)
	term.write(" " .. (text or (dirty and "changed, not saved" or "as saved in " .. conf.path)))
end

local function draw_all()
	term.clear()
	term.setTextColor(colors.white)
	term.setCursorPos(1, 1)
	term.write(" Asteroids sound tuner")
	for i = 1, #rows do draw_row(i) end
	term.setTextColor(colors.lightGray)
	local help = {
		"Up/Down     choose a setting",
		"Left/Right  change it, faster when held",
		"Space       play the chosen sound",
		"D default   A all defaults   S save",
		"Esc         leave",
	}
	for i, line in ipairs(help) do
		term.setCursorPos(1, top + #rows + 1 + i)
		term.write(" " .. line)
	end
	status()
end

local function group_of(i)
	return rows[i][1]:match("^%a+")
end

local function play(group, name)
	if group == "thump" then
		if name == "thump_low" then high = false elseif name == "thump_high" then high = true else high = not high end
		snd.thump(high)
	elseif group == "fire" then
		snd.fire()
	elseif group == "bang" then
		snd.bang(name == "bang_large" and 3 or name == "bang_medium" and 2 or name == "bang_small" and 1 or name == "bang_ship" and 0 or 3)
	end
end

local function thrust(on)
	thrust_on = on
	snd.thrust(false)
	if on then snd.thrust(true) else snd.hush() end
end

local function changed()
	dirty, leaving = true, false
	snd.apply()
	if thrust_on and group_of(selected) == "thrust" then thrust(true) end
	draw_row(selected)
	status()
end

local function change(direction, times)
	local name = rows[selected][1]
	local e = conf.info[name]
	local v, step = set[name], e[5]
	if e.off and v == 0 then
		if direction < 0 then return end
		v = e[3]
	else
		v = v + direction * step * times
		if e.off and v < e[3] then v = 0 end
		if step < 1 then v = math.floor(v / step + 0.5) * step end
	end
	v = conf.limit(name, v)
	if v ~= set[name] then
		set[name] = v
		changed()
	end
end

local function move(direction)
	local was = selected
	repeat
		selected = (selected - 1 + direction) % #rows + 1
	until not rows[selected].title
	draw_row(was)
	draw_row(selected)
end

local function press(code)
	local name = rows[selected][1]
	if code == keys.up then move(-1)
	elseif code == keys.down then move(1)
	elseif code == " " then
		if group_of(selected) == "thrust" then thrust(not thrust_on) else play(group_of(selected), name) end
	elseif code == "h" or code == "H" then play("thump")
	elseif code == "f" or code == "F" then play("fire")
	elseif code == "1" then play("bang", "bang_large")
	elseif code == "2" then play("bang", "bang_medium")
	elseif code == "3" then play("bang", "bang_small")
	elseif code == "4" then play("bang", "bang_ship")
	elseif code == "t" or code == "T" then thrust(not thrust_on)
	elseif code == "d" or code == "D" then
		if not is_default(name) then
			set[name] = conf.default(name)
			changed()
		end
	elseif code == "a" or code == "A" then
		for _, row in ipairs(rows) do
			if not row.title then set[row[1]] = conf.default(row[1]) end
		end
		dirty, leaving = true, false
		snd.apply()
		if thrust_on then thrust(true) end
		draw_all()
	elseif code == "s" or code == "S" then
		local ok = pcall(conf.save)
		dirty = dirty and not ok
		leaving = false
		status(not ok and "could not write " .. conf.path or nil)
	end
end

local blink = term.getCursorBlink()
local color = term.getTextColor()
term.setCursorBlink(false)
draw_all()
if conf.problem then status("unreadable file: S replaces it") end

-- Left and Right repeat while held and take bigger steps the longer they are, since some settings span
-- thousands of steps; the sound is played once the key is let go, not at every step.
local held, since, again
while true do
	local state, _, code = keys.poll()
	local now = os.clock()
	if state == PRESSED then
		if code == keys.esc then
			if not dirty or leaving then break end
			leaving = true
			status("not saved: S saves, Esc again leaves")
		elseif code == keys.left or code == keys.right then
			held, since, again = code, now, now + 0.4
			change(code == keys.right and 1 or -1, 1)
		else
			press(code)
		end
	elseif state == IDLE and held then
		if not keys.getState(held) then
			held = nil
			if group_of(selected) ~= "thrust" then play(group_of(selected), rows[selected][1]) end
		elseif now >= again then
			again = now + 0.06
			change(held == keys.right and 1 or -1, now - since > 3 and 25 or now - since > 1.5 and 5 or 1)
		end
	end
end

snd.hush()
keys.flush()
term.setTextColor(color)
term.setCursorBlink(blink)
term.clear()
print(dirty and "Sound settings left as they were saved." or "Sound settings are in " .. conf.path .. ".")
