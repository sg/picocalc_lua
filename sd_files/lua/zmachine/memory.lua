-- Z-Machine Memory Module
-- Handles story file loading and memory access
-- Uses PSRAM for story storage, with the changed parts of dynamic memory held as strings

local memory = {}
memory.VERSION = "2.0"

-- Memory regions
memory.story = nil          -- PSRAM address for story file
memory.story_size = 0       -- Size of loaded story
memory.dynamic_size = 0     -- Size of dynamic memory region
memory.static_base = 0      -- Start of static memory

-- A page of dynamic memory the game has written to is kept here as a string
-- (false until then), since a table entry per changed byte cost far more and
-- grew by doubling, which the heap could not always supply.
local PAGE_BITS = 7
local PAGE_SIZE = 1 << PAGE_BITS
local PAGE_MASK = PAGE_SIZE - 1
local pages = {}

local byte, char, sub = string.byte, string.char, string.sub

-- Read cache for performance
local read_cache = nil
local cache_base = -1
local CACHE_SIZE = 256

-- Header locations (offsets are 0-based)
memory.HDR_VERSION = 0x00
memory.HDR_FLAGS1 = 0x01
memory.HDR_HIMEM = 0x04
memory.HDR_PC = 0x06
memory.HDR_DICT = 0x08
memory.HDR_OBJECTS = 0x0A
memory.HDR_GLOBALS = 0x0C
memory.HDR_STATIC = 0x0E
memory.HDR_FLAGS2 = 0x10
memory.HDR_ABBREVS = 0x18
memory.HDR_FILE_LEN = 0x1A
memory.HDR_CHECKSUM = 0x1C
memory.HDR_ROUTINE_OFF = 0x28
memory.HDR_STRING_OFF = 0x2A

-- on firmware up to v0.6.6 psram.read takes its buffer from the C heap, which
-- runs no collection of its own, so it can fail while garbage holds the space;
-- the second pass frees what the first finalized
local function story_read(offset, count)
    local data = psram.read(memory.story, offset, count)
    for _ = 1, 2 do
        if data then return data end
        collectgarbage()
        data = psram.read(memory.story, offset, count)
    end
    -- carrying on with zeros in place of the story would run the game off into garbage
    return data or error("out of memory reading the story")
end

-- Read a byte from PSRAM (internal, bypasses write overlay)
local function psram_read_byte(addr)
    -- Check cache first
    if read_cache and addr >= cache_base and addr < cache_base + CACHE_SIZE then
        return string.byte(read_cache, addr - cache_base + 1) or 0
    end

    -- Cache miss - read a chunk
    local base = addr - (addr % CACHE_SIZE)
    local to_read = math.min(CACHE_SIZE, memory.story_size - base)
    if to_read <= 0 then
        return 0
    end

    -- dropped first so that a collection during the read can reclaim it
    read_cache, cache_base = nil, -1
    read_cache = story_read(base, to_read)
    cache_base = base

    return string.byte(read_cache, addr - cache_base + 1) or 0
end

-- Invalidate cache (call after writes to dynamic memory)
local function invalidate_cache()
    read_cache = nil
    cache_base = -1
end

-- Read a byte from memory (0-based address)
function memory.read_byte(addr)
    if addr < 0 or addr >= memory.story_size then
        error("Memory access error: address " .. addr .. " out of bounds")
    end

    if addr < memory.dynamic_size then
        local page = pages[(addr >> PAGE_BITS) + 1]
        if page then
            return byte(page, (addr & PAGE_MASK) + 1)
        end
    end

    -- Read from PSRAM
    return psram_read_byte(addr)
end

-- Read a 16-bit word (big-endian, Z-machine format)
function memory.read_word(addr)
    local high = memory.read_byte(addr)
    local low = memory.read_byte(addr + 1)
    return high * 256 + low
end

-- Read a signed 16-bit word
function memory.read_word_signed(addr)
    local val = memory.read_word(addr)
    if val >= 0x8000 then
        return val - 0x10000
    end
    return val
end

-- Write a byte to memory (only dynamic memory is writable)
function memory.write_byte(addr, value)
    if addr < 0 then
        error("Memory write error: negative address " .. addr)
    end

    if addr >= memory.dynamic_size then
        error("Memory write error: address " .. addr .. " is in static memory")
    end

    local index = (addr >> PAGE_BITS) + 1
    local page = pages[index] or memory.original_page(index)
    local offset = addr & PAGE_MASK
    pages[index] = sub(page, 1, offset) .. char(value & 0xFF) .. sub(page, offset + 2)
end

-- Write a 16-bit word (big-endian)
function memory.write_word(addr, value)
    local offset = addr & PAGE_MASK
    if offset == PAGE_MASK or addr < 0 or addr + 1 >= memory.dynamic_size then
        memory.write_byte(addr, (value & 0xFF00) >> 8)
        memory.write_byte(addr + 1, value & 0xFF)
        return
    end
    -- both bytes lie in one page, so it is rebuilt once
    local index = (addr >> PAGE_BITS) + 1
    local page = pages[index] or memory.original_page(index)
    pages[index] = sub(page, 1, offset) .. char((value >> 8) & 0xFF, value & 0xFF) .. sub(page, offset + 3)
end

-- Number of pages dynamic memory is cut into
function memory.page_count()
    return (memory.dynamic_size + PAGE_MASK) >> PAGE_BITS
end

-- A page of dynamic memory as the story file has it
function memory.original_page(index)
    local base = (index - 1) << PAGE_BITS
    return story_read(base, math.min(PAGE_SIZE, memory.dynamic_size - base))
end

-- Bytes of the story file as loaded, whatever the game has since written
function memory.original_bytes(addr, count)
    return story_read(addr, count)
end

-- A page as the game has changed it, or false if it has not
function memory.get_page(index)
    return pages[index]
end

function memory.set_page(index, page)
    pages[index] = page
end

-- Read multiple bytes as a string
function memory.read_bytes(addr, count)
    local bytes = {}
    for i = 0, count - 1 do
        bytes[i + 1] = string.char(memory.read_byte(addr + i))
    end
    return table.concat(bytes)
end

-- Load a story file into memory
function memory.load(filepath)
    -- Clean up any previous story
    memory.unload()

    -- Force garbage collection before loading
    collectgarbage("collect")

    -- Check file exists
    if not fs.exists(filepath) then
        return false, "File not found: " .. filepath
    end

    -- Get file size
    local size = fs.getSize(filepath)
    if size == 0 then
        return false, "Empty file: " .. filepath
    end

    -- Open file
    local f = fs.open(filepath, "r")
    if not f then
        return false, "Cannot open file: " .. filepath
    end

    -- Allocate PSRAM for story
    local psram_addr, err = psram.alloc(size, "zmachine_story")
    if not psram_addr then
        f:close()
        return false, "Cannot allocate PSRAM (" .. size .. " bytes): " .. (err or "unknown")
    end

    -- Read file in chunks and write to PSRAM
    local chunk_size = 4096
    local offset = 0

    while offset < size do
        local to_read = math.min(chunk_size, size - offset)
        local data = f:read(to_read)
        if not data then
            break
        end

        local ok, werr = psram.write(psram_addr, offset, data)
        if not ok then
            f:close()
            psram.free(psram_addr)
            return false, "PSRAM write error at offset " .. offset .. ": " .. (werr or "unknown")
        end

        offset = offset + #data

        -- Yield occasionally to prevent watchdog
        if offset % 16384 == 0 then
            collectgarbage("step")
        end
    end

    f:close()

    memory.story = psram_addr
    memory.story_size = size
    invalidate_cache()

    -- Read header to get dynamic memory size
    local header_data, rerr = psram.read(psram_addr, 0, 64)
    if not header_data or #header_data < 64 then
        psram.free(psram_addr)
        memory.story = nil
        return false, "Cannot read header: " .. (rerr or "unknown")
    end

    -- Get static memory base (end of dynamic memory)
    memory.static_base = string.byte(header_data, memory.HDR_STATIC + 1) * 256 +
                         string.byte(header_data, memory.HDR_STATIC + 2)

    -- Dynamic memory is everything below static base
    memory.dynamic_size = memory.static_base
    memory.reset_dynamic()

    -- Validate version
    local version = string.byte(header_data, memory.HDR_VERSION + 1)
    if version < 1 or version > 8 then
        memory.unload()
        return false, "Invalid Z-machine version: " .. version
    end

    return true, version
end

-- Unload story and free resources
function memory.unload()
    if memory.story then
        psram.free(memory.story)
        memory.story = nil
    end
    memory.story_size = 0
    memory.dynamic_size = 0
    memory.static_base = 0
    pages = {}
    invalidate_cache()
    collectgarbage("collect")
end

-- Get header value helpers
function memory.get_version()
    return memory.read_byte(memory.HDR_VERSION)
end

function memory.get_himem()
    return memory.read_word(memory.HDR_HIMEM)
end

function memory.get_initial_pc()
    return memory.read_word(memory.HDR_PC)
end

function memory.get_dictionary()
    return memory.read_word(memory.HDR_DICT)
end

function memory.get_object_table()
    return memory.read_word(memory.HDR_OBJECTS)
end

function memory.get_globals()
    return memory.read_word(memory.HDR_GLOBALS)
end

function memory.get_abbrevs()
    return memory.read_word(memory.HDR_ABBREVS)
end

function memory.get_routine_offset()
    return memory.read_word(memory.HDR_ROUTINE_OFF) * 8
end

function memory.get_string_offset()
    return memory.read_word(memory.HDR_STRING_OFF) * 8
end

-- Get a snapshot of dynamic memory (for undo)
function memory.get_dynamic_snapshot()
    -- the pages are strings, which never change, so copying the list is enough
    local snapshot = {}
    for i = 1, memory.page_count() do
        snapshot[i] = pages[i]
    end
    return snapshot
end

-- Restore dynamic memory from snapshot
function memory.restore_dynamic(snapshot)
    for i = 1, memory.page_count() do
        pages[i] = snapshot[i] or false
    end
end

-- Reset dynamic memory to original state (for restart)
function memory.reset_dynamic()
    pages = {}
    for i = 1, memory.page_count() do
        pages[i] = false
    end
end

-- Pack an address for routine calls (version-dependent)
function memory.pack_routine_addr(addr, version)
    if version <= 3 then
        return addr * 2
    elseif version <= 5 then
        return addr * 4
    elseif version == 6 or version == 7 then
        return addr * 4 + memory.get_routine_offset()
    else
        return addr * 8
    end
end

-- Pack an address for strings (version-dependent)
function memory.pack_string_addr(addr, version)
    if version <= 3 then
        return addr * 2
    elseif version <= 5 then
        return addr * 4
    elseif version == 6 or version == 7 then
        return addr * 4 + memory.get_string_offset()
    else
        return addr * 8
    end
end

return memory
