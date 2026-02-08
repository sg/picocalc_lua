-- Z-Machine I/O Module
-- Handles terminal output, status line, and input

local zio = {}
zio.VERSION = "1.1"

local ansi = require("lua/modules/simple-colors")

-- Module references
local mem = nil
local txt = nil
local version = 3

-- Screen state
local screen_width = 50
local screen_height = 40
local current_window = 0
local upper_window_height = 0
local cursor_x = 1
local cursor_y = 1
local buffering = true
local buffer = {}  -- Reusable table for buffering
local buffer_count = 0  -- Number of entries in buffer
local buffer_chars = 0  -- Total character count

-- Text styles
local current_style = 0
local STYLE_REVERSE = 1
local STYLE_BOLD = 2
local STYLE_ITALIC = 4
local STYLE_FIXED = 8

-- Initialize with memory module
function zio.init(memory_module, text_module, ver)
    mem = memory_module
    txt = text_module
    version = ver or 3
    screen_width, screen_height = term.getSize()
    zio.reset()
end

-- Reset I/O state
function zio.reset()
    current_window = 0
    upper_window_height = (version <= 3) and 1 or 0
    cursor_x = 1
    cursor_y = (version <= 3) and 2 or 1
    buffering = true
    -- Clear buffer table
    for i = 1, #buffer do buffer[i] = nil end
    buffer_count = 0
    buffer_chars = 0
    current_style = 0
    term.clear()
    term.setCursorPos(1, cursor_y)
end

-- Write text directly - let terminal handle it
local function write_wrapped(text)
    local start = 1
    term.setCursorBlink(false)
    while start <= #text do
        local newline_pos = text:find("\n", start, true)
        if newline_pos then
            -- Output text before newline
            if newline_pos > start then
                term.write(text:sub(start, newline_pos - 1))
            end
            -- Output newline
            term.write("\n")
            start = newline_pos + 1
        else
            -- Output remaining text (no newline)
            term.write(text:sub(start))
            break
        end
    end
    term.setCursorBlink(true)
end

-- Flush output buffer
function zio.flush()
    if buffer_count > 0 then
        local text = table.concat(buffer, "", 1, buffer_count)
        -- Clear buffer table
        for i = 1, buffer_count do buffer[i] = nil end
        buffer_count = 0
        buffer_chars = 0

        if buffering then
            write_wrapped(text)
        else
            term.setCursorBlink(false)
            term.write(text)
            term.setCursorBlink(true)
        end
    end
end

-- Print a string (main entry point)
function zio.print(text)
    if buffering then
        buffer_count = buffer_count + 1
        buffer[buffer_count] = text
        buffer_chars = buffer_chars + #text
        -- Flush if buffer gets large to prevent OOM
        if buffer_chars > 500 then
            zio.flush()
        end
    else
        term.setCursorBlink(false)
        term.write(text)
        term.setCursorBlink(true)
    end
end

-- Print a newline
function zio.newline()
    zio.print("\n")
end

-- Print Z-encoded text from packed address
function zio.print_paddr(packed_addr)
    local addr = mem.pack_string_addr(packed_addr, version)
    local text_str, _ = txt.decode(addr)
    zio.print(text_str)
end

-- Print Z-encoded text at byte address
function zio.print_addr(addr)
    local text_str, _ = txt.decode(addr)
    zio.print(text_str)
end

-- Print object name
function zio.print_obj(obj)
    local objects = require("lua/zmachine/objects")
    local name = objects.get_name(obj)
    zio.print(name)
end

-- Print a number
function zio.print_num(num)
    zio.print(tostring(num))
end

-- Set text style
function zio.set_style(style)
    zio.flush()
    current_style = style

    if style == 0 then
        term.write(ansi.reset)
    else
        if (style & STYLE_REVERSE) ~= 0 then
            term.write(ansi.reverse)
        end
        if (style & STYLE_BOLD) ~= 0 then
            term.write(ansi.bold)
        end
        if (style & STYLE_ITALIC) ~= 0 then
            term.write(ansi.italic)
        end
    end
end

-- Set buffering mode
function zio.set_buffering(enabled)
    if not enabled then
        zio.flush()
    end
    buffering = enabled
end

-- Split window
function zio.split_window(lines)
    zio.flush()
    upper_window_height = lines
    if current_window == 0 then
        local x, y = term.getCursorPos()
        if y <= upper_window_height then
            term.setCursorPos(1, upper_window_height + 1)
        end
    end
end

-- Set current window
function zio.set_window(win)
    zio.flush()
    current_window = win

    if win == 1 then
        buffering = false
        term.setCursorPos(1, 1)
    else
        buffering = true
        local x, y = term.getCursorPos()
        if y <= upper_window_height then
            term.setCursorPos(1, upper_window_height + 1)
        end
    end
end

-- Set cursor position
function zio.set_cursor(row, col)
    zio.flush()
    if current_window == 1 then
        term.setCursorPos(col, row)
    else
        term.setCursorPos(col, row + upper_window_height)
    end
end

-- Erase window
function zio.erase_window(win)
    zio.flush()
    if win == -1 then
        term.clear()
        upper_window_height = 0
        term.setCursorPos(1, 1)
    elseif win == -2 then
        term.clear()
        term.setCursorPos(1, upper_window_height + 1)
    elseif win == 0 then
        for y = upper_window_height + 1, screen_height do
            term.setCursorPos(1, y)
            term.clearLine()
        end
        term.setCursorPos(1, upper_window_height + 1)
    elseif win == 1 then
        for y = 1, upper_window_height do
            term.setCursorPos(1, y)
            term.clearLine()
        end
        term.setCursorPos(1, 1)
    end
end

-- Erase line
function zio.erase_line()
    zio.flush()
    local x, y = term.getCursorPos()
    if x == 0 then x = 1 end
    if y == 0 then y = 1 end
    term.clearLine()
    term.setCursorPos(x, y)
end

-- Draw V3 status line
function zio.draw_status_line(location, score_or_time, moves_or_hours, is_time)
    local old_x, old_y = term.getCursorPos()
    -- Handle 0-indexed positions
    if old_x == 0 then old_x = 1 end
    if old_y == 0 then old_y = 1 end

    term.setCursorPos(1, 1)
    term.write(ansi.reverse)

    local status_text
    if is_time then
        status_text = string.format(" %-" .. (screen_width - 20) .. "s Time: %2d:%02d ",
            location:sub(1, screen_width - 20), score_or_time, moves_or_hours)
    else
        status_text = string.format(" %-" .. (screen_width - 25) .. "s Score: %d  Moves: %d ",
            location:sub(1, screen_width - 25), score_or_time, moves_or_hours)
    end

    term.write(status_text:sub(1, screen_width))
    term.write(ansi.reset)
    term.setCursorPos(old_x, old_y)
end

-- Read a line of input
function zio.read_line(max_len, initial)
    zio.flush()

    local input = initial or ""

    if #input > 0 then
        term.write(input)
    end

    term.setCursorBlink(true)

    while true do
        local key, mods, code = keys.wait(true)

        -- Handle code being a string (the character itself) or number
        local char_code = nil
        if type(code) == "number" then
            char_code = code
        elseif type(code) == "string" and #code == 1 then
            char_code = string.byte(code)
        end

        if key == keys.enter or char_code == 13 or char_code == 10 then
            term.setCursorBlink(false)
            term.write("\n")
            term.setCursorBlink(true)
            return input:lower()

        elseif key == keys.backspace or char_code == 8 or char_code == 127 then
            if #input > 0 then
                input = input:sub(1, -2)
                -- Use backspace-space-backspace sequence to erase character
                term.setCursorBlink(false)
                term.write("\b \b")
                term.setCursorBlink(true)
            end

        elseif char_code and char_code >= 32 and char_code <= 126 then
            if #input < (max_len or 255) then
                local chr = string.char(char_code)
                input = input .. chr
                term.setCursorBlink(false)
                term.write(chr)
                term.setCursorBlink(true)
            end
        end
    end
end

-- Read a single character
function zio.read_char()
    zio.flush()

    local key, mods, code = keys.wait(true)
    term.setCursorBlink(false)

    -- Handle code being a string (the character itself) or number
    local char_code = nil
    if type(code) == "number" then
        char_code = code
    elseif type(code) == "string" and #code == 1 then
        char_code = string.byte(code)
    end

    if char_code and char_code >= 32 and char_code <= 126 then
        return char_code
    elseif key == keys.enter or char_code == 13 or char_code == 10 then
        return 13
    elseif key == keys.backspace or char_code == 8 or char_code == 127 then
        return 8
    elseif key == keys.up then
        return 129
    elseif key == keys.down then
        return 130
    elseif key == keys.left then
        return 131
    elseif key == keys.right then
        return 132
    else
        return 0
    end
end

-- Show "[MORE]" prompt
function zio.more()
    zio.flush()
    local old_x, old_y = term.getCursorPos()
    if old_x == 0 then old_x = 1 end
    if old_y == 0 then old_y = 1 end
    term.setCursorBlink(false)
    term.write("[MORE]")
    keys.wait()
    term.setCursorPos(old_x, old_y)
    term.write("      ")
    term.setCursorPos(old_x, old_y)
    term.setCursorBlink(true)
end

-- Sound beep
function zio.beep()
    term.write("\a")
    
end

-- Get screen dimensions
function zio.get_screen_size()
    return screen_width, screen_height
end

-- Check for available input
function zio.input_available()
    return false
end

return zio
