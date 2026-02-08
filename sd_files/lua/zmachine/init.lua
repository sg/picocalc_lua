-- Z-Machine Interpreter for PicoCalc
-- Main entry point

local zmachine = {}
zmachine.VERSION = "1.0"

-- Run a Z-machine game
function zmachine.run(filepath)
    -- Force garbage collection before starting
    collectgarbage("collect")

    -- Load VM module
    local vm = require("lua/zmachine/vm")

    -- Initialize with story file
    local ok, result = vm.init(filepath)
    if not ok then
        vm.shutdown()
        return false, result
    end

    local version = result
    print("Z-machine version " .. version .. " interpreter ready.")
    print("Type commands at the prompt. Use 'quit' to exit.\n")

    -- Run the interpreter
    local success, err = pcall(function()
        vm.run()
    end)

    -- Clean up
    vm.shutdown()

    if not success then
        return false, err
    end

    return true
end

-- Get information about a story file without running it
-- Lightweight: reads header directly from file, no PSRAM allocation
function zmachine.info(filepath)
    if not fs.exists(filepath) then
        return nil, "File not found: " .. filepath
    end

    local f = fs.open(filepath, "r")
    if not f then
        return nil, "Cannot open file: " .. filepath
    end

    -- Read just the 64-byte header
    local header = f:read(64)
    f:close()

    if not header or #header < 64 then
        return nil, "File too small to be a Z-machine story"
    end

    -- Helper to read bytes from header string
    local function byte(offset)
        return string.byte(header, offset + 1) or 0
    end

    local function word(offset)
        return byte(offset) * 256 + byte(offset + 1)
    end

    local version = byte(0x00)
    if version < 1 or version > 8 then
        return nil, "Invalid Z-machine version: " .. version
    end

    local info = {
        version = version,
        release = word(0x02),
        himem = word(0x04),
        initial_pc = word(0x06),
        dictionary = word(0x08),
        object_table = word(0x0A),
        globals = word(0x0C),
        static_base = word(0x0E),
        story_size = fs.getSize(filepath),
        dynamic_size = word(0x0E),  -- Same as static_base
    }

    -- Read serial number (at 0x12, 6 bytes)
    local serial = ""
    for i = 0, 5 do
        local b = byte(0x12 + i)
        if b >= 32 and b < 127 then
            serial = serial .. string.char(b)
        end
    end
    info.serial = serial

    return info
end

return zmachine
