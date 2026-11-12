-- Runs the SD card's Z-machine interpreter under host Lua with a fake terminal, keyboard, PSRAM and card,
-- and prints the screen as it stands at the end. The fake terminal reports any write that would wrap or
-- scroll, which the interpreter must never cause.
--
--   lua5.4 tools/zmachine/harness.lua sd_files STORY SCRIPT [WORKDIR]
--
-- STORY is a .z3 or .z5 file (none are kept in this repository). SCRIPT has one typed line per line, and
-- "\k X" sends the single key X. Saves go to WORKDIR. Environment: ROWS and COLS for the screen size,
-- TRACE=file for everything the game prints, DUMP_EACH=1 for the screen before each Enter, LENIENT=1 to
-- let the terminal wrap and scroll.
local sdroot, story, script, workdir = arg[1], arg[2], arg[3], arg[4] or "."

package.path = sdroot .. "/?.lua;" .. package.path

local W, H = tonumber(os.getenv("COLS") or 53), tonumber(os.getenv("ROWS") or 40)
local grid, attr = {}, {}
local cx, cy = 0, 0
local inverse = false
local problems = {}
local function blank_row(y) grid[y] = {}; attr[y] = {}; for x = 0, W - 1 do grid[y][x] = " "; attr[y][x] = false end end
local function clear() for y = 0, H - 1 do blank_row(y) end; cx, cy = 0, 0 end
clear()

local function dump(title)
  print("+" .. string.rep("-", W) .. "+ " .. (title or ""))
  for y = 0, H - 1 do
    local t = {}
    for x = 0, W - 1 do t[#t + 1] = grid[y][x] end
    local inv = {}
    for x = 0, W - 1 do inv[#inv + 1] = attr[y][x] and "^" or " " end
    local line = table.concat(t)
    print("|" .. line .. "|" .. (table.concat(inv):find("%^") and " R" or ""))
  end
  print("+" .. string.rep("-", W) .. "+ cursor " .. cx + 1 .. "," .. cy + 1)
end

-- the old interpreter leans on the terminal to wrap and scroll, which the new one must never do
local lenient = os.getenv("LENIENT")
local function scroll()
  for y = 0, H - 2 do grid[y] = grid[y + 1]; attr[y] = attr[y + 1] end
  blank_row(H - 1); cy = H - 1
end

term = {}
function term.getSize() return W, H end
function term.clear() clear() end
function term.clearLine() blank_row(cy) end
function term.setCursorBlink() end
function term.getCursorPos() return cx, cy end
function term.setCursorPos(x, y)
  if x < 1 or x > W or y < 1 or y > H then problems[#problems + 1] = "setCursorPos out of range " .. x .. "," .. y end
  cx, cy = math.max(0, math.min(W - 1, x - 1)), math.max(0, math.min(H - 1, y - 1))
end
function term.write(s)
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\27" then
      local a, b, params, fin = s:find("^%[([%d;?]*)(%a)", i + 1)
      assert(a, "bad escape")
      if fin == "m" then
        if params == "" or params == "0" then inverse = false elseif params == "7" then inverse = true end
      elseif fin == "K" then
        for x = cx, W - 1 do grid[cy][x] = " "; attr[cy][x] = false end
      else error("unhandled escape " .. fin) end
      i = b + 1
    elseif c == "\n" then
      if not lenient then problems[#problems + 1] = "newline written to the terminal" end
      cx = 0; cy = cy + 1; i = i + 1
      if cy >= H then
        if not lenient then error("terminal scrolled") end
        scroll()
      end
    elseif c == "\7" or c == "\8" then i = i + 1
    else
      if cx >= W then
        if not lenient then error("terminal wrapped at row " .. cy + 1 .. " writing " .. s) end
        cx = 0; cy = cy + 1
        if cy >= H then scroll() end
      end
      grid[cy][cx] = c; attr[cy][cx] = inverse
      cx = cx + 1; i = i + 1
    end
  end
end

-- keyboard: lines from the script, then stop
local queue = {}
for line in io.lines(script) do
  local k = line:match("^\\k (.+)$")
  if k then
    if k == "BS" then k = "\8" elseif k == "ENTER" then k = "\n" elseif k == "DUMP" then k = "\0DUMP" end
    queue[#queue + 1] = k
  else
    for ch in line:gmatch(".") do queue[#queue + 1] = ch end
    queue[#queue + 1] = "\n"
  end
end
local qpos = 0
keys = { enter = "\n", backspace = "\8", esc = "\27", up = "\181", down = "\182", left = "\180", right = "\183" }
local Stop = {}
function keys.wait()
  while true do
    qpos = qpos + 1
    local k = queue[qpos]
    if not k then dump("end of script"); error(Stop) end
    if k == "\0DUMP" then dump("dump") else
      if k == "\n" and os.getenv("DUMP_EACH") then dump("before enter") end
      return 1, 0, k
    end
  end
end

local blocks = {}
psram = {}
function psram.alloc(size) blocks[#blocks + 1] = string.rep("\0", size); return #blocks end
function psram.free(h) blocks[h] = nil end
function psram.write(h, off, data) local b = blocks[h]; blocks[h] = b:sub(1, off) .. data .. b:sub(off + #data + 1); return true end
function psram.read(h, off, n) return blocks[h]:sub(off + 1, off + n) end

local function real(path) if path == story then return path end return workdir .. "/" .. path:gsub("^/", "") end
fs = {}
function fs.exists(p) local f = io.open(real(p), "rb"); if f then f:close() return true end return false end
function fs.getSize(p) local f = assert(io.open(real(p), "rb")); local n = f:seek("end"); f:close(); return n end
function fs.delete(p) os.remove(real(p)) end
function fs.open(p, mode)
  local f = io.open(real(p), mode .. "b")
  if not f then error("cannot open " .. p) end
  local h = {}
  function h:read(n) local d = f:read(n or 1); return d end
  function h:write(s) f:write(s) end
  function h:readLine() return f:read("l") end
  function h:close() f:close() end
  function h:flush() f:flush() end
  return h
end
sys = { freeMemory = function() return 0 end }
-- the device resolves /lua/... on its card
local host_loadfile = loadfile
function loadfile(path, ...) return host_loadfile(sdroot .. path, ...) end

-- TRACE=file logs everything the game prints, before any wrapping, to compare interpreters
math.randomseed(42)
if os.getenv("TRACE") then
  local log = assert(io.open(os.getenv("TRACE"), "w"))
  local zio = require("lua/zmachine/io")
  local print_fn = zio.print
  zio.print = function(text) log:write(text); log:flush(); return print_fn(text) end
  local read_line = zio.read_line
  zio.read_line = function(...) local r = read_line(...); log:write("[" .. r .. "]\n"); return r end
end

local zm = require("lua/zmachine/init")
local ok, res, err = pcall(zm.run, story)
if ok and res then dump("game ended")
elseif ok and err ~= Stop then print("zmachine.run failed: " .. tostring(err))
elseif ok then
elseif res ~= Stop then print("ERROR: " .. tostring(res)); dump("at error") end
for _, p in ipairs(problems) do print("PROBLEM: " .. p) end
