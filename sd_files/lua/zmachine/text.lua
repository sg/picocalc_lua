-- Z-Machine Text Decoder
-- Handles ZSCII encoding, alphabet tables, and abbreviations

local text = {}
text.VERSION = "1.0"

-- Memory module reference (set during init)
local mem = nil

-- Alphabet tables for different versions
-- A0 = lowercase, A1 = uppercase, A2 = punctuation
local alphabet_v1 = {
    [0] = " ??????abcdefghijklmnopqrstuvwxyz",
    [1] = " ??????ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    [2] = " ???????\n0123456789.,!?_#'\"/\\<-:()"
}

local alphabet_v2 = {
    [0] = " ??????abcdefghijklmnopqrstuvwxyz",
    [1] = " ??????ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    [2] = " ??????^\n0123456789.,!?_#'\"/\\-:()"
}

local alphabet_v3 = {
    [0] = "      abcdefghijklmnopqrstuvwxyz",
    [1] = "      ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    [2] = "       \n0123456789.,!?_#'\"/\\-:()"
}

-- Current alphabet table (set based on version)
local alphabet = alphabet_v3

-- Z-character special codes
local ZCHAR_SHIFT_UP = 4
local ZCHAR_SHIFT_DOWN = 5
local ZCHAR_ABBREV_1 = 1
local ZCHAR_ABBREV_2 = 2
local ZCHAR_ABBREV_3 = 3

-- State for text decoding
local current_alphabet = 0
local shift_lock = false

-- Initialize text module with memory reference and version
function text.init(memory_module, version)
    mem = memory_module

    -- Select alphabet based on version
    if version == 1 then
        alphabet = alphabet_v1
    elseif version == 2 then
        alphabet = alphabet_v2
    else
        alphabet = alphabet_v3
    end

    text.reset()
end

-- Reset decoder state
function text.reset()
    current_alphabet = 0
    shift_lock = false
end

-- Extract 3 Z-characters from a 2-byte word
local function extract_zchars(word)
    local z1 = (word & 0x7C00) >> 10
    local z2 = (word & 0x03E0) >> 5
    local z3 = word & 0x001F
    local is_end = (word & 0x8000) ~= 0
    return z1, z2, z3, is_end
end

-- Decode a single Z-character to output text
local function decode_zchar(zchar, state)
    -- Handle special state: waiting for 10-bit character (two zchars)
    if state.mode == "tenbit_high" then
        state.tenbit_value = zchar * 32
        state.mode = "tenbit_low"
        return ""
    end

    if state.mode == "tenbit_low" then
        local char_code = state.tenbit_value + zchar
        state.mode = nil
        current_alphabet = 0
        return string.char(char_code)
    end

    -- Handle abbreviation lookup
    if state.mode == "abbrev" then
        local abbrev_num = (state.abbrev_table - 1) * 32 + zchar
        state.mode = nil
        return text.get_abbreviation(abbrev_num)
    end

    -- Handle shift characters (versions vary)
    if zchar == 0 then
        return " "
    end

    -- Abbreviations (V3+)
    if zchar >= 1 and zchar <= 3 and mem.get_version() >= 3 then
        state.mode = "abbrev"
        state.abbrev_table = zchar
        return ""
    end

    -- Shift characters
    if zchar == 4 then
        if mem.get_version() <= 2 then
            -- V1-2: shift lock up
            current_alphabet = (current_alphabet + 1) % 3
            shift_lock = true
        else
            -- V3+: temporary shift up
            current_alphabet = 1
        end
        return ""
    end

    if zchar == 5 then
        if mem.get_version() <= 2 then
            -- V1-2: shift lock down
            current_alphabet = (current_alphabet + 2) % 3
            shift_lock = true
        else
            -- V3+: temporary shift down
            current_alphabet = 2
        end
        return ""
    end

    -- Regular characters (6-31)
    if zchar >= 6 and zchar <= 31 then
        local alpha_table = alphabet[current_alphabet]

        -- Special case: A2 char 6 is 10-bit ZSCII escape
        if current_alphabet == 2 and zchar == 6 then
            state.mode = "tenbit_high"
            if not shift_lock then
                current_alphabet = 0
            end
            return ""
        end

        -- Get character from alphabet table
        local result = alpha_table:sub(zchar + 1, zchar + 1)

        -- Reset to A0 after non-shift-lock shift
        if not shift_lock then
            current_alphabet = 0
        end

        -- Handle special characters
        if result == "^" then
            return "\n"  -- V2 newline
        end

        return result
    end

    return ""
end

-- Reusable tables for decoding (separate for main and abbreviations)
local decode_state = {}
local decode_result = {}
local abbrev_state = {}
local abbrev_result = {}

-- Internal decode function that uses provided tables
local function decode_internal(addr, state, result)
    -- Clear state
    state.mode = nil
    state.tenbit_value = nil
    state.abbrev_table = nil

    -- Clear result table
    local count = 0
    for i = 1, #result do result[i] = nil end

    local bytes = 0

    while true do
        local word = mem.read_word(addr + bytes)
        bytes = bytes + 2

        local z1, z2, z3, is_end = extract_zchars(word)

        count = count + 1
        result[count] = decode_zchar(z1, state)
        count = count + 1
        result[count] = decode_zchar(z2, state)
        count = count + 1
        result[count] = decode_zchar(z3, state)

        if is_end then
            break
        end

        -- Safety limit
        if bytes > 1000 then
            break
        end
    end

    return table.concat(result, "", 1, count), bytes
end

-- Decode Z-encoded text starting at address
-- Returns decoded string and number of bytes consumed
function text.decode(addr)
    if not mem then
        error("Text module not initialized")
    end

    text.reset()
    return decode_internal(addr, decode_state, decode_result)
end

-- Get abbreviation by number (0-95)
function text.get_abbreviation(num)
    if not mem then
        return ""
    end

    local abbrev_table_addr = mem.get_abbrevs()
    if abbrev_table_addr == 0 then
        return ""
    end

    -- Each abbreviation entry is 2 bytes (word address)
    local entry_addr = abbrev_table_addr + (num * 2)
    local word_addr = mem.read_word(entry_addr)

    -- Convert word address to byte address
    local byte_addr = word_addr * 2

    -- Decode using separate tables (abbreviations can't contain abbreviations)
    local saved_alphabet = current_alphabet
    local saved_lock = shift_lock
    current_alphabet = 0
    shift_lock = false

    local abbrev_text, _ = decode_internal(byte_addr, abbrev_state, abbrev_result)

    current_alphabet = saved_alphabet
    shift_lock = saved_lock

    return abbrev_text
end

-- ZSCII to ASCII/Unicode conversion table
local zscii_table = {
    -- 155-251: extra characters (simplified to ASCII equivalents)
    [155] = "a", [156] = "o", [157] = "u", [158] = "A", [159] = "O",
    [160] = "U", [161] = "s", [162] = ">>", [163] = "<<", [164] = "e",
    [165] = "i", [166] = "y", [167] = "E", [168] = "I", [169] = "a",
    [170] = "e", [171] = "i", [172] = "o", [173] = "u", [174] = "y",
    [175] = "A", [176] = "E", [177] = "I", [178] = "O", [179] = "U",
    [180] = "Y", [181] = "a", [182] = "e", [183] = "i", [184] = "o",
    [185] = "u", [186] = "A", [187] = "E", [188] = "I", [189] = "O",
    [190] = "U", [191] = "a", [192] = "e", [193] = "i", [194] = "o",
    [195] = "u", [196] = "n", [197] = "o", [198] = "a", [199] = "A",
    [200] = "O", [201] = "A", [202] = "c", [203] = "C", [204] = "th",
    [205] = "th", [206] = "Th", [207] = "Th", [208] = "L", [209] = "oe",
    [210] = "OE", [211] = "!"
}

-- Convert ZSCII code to printable character
function text.zscii_to_char(code)
    -- NULL
    if code == 0 then
        return ""
    end

    -- Delete (backspace)
    if code == 8 then
        return "\b"
    end

    -- Tab (V6)
    if code == 9 then
        return "\t"
    end

    -- Newline
    if code == 13 then
        return "\n"
    end

    -- Standard ASCII
    if code >= 32 and code <= 126 then
        return string.char(code)
    end

    -- Extra characters
    if zscii_table[code] then
        return zscii_table[code]
    end

    -- Unknown
    return "?"
end

-- Convert ASCII/input to ZSCII code
function text.char_to_zscii(char)
    local code = string.byte(char)

    -- Newline
    if code == 10 or code == 13 then
        return 13
    end

    -- Standard ASCII
    if code >= 32 and code <= 126 then
        return code
    end

    return 0
end

-- Encode text to Z-characters for dictionary lookup
function text.encode_for_dictionary(str, version)
    version = version or 3

    -- Resolution: V1-3 = 6 Z-chars (3 words), V4+ = 9 Z-chars (3 words)
    local max_zchars = (version <= 3) and 6 or 9

    local zchars = {}

    for i = 1, #str do
        local c = str:sub(i, i):lower()

        -- Find in alphabet A0
        local pos = alphabet[0]:find(c, 1, true)
        if pos then
            table.insert(zchars, pos - 1)
        else
            -- Find in alphabet A2
            pos = alphabet[2]:find(c, 1, true)
            if pos then
                table.insert(zchars, 5)  -- Shift to A2
                table.insert(zchars, pos - 1)
            else
                -- Use 10-bit ZSCII escape
                local code = string.byte(c)
                table.insert(zchars, 5)  -- Shift to A2
                table.insert(zchars, 6)  -- 10-bit escape
                table.insert(zchars, code >> 5)
                table.insert(zchars, code & 0x1F)
            end
        end

        if #zchars >= max_zchars then
            break
        end
    end

    -- Pad with 5s (padding character)
    while #zchars < max_zchars do
        table.insert(zchars, 5)
    end

    -- Truncate to max
    while #zchars > max_zchars do
        table.remove(zchars)
    end

    -- Pack into words
    local words = {}
    for i = 1, #zchars, 3 do
        local z1 = zchars[i] or 5
        local z2 = zchars[i + 1] or 5
        local z3 = zchars[i + 2] or 5
        local word = (z1 << 10) + (z2 << 5) + z3
        -- Set end bit on last word
        if i + 3 > #zchars then
            word = word + 0x8000
        end
        table.insert(words, word)
    end

    return words
end

return text
