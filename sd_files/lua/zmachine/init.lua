-- Z-Machine Interpreter for PicoCalc
-- Main entry point

local zmachine = {}
zmachine.VERSION = "1.0"

-- quetzal is loaded with the rest so that saving never has to compile code in what a game leaves free
local MODULES = { "memory", "text", "objects", "io", "opcodes", "quetzal", "vm" }

-- Debug information is a quarter of the interpreter's code and a game is left little memory,
-- so the modules are loaded without it; set the global ZMACHINE_DEBUG for line numbers in errors.
local function load_modules()
    for _, name in ipairs(MODULES) do
        local path = "lua/zmachine/" .. name
        if not package.loaded[path] then
            local chunk = assert(loadfile("/" .. path .. ".lua"))
            if not ZMACHINE_DEBUG then
                local code = string.dump(chunk, true)
                chunk = nil
                collectgarbage()
                chunk = assert(load(code, "=" .. path, "b"))
            end
            package.loaded[path] = chunk()
            collectgarbage()
        end
    end
end

-- Run a Z-machine game
function zmachine.run(filepath)
    -- Force garbage collection before starting
    collectgarbage("collect")

    local loaded, load_err = pcall(load_modules)
    if not loaded then
        return false, load_err
    end

    -- Load VM module
    local vm = require("lua/zmachine/vm")

    -- Initialize with story file
    local ok, result = vm.init(filepath)
    if not ok then
        vm.shutdown()
        return false, result
    end

    -- Run the interpreter
    local success, err = pcall(function()
        vm.run()
    end)

    -- the screen may hold text not yet drawn, and the shell needs the cursor below it
    pcall(vm.zio.finish)

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
