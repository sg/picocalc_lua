--[[

  readline.lua - line editing with history support

  Usage:
    local readline = require("lua/shell/modules/readline")

    -- simple usage
    local line = readline.read("prompt> ")

    -- with history
    readline.load_history(".my_history")
    local line = readline.read("prompt> ")
    readline.save_history(".my_history")

    -- with tab completion
    local complete_fn = function(buffer, cursor_x)
      -- return completions, replace_start, replace_end
      return {"option1", "option2"}, 1, #buffer
    end
    local line = readline.read("prompt> ", complete_fn)

  Features:
    - Up/Down arrows to navigate history
    - Left/Right arrows to move cursor within line
    - Home/End to jump to start/end of line
    - Backspace/Delete to remove characters
    - Tab completion with callback
    - Esc to cancel input
]]

local readline = {
  history = {},
  max_history = 100,
  max_completions = 50,  -- limit completions for memory
  max_display = 20,      -- max completions to show at once
}

-- blit buffer to display if buffer mode is active
-- called after display updates to make changes visible
local function maybe_blit()
  if _G._buffer_mode_blit then
    draw.blitBuffer()
  end
end

-- internal state for current input
local state = {
  buffer = "",      -- current input text
  cursor_x = 1,     -- cursor X position (1 = before first char)
  history_pos = 0,  -- 0 = current input, 1+ = history entries
  saved_input = "", -- save current input when browsing history
  prompt = "",      -- the prompt string
  prompt_len = 0,   -- visible length of prompt (without ANSI codes)
  complete_fn = nil,      -- completion callback function
  last_tab_buffer = nil,  -- buffer state at last tab press
  tab_count = 0,          -- consecutive tab presses
  start_y = nil,    -- Y position where prompt started
  width = nil,      -- screen width (cached)
}

-- calculate visible string length (strips ANSI escape codes)
local function visible_length(str)
  local stripped = str:gsub("\27%[[%d;]*m", "")
  return #stripped
end

-- calculate wrapped cursor position from linear offset (0-based offset)
local function calc_cursor_pos(total_offset)
  local lines_down = math.floor(total_offset / state.width)
  local x = (total_offset % state.width) + 1
  local y = state.start_y + lines_down
  return x, y
end

-- get cursor offset from start of prompt (0-based)
local function get_cursor_offset()
  return state.prompt_len + state.cursor_x - 1
end

-- adjust start_y if content scrolled the screen
local function handle_scroll_after_write()
  local _, height = term.getSize()
  local end_offset = state.prompt_len + #state.buffer
  local _, end_y = calc_cursor_pos(end_offset)
  if end_y > height then
    state.start_y = state.start_y - (end_y - height)
    if state.start_y < 1 then state.start_y = 1 end
  end
end

-- full redraw - clears all affected lines and rewrites everything
-- only called when needed (history nav, cursor movement edits)
local function full_redraw()
  local _, height = term.getSize()
  local total_len = state.prompt_len + #state.buffer
  local num_lines = math.floor(total_len / state.width) + 1

  -- clear all lines that content spans
  for i = 0, num_lines - 1 do
    local y = state.start_y + i
    if y >= 1 and y <= height then
      term.setCursorPos(1, y)
      term.clearLine()
    end
  end

  -- rewrite from start position
  term.setCursorPos(1, state.start_y)
  term.write(state.prompt .. state.buffer)

  -- handle scroll if we pushed past bottom
  handle_scroll_after_write()

  -- position cursor using wrapped calculation
  local x, y = calc_cursor_pos(get_cursor_offset())
  term.setCursorPos(x, y)
  maybe_blit()
end

-- refresh from cursor position to end of line
-- used after inserting/deleting in middle of line
local function refresh_from_cursor()
  -- write from cursor to end of buffer, add space to clear any trailing char
  local after = state.buffer:sub(state.cursor_x)
  term.write(after .. " ")

  -- handle scroll if we pushed past bottom
  handle_scroll_after_write()

  -- move cursor back to correct position
  local x, y = calc_cursor_pos(get_cursor_offset())
  term.setCursorPos(x, y)
end

-- insert character at cursor position
local function insert_char(char)
  if state.cursor_x > #state.buffer then
    -- appending at end, just write the char
    state.buffer = state.buffer .. char
    state.cursor_x = state.cursor_x + 1
    term.write(char)

    -- handle scroll if we pushed past bottom
    handle_scroll_after_write()

    -- position cursor using wrapped calculation
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
  else
    -- inserting in middle - need to refresh
    local before = state.buffer:sub(1, state.cursor_x - 1)
    local after = state.buffer:sub(state.cursor_x)
    state.buffer = before .. char .. after
    state.cursor_x = state.cursor_x + 1

    -- write char and everything after it
    term.write(char .. after)

    -- handle scroll if we pushed past bottom
    handle_scroll_after_write()

    -- position cursor using wrapped calculation
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
  end
  maybe_blit()
end

-- delete character before cursor (backspace)
local function delete_backward()
  if state.cursor_x > 1 then
    local before = state.buffer:sub(1, state.cursor_x - 2)
    local after = state.buffer:sub(state.cursor_x)
    state.buffer = before .. after
    state.cursor_x = state.cursor_x - 1

    -- position cursor at new location
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)

    -- write rest of line plus space to clear trailing char
    term.write(after .. " ")

    -- reposition cursor
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- delete character at cursor (delete key)
local function delete_forward()
  if state.cursor_x <= #state.buffer then
    local before = state.buffer:sub(1, state.cursor_x - 1)
    local after = state.buffer:sub(state.cursor_x + 1)
    state.buffer = before .. after

    -- write rest of line plus space to clear trailing char
    term.write(after .. " ")

    -- reposition cursor
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- move cursor left
local function cursor_left()
  if state.cursor_x > 1 then
    state.cursor_x = state.cursor_x - 1
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- move cursor right
local function cursor_right()
  if state.cursor_x <= #state.buffer then
    state.cursor_x = state.cursor_x + 1
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- move cursor to start of input
local function cursor_home()
  if state.cursor_x > 1 then
    state.cursor_x = 1
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- move cursor to end of input
local function cursor_end()
  if state.cursor_x <= #state.buffer then
    state.cursor_x = #state.buffer + 1
    local x, y = calc_cursor_pos(get_cursor_offset())
    term.setCursorPos(x, y)
    maybe_blit()
  end
end

-- set buffer content
local function set_buffer(text)
  state.buffer = text
  state.cursor_x = #text + 1  -- cursor at end
  full_redraw()
end

-- navigate history up (older)
local function history_up()
  if #readline.history == 0 then
    return
  end

  -- save current input when starting to browse
  if state.history_pos == 0 then
    state.saved_input = state.buffer
  end

  -- move up in history
  if state.history_pos < #readline.history then
    state.history_pos = state.history_pos + 1
    local idx = #readline.history - state.history_pos + 1
    set_buffer(readline.history[idx])
  end
end

-- navigate history down (newer)
local function history_down()
  if state.history_pos > 0 then
    state.history_pos = state.history_pos - 1

    if state.history_pos == 0 then
      -- restore saved input
      set_buffer(state.saved_input)
    else
      local idx = #readline.history - state.history_pos + 1
      set_buffer(readline.history[idx])
    end
  end
end

-- find longest common prefix among a list of strings
local function find_common_prefix(strings)
  if not strings or #strings == 0 then
    return ""
  end
  if #strings == 1 then
    return strings[1]
  end

  local prefix = strings[1]
  for i = 2, #strings do
    local s = strings[i]
    local j = 1
    while j <= #prefix and j <= #s do
      if prefix:sub(j, j) ~= s:sub(j, j) then
        break
      end
      j = j + 1
    end
    prefix = prefix:sub(1, j - 1)
    if prefix == "" then
      break
    end
  end
  return prefix
end

-- apply completion text to buffer
local function apply_completion(text, start_pos, end_pos)
  local before = state.buffer:sub(1, start_pos - 1)
  local after = state.buffer:sub(end_pos + 1)
  state.buffer = before .. text .. after
  state.cursor_x = start_pos + #text
  full_redraw()
end

-- show multiple completions to the user
local function show_completions(completions)
  local width = term.getSize()

  -- print newline to move below prompt
  print("")

  -- limit display for memory and readability
  local show_count = math.min(#completions, readline.max_display)

  -- calculate column width based on longest entry
  local max_len = 0
  for i = 1, show_count do
    if #completions[i] > max_len then
      max_len = #completions[i]
    end
  end
  max_len = max_len + 2  -- padding

  local cols = math.max(1, math.floor(width / max_len))
  local col = 0

  for i = 1, show_count do
    local entry = completions[i]
    term.write(entry)
    col = col + 1
    if col >= cols then
      print("")
      col = 0
    else
      -- pad to column width
      local pad = max_len - #entry
      if pad > 0 then
        term.write(string.rep(" ", pad))
      end
    end
  end

  -- show "and N more" if truncated
  if #completions > readline.max_display then
    if col > 0 then print("") end
    term.write("... and " .. (#completions - readline.max_display) .. " more\n")
  elseif col > 0 then
    print("")
  end

  -- redraw prompt and buffer
  term.write(state.prompt .. state.buffer)

  -- recalculate start_y since we're on a new line after showing completions
  local _, cur_y = term.getCursorPos()
  cur_y = cur_y + 1  -- convert from 0-based to 1-based
  local total_len = state.prompt_len + #state.buffer
  local lines_used = math.floor(total_len / state.width)
  state.start_y = cur_y - lines_used

  local x, y = calc_cursor_pos(get_cursor_offset())
  term.setCursorPos(x, y)

  collectgarbage()
  maybe_blit()
end

-- handle tab completion
local function handle_completion()
  if not state.complete_fn then
    return
  end

  -- track consecutive tabs on same buffer
  if state.buffer == state.last_tab_buffer then
    state.tab_count = state.tab_count + 1
  else
    state.tab_count = 1
    state.last_tab_buffer = state.buffer
  end

  -- call completion function
  local completions, replace_start, replace_end = state.complete_fn(state.buffer, state.cursor_x)

  if not completions or #completions == 0 then
    return
  end

  -- limit completions for memory
  if #completions > readline.max_completions then
    local limited = {}
    for i = 1, readline.max_completions do
      limited[i] = completions[i]
    end
    completions = limited
  end

  if #completions == 1 then
    -- single match: insert it
    apply_completion(completions[1], replace_start, replace_end)
    state.last_tab_buffer = state.buffer  -- update for next tab
  else
    -- multiple matches
    local prefix = find_common_prefix(completions)
    local current = state.buffer:sub(replace_start, replace_end)

    if #prefix > #current then
      -- extend with common prefix
      apply_completion(prefix, replace_start, replace_end)
      state.last_tab_buffer = state.buffer
    elseif state.tab_count >= 2 then
      -- second tab: show options
      show_completions(completions)
    end
  end
end

-- add entry to history
function readline.add_history(line)
  if not line or line == "" then
    return
  end

  -- don't add duplicates of the last entry
  if #readline.history > 0 and readline.history[#readline.history] == line then
    return
  end

  table.insert(readline.history, line)

  -- trim history if too long
  while #readline.history > readline.max_history do
    table.remove(readline.history, 1)
  end
end

-- clear history
function readline.clear_history()
  readline.history = {}
end

-- load history from file
function readline.load_history(filename)
  if not fs.exists(filename) then
    return false
  end

  local f = fs.open(filename, "r")
  if not f then
    return false
  end

  readline.history = {}
  while true do
    local line = f:readLine()
    if not line then
      break
    end
    table.insert(readline.history, line)
  end
  f:close()

  -- trim if loaded file was too long
  while #readline.history > readline.max_history do
    table.remove(readline.history, 1)
  end

  return true
end

-- save history to file
function readline.save_history(filename)
  term.write("Saving command history...\n")
  local f = fs.open(filename, "w")
  if not f then
    term.write("Error: Couldn't open '" .. filename .. "'\n")
    return false
  end

  for _, line in ipairs(readline.history) do
    f:writeLine(line)
  end
  f:flush()  -- ensure data is written to SD card before closing
  f:close()
  term.write("Saved to: " .. filename .. "\n")
  return true
end

-- main read function
-- complete_fn(buffer, cursor_x) should return: completions, replace_start, replace_end
function readline.read(prompt, complete_fn)
  prompt = prompt or ">"

  -- initialize state
  state.buffer = ""
  state.cursor_x = 1
  state.history_pos = 0
  state.saved_input = ""
  state.prompt = prompt
  state.prompt_len = visible_length(prompt)
  state.complete_fn = complete_fn
  state.last_tab_buffer = nil
  state.tab_count = 0

  -- cache screen width
  state.width = term.getSize()

  -- show prompt
  term.setCursorBlink(false)
  term.write(prompt)
  term.setCursorBlink(true)

  -- capture starting Y position (accounting for prompt wrap)
  local _, cur_y = term.getCursorPos()
  cur_y = cur_y + 1  -- convert from 0-based to 1-based
  local prompt_lines = math.floor((state.prompt_len - 1) / state.width)
  state.start_y = cur_y - prompt_lines
  maybe_blit()

  while true do
    local key_state, modifiers, code = keys.wait(true, true)

    -- handle special keys
    if code == keys.enter then
      -- accept input
      term.write("\n")  -- move to next line
      return state.buffer

    elseif code == keys.backspace then
      delete_backward()

    elseif code == keys.delete then
      delete_forward()

    elseif code == keys.left then
      cursor_left()

    elseif code == keys.right then
      cursor_right()

    elseif code == keys.up then
      history_up()

    elseif code == keys.down then
      history_down()

    elseif code == keys.home then
      cursor_home()

    elseif code == keys["end"] then
      cursor_end()

    elseif code == keys.esc then
      -- cancel input
      print("")
      return nil

    elseif code == keys.tab then
      -- tab completion
      handle_completion()

    elseif type(code) == "string" and #code == 1 and keys.isPrintable(code) then
      -- regular printable character
      term.setCursorBlink(false)
      insert_char(code)
      term.setCursorBlink(true)
      
    end
  end
end

return readline
