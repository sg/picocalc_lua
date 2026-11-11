--[[

  asteroids-sound.lua - the sounds of asteroids.lua, made from the
                        settings asteroids-conf.lua holds

  Shared with asteroids-sound-tune.lua, so that what is tuned
  there is what the game plays.

]]

local set = require("lua/modules/asteroids-conf").values

local M = {}

local ch_thump, ch_fire, ch_bang, ch_thrust = 0, 1, 2, 3
local noise = sound.presets.noise

-- Firmware without the noise wave has no pitch slide or filter either, and keeps the drums it always played.
M.arcade = noise ~= nil
M.has_thrust = M.arcade and noise.bandpass ~= nil

local snd_thump = sound.instrument(sound.presets.square)
local snd_fire, snd_bang, snd_thrust, snd_hush
if M.arcade then
	snd_fire = sound.instrument(sound.presets.square)
	snd_bang = sound.instrument(noise)
	snd_hush = sound.instrument(noise)
	snd_hush.volume, snd_hush.decay = 0, 1
end
if M.has_thrust then
	snd_thrust = sound.instrument(noise)
	snd_thrust.decay, snd_thrust.sustain, snd_thrust.release = 0, 1, 60
end

local bang_sizes = {"bang_small", "bang_medium", "bang_large"}
local thrusting = false

-- Slice n of the pulse wave is high for n/64 of its cycle, and the shot's widens as its pitch falls.
function M.apply()
	snd_thump.volume, snd_thump.decay, snd_thump.lowpass = set.thump_volume, set.thump_length, set.thump_lowpass
	snd_thump.table_start, snd_thump.table_end = 29, 29
	if snd_fire then
		snd_fire.volume, snd_fire.decay = set.fire_volume, set.fire_length
		snd_fire.table_mode, snd_fire.table_start, snd_fire.table_end = sound.tableModes.oneShot, 46, 60
		snd_fire.table_playrate = math.max(1, set.fire_length * 16 // 14)
		snd_fire.slide, snd_fire.slide_time = set.fire_to / set.fire_from, set.fire_length
		snd_bang.volume, snd_bang.decay, snd_bang.lowpass = set.bang_volume, set.bang_length, set.bang_lowpass
	end
	if snd_thrust then
		snd_thrust.volume, snd_thrust.lowpass = set.thrust_volume, set.thrust_lowpass
		snd_thrust.bandpass, snd_thrust.resonance = set.thrust_band, set.thrust_resonance
	end
end

-- A wavetable at pitch 1 sounds at 131 Hz, and the noise at pitch 1 changes 16000 times a second.
function M.thump(high)
	sound.playPitch(ch_thump, (high and set.thump_high or set.thump_low) / 131, snd_thump)
end

function M.fire()
	if snd_fire then
		sound.playPitch(ch_fire, set.fire_from / 131, snd_fire)
	else
		sound.playPitch(ch_fire, 2, sound.drums.tom)
	end
end

-- The size is a rock's, from 1 for the smallest to 3, and anything else is the ship.
function M.bang(size)
	local rate = set[bang_sizes[size] or "bang_ship"]
	if snd_bang then
		sound.playPitch(ch_bang, rate / 16000, snd_bang)
	else
		sound.playPitch(ch_bang, rate / 4800, sound.drums.snare2)
	end
end

-- A note asked for within the last sound buffer is not yet playing and cannot be stopped, so the stop is
-- given on every call without thrust rather than once.
function M.thrust(on)
	if not snd_thrust then return end
	if not on then
		sound.off(ch_thrust)
	elseif not thrusting then
		sound.playPitch(ch_thrust, set.thrust_rate / 16000, snd_thrust)
	end
	thrusting = on and true or false
end

-- The thrust may have been asked for too lately to be stopped, but a silent note in its place cannot miss it.
function M.hush()
	if snd_hush then sound.playPitch(ch_thrust, 1, snd_hush) end
	thrusting = false
end

return M
