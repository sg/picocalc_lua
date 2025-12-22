--[[
    readline.lua - Line editing with history support

    A reusable input module with command history and cursor movement.

    Usage:
        local readline = require("lua/readline")

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

-- Internal state for current input
local state = {
    buffer = "",      -- Current input text
    cursor = 1,       -- Cursor position (1 = before first char)
    history_pos = 0,  -- 0 = current input, 1+ = history entries
    saved_input = "", -- Save current input when browsing history
    prompt = "",      -- The prompt string
    prompt_len = 0,   -- Visible length of prompt (without ANSI codes)
    prev_len = 0,     -- Previous buffer length (for calculating move distance)
}

-- Calculate visible string length (strips ANSI escape codes)
local function visible_length(str)
    local stripped = str:gsub("\27%[[%d;]*m", "")
    return #stripped
end

-- Move cursor left n positions
local function move_left(n)
    if n > 0 then
        term.write("\27[" .. n .. "D")
    end
end

-- Redraw the current line
local function redraw()
    -- Calculate how far back we need to go from current screen position
    -- Current screen position is: prompt_len + prev_len (where cursor was at end)
    -- But cursor might not be at end, so we need: prompt_len + cursor - 1 positions from start
    -- Move back to start of input area (after prompt would require knowing screen pos)

    -- Move cursor back to start of prompt
    local current_screen_pos = state.prompt_len + state.prev_len
    if current_screen_pos > 0 then
        move_left(current_screen_pos)
    end

    -- Write prompt and buffer
    term.write(state.prompt .. state.buffer)
    -- Clear to end of line (remove any leftover characters)
    term.write("\27[K")

    -- Update prev_len for next redraw
    state.prev_len = #state.buffer

    -- Move cursor back to correct position within buffer
    local chars_after_cursor = #state.buffer - state.cursor + 1
    if chars_after_cursor > 0 then
        move_left(chars_after_cursor)
    end
end

-- Insert character at cursor position
local function insert_char(char)
    local before = state.buffer:sub(1, state.cursor - 1)
    local after = state.buffer:sub(state.cursor)
    state.buffer = before .. char .. after
    state.cursor = state.cursor + 1
    redraw()
end

-- Delete character before cursor (backspace)
local function delete_backward()
    if state.cursor > 1 then
        local before = state.buffer:sub(1, state.cursor - 2)
        local after = state.buffer:sub(state.cursor)
        state.buffer = before .. after
        state.cursor = state.cursor - 1
        redraw()
    end
end

-- Delete character at cursor (delete key)
local function delete_forward()
    if state.cursor <= #state.buffer then
        local before = state.buffer:sub(1, state.cursor - 1)
        local after = state.buffer:sub(state.cursor + 1)
        state.buffer = before .. after
        redraw()
    end
end

-- Move cursor left
local function cursor_left()
    if state.cursor > 1 then
        state.cursor = state.cursor - 1
        term.write("\27[D")  -- Move cursor left one position
    end
end

-- Move cursor right
local function cursor_right()
    if state.cursor <= #state.buffer then
        state.cursor = state.cursor + 1
        term.write("\27[C")  -- Move cursor right one position
    end
end

-- Move cursor to start of input
local function cursor_home()
    if state.cursor > 1 then
        local move = state.cursor - 1
        state.cursor = 1
        term.write("\27[" .. move .. "D")
    end
end

-- Move cursor to end of input
local function cursor_end()
    if state.cursor <= #state.buffer then
        local move = #state.buffer - state.cursor + 1
        state.cursor = #state.buffer + 1
        term.write("\27[" .. move .. "C")
    end
end

-- Clear the entire line
local function clear_line()
    state.buffer = ""
    state.cursor = 1
    redraw()
end

-- Set buffer content (used by history navigation)
local function set_buffer(text)
    state.buffer = text
    state.cursor = #text + 1  -- Cursor at end
    redraw()
end

-- Navigate history up (older)
local function history_up()
    if #readline.history == 0 then
        return
    end

    -- Save current input when starting to browse
    if state.history_pos == 0 then
        state.saved_input = state.buffer
    end

    -- Move up in history
    if state.history_pos < #readline.history then
        state.history_pos = state.history_pos + 1
        local idx = #readline.history - state.history_pos + 1
        set_buffer(readline.history[idx])
    end
end

-- Navigate history down (newer)
local function history_down()
    if state.history_pos > 0 then
        state.history_pos = state.history_pos - 1

        if state.history_pos == 0 then
            -- Restore saved input
            set_buffer(state.saved_input)
        else
            local idx = #readline.history - state.history_pos + 1
            set_buffer(readline.history[idx])
        end
    end
end

-- Add entry to history
function readline.add_history(line)
    if not line or line == "" then
        return
    end

    -- Don't add duplicates of the last entry
    if #readline.history > 0 and readline.history[#readline.history] == line then
        return
    end

    table.insert(readline.history, line)

    -- Trim history if too long
    while #readline.history > readline.max_history do
        table.remove(readline.history, 1)
    end
end

-- Clear history
function readline.clear_history()
    readline.history = {}
end

-- Load history from file
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

    -- Trim if loaded file was too long
    while #readline.history > readline.max_history do
        table.remove(readline.history, 1)
    end

    return true
end

-- Save history to file
function readline.save_history(filename)
    local f = fs.open(filename, "w")
    if not f then
        return false
    end

    for _, line in ipairs(readline.history) do
        f:writeLine(line)
    end
    f:close()
    return true
end

-- Main read function
function readline.read(prompt)
    prompt = prompt or ""

    -- Initialize state
    state.buffer = ""
    state.cursor = 1
    state.history_pos = 0
    state.saved_input = ""
    state.prompt = prompt
    state.prompt_len = visible_length(prompt)
    state.prev_len = 0

    -- Show prompt
    term.write(prompt)
    term.setCursorBlink(true)

    while true do
        local key_state, modifiers, code = keys.wait(true, true)

        -- Handle special keys
        if code == keys.enter then
            -- Accept input
            term.setCursorBlink(false)
            print("")  -- Move to next line
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
            -- Cancel input
            term.setCursorBlink(false)
            print("")
            return nil

        elseif type(code) == "string" and #code == 1 and keys.isPrintable(code) then
            -- Regular printable character
            insert_char(code)
        end
    end
end

return readline
