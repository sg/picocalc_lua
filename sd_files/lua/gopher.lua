--[[
  gopher.lua - gopher browser for picocalc_lua

  usage:
    dofile("lua/gopher.lua")

    or if using the shell:
    shell> run gopher.lua

  controls:
    Up/Down     - Navigate menu items / scroll text
    Enter       - Open selected item
    Backspace   - Go back in history
    g           - Go to URL
    h           - Go to home server
    r           - Reload current page
    /           - Search in current page (type 7)
    s           - Save current text to file
    q / Esc     - Quit
    PgUp/PgDn   - Page scroll
    Home/End    - Jump to start/end
]]

-- load the protocol module
local gopher = require("lua/shell/modules/gopher-client")

-- ANSI escape codes
local ESC = "\27["
local RESET = ESC .. "0m"
local BOLD = ESC .. "1m"
local DIM = ESC .. "2m"
local INVERSE = ESC .. "7m"
local COLOR = {
  black   = ESC .. "30m",
  red     = ESC .. "91m",
  green   = ESC .. "92m",
  yellow  = ESC .. "93m",
  blue    = ESC .. "94m",
  magenta = ESC .. "95m",
  cyan    = ESC .. "96m",
  white   = ESC .. "97m",
  gray    = ESC .. "90m",
}
local CLEAR_LINE = ESC .. "K"

-- browser state
local state = {
  -- current location
  host = "gopher.floodgap.com",
  port = 70,
  selector = "",
  page_type = "1",

  -- content
  items = {},         -- menu items (for menus)
  lines = {},         -- text lines (for text files)
  display_lines = {}, -- wrapped lines for display
  is_menu = true,     -- true = menu mode, false = text mode

  -- navigation
  cursor = 1,         -- selected item (menu mode)
  scroll = 0,         -- scroll offset
  history = {},       -- navigation history

  -- display
  width = 80,
  height = 24,
  status = "",
  error_msg = nil,

  -- state
  running = true,
  loading = false,
}

-- initialize terminal
local function init_display()
  state.width, state.height = term.getSize()
  term.clear()
  term.setCursorBlink(false)
end

-- get number of content lines available
local function content_height()
  return state.height - 3  -- URL bar + content + status bar
end

-- truncate string to fit width
local function truncate(str, max_width)
  if not str then return "" end
  if #str <= max_width then return str end
  return str:sub(1, max_width - 3) .. "..."
end

-- word wrap a string to fit within max_width
-- returns a table of wrapped lines
local function word_wrap(str, max_width)
  if not str or str == "" then
    return {""}
  end

  if #str <= max_width then
    return {str}
  end

  local lines = {}
  local remaining = str

  while #remaining > 0 do
    if #remaining <= max_width then
      table.insert(lines, remaining)
      break
    end

    -- find a good break point (space) within max_width
    local break_at = max_width
    local space_pos = nil

    -- look for last space within max_width
    for i = max_width, 1, -1 do
      if remaining:sub(i, i) == " " then
        space_pos = i
        break
      end
    end

    if space_pos and space_pos > 1 then
      -- break at space
      break_at = space_pos
      table.insert(lines, remaining:sub(1, break_at - 1))
      remaining = remaining:sub(break_at + 1)  -- Skip the space
    else
      -- no space found, hard break
      table.insert(lines, remaining:sub(1, max_width))
      remaining = remaining:sub(max_width + 1)
    end
  end

  return lines
end

-- get short prefix for navigable item types (shown before text)
local function get_item_prefix(item_type)
  if item_type == gopher.types.MENU then
    return "[+]"  -- Directory/menu
  elseif item_type == gopher.types.TEXT then
    return "[=]"  -- Text file
  elseif item_type == gopher.types.SEARCH then
    return "[?]"  -- Search
  elseif item_type == gopher.types.HTML then
    return "[@]"  -- HTML link
  elseif gopher.is_downloadable(item_type) then
    return "[*]"  -- Binary/download
  else
    return nil  -- No prefix for info lines
  end
end

-- build display lines from menu items (with word wrapping)
-- returns: display_lines table, each entry has {text, item_idx, is_continuation, is_info}
local function build_menu_display()
  state.display_lines = {}

  for idx, item in ipairs(state.items) do
    local is_info = (item.type == gopher.types.INFO)
    local prefix = get_item_prefix(item.type)

    -- calculate available width for text
    local available = state.width - 2  -- margins
    if prefix then
      available = available - #prefix - 1  -- prefix + space
    end

    -- wrap the display text
    local wrapped = word_wrap(item.display, available)

    for i, line_text in ipairs(wrapped) do
      table.insert(state.display_lines, {
        text = line_text,
        item_idx = idx,
        is_first = (i == 1),
        is_info = is_info,
        prefix = prefix,
      })
    end
  end
end

-- build display lines from text content (with word wrapping)
local function build_text_display()
  state.display_lines = {}
  local available = state.width - 1  -- margin

  for _, line in ipairs(state.lines) do
    if line == "" then
      table.insert(state.display_lines, "")
    else
      local wrapped = word_wrap(line, available)
      for _, wrapped_line in ipairs(wrapped) do
        table.insert(state.display_lines, wrapped_line)
      end
    end
  end
end

-- find display line index for a given item index
local function item_to_display_line(item_idx)
  for i, dl in ipairs(state.display_lines) do
    if dl.item_idx == item_idx and dl.is_first then
      return i
    end
  end
  return 1
end

-- find item index for a given display line
local function display_line_to_item(display_idx)
  if state.display_lines[display_idx] then
    return state.display_lines[display_idx].item_idx
  end
  return 1
end

-- draw the URL bar (top line)
local function draw_url_bar()
  term.setCursorPos(1, 1)
  local url = gopher.build_url(state.host, state.port, state.page_type, state.selector)
  local display = truncate(url, state.width - 2)

  term.write(COLOR.cyan .. BOLD .. " " .. display .. RESET .. CLEAR_LINE .. "\n")
end

-- get color for item type
local function get_item_color(item_type)
  if item_type == gopher.types.INFO then
    return COLOR.white  -- Plain white for readable info text
  elseif item_type == gopher.types.MENU then
    return COLOR.cyan
  elseif item_type == gopher.types.TEXT then
    return COLOR.green
  elseif item_type == gopher.types.SEARCH then
    return COLOR.yellow
  elseif item_type == gopher.types.ERROR then
    return COLOR.red
  elseif item_type == gopher.types.HTML then
    return COLOR.magenta
  elseif gopher.is_downloadable(item_type) then
    return COLOR.blue
  else
    return COLOR.white
  end
end

-- draw menu content (using wrapped display_lines)
local function draw_menu()
  local ch = content_height()

  for y = 1, ch do
    term.setCursorPos(1, y + 1)
    local dl_idx = state.scroll + y

    if dl_idx <= #state.display_lines then
      local dl = state.display_lines[dl_idx]
      local item = state.items[dl.item_idx]
      local is_selected = (dl.item_idx == state.cursor)
      local color = get_item_color(item.type)

      -- build the line
      local line = ""

      if dl.is_info then
        -- info lines: plain text, indent continuation lines
        local indent = dl.is_first and " " or "  "
        if is_selected and dl.is_first then
          line = INVERSE .. indent .. color .. dl.text .. RESET
        else
          line = indent .. color .. dl.text .. RESET
        end
      else
        -- navigable items
        if dl.is_first then
          -- first line: show cursor and prefix
          local cursor_char = is_selected and ">" or " "
          if is_selected then
            line = INVERSE .. cursor_char .. color .. dl.prefix .. " " .. dl.text .. RESET
          else
            line = cursor_char .. color .. dl.prefix .. " " .. dl.text .. RESET
          end
        else
          -- continuation line: indent to align with first line text
          local indent = "      "  -- align with text after "[+] "
          if is_selected then
            line = INVERSE .. indent .. color .. dl.text .. RESET
          else
            line = indent .. color .. dl.text .. RESET
          end
        end
      end

      term.write(line .. CLEAR_LINE)
    else
      term.write(CLEAR_LINE)
    end
    term.write("\n")
  end
end

-- draw text content (using wrapped display_lines)
local function draw_text()
  local ch = content_height()

  for y = 1, ch do
    term.setCursorPos(1, y + 1)
    local line_idx = state.scroll + y

    if line_idx <= #state.display_lines then
      local line = state.display_lines[line_idx]
      term.write(" " .. COLOR.white .. line .. RESET .. CLEAR_LINE)
    else
      term.write(CLEAR_LINE)
    end
      term.write("\n")
  end
end

-- draw status bar (bottom line)
local function draw_status_bar()
  term.setCursorPos(1, state.height)

  local left = ""
  local right = ""

  if state.loading then
    left = " Loading..."
  elseif state.error_msg then
    local err_text = truncate(state.error_msg, state.width - 10)
    left = COLOR.red .. " Err: " .. err_text .. RESET
  elseif state.status ~= "" then
    left = " " .. truncate(state.status, state.width - 15)
  else
    if state.is_menu then
      left = string.format(" %d/%d", state.cursor, #state.items)
    else
      left = string.format(" %d/%d", state.scroll + 1, #state.display_lines)
    end
  end

  -- help hints (short for narrow displays)
  if state.width < 60 then
    if state.is_menu then
      right = "g:Goto q:Quit"
    else
      right = "Bksp:Back q:Quit"
    end
  else
    if state.is_menu then
      right = "[Enter]Open [g]Goto [q]Quit"
    else
      right = "[Bksp]Back [s]Save [q]Quit"
    end
  end

  -- calculate padding
  local left_plain = left:gsub("\27%[[%d;]*m", "")  -- Remove ANSI codes for length
  local padding = state.width - #left_plain - #right - 1
  if padding < 0 then
    -- not enough room, truncate left side
    right = ""
    padding = 0
  end

  term.write(COLOR.cyan .. left .. string.rep(" ", padding) .. DIM .. right .. RESET .. CLEAR_LINE)
end

-- full screen redraw
local function redraw()
  draw_url_bar()
  if state.is_menu then
    draw_menu()
  else
    draw_text()
  end
  draw_status_bar()
end

-- ensure cursor is visible (adjust scroll based on display lines)
local function ensure_cursor_visible()
  local ch = content_height()

  if state.is_menu then
    -- find the display line for current cursor item
    local cursor_display_line = item_to_display_line(state.cursor)

    if cursor_display_line <= state.scroll then
      state.scroll = cursor_display_line - 1
    elseif cursor_display_line > state.scroll + ch then
      state.scroll = cursor_display_line - ch
    end

    -- clamp scroll
    local max_scroll = math.max(0, #state.display_lines - ch)
    state.scroll = math.max(0, math.min(state.scroll, max_scroll))
  else
    -- text mode: simple scroll clamping
    local max_scroll = math.max(0, #state.display_lines - ch)
    state.scroll = math.max(0, math.min(state.scroll, max_scroll))
  end
end

-- navigate to a gopher location
local function navigate(host, port, selector, page_type, add_to_history)
  -- save current position to history
  if add_to_history and #state.items > 0 then
    table.insert(state.history, {
      host = state.host,
      port = state.port,
      selector = state.selector,
      page_type = state.page_type,
      cursor = state.cursor,
      scroll = state.scroll,
    })
  end

  -- update state
  state.host = host
  state.port = port or 70
  state.selector = selector or ""
  state.page_type = page_type or "1"
  state.cursor = 1
  state.scroll = 0
  state.error_msg = nil
  state.loading = true
  state.status = "Connecting to " .. host .. "..."

  redraw()

  -- fetch content
  local response, err = gopher.fetch(host, port, selector)

  state.loading = false

  if not response then
    state.error_msg = err or "unknown error"
    state.items = {}
    state.lines = {}
    state.display_lines = {}
    state.is_menu = true
    redraw()
    return false
  end

  -- parse based on type
  if page_type == gopher.types.MENU or page_type == "1" then
    state.items = gopher.parse_menu(response)
    state.lines = {}
    state.is_menu = true
    state.status = ""
    build_menu_display()
  else
    -- text or other content
    state.lines = {}
    for line in response:gmatch("[^\r\n]*") do
      -- skip end marker
      if line ~= "." then
        table.insert(state.lines, line)
      end
    end
    state.items = {}
    state.is_menu = false
    state.status = ""
    build_text_display()
  end

  redraw()
  return true
end

-- go back in history
local function go_back()
  if #state.history == 0 then
    state.status = "No history"
    draw_status_bar()
    return
  end

  local prev = table.remove(state.history)
  state.host = prev.host
  state.port = prev.port
  state.selector = prev.selector
  state.page_type = prev.page_type
  state.error_msg = nil
  state.loading = true
  state.status = "Going back..."

  redraw()

  -- fetch content
  local response, err = gopher.fetch(state.host, state.port, state.selector)

  state.loading = false

  if not response then
    state.error_msg = err
    state.items = {}
    state.lines = {}
    state.display_lines = {}
    state.is_menu = true
  else
    if state.page_type == gopher.types.MENU or state.page_type == "1" then
      state.items = gopher.parse_menu(response)
      state.lines = {}
      state.is_menu = true
      build_menu_display()
    else
      state.lines = {}
      for line in response:gmatch("[^\r\n]*") do
        if line ~= "." then
          table.insert(state.lines, line)
        end
      end
      state.items = {}
      state.is_menu = false
      build_text_display()
    end
  end

  -- restore position
  state.cursor = prev.cursor
  state.scroll = prev.scroll
  state.status = ""

  redraw()
end

-- open selected item
local function open_selected()
  if not state.is_menu or #state.items == 0 then
    return
  end

  local item = state.items[state.cursor]
  if not item then return end

  -- handle different types
  if item.type == gopher.types.INFO then
    -- info items are not navigable
    state.status = "Info item (not a link)"
    draw_status_bar()
    return
  end

  if item.type == gopher.types.SEARCH then
    -- prompt for search query
    term.setCursorPos(1, state.height)
    term.write(CLEAR_LINE)
    term.write(COLOR.green .. " Search: " .. RESET)
    term.setCursorBlink(true)
    local query = term.read()
    term.setCursorBlink(false)

    if query and query ~= "" then
      -- perform search
      state.loading = true
      state.status = "Searching..."
      redraw()

      local response, err = gopher.search(item.host, item.port, item.selector, query)
      state.loading = false

      if response then
        -- save to history
        table.insert(state.history, {
          host = state.host,
          port = state.port,
          selector = state.selector,
          page_type = state.page_type,
          cursor = state.cursor,
          scroll = state.scroll,
        })

        -- update state with search results
        state.host = item.host
        state.port = item.port
        state.selector = item.selector .. "\t" .. query
        state.page_type = "1"
        state.items = gopher.parse_menu(response)
        state.lines = {}
        state.is_menu = true
        state.cursor = 1
        state.scroll = 0
        state.status = ""
        build_menu_display()
      else
        state.error_msg = err
      end
    end
    redraw()
    return
  end

  if item.type == gopher.types.HTML then
    -- HTML links often start with "URL:"
    local url = item.selector
    if url:match("^URL:") then
      url = url:sub(5)
    end
    state.status = "HTML: " .. truncate(url, state.width - 10)
    draw_status_bar()
    return
  end

  if gopher.is_downloadable(item.type) then
    state.status = "Binary file (download not supported)"
    draw_status_bar()
    return
  end

  if not gopher.is_navigable(item.type) then
    state.status = "Cannot open this item type"
    draw_status_bar()
    return
  end

  -- navigate to the item
  navigate(item.host, item.port, item.selector, item.type, true)
end

-- prompt for URL and navigate
local function goto_url()
  term.setCursorPos(1, state.height)
  term.write(CLEAR_LINE)
  term.write(COLOR.cyan .. " Gopher URL: " .. RESET)
  term.setCursorBlink(true)
  local url = term.read()
  term.setCursorBlink(false)

  if url and url ~= "" then
    local host, port, gtype, selector = gopher.parse_url(url)
    if host then
      navigate(host, port, selector, gtype, true)
    else
      state.error_msg = "Invalid URL"
      redraw()
    end
  else
    redraw()
  end
end

-- save current text to file
local function save_text()
  if state.is_menu then
    state.status = "Can only save text files"
    draw_status_bar()
    return
  end

  term.setCursorPos(1, state.height)
  term.write(CLEAR_LINE)
  term.write(COLOR.cyan .. " Save as: " .. RESET)
  term.setCursorBlink(true)
  local filename = term.read()
  term.setCursorBlink(false)

  if filename and filename ~= "" then
    local f = fs.open(filename, "w")
    if f then
      for _, line in ipairs(state.lines) do
        f:writeLine(line)
      end
      f:close()
      state.status = "Saved to " .. filename
    else
      state.error_msg = "Cannot write file"
    end
  end
  redraw()
end

-- handle keyboard input
local function handle_input()
  local key_state, modifiers, code = keys.wait(true, true)

  -- movement keys
  if code == keys.up then
    if state.is_menu then
      if state.cursor > 1 then
        state.cursor = state.cursor - 1
        ensure_cursor_visible()
        redraw()
      end
    else
      if state.scroll > 0 then
        state.scroll = state.scroll - 1
        redraw()
      end
    end

  elseif code == keys.down then
    if state.is_menu then
      if state.cursor < #state.items then
        state.cursor = state.cursor + 1
        ensure_cursor_visible()
        redraw()
      end
    else
      if state.scroll < #state.display_lines - content_height() then
        state.scroll = state.scroll + 1
        redraw()
      end
    end

  elseif code == keys.pageUp then
    local ch = content_height()
    if state.is_menu then
      state.cursor = math.max(1, state.cursor - ch)
      ensure_cursor_visible()
    else
      state.scroll = math.max(0, state.scroll - ch)
    end
    redraw()

  elseif code == keys.pageDown then
    local ch = content_height()
    if state.is_menu then
      state.cursor = math.min(#state.items, state.cursor + ch)
      ensure_cursor_visible()
    else
      state.scroll = math.min(math.max(0, #state.display_lines - ch), state.scroll + ch)
    end
    redraw()

  elseif code == keys.home then
    if state.is_menu then
      state.cursor = 1
    end
    state.scroll = 0
    redraw()

  elseif code == keys["end"] then
    if state.is_menu then
      state.cursor = #state.items
      ensure_cursor_visible()
    else
      state.scroll = math.max(0, #state.display_lines - content_height())
    end
    redraw()

  elseif code == keys.enter then
    if state.is_menu then
      open_selected()
    end

  elseif code == keys.backspace or code == keys.left then
    go_back()

  elseif code == keys.esc then
    if state.is_menu then
      state.running = false
    else
      -- in text mode, go back to menu
      go_back()
    end

  -- letter keys
  elseif code == "q" or code == "Q" then
    state.running = false

  elseif code == "g" or code == "G" then
    goto_url()

  elseif code == "h" or code == "H" then
    -- go home
    navigate("gopher.floodgap.com", 70, "", "1", true)

  elseif code == "r" or code == "R" then
    -- reload
    navigate(state.host, state.port, state.selector, state.page_type, false)

  elseif code == "s" or code == "S" then
    save_text()

  elseif code == "/" then
    -- search shortcut (same as selecting a search item)
    if state.is_menu then
      -- find first search item
      for i, item in ipairs(state.items) do
        if item.type == gopher.types.SEARCH then
          state.cursor = i
          ensure_cursor_visible()
          redraw()
          open_selected()
          break
        end
      end
    end
  end
end

-- main function
local function main()
  -- confirm wifi is connected
  if not wifi.isConnected() then
    print("Error: Wi-Fi not connected")
    print("Run: dofile('lua/wifi-start.lua')")
    return
  end

  -- initialize
  init_display()

  -- load home page
  navigate(state.host, state.port, state.selector, state.page_type, false)

  -- main loop
  while state.running do
    handle_input()
  end

  -- cleanup
  term.clear()
  term.setCursorBlink(true)
  print("Goodbye!")
end

-- Run
main()
