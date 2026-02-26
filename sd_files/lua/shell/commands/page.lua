--[[

  page.lua - Bidirectional scrolling file viewer
             Similar to 'less'

  Controls:
    Arrow Down   - Scroll one line down
    Arrow Up     - Scroll one line up
    Space        - Scroll one page down
    b            - Scroll one page up
    PageUp       - Page up
    PageDown     - Page down
    Home         - Jump to start
    End          - Jump to end
    Q / Esc      - Quit

  Memory-efficient: Uses line offset index and windowed buffer
  to support bidirectional scrolling without loading entire file.

]]

-- ANSI escape codes
local ESC = "\27["
local RESET = ESC .. "0m"
local DIM = ESC .. "2m"
local CLEAR_LINE = ESC .. "K"
local COLOR = {
  cyan    = ESC .. "96m",
  green   = ESC .. "92m",
  yellow  = ESC .. "93m",
  white   = ESC .. "97m",
}

-- Configuration
local INDEX_INTERVAL = 50    -- record byte offset every N source lines
local BUFFER_SCREENS = 3     -- keep this many screens of lines in buffer

-- viewer state
local state = {
  -- file info
  fspath = "",
  total_source_lines = 0,
  total_display_lines = 0,

  -- line index: array of {offset=byte_pos, source_line=n, display_line=n}
  -- recorded every INDEX_INTERVAL source lines
  index = {},

  -- buffer window
  buffer_start_display = 0,  -- first display line in buffer (0-based)
  buffer = {},               -- display lines currently loaded

  -- viewport
  scroll = 0,          -- first visible display line (0-based, absolute)
  width = 52,
  height = 40,
}

-- word wrap a string to fit within max_width
-- returns a table of wrapped lines
-- uses position tracking to avoid intermediate substring garbage
local function word_wrap(str, max_width)
  if not str or str == "" then
    return {""}
  end

  local len = #str
  if len <= max_width then
    return {str}
  end

  local lines = {}
  local pos = 1

  while pos <= len do
    if len - pos + 1 <= max_width then
      table.insert(lines, str:sub(pos))
      break
    end

    local space_pos = nil
    local search_end = pos + max_width - 1
    for i = search_end, pos, -1 do
      if str:byte(i) == 32 then
        space_pos = i
        break
      end
    end

    if space_pos and space_pos > pos then
      table.insert(lines, str:sub(pos, space_pos - 1))
      pos = space_pos + 1
    else
      table.insert(lines, str:sub(pos, pos + max_width - 1))
      pos = pos + max_width
    end
  end

  return lines
end

-- count how many display lines a source line produces
-- uses position tracking and str:byte() to avoid creating any strings
local function count_wrapped_lines(str, max_width)
  if not str or str == "" then
    return 1
  end
  local len = #str
  if len <= max_width then
    return 1
  end

  local count = 0
  local pos = 1

  while pos <= len do
    if len - pos + 1 <= max_width then
      count = count + 1
      break
    end

    local space_pos = nil
    local search_end = pos + max_width - 1
    for i = search_end, pos, -1 do
      if str:byte(i) == 32 then
        space_pos = i
        break
      end
    end

    if space_pos and space_pos > pos then
      pos = space_pos + 1
    else
      pos = pos + max_width
    end
    count = count + 1
  end

  return count
end

-- get content height (reserve 1 for status bar)
local function content_height()
  return state.height - 1
end

-- get buffer capacity in display lines
local function buffer_capacity()
  return content_height() * BUFFER_SCREENS
end

-- build index by scanning file
-- records byte offset every INDEX_INTERVAL source lines
local function build_index(fspath)
  state.index = {}
  state.total_source_lines = 0
  state.total_display_lines = 0

  local wrap_width = state.width - 1
  local f = fs.open(fspath, "r")
  if not f then
    return false, "Cannot open file"
  end

  local source_line = 0
  local display_line = 0

  -- record first position
  table.insert(state.index, {
    offset = 0,
    source_line = 0,
    display_line = 0,
  })

  while true do
    local line = f:readLine()
    if not line then
      break
    end

    -- count display lines using actual word wrap logic
    local wrapped_count = count_wrapped_lines(line, wrap_width)

    source_line = source_line + 1
    display_line = display_line + wrapped_count

    -- record index entry every INDEX_INTERVAL lines
    -- use actual file position instead of calculating manually
    if source_line % INDEX_INTERVAL == 0 then
      local current_pos = f:seek("cur", 0)  -- get current position
      table.insert(state.index, {
        offset = current_pos,
        source_line = source_line,
        display_line = display_line,
      })
      collectgarbage("collect")
    end
  end

  f:close()

  state.total_source_lines = source_line
  state.total_display_lines = display_line

  return true
end

-- find the best index entry to start loading from for a given display line
local function find_index_entry(target_display_line)
  local best = state.index[1]
  for _, entry in ipairs(state.index) do
    if entry.display_line <= target_display_line then
      best = entry
    else
      break
    end
  end
  return best
end

-- load buffer starting from near a target display line
local function load_buffer(target_display_line)
  -- find best starting index entry
  local entry = find_index_entry(target_display_line)

  local f = fs.open(state.fspath, "r")
  if not f then
    return false
  end

  -- seek to the indexed position
  if entry.offset > 0 then
    f:seek("set", entry.offset)
  end

  local wrap_width = state.width - 1
  local capacity = buffer_capacity()

  state.buffer = {}
  collectgarbage("collect")
  state.buffer_start_display = entry.display_line

  local lines_loaded = 0

  -- load lines until buffer is full or EOF
  while lines_loaded < capacity do
    local line = f:readLine()
    if not line then
      break
    end

    local wrapped = word_wrap(line, wrap_width)
    for _, wline in ipairs(wrapped) do
      table.insert(state.buffer, wline)
      lines_loaded = lines_loaded + 1
      if lines_loaded >= capacity then
        break
      end
    end
  end

  f:close()
  return true
end

-- check if display line is within current buffer
local function is_in_buffer(display_line)
  local buf_end = state.buffer_start_display + #state.buffer
  return display_line >= state.buffer_start_display and display_line < buf_end
end

-- ensure the viewport is covered by buffer, reload if needed
local function ensure_buffer_covers_viewport()
  local view_start = state.scroll
  local view_end = state.scroll + content_height()

  -- check if viewport is within buffer with some margin
  -- we want at least a few lines of padding on each end
  local margin = 5
  local buf_end = state.buffer_start_display + #state.buffer

  local start_ok = view_start >= state.buffer_start_display + margin or view_start < margin
  local end_ok = view_end <= buf_end - margin or view_end >= state.total_display_lines - margin

  if start_ok and end_ok and is_in_buffer(view_start) and is_in_buffer(view_end - 1) then
    return  -- buffer adequately covers viewport
  end

  -- need to reload - load from well before view_start
  local target = math.max(0, view_start - content_height())
  load_buffer(target)

  -- verify we actually cover the viewport now, if not try from earlier
  if not is_in_buffer(view_start) or not is_in_buffer(view_end - 1) then
    collectgarbage("collect")
    load_buffer(math.max(0, view_start - content_height() * 2))
  end
end

-- get a display line from buffer (absolute display line index, 0-based)
local function get_display_line(display_line)
  local buf_idx = display_line - state.buffer_start_display + 1
  if buf_idx >= 1 and buf_idx <= #state.buffer then
    return state.buffer[buf_idx]
  end
  return nil
end

-- clamp scroll to valid range
local function clamp_scroll()
  local max_scroll = math.max(0, state.total_display_lines - content_height())
  state.scroll = math.max(0, math.min(state.scroll, max_scroll))
end

-- scroll by n lines
local function scroll_by(n)
  state.scroll = state.scroll + n
  clamp_scroll()
  ensure_buffer_covers_viewport()
end

-- scroll by one page
local function scroll_page(direction)
  scroll_by(direction * content_height())
end

-- draw status bar
local function draw_status_bar()
  term.setCursorPos(1, state.height)

  local ch = content_height()
  local total = state.total_display_lines

  local top_line = state.scroll + 1
  local bot_line = math.min(state.scroll + ch, total)

  local pct = 0
  if total > 0 then
    if total <= ch then
      pct = 100
    else
      pct = math.floor((state.scroll + ch) / total * 100)
    end
  end

  local left = string.format(" %d-%d/%d (%d%%)", top_line, bot_line, total, pct)

  local free_mem = sys.freeMemory()
  local mem_str = ""
  if free_mem then
    mem_str = string.format("Mem: %dK ", math.floor(free_mem / 1024))
  end
  local right = mem_str .. "[b/Space]Pg [q]Quit"

  local padding = state.width - #left - #right - 1
  if padding < 0 then
    right = ""
    padding = 0
  end

  term.write(COLOR.cyan)
  term.write(left)
  term.write(string.rep(" ", padding))
  term.write(DIM)
  term.write(right)
  term.write(RESET)
  term.write(CLEAR_LINE)
end

-- draw content area
-- uses sequential term.write() calls to avoid concatenation garbage
local function draw_content()
  local ch = content_height()
  local white = COLOR.white

  for y = 1, ch do
    term.setCursorPos(1, y)
    local line_idx = state.scroll + y - 1  -- 0-based

    local line = get_display_line(line_idx)
    if line then
      term.write(" ")
      term.write(white)
      term.write(line)
      term.write(RESET)
      term.write(CLEAR_LINE)
    else
      term.write(CLEAR_LINE)
    end
  end
end

-- full redraw
local function redraw()
  draw_content()
  draw_status_bar()
  collectgarbage("collect")
end

-- handle keyboard input
local function handle_input()
  local key_state, modifiers, code = keys.wait(true, true)

  if code == "q" or code == "Q" or code == keys.esc then
    return false
  end

  if code == keys.up then
    scroll_by(-1)
    redraw()

  elseif code == keys.down then
    scroll_by(1)
    redraw()

  elseif code == " " then
    scroll_page(1)
    redraw()

  elseif code == "b" or code == "B" then
    scroll_page(-1)
    redraw()

  elseif code == keys.pageUp then
    scroll_page(-1)
    redraw()

  elseif code == keys.pageDown then
    scroll_page(1)
    redraw()

  elseif code == keys.home then
    state.scroll = 0
    ensure_buffer_covers_viewport()
    redraw()

  elseif code == keys["end"] then
    state.scroll = math.max(0, state.total_display_lines - content_height())
    ensure_buffer_covers_viewport()
    redraw()
  end

  return true
end

return {
  name = "page",
  category = "util",
  aliases = {"less", "more"},
  help = COLOR.cyan .. "page" .. COLOR.yellow .. " <file>" .. COLOR.white .. " - view file with scrolling",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: page <file>")
    end

    local path = sh:resolve_path(args[1])
    local fspath = sh:fs_path(path)

    if not fs.exists(fspath) then
      return sh:error("'" .. args[1] .. "' not found")
    end

    if fs.isDir(fspath) then
      return sh:error("'" .. args[1] .. "' is a directory")
    end

    -- turn off cursor blink
    term.setCursorBlink(false)

    -- get terminal dimensions
    state.width, state.height = term.getSize()
    state.fspath = fspath
    state.scroll = 0

    -- build line index (first pass through file)
    print("Indexing file...")
    local ok, err = build_index(fspath)
    if not ok then
      return sh:error(err)
    end

    -- check for empty file
    if state.total_display_lines == 0 then
      print("(empty file)")
      return
    end

    -- report index size for very large files
    if #state.index > 100 then
      print(string.format("Indexed %d lines (%d bookmarks)",
        state.total_source_lines, #state.index))
    end

    -- load initial buffer
    load_buffer(0)

    -- initial display
    term.clear()
    redraw()

    -- main loop
    while handle_input() do
      -- continue
    end

    -- cleanup
    term.clear()
    term.setCursorPos(1, 1)
    -- turn cursor blink back on
    term.setCursorBlink(true)

  end
}
