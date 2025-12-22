local keymap = {
	"5","6","4","7","3","8","2","9",
	"t","y","r","u","e","i","w","o",
	"g","h","f","j","d","k","s","l",
	"b","n","v","m","c",",","x","."
}

local pkeys = {}
for k,v in pairs(keymap) do
	pkeys[v] = k-1
end

local dkeys = {}
dkeys["1"] = sound.instrument(5)
dkeys["q"] = sound.instrument(7)
dkeys["a"] = sound.instrument(9,0.5)
dkeys["z"] = sound.instrument(11)

local pat_len = 32
local channels = 4

local pat = {}
for i = 1, channels do
	pat[i] = {}
end

local curx, cury = 0, 0
local playing = false
local curplay = 0
local lastframe = 0
local beattime = 0.48 / 4 * 1000
local octave = 3
local recording = true

function noteString(note)
	local notes = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
	return notes[(note % 12)+1] .. math.floor(note / 12)
end

function updateBeatCursor()
	for y = 1,pat_len do
		term.setCursorPos(1, y)
		if playing and curplay+1 == y then
			term.write(">")
		else
			term.write(" ")
		end
	end
end

function drawPattern()
	for y = 1,pat_len do
		for x = 1,channels do
			term.setCursorPos(x*4, y)
			local note = ""
			if x == curx+1 and y == cury+1 then
				if recording then note = note .. "\27[91m" end
				note = note .. "\27[7m"
			end
			if pat[x][y] == nil then
				note = note .. "---"
			else
				note = note .. noteString(pat[x][y][1])
			end
			term.write(note .. "\27[0m")
		end
	end
end

function playBeat()
	updateBeatCursor()
	for i = 1,channels do
		if pat[i][curplay+1] then
			sound.play(i, pat[i][curplay+1][1], pat[i][curplay+1][2])
		end
	end
	curplay = (curplay + 1) % pat_len
end

function startStop()
	if playing then
		playing = false
		curplay = 0
		updateBeatCursor()
		sys.stopTimer()
	else
		playing = true
		sys.repeatTimer(beattime, playBeat)
	end
end

local insts = {
	sound.instrument(0,0.4,0,300,0,0,2,32,500),
	sound.instrument(3,0.6,50,600,0,0,2,10,0),
	sound.instrument(0,0.2,0,400,0,0,2,32,0)
}

local curinst = 0

drawPattern()
while true do
	repeat
		state, _, code = keys.poll()

		if state == keys.states.pressed then
			if code == keys.up then
				cury = ((cury - 1) % pat_len)
			elseif code == keys.down then
				cury = ((cury + 1) % pat_len)
			elseif code == keys.left then
				curx = ((curx - 1) % channels)
			elseif code == keys.right then
				curx = ((curx + 1) % channels)
			elseif code == keys.delete then
				pat[curx+1][cury+1] = nil
				cury = ((cury + 1) % pat_len)
			elseif code == "[" then
				if octave > 0 then octave = octave - 1 end
			elseif code == "]" then
				if octave < 5 then octave = octave + 1 end
			elseif code == "-" then
				curinst = (curinst-1)  % #insts
			elseif code == "=" then
				curinst = (curinst+1) % #insts
			elseif code == keys.enter then
				startStop()
			elseif code == " " then
				recording = not recording
			elseif pkeys[code] then
				local note = pkeys[code] + (octave * 12)
				local inst = insts[curinst+1]
				if recording then
					pat[curx+1][cury+1] = {note, inst}
					cury = (cury+1) % pat_len
				end
				if not playing then
					sound.play(curx, note, inst)
				end
			elseif dkeys[code] then
				if recording then
					pat[curx+1][cury+1] = {36, dkeys[code]}
					cury = (cury+1) % pat_len
				end
				if not playing then
					sound.play(curx, 36, dkeys[code])
				end
			end
			drawPattern()
		end
	until code == "\0"
end
