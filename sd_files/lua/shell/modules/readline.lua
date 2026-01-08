--[[

  readline.lua - Line editing with history support

  Usage:
    local readline = require("lua/shell/modules/readline")

    -- Simple usage
    local line = readline.read("prompt> ")

    -- With history
    readline.load_history(".my_history")
    local line = readline.read("prompt> ")
    readline.save_history(".my_history")

  Features:
    - Up/Down arrows to navigate history
    - Left/Right arrows to move cursor within line
    - Home/End to jump to start/end of line
    - Backspace/Delete to remove characters
    - Esc to cancel input
]]

local readline = {
  history = {},
  max_history = 100,
}

-- internal state for current input
local state = {
  buffer = "",      -- current input text
  cursor_x = 1,     -- cursor X position (1 = before first char)
  history_pos = 0,  -- 0 = current input, 1+ = history entries
  saved_input = "", -- save current input when browsing history
  prompt = "",      -- the prompt string
  prompt_len = 0,   -- visible length of prompt (without ANSI codes)
}

-- calculate visible string length (strips ANSI escape codes)
local function visible_length(str)
  local stripped = str:gsub("\27%[[%d;]*m", "")
  return #stripped
end

-- get cursor position (convert from 0-based to 1-based for setCursorPos)
local function getCursorLineY()
  local _, y = term.getCursorPos()
  return y + 1  -- term.getCursorPos returns 0-based, setCursorPos expects 1-based
end

-- full redraw - clears line and rewrites everything
-- only called when needed (history nav, 
-- cursor movement edits)
local function full_redraw()

  local y = getCursorLineY()

  -- clear line and rewrite from column 1
  term.setCursorPos(1, y)
  term.clearLine()
  term.write(state.prompt .. state.buffer)

  -- set cursor psition
  local cursor_x = state.prompt_len + state.cursor_x
  term.setCursorPos(cursor_x, y)
end

-- refresh from cursor position to end of line
-- used after inserting/deleting in middle of line
local function refresh_from_cursor()
  local x = state.prompt_len + state.cursor_x
  local y = getCursorLineY()

  -- write from cursor to end of buffer, add space to clear any trailing char
  local after = state.buffer:sub(state.cursor_x)
  term.write(after .. " ")

  -- move cursor back to correct position
  term.setCursorPos(x, y)
end

-- insert character at cursor position
local function insert_char(char)
  if state.cursor_x > #state.buffer then
    -- appending at end, just write the char
    state.buffer = state.buffer .. char
    state.cursor_x = state.cursor_x + 1
    term.write(char)
    full_redraw() -- try to remove cursor pixel erases
  else
    -- inserting in middle - need to refresh
    local before = state.buffer:sub(1, state.cursor_x - 1)
    local after = state.buffer:sub(state.cursor_x)
    state.buffer = before .. char .. after
    state.cursor_x = state.cursor_x + 1

    -- write char and everything after it,
    -- then reposition cursor
    term.write(char .. after)
    term.setCursorPos(state.prompt_len + state.cursor_x, getCursorLineY())
  end
end

-- delete character before cursor (backspace)
local function delete_backward()
  if state.cursor_x > 1 then
    local before = state.buffer:sub(1, state.cursor_x - 2)
    local after = state.buffer:sub(state.cursor_x)
    state.buffer = before .. after
    state.cursor_x = state.cursor_x - 1

    -- move back one, write rest of line,
    -- clear extra
    local new_x = state.prompt_len + state.cursor_x
    local y = getCursorLineY()
    term.setCursorPos(new_x, y)
    term.write(after .. " ")  -- space clears the last char
    term.setCursorPos(new_x, y)
  end
end

-- delete character at cursor (delete key)
local function delete_forward()
  if state.cursor_x <= #state.buffer then
    local before = state.buffer:sub(1, state.cursor_x - 1)
    local after = state.buffer:sub(state.cursor_x + 1)
    state.buffer = before .. after

    -- rewrite from cursor position
    local new_x = state.prompt_len + state.cursor_x
    term.write(after .. " ")  -- Space clears the last char
    term.setCursorPos(new_x, getCursorLineY())
  end
end

-- move cursor left
local function cursor_left()
  if state.cursor_x > 1 then
    state.cursor_x = state.cursor_x - 1
    term.setCursorPos(state.prompt_len + state.cursor_x, getCursorLineY())
  end
end

-- move cursor right
local function cursor_right()
  if state.cursor_x <= #state.buffer then
    state.cursor_x = state.cursor_x + 1
    term.setCursorPos(state.prompt_len + state.cursor_x, getCursorLineY())
  end
end

-- move cursor to start of input
local function cursor_home()
  if state.cursor_x > 1 then
    state.cursor_x = 1
    term.setCursorPos(state.prompt_len + 1, getCursorLineY())
  end
end

-- move cursor to end of input
local function cursor_end()
  if state.cursor_x <= #state.buffer then
    state.cursor_x = #state.buffer + 1
    term.setCursorPos(state.prompt_len + state.cursor_x, getCursorLineY())
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
   return sh:error("Couldn't open '"..filename.."'\n")
  end

  for _, line in ipairs(readline.history) do
    f:writeLine(line)
  end
  f:close()
  term.write("Saved to: " .. filename .." \n")
  return true
end

-- main read function
function readline.read(prompt)
  prompt = prompt or ">"

  -- initialize state
  state.buffer = ""
  state.cursor_x = 1
  state.history_pos = 0
  state.saved_input = ""
  state.prompt = prompt
  state.prompt_len = visible_length(prompt)

  -- show prompt
  term.setCursorBlink(false)
  term.write(prompt)
  term.setCursorBlink(true)
  
  while true do
    local key_state, modifiers, code = keys.wait(true, true)

    -- handle special keys
    if code == keys.enter then
      -- accept input
      print("")  -- move to next line
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

    elseif type(code) == "string" and #code == 1 and keys.isPrintable(code) then
      -- regular printable character
      term.setCursorBlink(false)
      insert_char(code)
      term.setCursorBlink(true)
      
    end
  end
end

return readline
