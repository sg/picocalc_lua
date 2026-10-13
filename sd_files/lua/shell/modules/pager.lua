--[[

  pager.lua - scrolling viewer shared by the page command
              and by commands run with -p

  pager.view(store)         interactive viewer over a store
  pager.file_store(fspath)  store over a file, indexed so it
                            scrolls both ways without holding
                            the file in memory
  pager.run(fn, ...)        calls fn(...) with print and
                            term.write captured; output that
                            fits on one screen is printed as
                            is, longer output opens the viewer
  pager.wrap(line, width)   display lines for one source line

  A store serves 0-based display lines already wrapped to the
  screen width:
    first()           lowest line still available
    total()           lines produced so far
    at_end()          true once no more lines can appear
    ensure(from, to)  make lines from..to available if possible
    line(i)           display line i, or nil
    close()           release the source

  The run store pulls lines from the command on demand: the
  command runs inside a coroutine and each line it prints is
  yielded to the viewer, which keeps only a window of recent
  lines. Memory stays flat however much the command prints,
  and quitting closes the coroutine, so files the command had
  open are closed with it.

  Controls:
    Down / Enter        scroll one line down
    Up                  scroll one line up
    Space / PageDown    scroll one page down
    b / PageUp          scroll one page up
    Home                jump to the first line still held
    End                 jump to the end (runs the command to
                        completion under -p)
    q / Esc             quit

]]

local ESC = "\27["
local RESET = ESC .. "0m"
local DIM = ESC .. "2m"
local CLEAR_LINE = ESC .. "K"
local CYAN = ESC .. "96m"
local WHITE = ESC .. "97m"

local INDEX_INTERVAL = 50   -- source lines between recorded file offsets
local WINDOW_SCREENS = 3    -- display lines held in memory, in screens

local pager = {}

-- wrapping ---------------------------------------------------------------

-- a CSI escape sequence; colour codes take no columns, others are dropped
local CSI = "\27%[[%d;]*%a"

local function last_space(str, from, to)
  for i = to, from, -1 do
    if str:byte(i) == 32 then return i end
  end
end

-- split a plain line at spaces into pieces of at most max_width columns;
-- pieces are appended to out when given, the count is returned either way
local function wrap_plain(str, max_width, out)
  local len = #str
  local pos, count = 1, 0
  while true do
    if len - pos + 1 <= max_width then
      if out then out[#out + 1] = pos == 1 and str or str:sub(pos) end
      return count + 1
    end
    local stop = pos + max_width - 1
    local next_pos = stop + 1
    -- a space just past the piece is the ideal break, one at its start is useless
    local sp = last_space(str, pos + 1, math.min(stop + 1, len))
    if sp then stop, next_pos = sp - 1, sp + 1 end
    if out then out[#out + 1] = str:sub(pos, stop) end
    count = count + 1
    pos = next_pos
  end
end

-- the same for a line holding escape sequences: the current colour is
-- restarted on every continuation piece
local function wrap_escaped(str, max_width, out)
  local len = #str
  local pieces, width, colour = {}, 0, nil
  local pos, count = 1, 0

  local function flush()
    if out then out[#out + 1] = table.concat(pieces) end
    count = count + 1
    pieces, width = { colour }, 0
  end

  while pos <= len do
    local s, e = str:find(CSI, pos)
    local text_end = (s or len + 1) - 1
    while pos <= text_end do
      local room = max_width - width
      local remaining = text_end - pos + 1
      if remaining <= room then
        pieces[#pieces + 1] = str:sub(pos, text_end)
        width = width + remaining
        pos = text_end + 1
      else
        local stop = pos + room - 1
        local next_pos = stop + 1
        local sp = last_space(str, pos + 1, math.min(stop + 1, text_end))
        if sp then stop, next_pos = sp - 1, sp + 1 end
        pieces[#pieces + 1] = str:sub(pos, stop)
        flush()
        pos = next_pos
      end
    end
    if s then
      if str:byte(e) == 109 then
        colour = str:sub(s, e)
        pieces[#pieces + 1] = colour
      end
      pos = e + 1
    end
  end

  -- trailing colour codes alone do not deserve a line of their own
  if width > 0 or count == 0 then
    if out then out[#out + 1] = table.concat(pieces) end
    count = count + 1
  end
  return count
end

-- display lines for one source line; only the count when out is nil
local function wrap(str, max_width, out)
  -- the CR of a CRLF file would move the cursor when drawn
  if str:byte(-1) == 13 then str = str:sub(1, -2) end
  if str:find("\27", 1, true) then
    return wrap_escaped(str, max_width, out)
  end
  return wrap_plain(str, max_width, out)
end

function pager.wrap(str, max_width)
  local out = {}
  wrap(str, max_width, out)
  return out
end

-- file store -------------------------------------------------------------

function pager.file_store(fspath)
  local width, height = term.getSize()
  local wrap_width = width - 1
  local screen = height - 1
  local window = screen * WINDOW_SCREENS

  -- display line number at a byte offset, every INDEX_INTERVAL source lines
  local index = { { offset = 0, display = 0 } }
  local total = 0
  do
    local f <close> = fs.open(fspath, "r")
    local source = 0
    while true do
      local line = f:readLine()
      if not line then break end
      source = source + 1
      total = total + wrap(line, wrap_width)
      if source % INDEX_INTERVAL == 0 then
        index[#index + 1] = { offset = f:seek("cur"), display = total }
      end
    end
  end

  local buffer, buffer_start = {}, 0

  -- refill the buffer so it starts at display line start
  local function load(start)
    local entry = index[1]
    for i = 2, #index do
      if index[i].display > start then break end
      entry = index[i]
    end

    local f <close> = fs.open(fspath, "r")
    if entry.offset > 0 then f:seek("set", entry.offset) end
    buffer, buffer_start = {}, start

    local pieces = {}
    local at = entry.display
    while #buffer < window do
      local line = f:readLine()
      if not line then break end
      local n = wrap(line, wrap_width, pieces)
      for k = 1, n do
        if at >= start and #buffer < window then
          buffer[#buffer + 1] = pieces[k]
        end
        at = at + 1
        pieces[k] = nil
      end
    end
  end

  local store = {}
  function store:first() return 0 end
  function store:total() return total end
  function store:at_end() return true end
  function store:line(i) return buffer[i - buffer_start + 1] end
  function store:close() buffer = {} end

  function store:ensure(from, to)
    if to >= total then to = total - 1 end
    if to < from then return end
    if from < buffer_start or to >= buffer_start + #buffer then
      -- start a screen earlier so scrolling back does not reload at once
      load(math.max(0, from - screen))
    end
  end

  return store
end

-- run store --------------------------------------------------------------

local function run_store(fn, ...)
  local width, height = term.getSize()
  local wrap_width = width - 1
  local window = (height - 1) * WINDOW_SCREENS

  local lines, first = {}, 0
  local pending = ""            -- text since the last newline the command wrote
  local done, ok, result = false, true, nil
  local real_print, real_write

  local nargs = select("#", ...)
  local args = { ... }
  local co = coroutine.create(function()
    return fn(table.unpack(args, 1, nargs))
  end)

  -- hand complete lines to the viewer; where a yield is impossible, such
  -- as inside a gsub callback, the text goes straight to the screen
  local function emit(text)
    pending = pending .. text
    local start = 1
    while true do
      local nl = pending:find("\n", start, true)
      if not nl then break end
      local line = pending:sub(start, nl - 1)
      start = nl + 1
      if coroutine.isyieldable() then
        coroutine.yield(line)
      else
        real_write(line .. "\n")
      end
    end
    if start > 1 then pending = pending:sub(start) end
  end

  local function captured_print(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring((select(i, ...)))
    end
    emit(table.concat(parts, "\t") .. "\n")
  end

  local function captured_write(text)
    emit(tostring(text))
  end

  -- the redirection is only in place while the command itself runs
  local function resume()
    real_print, real_write = print, term.write
    print, term.write = captured_print, captured_write
    local alive, value = coroutine.resume(co)
    print, term.write = real_print, real_write
    return alive, value
  end

  -- advance the command until it has produced another line
  local function pull()
    if done then return false end
    local alive, value = resume()
    if not alive then
      done, ok, result = true, false, debug.traceback(co, tostring(value))
      return false
    end
    if coroutine.status(co) == "dead" then
      done, result = true, value
      if pending == "" then return false end
      value, pending = pending, ""
    end
    wrap(value, wrap_width, lines)
    return true
  end

  -- forget the oldest lines once the window is full, never ones at or past keep
  local function trim(keep)
    local n = #lines
    local drop = math.min(n - window, keep - first)
    if drop > 0 then
      table.move(lines, drop + 1, n, 1)
      for i = n - drop + 1, n do lines[i] = nil end
      first = first + drop
    end
  end

  local store = {}
  function store:first() return first end
  function store:total() return first + #lines end
  function store:at_end() return done end
  function store:line(i) return lines[i - first + 1] end
  function store:result() return ok, result end

  function store:ensure(from, to)
    while first + #lines <= to and pull() do
      trim(from)
    end
    trim(from)
  end

  function store:close()
    if not done then
      done = true
      local closed, err = coroutine.close(co)
      if not closed then ok, result = false, tostring(err) end
    end
    lines = {}
  end

  return store
end

-- viewer -----------------------------------------------------------------

function pager.view(store)
  local width, height = term.getSize()
  local content = height - 1
  local scroll = store:first()

  local function go(target)
    if target < store:first() then target = store:first() end
    store:ensure(target, target + content - 1)
    local max_scroll = math.max(store:first(), store:total() - content)
    if target > max_scroll then target = max_scroll end
    scroll = target
    store:ensure(scroll, scroll + content - 1)
  end

  local function draw()
    for y = 1, content do
      term.setCursorPos(1, y)
      local line = store:line(scroll + y - 1)
      if line then
        term.write(" " .. WHITE .. line .. RESET .. CLEAR_LINE)
      else
        term.write(CLEAR_LINE)
      end
    end

    local total = store:total()
    local top = scroll + 1
    local bottom = math.min(scroll + content, total)
    local left
    if store:at_end() then
      local pct = total <= content and 100 or bottom * 100 // total
      left = string.format(" %d-%d/%d (%d%%)", top, bottom, total, pct)
    else
      left = string.format(" %d-%d/%d+", top, bottom, total)
    end
    local right = "[b/Space]Pg [q]Quit"
    if sys and sys.freeMemory then
      right = string.format("Mem: %dK ", sys.freeMemory() // 1024) .. right
    end
    local padding = width - #left - #right - 1
    if padding < 0 then right, padding = "", 0 end
    term.setCursorPos(1, height)
    term.write(CYAN .. left .. string.rep(" ", padding) .. DIM .. right .. RESET .. CLEAR_LINE)
  end

  local actions = {
    [keys.down] = function() go(scroll + 1) end,
    [keys.enter] = function() go(scroll + 1) end,
    [keys.up] = function() go(scroll - 1) end,
    [" "] = function() go(scroll + content) end,
    [keys.pageDown] = function() go(scroll + content) end,
    ["b"] = function() go(scroll - content) end,
    ["B"] = function() go(scroll - content) end,
    [keys.pageUp] = function() go(scroll - content) end,
    [keys.home] = function() go(store:first()) end,
    [keys["end"]] = function() go(math.huge) end,
  }

  local function loop()
    go(scroll)
    draw()
    while true do
      local _, _, code = keys.wait(true, true)
      if code == "q" or code == "Q" or code == keys.esc then return end
      local action = actions[code]
      if action then
        action()
        draw()
      end
    end
  end

  term.setCursorBlink(false)
  term.clear()
  local finished, err = pcall(loop)
  term.clear()
  term.setCursorPos(1, 1)
  term.setCursorBlink(true)
  if not finished then error(err, 0) end
end

-- run fn(...) with its output paged; returns like pcall(fn, ...)
function pager.run(fn, ...)
  local _, height = term.getSize()
  local content = height - 1
  local store = run_store(fn, ...)

  -- one line more than a screen tells short output from long
  store:ensure(0, content)
  if store:at_end() and store:total() <= content then
    for i = 0, store:total() - 1 do
      term.write(store:line(i) .. "\n")
    end
  else
    pager.view(store)
  end
  store:close()
  return store:result()
end

return pager
