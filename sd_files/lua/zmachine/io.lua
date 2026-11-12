-- Z-Machine I/O Module
-- Screen model, status line, and input
--
-- The terminal can only scroll the whole screen, which would carry the
-- status line and upper window away, so this module never lets it scroll:
-- it keeps the text of every lower window row and repaints those rows.

local zio = {}
zio.VERSION = "2.0"

local ansi = require("lua/modules/simple-colors")

local RESET = ansi.reset
local CLEAR_EOL = ansi.clrline

local STYLE_REVERSE = 1
local STYLE_BOLD = 2
local STYLE_ITALIC = 4

-- Module references
local mem = nil
local txt = nil
local version = 3

-- Screen geometry
local width, height = 53, 40
local top = 0             -- rows the V1-3 status line takes above both windows
local upper = 0           -- rows of the upper window

-- Upper window
local window = 0
local ux, uy = 1, 1

-- Lower window
local lines = {}          -- finished text of the rows above the one being written
local row = 1             -- row being written, counted from the top of the window
local cur, cur_len = "", 0 -- its text; cur also holds style escapes, which cur_len leaves out
local word = ""           -- run of characters not yet placed, so it can move to the next row whole
local wrap = true
local dirty = {}
local dirty_all = false
local unseen = 0          -- rows written since the player last had to press a key

local style_seq = ""

local function lower_height()
    return height - top - upper
end

local function place_cursor()
    term.setCursorPos(math.min(cur_len + 1, width), top + upper + row)
end

local function paint()
    for r = 1, lower_height() do
        if dirty_all or dirty[r] then
            term.setCursorPos(1, top + upper + r)
            term.write((r == row and cur or lines[r] or "") .. RESET .. CLEAR_EOL)
            dirty[r] = nil
        end
    end
    dirty_all = false
    place_cursor()
end

local function more()
    paint()
    -- the status line is otherwise only drawn when the game asks for a command
    if zio.status_hook then zio.status_hook() end
    term.setCursorPos(1, top + upper + row)
    term.write("[MORE]")
    keys.wait(true)
    dirty[row] = true
    unseen = 0
end

local function new_row()
    lines[row] = cur
    dirty[row] = true
    if row < lower_height() then
        row = row + 1
    else
        table.remove(lines, 1)
        dirty_all = true
    end
    cur, cur_len = style_seq, 0
    dirty[row] = true
    unseen = unseen + 1
    -- one row short of a windowful, so the last row read stays in view
    if unseen >= lower_height() - 1 then
        more()
    end
end

local function place(s)
    cur = cur .. s
    cur_len = cur_len + #s
    dirty[row] = true
end

-- fills each row to the edge before moving on
local function place_hard(s)
    while #s > 0 do
        if cur_len >= width then new_row() end
        local n = math.min(#s, width - cur_len)
        place(s:sub(1, n))
        s = s:sub(n + 1)
    end
end

local function commit_word()
    if word == "" then return end
    local w = word
    word = ""
    if cur_len > 0 and cur_len + #w > width then new_row() end
    place_hard(w)
end

local function out_lower(text)
    local pos = 1
    while pos <= #text do
        local a, b = text:find("^[^ \n]+", pos)
        if a then
            if wrap then
                word = word .. text:sub(a, b)
                if #word >= width then commit_word() end
            else
                place_hard(text:sub(a, b))
            end
            pos = b + 1
        else
            commit_word()
            if text:byte(pos) == 10 then
                new_row()
            elseif not wrap then
                place_hard(" ")
            elseif cur_len < width then
                -- a space at the edge is dropped, so no wrapped row starts with one
                place(" ")
            end
            pos = pos + 1
        end
    end
end

-- the upper window is drawn as it is written and never wraps or scrolls
local function out_upper(text)
    for piece, nl in text:gmatch("([^\n]*)(\n?)") do
        if piece ~= "" then
            if uy <= upper and ux <= width then
                term.setCursorPos(ux, top + uy)
                term.write(style_seq .. piece:sub(1, width - ux + 1) .. RESET)
            end
            ux = ux + #piece
        end
        if nl ~= "" then
            ux, uy = 1, uy + 1
        end
    end
end

local function clear_rows(from, to)
    for y = from, to do
        term.setCursorPos(1, y)
        term.clearLine()
    end
end

local function clear_lower()
    -- V4 starts printing at the bottom of the window, later versions at the top
    row = (version == 4) and lower_height() or 1
    lines = {}
    for r = 1, row - 1 do lines[r] = "" end
    cur, cur_len = style_seq, 0
    word = ""
    dirty_all = true
    unseen = 0
end

-- Initialize with memory module
function zio.init(memory_module, text_module, ver)
    mem = memory_module
    txt = text_module
    version = ver or 3
    width, height = term.getSize()
    zio.reset()
end

-- Reset I/O state
function zio.reset()
    top = (version <= 3) and 1 or 0
    upper = 0
    window = 0
    ux, uy = 1, 1
    wrap = true
    style_seq = ""
    term.setCursorBlink(false)
    term.write(RESET)
    -- also returns the terminal to an unscrolled screen, which the row arithmetic here relies on
    term.clear()
    clear_lower()
    dirty_all = false
    place_cursor()
end

-- Bring the screen up to date with everything printed so far
function zio.flush()
    commit_word()
    paint()
end

-- Leave the cursor after the last text so the shell carries on below it
function zio.finish()
    zio.flush()
    term.write(RESET)
    term.setCursorPos(math.min(cur_len + 1, width), top + upper + row)
end

-- Print a string (main entry point)
function zio.print(text)
    if text:find("[^\n\32-\126]") then
        -- anything else would move the terminal's cursor without this module knowing
        text = text:gsub("\t", " "):gsub("[^\n\32-\126]", "")
    end
    if text == "" then return end
    if window == 1 then
        out_upper(text)
    else
        out_lower(text)
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
    style_seq = ""
    if (style & STYLE_REVERSE) ~= 0 then style_seq = style_seq .. ansi.reverse end
    if (style & STYLE_BOLD) ~= 0 then style_seq = style_seq .. ansi.bold end
    if (style & STYLE_ITALIC) ~= 0 then style_seq = style_seq .. ansi.italic end
    if window == 0 then
        commit_word()
        cur = cur .. RESET .. style_seq
    end
end

-- Set buffering mode
function zio.set_buffering(enabled)
    commit_word()
    wrap = enabled
end

-- Split window
function zio.split_window(n)
    zio.flush()
    n = math.max(0, math.min(n, height - top - 1))
    local grow = n - upper
    if grow > 0 then
        -- rows the upper window now covers
        for _ = 1, grow do table.remove(lines, 1) end
        row = row - grow
        if row < 1 then
            row = 1
            cur, cur_len = style_seq, 0
        end
    elseif grow < 0 then
        for _ = 1, -grow do table.insert(lines, 1, "") end
        row = row - grow
        dirty_all = true
    end
    upper = n
    if version <= 3 then
        clear_rows(top + 1, top + upper)
    end
    if uy > upper then ux, uy = 1, 1 end
    paint()
end

-- Set current window
function zio.set_window(win)
    zio.flush()
    window = (win == 1) and 1 or 0
    if window == 1 then
        ux, uy = 1, 1
    end
end

-- Whether output is going to the upper window
function zio.in_upper()
    return window == 1
end

-- Set cursor position
function zio.set_cursor(r, col)
    -- only the upper window is addressable before V6
    if window == 1 then
        uy = math.max(1, r)
        ux = math.max(1, col)
    end
end

-- Cursor position within the current window, as row, column
function zio.get_cursor()
    if window == 1 then
        return uy, ux
    end
    commit_word()
    return row, cur_len + 1
end

-- Erase window
function zio.erase_window(win)
    zio.flush()
    if win == -1 or win == -2 then
        if win == -1 then
            upper = 0
            window = 0
        end
        term.clear()
        clear_lower()
        dirty_all = false
        ux, uy = 1, 1
    elseif win == 0 then
        clear_lower()
    elseif win == 1 then
        clear_rows(top + 1, top + upper)
        ux, uy = 1, 1
    end
    place_cursor()
end

-- Erase line
function zio.erase_line()
    if window == 1 then
        if uy <= upper and ux <= width then
            term.setCursorPos(ux, top + uy)
            term.write(RESET .. CLEAR_EOL)
        end
    end
end

-- Draw V3 status line
function zio.draw_status_line(location, score_or_hours, moves_or_minutes, is_time)
    local right
    if is_time then
        right = string.format("Time: %d:%02d ", score_or_hours, moves_or_minutes)
    else
        right = string.format("Score: %d  Moves: %d ", score_or_hours, moves_or_minutes)
    end
    local room = math.max(1, width - #right - 2)
    local text = string.format(" %-" .. room .. "s %s", location:sub(1, room), right)

    term.setCursorPos(1, 1)
    term.write(ansi.reverse .. text:sub(1, width) .. RESET)
    place_cursor()
end

local function echo(ch)
    if cur_len >= width then
        new_row()
        paint()
    end
    place(ch)
    dirty[row] = nil
    term.setCursorBlink(false)
    term.setCursorPos(cur_len, top + upper + row)
    term.write(ch)
    term.setCursorBlink(true)
end

local function unecho()
    if cur_len == 0 then
        -- the typing wrapped here from the row above, which it filled
        if row == 1 then return end
        row = row - 1
        cur, cur_len = lines[row], width
        lines[row] = nil
    end
    cur = cur:sub(1, -2)
    cur_len = cur_len - 1
    term.setCursorBlink(false)
    term.setCursorPos(cur_len + 1, top + upper + row)
    term.write(" ")
    term.setCursorPos(cur_len + 1, top + upper + row)
    term.setCursorBlink(true)
end

-- Read a line of input
function zio.read_line(max_len, initial)
    zio.flush()
    unseen = 0

    -- V5 games print any text they preload, so it is not echoed here
    local input = initial or ""
    max_len = max_len or 255

    term.setCursorBlink(true)

    while true do
        local _, _, code = keys.wait(true)

        if code == keys.enter or code == "\r" then
            term.setCursorBlink(false)
            new_row()
            return input:lower()

        elseif code == keys.backspace or code == "\127" then
            if #input > 0 then
                input = input:sub(1, -2)
                unecho()
            end

        elseif #code == 1 and code >= " " and code <= "~" then
            if #input < max_len then
                input = input .. code
                echo(code)
            end
        end
    end
end

-- Read a single character
function zio.read_char()
    zio.flush()
    unseen = 0
    term.setCursorBlink(true)

    local result
    repeat
        local _, _, code = keys.wait(true)
        if code == keys.enter or code == "\r" then
            result = 13
        elseif code == keys.backspace or code == "\127" then
            result = 8
        elseif code == keys.esc then
            result = 27
        elseif code == keys.up then
            result = 129
        elseif code == keys.down then
            result = 130
        elseif code == keys.left then
            result = 131
        elseif code == keys.right then
            result = 132
        elseif #code == 1 and code >= " " and code <= "~" then
            result = code:byte()
        end
    until result

    term.setCursorBlink(false)
    return result
end

-- Sound beep
function zio.beep()
    term.write("\a")
end

-- Get screen dimensions
function zio.get_screen_size()
    return width, height
end

-- Check for available input
function zio.input_available()
    return false
end

return zio
