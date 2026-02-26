--[[

  mesh/ui.lua - MeshCore Terminal UI

  Handles screen layout and display for the MeshCore client.

  Screen regions:
    Row 1:         Status bar (node name, connection, battery)
    Row 2:         Target bar (current target/channel, free memory)
    Rows 3..h-2:   Message area (or contact list in contacts mode)
    Row h-1:       Separator
    Row h:         Input line

  Usage:
    local UI = require("lua/modules/mesh/ui")
    local ui = UI.new(client)
    ui:init()
    ui:add_message("Nick", "Hello!", "dm_in")
    ui:refresh()

]]

local emoji

local UI = {}
UI.__index = UI

-- Message type colors
local MSG_COLORS = {
  dm_in    = colors.lightBlue,
  dm_out   = colors.white,
  chan_in   = colors.lime,
  chan_out  = colors.green,
  system   = colors.cyan,
  error    = colors.red,
  ack      = colors.yellow,
}

function UI.new(client)
  local self = setmetatable({
    client = client,
    width = 0,
    height = 0,
    scroll_offset = 0,
    message_buffer = {},
    max_messages = 40,
    input_buffer = "",
    input_cursor = 1,
    input_history = {},
    history_pos = 0,
    saved_input = "",
    needs_redraw = true,

    -- Mode: "chat" or "contacts"
    mode = "chat",

    -- Contact list view state
    contact_scroll = 0,
    contact_selected = 1,

    -- Current DM target (contact index) and channel
    current_target = nil,
    current_target_name = nil,
    current_channel = 0,

    -- Timezone offset in hours from UTC (e.g. -5 for EST)
    tz_offset = 0,
  }, UI)

  return self
end

-- Initialize the UI
function UI:init()
  self.width, self.height = term.getSize()
  term.clear()
  term.setCursorPos(1, 1)
  term.setCursorBlink(true)
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

-- Mark UI as needing redraw
function UI:invalidate()
  self.needs_redraw = true
end

-- Full refresh
function UI:refresh()
  if not self.needs_redraw then
    return
  end

  self:draw_status_bar()
  if self.mode == "contacts" then
    self:draw_contact_list()
  else
    self:draw_messages()
  end
  self:draw_input_line()

  self.needs_redraw = false

  if _G._buffer_mode_blit then draw.blitBuffer() end
end

-- Draw status bar (row 1) and target bar (row 2)
function UI:draw_status_bar()
  local old_bg = term.getBackgroundColor()
  local old_fg = term.getTextColor()
  local client = self.client

  -- Row 1: Node name | connected/disconnected | battery
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.clearLine()

  local parts = {}
  if client.self_name then
    table.insert(parts, client.self_name)
  else
    table.insert(parts, "MeshCore")
  end

  if client.connected then
    table.insert(parts, "connected")
  else
    table.insert(parts, "disconnected")
  end

  if client.battery_display then
    table.insert(parts, "Batt: " .. client.battery_display)
  end

  local row1 = table.concat(parts, " | ")
  if #row1 > self.width then
    row1 = row1:sub(1, self.width - 3) .. "..."
  end
  term.write(row1)
  local remaining = self.width - #row1
  if remaining > 0 then
    term.write(string.rep(" ", remaining))
  end

  -- Row 2: Target/Channel | Mem
  term.setCursorPos(1, 2)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.clearLine()

  local parts2 = {}
  if self.current_target_name then
    table.insert(parts2, "To: " .. self.current_target_name)
  else
    table.insert(parts2, "Ch: " .. self.client:channel_label(self.current_channel))
  end

  local free_mem = sys.freeMemory()
  if free_mem then
    local free_kb = math.floor(free_mem / 1024)
    table.insert(parts2, "Mem: " .. free_kb .. "K")
  end

  if self.mode == "contacts" then
    table.insert(parts2, "[CONTACTS]")
  end

  local row2 = table.concat(parts2, " | ")
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

-- Format epoch timestamp as "[HH:MM:SS] " using tz_offset
function UI:format_time(epoch)
  if not epoch or epoch == 0 then return "" end
  local adjusted = epoch + self.tz_offset * 3600
  local secs = adjusted % 86400
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  local s = secs % 60
  return string.format("[%02d:%02d:%02d] ", h, m, s)
end

-- Format a message for display
function UI:format_message(msg)
  local prefix = ""
  local text = msg.text or ""
  local ts = self:format_time(msg.ts)

  if msg.type == "dm_in" then
    prefix = ts .. "[" .. msg.nick .. "] "
  elseif msg.type == "dm_out" then
    prefix = ts .. "[-> " .. msg.nick .. "] "
  elseif msg.type == "chan_in" then
    prefix = ts .. "<" .. self.client:channel_label(tonumber(msg.channel) or 0) .. "> "
    if msg.nick and msg.nick ~= "" then
      -- Include sender name for channel messages
      text = msg.nick .. ": " .. text
    end
  elseif msg.type == "chan_out" then
    prefix = ts .. "<" .. self.client:channel_label(tonumber(msg.channel) or 0) .. "> "
  elseif msg.type == "system" then
    prefix = ts .. "*** "
  elseif msg.type == "error" then
    prefix = ts .. "!!! "
  elseif msg.type == "ack" then
    prefix = ts .. "  > "
  end

  return prefix, text
end

-- Word-wrap text to fit within width, returns array of lines
function UI:wrap_text(prefix, text, width)
  local lines = {}
  local prefix_len = #prefix
  local first_line_width = width - prefix_len
  local cont_width = width - 2

  if first_line_width < 10 then first_line_width = width end
  if cont_width < 10 then cont_width = width end

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
      table.insert(lines, {prefix = line_prefix, text = remaining})
      break
    else
      local break_at = line_width
      for i = line_width, math.max(1, line_width - 20), -1 do
        if remaining:sub(i, i) == " " then
          break_at = i
          break
        end
      end

      local line_text = remaining:sub(1, break_at)
      remaining = remaining:sub(break_at + 1)
      remaining = remaining:gsub("^%s+", "")

      table.insert(lines, {prefix = line_prefix, text = line_text})
    end

    is_first = false
  end

  return lines
end

-- Calculate display lines for a message (with caching)
function UI:get_message_line_count(msg)
  local cache_key = self.width
  if msg._line_cache_width == cache_key and msg._line_count then
    return msg._line_count
  end

  local prefix, text = self:format_message(msg)
  local wrapped = self:wrap_text(prefix, text, self.width)
  local count = #wrapped

  msg._line_cache_width = cache_key
  msg._line_count = count
  return count
end

-- Count total visible lines
function UI:count_visible_lines()
  local count = 0
  for _, msg in ipairs(self.message_buffer) do
    count = count + self:get_message_line_count(msg)
  end
  return count
end

-- Draw message area (rows 3 to height-2)
function UI:draw_messages()
  local msg_start = 3
  local msg_end = self.height - 2
  local msg_height = msg_end - msg_start + 1

  local total_lines = self:count_visible_lines()
  local start_line = math.max(1, total_lines - msg_height + 1 - self.scroll_offset)
  local end_line = math.min(total_lines, start_line + msg_height - 1)

  local lines_to_display = end_line - start_line + 1
  if total_lines == 0 then lines_to_display = 0 end

  local blank_rows = msg_height - lines_to_display

  for i = 0, blank_rows - 1 do
    term.setCursorPos(1, msg_start + i)
    term.clearLine()
  end

  local screen_row = msg_start + blank_rows
  local current_line = 0

  for _, msg in ipairs(self.message_buffer) do
    if screen_row > msg_end then break end

    local msg_line_count = self:get_message_line_count(msg)
    local msg_end_line = current_line + msg_line_count

    if msg_end_line >= start_line and current_line + 1 <= end_line then
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

-- Draw a single wrapped line with appropriate color
function UI:draw_wrapped_line(row, msg, line_data)
  term.setCursorPos(1, row)
  term.clearLine()

  local color = MSG_COLORS[msg.type] or colors.white
  term.setTextColor(color)
  term.write(line_data.prefix)
  term.write(line_data.text)
  term.setTextColor(colors.white)
end

-- Draw contact list overlay
function UI:draw_contact_list()
  local list_start = 3
  local list_end = self.height - 2
  local list_height = list_end - list_start + 1

  local contacts = self.client.contacts
  local total = #contacts

  -- Adjust scroll to keep selected visible
  if self.contact_selected < self.contact_scroll + 1 then
    self.contact_scroll = self.contact_selected - 1
  elseif self.contact_selected > self.contact_scroll + list_height then
    self.contact_scroll = self.contact_selected - list_height
  end

  for i = 0, list_height - 1 do
    local row = list_start + i
    local idx = self.contact_scroll + i + 1
    term.setCursorPos(1, row)
    term.clearLine()

    if idx <= total then
      local contact = contacts[idx]
      local is_selected = (idx == self.contact_selected)

      if is_selected then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
      else
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
      end

      -- Format: index. name [type]
      local type_str = ""
      if contact.type == 1 then type_str = " [C]"      -- chat/companion
      elseif contact.type == 2 then type_str = " [R]"   -- repeater
      end

      local line = string.format("%2d. %-20s%s", idx, contact.name, type_str)
      if #line > self.width then
        line = line:sub(1, self.width)
      end
      term.write(line)

      -- Fill rest of line if selected
      if is_selected then
        local rem = self.width - #line
        if rem > 0 then
          term.write(string.rep(" ", rem))
        end
      end

      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end
  end

  -- Show hint at bottom of list area if there are contacts
  if total > 0 then
    term.setCursorPos(1, list_end)
    term.setTextColor(colors.gray)
    if total > list_height then
      term.write(string.format("  %d/%d contacts  Enter=select  Esc=back", self.contact_selected, total))
    else
      term.write("  Enter=select  Esc=back")
    end
    term.setTextColor(colors.white)
  elseif total == 0 then
    term.setCursorPos(1, list_start)
    term.setTextColor(colors.gray)
    term.write("  No contacts loaded. Press Esc to go back.")
    term.setTextColor(colors.white)
  end
end

-- Draw input area
function UI:draw_input_line()
  local input_row = self.height - 1

  -- Separator
  term.setCursorPos(1, input_row)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", self.width))

  -- Input prompt
  term.setCursorPos(1, self.height)
  term.clearLine()
  term.setTextColor(colors.green)
  term.write("> ")
  term.setTextColor(colors.white)

  local max_input = self.width - 3
  local display_input = self.input_buffer
  if #display_input > max_input then
    local start = math.max(1, self.input_cursor - max_input + 10)
    display_input = display_input:sub(start, start + max_input - 1)
  end
  term.write(display_input)

  local cursor_x = 3 + math.min(self.input_cursor - 1, max_input - 1)
  term.setCursorPos(cursor_x, self.height)
end

-- Add a message to the buffer
function UI:add_message(nick, text, msg_type, channel, ts)
  -- Lazy-load emoji module and decode incoming chat messages
  if msg_type == "dm_in" or msg_type == "chan_in" then
    if not emoji then
      collectgarbage("collect")
      emoji = require("lua/modules/mesh/emoji")
      collectgarbage("collect")
    end
    text = emoji.replace(text or "")
  end

  local msg = {
    nick = nick or "",
    text = text or "",
    type = msg_type or "system",
    channel = channel,
    ts = ts,
  }

  table.insert(self.message_buffer, msg)

  -- Write to log file if open
  if self.logfh then
    local prefix, body = self:format_message(msg)
    self.logfh:writeLine(prefix .. body)
    self.logfh:flush()
  end

  while #self.message_buffer > self.max_messages do
    table.remove(self.message_buffer, 1)
    collectgarbage("collect")
  end

  if self.scroll_offset > 0 then
    self.scroll_offset = 0
  end

  self:invalidate()
end

function UI:add_system(text, ts)
  self:add_message("", text, "system", nil, ts)
end

function UI:add_error(text, ts)
  self:add_message("", text, "error", nil, ts)
end

-- Clear all messages
function UI:clear_messages()
  self.message_buffer = {}
  self.scroll_offset = 0
  self:invalidate()
  collectgarbage("collect")
end

-- Scroll controls
function UI:scroll_up(lines)
  lines = lines or 1
  local total_lines = self:count_visible_lines()
  local msg_height = self.height - 4
  local max_scroll = math.max(0, total_lines - msg_height)
  self.scroll_offset = math.min(self.scroll_offset + lines, max_scroll)
  self:invalidate()
end

function UI:scroll_down(lines)
  lines = lines or 1
  self.scroll_offset = math.max(0, self.scroll_offset - lines)
  self:invalidate()
end

-- Input handling functions (identical to IRC)
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
  if #self.input_history == 0 then return end

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
    if #self.input_history == 0 or self.input_history[#self.input_history] ~= line then
      table.insert(self.input_history, line)
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

-- Non-blocking input check
-- Returns: input line if Enter pressed, nil otherwise
-- Special returns: "quit", "scroll_up", "scroll_down"
function UI:check_input()
  local key_state, modifiers, code = keys.poll()

  if key_state ~= keys.states.pressed then
    return nil
  end

  -- Contact list mode has its own key handling
  if self.mode == "contacts" then
    return self:handle_contacts_input(code, modifiers)
  end

  -- Chat mode keys
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

-- Handle keys in contacts mode
function UI:handle_contacts_input(code, modifiers)
  local total = #self.client.contacts

  if code == keys.esc then
    self.mode = "chat"
    self:invalidate()
    return nil

  elseif code == keys.enter then
    if total > 0 and self.contact_selected >= 1 and self.contact_selected <= total then
      local contact = self.client.contacts[self.contact_selected]
      self.current_target = self.contact_selected
      self.current_target_name = contact.name
      self.mode = "chat"
      self:invalidate()
      return "contact_selected"
    end

  elseif code == keys.up then
    if self.contact_selected > 1 then
      self.contact_selected = self.contact_selected - 1
      self:invalidate()
    end

  elseif code == keys.down then
    if self.contact_selected < total then
      self.contact_selected = self.contact_selected + 1
      self:invalidate()
    end

  elseif code == keys.pageUp then
    local list_height = self.height - 4
    self.contact_selected = math.max(1, self.contact_selected - list_height)
    self:invalidate()

  elseif code == keys.pageDown then
    local list_height = self.height - 4
    self.contact_selected = math.min(total, self.contact_selected + list_height)
    self:invalidate()

  elseif code == keys.home then
    self.contact_selected = 1
    self:invalidate()

  elseif code == keys["end"] then
    self.contact_selected = math.max(1, total)
    self:invalidate()
  end

  return nil
end

-- Enter contacts mode
function UI:show_contacts()
  self.mode = "contacts"
  self.contact_selected = math.max(1, self.current_target or 1)
  self.contact_scroll = 0
  self:invalidate()
end

return UI
