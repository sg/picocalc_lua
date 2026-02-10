--[[

  irc/ui.lua - IRC Terminal UI

  Handles screen layout and display for the IRC client.

  Screen regions:
    Row 1: Status bar (server, channel, nick, user count)
    Rows 2 to height-2: Message area
    Rows height-1 to height: Input area

  Usage:
    local UI = require("lua/modules/irc/ui")
    local ui = UI.new(client)
    ui:init()
    ui:add_message("nick", "Hello!", "msg")
    ui:refresh()

]]

local UI = {}
UI.__index = UI

-- Debug logger (loaded on demand)
local Debug = nil

-- Message type colors
local MSG_COLORS = {
  msg = colors.white,
  action = colors.magenta,
  notice = colors.yellow,
  system = colors.cyan,
  join = colors.green,
  part = colors.red,
  quit = colors.red,
  kick = colors.red,
  nick = colors.cyan,
  error = colors.red,
  private = colors.lightBlue,
  topic = colors.yellow,
}

-- Create new UI instance
function UI.new(client)
  local self = setmetatable({
    client = client,
    width = 0,
    height = 0,
    scroll_offset = 0,
    message_buffer = {},   -- { {time, nick, text, type, channel}, ... }
    max_messages = 20,     -- keep last 20 messages (memory constrained)
    input_buffer = "",
    input_cursor = 1,
    input_history = {},
    history_pos = 0,
    saved_input = "",
    needs_redraw = true,
    show_all_channels = false,  -- when true, show messages from all channels
  }, UI)

  return self
end

-- Set debug logger (called from main irc.lua)
function UI.set_debug(debug_module)
  Debug = debug_module
end

-- Initialize the UI
function UI:init()
  -- Get terminal dimensions
  self.width, self.height = term.getSize()

  -- Clear screen and set up
  term.clear()
  term.setCursorPos(1, 1)
  term.setCursorBlink(true)

  -- Initial draw
  self:refresh()
end

-- Cleanup the UI
function UI:cleanup()
  term.setCursorBlink(false)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
end

-- Draw status bar (rows 1-2)
function UI:draw_status_bar()
  local old_bg = term.getBackgroundColor()
  local old_fg = term.getTextColor()

  local client = self.client

  -- Row 1: Server | Channel | User count
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.clearLine()

  local row1_parts = {}

  -- Server info
  if client.connected then
    table.insert(row1_parts, client.server)
  else
    table.insert(row1_parts, "disconnected")
  end

  -- Current channel
  if client.current_channel then
    table.insert(row1_parts, client.current_channel)
  else
    table.insert(row1_parts, "(no channel)")
  end

  -- User count in current channel
  local user_count = client:get_user_count()
  if user_count > 0 then
    table.insert(row1_parts, "Users: " .. user_count)
  end

  local row1 = table.concat(row1_parts, " | ")
  if #row1 > self.width then
    row1 = row1:sub(1, self.width - 3) .. "..."
  end
  term.write(row1)
  local remaining = self.width - #row1
  if remaining > 0 then
    term.write(string.rep(" ", remaining))
  end

  -- Row 2: Nick | Channel flags | Free memory
  term.setCursorPos(1, 2)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.clearLine()

  local row2_parts = {}

  -- Nick
  table.insert(row2_parts, client.current_nick)

  -- Channel flags/modes
  if client.current_channel and client.channels[client.current_channel] then
    local modes = client.channels[client.current_channel].modes or ""
    if modes ~= "" then
      table.insert(row2_parts, "+" .. modes)
    end
  end

  -- Free memory
  local free_mem = sys.freeMemory()
  if free_mem then
    -- Convert to KB for readability
    local free_kb = math.floor(free_mem / 1024)
    table.insert(row2_parts, "Mem: " .. free_kb .. "K")
  end

  local row2 = table.concat(row2_parts, " | ")
  if #row2 > self.width then
    row2 = row2:sub(1, self.width - 3) .. "..."
  end
  term.write(row2)
  remaining = self.width - #row2
  if remaining > 0 then
    term.write(string.rep(" ", remaining))
  end

  term.setBackgroundColor(old_bg)
  term.setTextColor(old_fg)
end

-- Check if a message should be visible in current view
function UI:is_message_visible(msg)
  local current_channel = self.client.current_channel
  -- Show message if:
  -- - show_all_channels is true
  -- - It's a system message (no channel)
  -- - It's for the current channel
  -- - It's a private message
  return self.show_all_channels
     or not msg.channel
     or msg.channel == current_channel
     or msg.type == "private"
     or msg.type == "system"
end

-- Format a message into its display prefix and text
function UI:format_message(msg)
  local prefix = ""
  local text = msg.text or ""

  if msg.type == "action" then
    prefix = "* " .. msg.nick .. " "
  elseif msg.type == "join" then
    prefix = "--> "
    text = msg.nick .. " has joined " .. (msg.channel or "")
  elseif msg.type == "part" then
    prefix = "<-- "
    text = msg.nick .. " has left " .. (msg.channel or "")
    if msg.text and msg.text ~= "" then
      text = text .. " (" .. msg.text .. ")"
    end
  elseif msg.type == "quit" then
    prefix = "<-- "
    text = msg.nick .. " has quit"
    if msg.text and msg.text ~= "" then
      text = text .. " (" .. msg.text .. ")"
    end
  elseif msg.type == "kick" then
    prefix = "*** "
  elseif msg.type == "nick" then
    prefix = "--- "
    text = msg.nick .. " is now known as " .. msg.text
  elseif msg.type == "notice" then
    prefix = "-" .. msg.nick .. "- "
  elseif msg.type == "system" then
    prefix = "*** "
  elseif msg.type == "error" then
    prefix = "!!! "
  elseif msg.type == "private" then
    prefix = "[" .. msg.nick .. "] "
  elseif msg.type == "topic" then
    prefix = "*** Topic: "
  elseif msg.type == "msg" then
    prefix = "<" .. msg.nick .. "> "
  end

  return prefix, text
end

-- Word-wrap text to fit within width, returns array of lines
function UI:wrap_text(prefix, text, width)
  local lines = {}
  local prefix_len = #prefix
  local first_line_width = width - prefix_len
  local cont_width = width - 2  -- continuation lines indented by 2

  if first_line_width < 10 then first_line_width = width end
  if cont_width < 10 then cont_width = width end

  -- Handle empty text
  if not text or text == "" then
    table.insert(lines, {prefix = prefix, text = ""})
    return lines
  end

  local remaining = text
  local is_first = true

  while #remaining > 0 do
    local line_width = is_first and first_line_width or cont_width
    local line_prefix = is_first and prefix or "  "

    if #remaining <= line_width then
      -- Fits on this line
      table.insert(lines, {prefix = line_prefix, text = remaining})
      break
    else
      -- Need to wrap - find a good break point
      local break_at = line_width

      -- Look for space to break at (search backwards from line_width)
      for i = line_width, math.max(1, line_width - 20), -1 do
        if remaining:sub(i, i) == " " then
          break_at = i
          break
        end
      end

      local line_text = remaining:sub(1, break_at)
      remaining = remaining:sub(break_at + 1)

      -- Trim leading space from remaining
      remaining = remaining:gsub("^%s+", "")

      table.insert(lines, {prefix = line_prefix, text = line_text})
    end

    is_first = false
  end

  return lines
end

-- Calculate how many display lines a message takes (with caching)
-- Uses actual wrap_text to ensure count matches display
function UI:get_message_line_count(msg)
  -- Cache line count to avoid repeated wrap calculations
  -- Cache key includes width in case terminal resizes
  local cache_key = self.width
  if msg._line_cache_width == cache_key and msg._line_count then
    return msg._line_count
  end

  -- Use actual wrap_text to get accurate line count
  -- This ensures count matches what draw_messages will produce
  local prefix, text = self:format_message(msg)
  local wrapped = self:wrap_text(prefix, text, self.width)
  local count = #wrapped

  -- Cache the result
  msg._line_cache_width = cache_key
  msg._line_count = count
  return count
end

-- Count total visible lines (accounting for word wrap)
function UI:count_visible_lines()
  local count = 0
  for _, msg in ipairs(self.message_buffer) do
    if self:is_message_visible(msg) then
      count = count + self:get_message_line_count(msg)
    end
  end
  return count
end

-- Get line info by line number (1-based)
-- Returns: msg, line_index_within_msg, wrapped_lines
function UI:get_line_info(target_line)
  local current_line = 0
  for _, msg in ipairs(self.message_buffer) do
    if self:is_message_visible(msg) then
      local prefix, text = self:format_message(msg)
      local lines = self:wrap_text(prefix, text, self.width)
      local msg_lines = #lines

      if current_line + msg_lines >= target_line then
        local line_in_msg = target_line - current_line
        return msg, line_in_msg, lines
      end
      current_line = current_line + msg_lines
    end
  end
  return nil, 0, nil
end

-- Draw message area (rows 3 to height-2)
-- Optimized: only wrap messages that will be displayed
-- Messages are anchored to the bottom (chat-style)
function UI:draw_messages()
  local msg_start = 3  -- Status bar now uses rows 1-2
  local msg_end = self.height - 2
  local msg_height = msg_end - msg_start + 1

  -- First pass: count total lines using cached counts (no table creation)
  local total_lines = self:count_visible_lines()
  local start_line = math.max(1, total_lines - msg_height + 1 - self.scroll_offset)
  local end_line = math.min(total_lines, start_line + msg_height - 1)

  -- Calculate how many lines we'll actually display
  local lines_to_display = end_line - start_line + 1
  if total_lines == 0 then lines_to_display = 0 end

  -- Calculate blank rows at top (messages anchor to bottom)
  local blank_rows = msg_height - lines_to_display

  -- Clear blank rows at the top
  for i = 0, blank_rows - 1 do
    term.setCursorPos(1, msg_start + i)
    term.clearLine()
  end

  -- Start drawing after the blank rows
  local screen_row = msg_start + blank_rows
  local current_line = 0

  -- Second pass: find and draw only the lines we need
  for _, msg in ipairs(self.message_buffer) do
    if screen_row > msg_end then break end

    if self:is_message_visible(msg) then
      local msg_line_count = self:get_message_line_count(msg)
      local msg_start_line = current_line + 1
      local msg_end_line = current_line + msg_line_count

      -- Check if any lines from this message are in our display range
      if msg_end_line >= start_line and msg_start_line <= end_line then
        -- Only wrap this message since we need to display it
        local prefix, text = self:format_message(msg)
        local wrapped = self:wrap_text(prefix, text, self.width)

        for i, line_data in ipairs(wrapped) do
          local line_num = current_line + i
          if line_num >= start_line and line_num <= end_line then
            self:draw_wrapped_line(screen_row, msg, line_data)
            screen_row = screen_row + 1
          end
        end
      end

      current_line = msg_end_line
    end
  end
end

-- Draw a single wrapped line
function UI:draw_wrapped_line(row, msg, line_data)
  term.setCursorPos(1, row)
  term.clearLine()

  local color = MSG_COLORS[msg.type] or colors.white
  term.setTextColor(color)

  -- For regular messages, nick prefix is cyan
  if msg.type == "msg" and line_data.prefix:match("^<") then
    term.setTextColor(colors.cyan)
    term.write(line_data.prefix)
    term.setTextColor(color)
    term.write(line_data.text)
  else
    term.write(line_data.prefix .. line_data.text)
  end

  term.setTextColor(colors.white)
end

-- Draw input area (rows height-1 to height)
function UI:draw_input_line()
  local input_row = self.height - 1

  -- Draw separator line
  term.setCursorPos(1, input_row)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", self.width))

  -- Draw input prompt
  term.setCursorPos(1, self.height)
  term.clearLine()
  term.setTextColor(colors.green)
  term.write("> ")
  term.setTextColor(colors.white)

  -- Draw input buffer
  local max_input = self.width - 3
  local display_input = self.input_buffer
  if #display_input > max_input then
    -- Show end of input if cursor is near end
    local start = math.max(1, self.input_cursor - max_input + 10)
    display_input = display_input:sub(start, start + max_input - 1)
  end
  term.write(display_input)

  -- Position cursor
  local cursor_x = 3 + math.min(self.input_cursor - 1, max_input - 1)
  term.setCursorPos(cursor_x, self.height)
end

-- Full refresh
function UI:refresh()
  if not self.needs_redraw then
    return
  end

  self:draw_status_bar()
  self:draw_messages()
  self:draw_input_line()

  self.needs_redraw = false
end

-- Mark UI as needing redraw
function UI:invalidate()
  self.needs_redraw = true
end

-- Add a message to the buffer
function UI:add_message(nick, text, msg_type, channel)
  table.insert(self.message_buffer, {
    time = os.time(),
    nick = nick or "",
    text = text or "",
    type = msg_type or "msg",
    channel = channel,
  })

  if Debug then
    Debug.mem("add_msg_" .. #self.message_buffer)
  end

  -- Trim buffer if too long
  local trimmed = false
  while #self.message_buffer > self.max_messages do
    table.remove(self.message_buffer, 1)
    trimmed = true
  end
  if trimmed then
    if Debug then
      Debug.log("TRIM", "buffer trimmed to " .. #self.message_buffer)
    end
    collectgarbage("collect")  -- free memory after trimming
  end

  -- Reset scroll when new message arrives
  if self.scroll_offset > 0 then
    -- Only auto-scroll if message is for current channel
    if not channel or channel == self.client.current_channel then
      self.scroll_offset = 0
    end
  end

  self:invalidate()
end

-- Add system message
function UI:add_system(text)
  self:add_message("", text, "system", nil)
end

-- Add error message
function UI:add_error(text)
  self:add_message("", text, "error", nil)
end

-- Scroll up
function UI:scroll_up(lines)
  lines = lines or 1
  local total_lines = self:count_visible_lines()
  local msg_height = self.height - 4
  local max_scroll = math.max(0, total_lines - msg_height)
  self.scroll_offset = math.min(self.scroll_offset + lines, max_scroll)
  self:invalidate()
end

-- Scroll down
function UI:scroll_down(lines)
  lines = lines or 1
  self.scroll_offset = math.max(0, self.scroll_offset - lines)
  self:invalidate()
end

-- Clear messages for current channel
function UI:clear_messages()
  local current_channel = self.client.current_channel
  local new_buffer = {}

  for _, msg in ipairs(self.message_buffer) do
    if msg.channel and msg.channel ~= current_channel then
      table.insert(new_buffer, msg)
    end
  end

  self.message_buffer = new_buffer
  self.scroll_offset = 0
  self:invalidate()
  collectgarbage("collect")  -- free memory after clearing
end

-- Input handling

function UI:insert_char(char)
  local before = self.input_buffer:sub(1, self.input_cursor - 1)
  local after = self.input_buffer:sub(self.input_cursor)
  self.input_buffer = before .. char .. after
  self.input_cursor = self.input_cursor + 1
  self:invalidate()
end

function UI:delete_backward()
  if self.input_cursor > 1 then
    local before = self.input_buffer:sub(1, self.input_cursor - 2)
    local after = self.input_buffer:sub(self.input_cursor)
    self.input_buffer = before .. after
    self.input_cursor = self.input_cursor - 1
    self:invalidate()
  end
end

function UI:delete_forward()
  if self.input_cursor <= #self.input_buffer then
    local before = self.input_buffer:sub(1, self.input_cursor - 1)
    local after = self.input_buffer:sub(self.input_cursor + 1)
    self.input_buffer = before .. after
    self:invalidate()
  end
end

function UI:cursor_left()
  if self.input_cursor > 1 then
    self.input_cursor = self.input_cursor - 1
    self:invalidate()
  end
end

function UI:cursor_right()
  if self.input_cursor <= #self.input_buffer then
    self.input_cursor = self.input_cursor + 1
    self:invalidate()
  end
end

function UI:cursor_home()
  self.input_cursor = 1
  self:invalidate()
end

function UI:cursor_end()
  self.input_cursor = #self.input_buffer + 1
  self:invalidate()
end

function UI:history_up()
  if #self.input_history == 0 then
    return
  end

  if self.history_pos == 0 then
    self.saved_input = self.input_buffer
  end

  if self.history_pos < #self.input_history then
    self.history_pos = self.history_pos + 1
    local idx = #self.input_history - self.history_pos + 1
    self.input_buffer = self.input_history[idx]
    self.input_cursor = #self.input_buffer + 1
    self:invalidate()
  end
end

function UI:history_down()
  if self.history_pos > 0 then
    self.history_pos = self.history_pos - 1

    if self.history_pos == 0 then
      self.input_buffer = self.saved_input
    else
      local idx = #self.input_history - self.history_pos + 1
      self.input_buffer = self.input_history[idx]
    end
    self.input_cursor = #self.input_buffer + 1
    self:invalidate()
  end
end

function UI:add_to_history(line)
  if line and line ~= "" then
    -- Don't add duplicates
    if #self.input_history == 0 or self.input_history[#self.input_history] ~= line then
      table.insert(self.input_history, line)
      -- Limit history size (reduced from 100 to 30 for memory)
      while #self.input_history > 30 do
        table.remove(self.input_history, 1)
      end
    end
  end
end

function UI:submit_input()
  local input = self.input_buffer
  self.input_buffer = ""
  self.input_cursor = 1
  self.history_pos = 0
  self:invalidate()

  if input ~= "" then
    self:add_to_history(input)
  end

  return input
end

function UI:cancel_input()
  self.input_buffer = ""
  self.input_cursor = 1
  self.history_pos = 0
  self:invalidate()
end

-- Non-blocking input check using keys.poll()
-- Returns: input line if Enter pressed, nil otherwise
-- Also returns special actions: "quit", "scroll_up", "scroll_down"
function UI:check_input()
  -- Use keys.poll() for non-blocking input (NOT keys.wait which blocks)
  local key_state, modifiers, code = keys.poll()

  -- Only process if a key was actually pressed
  if key_state ~= keys.states.pressed then
    return nil
  end

  -- Handle special keys
  if code == keys.enter then
    return self:submit_input()

  elseif code == keys.esc then
    return "quit"

  elseif code == keys.backspace then
    self:delete_backward()

  elseif code == keys.delete then
    self:delete_forward()

  elseif code == keys.left then
    self:cursor_left()

  elseif code == keys.right then
    self:cursor_right()

  elseif code == keys.up then
    -- Check for shift modifier (modifiers is a bitmask)
    if modifiers and (modifiers & keys.modifiers.shift) ~= 0 then
      self:scroll_up()
    else
      self:history_up()
    end

  elseif code == keys.down then
    if modifiers and (modifiers & keys.modifiers.shift) ~= 0 then
      self:scroll_down()
    else
      self:history_down()
    end

  elseif code == keys.home then
    self:cursor_home()

  elseif code == keys["end"] then
    self:cursor_end()

  elseif code == keys.pageUp then
    self:scroll_up(10)
    return "scroll_up"

  elseif code == keys.pageDown then
    self:scroll_down(10)
    return "scroll_down"

  elseif type(code) == "string" and #code == 1 and keys.isPrintable(code) then
    self:insert_char(code)
  end

  return nil
end

return UI
