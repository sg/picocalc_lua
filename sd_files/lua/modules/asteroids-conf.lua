--[[

  asteroids-conf.lua - the settings of asteroids.lua, kept in
                       lua/asteroids.conf

  Shared with asteroids-sound-tune.lua, which sets the sound
  settings by ear and saves them in the same file.

]]

local M = {}

M.path = "lua/asteroids.conf"

-- Each is name, default, least, most, step and what the file says of it; a step of 1 or more keeps the value
-- whole, and "off" lets it be 0 below its least.
local list = {
	"game",
	{"lives", 3, 0, 8, 1, "ships in reserve"},
	{"rocks", 4, 1, 8, 1, "large rocks in a wave"},
	{"rock_speed", 12, 1, 100, 0.5, "pixels a second at first"},
	{"rock_faster", 1.2, 0, 20, 0.1, "more for each rock shot"},
	{"rock_slower", 12, 0, 100, 0.5, "less for each wave"},
	{"ship_turn", 172, 30, 720, 1, "degrees a second"},
	{"ship_thrust", 24, 1, 400, 1, "speed gained a second"},
	{"ship_shield", 2.5, 0, 10, 0.25, "seconds safe when new"},
	{"shots", 5, 1, 12, 1, "in flight at once"},
	{"shot_speed", 140, 20, 600, 1, "pixels a second"},
	{"shot_reach", 40, 0, 320, 1, "pixels past an edge"},
	{"fire_repeat", 0.4, 0.05, 2, 0.05, "seconds, fire held"},
	{"fire_tap", 0.1, 0.05, 2, 0.05, "seconds, fire tapped"},

	-- The arcade board's values, except where its sound lay too low for a speaker this small: the explosion's
	-- filter is at 200 Hz for 52, and the thrust's band at 180 for 90 with no low-pass after it.
	"heartbeat",
	{"thump_low", 82, 40, 1000, 1, "Hz, its lower note"},
	{"thump_high", 87, 40, 1000, 1, "Hz, its higher note"},
	{"thump_length", 90, 20, 1000, 5, "milliseconds"},
	{"thump_lowpass", 482, 50, 8000, 10, "Hz, dulls above; 0 none", off = true},
	{"thump_volume", 0.5, 0, 1, 0.05, "0 to 1"},

	"shot",
	{"fire_from", 820, 50, 4000, 5, "Hz it starts at"},
	{"fire_to", 171, 50, 4000, 5, "Hz it slides to"},
	{"fire_length", 256, 20, 2000, 4, "milliseconds"},
	{"fire_volume", 0.15, 0, 1, 0.05, "0 to 1"},

	"explosion: noise, so many changes a second",
	{"bang_large", 1000, 200, 16000, 50, "for a large rock"},
	{"bang_medium", 2400, 200, 16000, 50, "for a medium rock"},
	{"bang_small", 4000, 200, 16000, 50, "for a small rock"},
	{"bang_ship", 2400, 200, 16000, 50, "for the ship"},
	{"bang_length", 1000, 50, 3000, 10, "milliseconds"},
	{"bang_lowpass", 200, 20, 8000, 10, "Hz, dulls above; 0 none", off = true},
	{"bang_volume", 1, 0, 1, 0.05, "0 to 1"},

	"thrust: noise through a band-pass filter",
	{"thrust_rate", 12000, 500, 16000, 100, "noise changes a second"},
	{"thrust_band", 180, 40, 2000, 5, "Hz, band centre; 0 none", off = true},
	{"thrust_resonance", 3, 0.5, 20, 0.5, "narrowness of the band"},
	{"thrust_lowpass", 0, 50, 8000, 10, "Hz, dulls above; 0 none", off = true},
	{"thrust_volume", 0.25, 0, 1, 0.05, "0 to 1"},
}

-- The lines are kept within the 53 columns of the PicoCalc's screen, where the file may well be edited.
local header = [=[
--[[

  asteroids.conf - settings for asteroids.lua

  Remove a line to return that setting to its
  default, or delete the file to return them all:
  the game writes a fresh one when it finds none.
  The screen is 320 pixels across.

  The sounds are easier to set by ear with
  asteroids-sound-tune.lua, which rewrites this
  file when it saves.

]]

return {
]=]

local info, values = {}, {}
for _, e in ipairs(list) do
	if type(e) == "table" then info[e[1]] = e end
end
M.info, M.values = info, values

function M.default(name)
	return info[name][2]
end

-- Whatever the file holds is brought within what the game and the sound driver can take.
function M.limit(name, v)
	local e = info[name]
	if v ~= v then return e[2] end
	if e.off and v <= 0 then return 0 end
	if e[5] >= 1 then v = math.floor(v + 0.5) end
	if v < e[3] then v = e[3] elseif v > e[4] then v = e[4] end
	return v
end

function M.save()
	local f = fs.open(M.path, "w")
	f:write(header)
	for _, e in ipairs(list) do
		if type(e) == "string" then
			f:write("\n  -- " .. e .. "\n")
		else
			local v = values[e[1]]
			-- numbers here are 32-bit floats, which a format of many digits would show the rounding of
			local number = v == math.floor(v) and string.format("%d", v) or string.format("%.4f", v):gsub("0+$", "")
			f:write(string.format("  %-23s-- %s\n", e[1] .. " = " .. number .. ",", e[6]))
		end
	end
	f:write("}\n")
	f:close()
end

-- A file that will not load, or a card that will not take a new one, still leaves the game its defaults,
-- and the file is left as it is for whoever was editing it to put right.
function M.load(create)
	for name, e in pairs(info) do values[name] = e[2] end
	M.problem = nil
	if fs.exists(M.path) then
		local ok, saved = pcall(dofile, M.path)
		if ok and type(saved) == "table" then
			for name in pairs(info) do
				if type(saved[name]) == "number" then values[name] = M.limit(name, saved[name]) end
			end
		else
			M.problem = M.path .. " could not be read, so the defaults were used"
		end
	elseif create then
		pcall(M.save)
	end
	return values
end

return M
