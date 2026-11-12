-- Z-Machine Saved Games
-- Reads and writes Quetzal (IFZS) files, the format other interpreters share:
-- dynamic memory as its difference from the story file, plus the call stack.

local quetzal = {}

local pack, unpack = string.pack, string.unpack

-- release, serial number and checksum, which together name a story file
local function story_id(mem)
    return mem.original_bytes(0x02, 2) .. mem.original_bytes(0x12, 6) .. mem.original_bytes(0x1C, 2)
end

local function chunk(id, data)
    return id .. pack(">I4", #data) .. data .. (#data % 2 == 1 and "\0" or "")
end

local function words(list, from, to)
    local parts = {}
    for i = from, to do
        parts[#parts + 1] = pack(">I2", list[i])
    end
    return table.concat(parts)
end

-- CMem: each byte XORed with the story file's, a zero followed by how many more zeros follow it
local function compress_memory(mem)
    local parts, out, n, run = {}, {}, 0, 0
    local function emit(b)
        n = n + 1
        out[n] = b
        if n == 128 then
            parts[#parts + 1] = string.char(table.unpack(out, 1, n))
            n = 0
        end
    end
    for index = 1, mem.page_count() do
        local page = mem.get_page(index)
        local original = mem.original_page(index)
        if not page then
            run = run + #original
        else
            for i = 1, #original do
                local x = page:byte(i) ~ original:byte(i)
                if x == 0 then
                    run = run + 1
                else
                    while run > 0 do
                        local k = math.min(run, 256)
                        emit(0)
                        emit(k - 1)
                        run = run - k
                    end
                    emit(x)
                end
            end
        end
    end
    -- unchanged bytes at the end are left out, as the format allows
    parts[#parts + 1] = string.char(table.unpack(out, 1, n))
    return table.concat(parts)
end

local function stack_chunk(vm)
    local frames, stack = vm.call_stack, vm.stack
    local parts = {}
    -- what the game pushed before calling any routine goes in a frame of its own
    local first_end = frames[1] and frames[1].stack_ptr or #stack
    parts[1] = pack(">I3BBBI2", 0, 0, 0, 0, first_end) .. words(stack, 1, first_end)
    for i, frame in ipairs(frames) do
        local stack_end = frames[i + 1] and frames[i + 1].stack_ptr or #stack
        local locals = #frame.locals
        local flags = locals | (frame.store_result and 0 or 0x10)
        parts[#parts + 1] = pack(">I3BBBI2", frame.return_pc, flags, frame.store_var or 0,
            (1 << frame.num_args) - 1, stack_end - frame.stack_ptr)
            .. words(frame.locals, 1, locals) .. words(stack, frame.stack_ptr + 1, stack_end)
    end
    return table.concat(parts)
end

-- Returns the file's contents for the game as it stands
function quetzal.encode(vm)
    local body = "IFZS"
        .. chunk("IFhd", story_id(vm.mem) .. pack(">I3", vm.pc))
        .. chunk("CMem", compress_memory(vm.mem))
        .. chunk("Stks", stack_chunk(vm))
    return "FORM" .. pack(">I4", #body) .. body
end

local function parse_stacks(data, version)
    local stack, frames = {}, {}
    local pos = 1
    local first = true
    while pos <= #data do
        if pos + 7 > #data then return nil end
        local return_pc, flags, store_var, args, used
        return_pc, flags, store_var, args, used, pos = unpack(">I3BBBI2", data, pos)
        local locals = flags & 0x0F
        if pos + (locals + used) * 2 - 1 > #data then return nil end
        local frame_locals = {}
        for i = 1, locals do
            frame_locals[i], pos = unpack(">I2", data, pos)
        end
        if not (first and version ~= 6) then
            local num_args = 0
            while args & 1 == 1 do
                num_args = num_args + 1
                args = args >> 1
            end
            local store_result = flags & 0x10 == 0
            frames[#frames + 1] = {
                return_pc = return_pc,
                stack_ptr = #stack,
                locals = frame_locals,
                store_result = store_result,
                store_var = store_result and store_var or nil,
                num_args = num_args,
            }
        end
        for _ = 1, used do
            stack[#stack + 1], pos = unpack(">I2", data, pos)
        end
        first = false
    end
    return stack, frames
end

-- how far a CMem chunk reaches, or nil if it is cut short
local function compressed_length(data)
    local addr, i = 0, 1
    while i <= #data do
        if data:byte(i) == 0 then
            if i == #data then return nil end
            addr = addr + data:byte(i + 1) + 1
            i = i + 2
        else
            addr = addr + 1
            i = i + 1
        end
    end
    return addr
end

-- XOR values for one page at a time, so memory use does not grow with the save
local function apply_memory(mem, next_xor)
    local values = {}
    for index = 1, mem.page_count() do
        local original = mem.original_page(index)
        local changed = false
        for i = 1, #original do
            local x = next_xor()
            if x ~= 0 then changed = true end
            values[i] = original:byte(i) ~ x
        end
        mem.set_page(index, changed and string.char(table.unpack(values, 1, #original)))
    end
end

-- Puts the saved game in data into vm; returns true, or false and why not
function quetzal.decode(vm, data)
    local mem = vm.mem
    if #data < 12 or data:sub(1, 4) ~= "FORM" or data:sub(9, 12) ~= "IFZS" then
        return false, "not a saved game"
    end

    local chunks = {}
    local pos = 13
    while pos + 7 <= #data do
        local id, len = data:sub(pos, pos + 3), unpack(">I4", data, pos + 4)
        if pos + 7 + len > #data then return false, "file is cut short" end
        chunks[id] = chunks[id] or { pos + 8, len }
        pos = pos + 8 + len + (len % 2)
    end

    local header = chunks.IFhd
    if not header or header[2] < 13 then return false, "no game header" end
    if data:sub(header[1], header[1] + 9) ~= story_id(mem) then
        return false, "saved from a different story"
    end
    local pc = unpack(">I3", data, header[1] + 10)

    local stks = chunks.Stks
    if not stks then return false, "no stack" end
    local stack, frames = parse_stacks(data:sub(stks[1], stks[1] + stks[2] - 1), vm.version)
    if not stack then return false, "stack is damaged" end

    -- everything is checked before the running game is touched
    local cmem, umem = chunks.CMem, chunks.UMem
    local next_xor
    if cmem then
        local body = data:sub(cmem[1], cmem[1] + cmem[2] - 1)
        local length = compressed_length(body)
        if not length or length > mem.dynamic_size then return false, "memory is damaged" end
        local i, zeros = 1, 0
        next_xor = function()
            if zeros > 0 then
                zeros = zeros - 1
                return 0
            end
            local b = body:byte(i)
            if not b then return 0 end
            if b == 0 then
                zeros = body:byte(i + 1)
                i = i + 2
            else
                i = i + 1
            end
            return b
        end
    elseif umem then
        if umem[2] ~= mem.dynamic_size then return false, "memory is the wrong size" end
        local at, addr = umem[1], 0
        next_xor = function()
            local b = data:byte(at + addr) ~ mem.original_bytes(addr, 1):byte()
            addr = addr + 1
            return b
        end
    else
        return false, "no memory"
    end

    apply_memory(mem, next_xor)
    vm.pc = pc
    vm.stack = stack
    vm.call_stack = frames
    return true
end

return quetzal
