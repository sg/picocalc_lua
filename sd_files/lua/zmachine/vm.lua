-- Z-Machine Virtual Machine Core
-- Main interpreter loop, instruction decoding, stack management

local vm = {}
vm.VERSION = "1.0"

-- Submodules (loaded lazily)
vm.mem = nil  -- memory
vm.txt = nil  -- text
vm.obj = nil  -- objects
vm.zio = nil  -- io
local ops = nil  -- opcodes

-- VM state
vm.version = 0
vm.pc = 0
vm.running = false
vm.stack = {}
vm.call_stack = {}
vm.undo_state = nil

-- Current instruction state (for opcode handlers)
local current_store_var = nil
local current_branch_data = nil

-- Handler tables (built once during init)
local handlers_0op = nil
local handlers_1op = nil
local handlers_2op = nil
local handlers_var = nil
local handlers_ext = nil

-- Forward declaration
local build_handler_tables

-- Reusable tables to avoid per-instruction allocations
local reuse_operands = {}
local reuse_op_types = {}
local reuse_more_types = {}

-- Clear and reuse a table
local function clear_table(t)
    for i = 1, #t do t[i] = nil end
    return t
end

-- Initialize the VM with a story file
function vm.init(filepath)
    -- Load submodules
    vm.mem = require("lua/zmachine/memory")
    vm.txt = require("lua/zmachine/text")
    vm.obj = require("lua/zmachine/objects")
    vm.zio = require("lua/zmachine/io")
    ops = require("lua/zmachine/opcodes")

    -- Load story file
    local ok, ver_or_err = vm.mem.load(filepath)
    if not ok then
        return false, ver_or_err
    end

    vm.version = ver_or_err

    -- Initialize submodules
    vm.txt.init(vm.mem, vm.version)
    vm.obj.init(vm.mem, vm.txt, vm.version)
    vm.zio.init(vm.mem, vm.txt, vm.version)
    vm.zio.status_hook = (vm.version <= 3) and vm.update_status_line or nil
    ops.init(vm)

    -- Build handler tables (once, not per instruction!)
    build_handler_tables()

    -- Set up header flags
    vm.setup_header()

    -- Initialize state
    vm.pc = vm.mem.get_initial_pc()
    vm.stack = {}
    vm.call_stack = {}
    vm.undo_state = nil
    vm.running = true

    return true, vm.version
end

-- Set up header flags to indicate interpreter capabilities
function vm.setup_header()
    local flags1 = vm.mem.read_byte(vm.mem.HDR_FLAGS1)

    if vm.version <= 3 then
        -- V1-3: Set status line availability, split screen
        flags1 = flags1 | 0x20  -- Status line available
        flags1 = flags1 & (~0x40)  -- Split screen available
    else
        -- V4+: Set capabilities
        flags1 = flags1 | 0x04  -- Bold available
        flags1 = flags1 | 0x08  -- Italic available
        flags1 = flags1 | 0x10  -- Fixed-width available
    end

    vm.mem.write_byte(vm.mem.HDR_FLAGS1, flags1)

    -- Set screen dimensions (at 0x20-0x27 for V4+)
    if vm.version >= 4 then
        local w, h = vm.zio.get_screen_size()
        vm.mem.write_byte(0x20, h)  -- Screen height in lines
        vm.mem.write_byte(0x21, w)  -- Screen width in chars

        if vm.version >= 5 then
            vm.mem.write_word(0x22, w)  -- Screen width in units
            vm.mem.write_word(0x24, h)  -- Screen height in units
            vm.mem.write_byte(0x26, 1)  -- Font width in units
            vm.mem.write_byte(0x27, 1)  -- Font height in units
        end
    end
end

-- Shut down the VM
function vm.shutdown()
    if vm.mem then
        vm.mem.unload()
    end

    -- Unload modules
    package.loaded["lua/zmachine/memory"] = nil
    package.loaded["lua/zmachine/text"] = nil
    package.loaded["lua/zmachine/objects"] = nil
    package.loaded["lua/zmachine/io"] = nil
    package.loaded["lua/zmachine/opcodes"] = nil
    package.loaded["lua/zmachine/quetzal"] = nil

    collectgarbage("collect")
end

-- Main execution loop
function vm.run()
    local gc_counter = 0

    while vm.running do
        vm.execute_instruction()
        gc_counter = gc_counter + 1

        -- Periodic garbage collection
        if gc_counter >= 100 then
            gc_counter = 0
            collectgarbage("collect")
        end
    end
end

-- Execute a single instruction
function vm.execute_instruction()
    local opcode = vm.mem.read_byte(vm.pc)
    vm.pc = vm.pc + 1

    -- Decode instruction form and operand types
    local form, opcode_num
    local op_types = clear_table(reuse_op_types)
    local op_count = 0

    if opcode == 0xBE and vm.version >= 5 then
        -- Extended opcode
        opcode_num = vm.mem.read_byte(vm.pc)
        vm.pc = vm.pc + 1
        form = "ext"
        op_count = vm.decode_var_types_into(op_types)

    elseif (opcode & 0xE0) == 0xE0 then
        -- Variable form VAR opcode (0xE0-0xFF)
        form = "var"
        opcode_num = opcode & 0x1F
        op_count = vm.decode_var_types_into(op_types)

        -- Double-variable (VAR:12, VAR:26)
        if opcode_num == 12 or opcode_num == 26 then
            local more_types = clear_table(reuse_more_types)
            local more_count = vm.decode_var_types_into(more_types)
            for i = 1, more_count do
                op_count = op_count + 1
                op_types[op_count] = more_types[i]
            end
        end

    elseif (opcode & 0xC0) == 0xC0 then
        -- Variable form 2OP opcode (0xC0-0xDF)
        form = "2op"
        opcode_num = opcode & 0x1F
        op_count = vm.decode_var_types_into(op_types)

    elseif (opcode & 0xC0) == 0x80 then
        -- Short form
        local op_type = (opcode & 0x30) >> 4
        opcode_num = opcode & 0x0F

        if op_type == 3 then
            form = "0op"
            op_count = 0
        else
            form = "1op"
            op_types[1] = op_type
            op_count = 1
        end

    else
        -- Long form (2OP)
        form = "2op"
        opcode_num = opcode & 0x1F

        op_types[1] = (opcode & 0x40) ~= 0 and 2 or 1  -- variable or small
        op_types[2] = (opcode & 0x20) ~= 0 and 2 or 1
        op_count = 2
    end

    -- Fetch operands (reuse table)
    local operands = clear_table(reuse_operands)
    local operand_count = 0
    for i = 1, op_count do
        local op_type = op_types[i]
        if op_type == 0 then
            -- Large constant (word)
            operand_count = operand_count + 1
            operands[operand_count] = vm.mem.read_word(vm.pc)
            vm.pc = vm.pc + 2
        elseif op_type == 1 then
            -- Small constant (byte)
            operand_count = operand_count + 1
            operands[operand_count] = vm.mem.read_byte(vm.pc)
            vm.pc = vm.pc + 1
        elseif op_type == 2 then
            -- Variable
            local var = vm.mem.read_byte(vm.pc)
            vm.pc = vm.pc + 1
            operand_count = operand_count + 1
            operands[operand_count] = vm.get_variable(var)
        end
        -- type 3 = omitted (stop)
    end

    -- Execute opcode
    vm.dispatch(form, opcode_num, operands)
end

-- Decode variable-form operand types into provided table
-- Returns count of types decoded
function vm.decode_var_types_into(types)
    local type_byte = vm.mem.read_byte(vm.pc)
    vm.pc = vm.pc + 1

    local count = 0
    for i = 3, 0, -1 do
        local t = (type_byte >> (i * 2)) & 3
        if t == 3 then
            break  -- Omitted, stop
        end
        count = count + 1
        types[count] = t
    end

    return count
end

-- Build handler tables (called once from init)
build_handler_tables = function()
    handlers_0op = {
        [0] = ops.op0.rtrue,
        [1] = ops.op0.rfalse,
        [2] = ops.op0.print,
        [3] = ops.op0.print_ret,
        [4] = ops.op0.nop,
        [5] = ops.op0.save,
        [6] = ops.op0.restore,
        [7] = ops.op0.restart,
        [8] = ops.op0.ret_popped,
        [9] = ops.op0.pop,
        [10] = ops.op0.quit,
        [11] = ops.op0.new_line,
        [12] = ops.op0.show_status,
        [13] = ops.op0.verify,
        [15] = ops.op0.piracy,
    }

    handlers_1op = {
        [0] = ops.op1.jz,
        [1] = ops.op1.get_sibling,
        [2] = ops.op1.get_child,
        [3] = ops.op1.get_parent,
        [4] = ops.op1.get_prop_len,
        [5] = ops.op1.inc,
        [6] = ops.op1.dec,
        [7] = ops.op1.print_addr,
        [8] = ops.op1.call_1s,
        [9] = ops.op1.remove_obj,
        [10] = ops.op1.print_obj,
        [11] = ops.op1.ret,
        [12] = ops.op1.jump,
        [13] = ops.op1.print_paddr,
        [14] = ops.op1.load,
        [15] = ops.op1.lnot,
    }

    handlers_2op = {
        [1] = ops.op2.je,
        [2] = ops.op2.jl,
        [3] = ops.op2.jg,
        [4] = ops.op2.dec_chk,
        [5] = ops.op2.inc_chk,
        [6] = ops.op2.jin,
        [7] = ops.op2.test,
        [8] = ops.op2.bor,
        [9] = ops.op2.band,
        [10] = ops.op2.test_attr,
        [11] = ops.op2.set_attr,
        [12] = ops.op2.clear_attr,
        [13] = ops.op2.store,
        [14] = ops.op2.insert_obj,
        [15] = ops.op2.loadw,
        [16] = ops.op2.loadb,
        [17] = ops.op2.get_prop,
        [18] = ops.op2.get_prop_addr,
        [19] = ops.op2.get_next_prop,
        [20] = ops.op2.add,
        [21] = ops.op2.sub,
        [22] = ops.op2.mul,
        [23] = ops.op2.div,
        [24] = ops.op2.mod,
        [25] = ops.op2.call_2s,
        [26] = ops.op2.call_2n,
        [27] = ops.op2.set_colour,
        [28] = ops.op2.throw,
    }

    handlers_var = {
        [0] = ops.var.call,
        [1] = ops.var.storew,
        [2] = ops.var.storeb,
        [3] = ops.var.put_prop,
        [4] = ops.var.sread,
        [5] = ops.var.print_char,
        [6] = ops.var.print_num,
        [7] = ops.var.random,
        [8] = ops.var.push,
        [9] = ops.var.pull,
        [10] = ops.var.split_window,
        [11] = ops.var.set_window,
        [12] = ops.var.call_vs2,
        [13] = ops.var.erase_window,
        [14] = ops.var.erase_line,
        [15] = ops.var.set_cursor,
        [16] = ops.var.get_cursor,
        [17] = ops.var.set_text_style,
        [18] = ops.var.buffer_mode,
        [19] = ops.var.output_stream,
        [20] = ops.var.input_stream,
        [21] = ops.var.sound_effect,
        [22] = ops.var.read_char,
        [23] = ops.var.scan_table,
        [24] = ops.var.bnot,
        [25] = ops.var.call_vn,
        [26] = ops.var.call_vn2,
        [27] = ops.var.tokenise,
        [28] = ops.var.encode_text,
        [29] = ops.var.copy_table,
        [30] = ops.var.print_table,
        [31] = ops.var.check_arg_count,
    }

    handlers_ext = {
        [0] = ops.ext.save,
        [1] = ops.ext.restore,
        [2] = ops.ext.log_shift,
        [3] = ops.ext.art_shift,
        [4] = ops.ext.set_font,
        [9] = ops.ext.save_undo,
        [10] = ops.ext.restore_undo,
        [11] = ops.ext.print_unicode,
        [12] = ops.ext.check_unicode,
        [13] = ops.ext.set_true_colour,
    }
end

-- Dispatch to opcode handler
function vm.dispatch(form, opcode_num, operands)
    local handler

    if form == "0op" then
        handler = handlers_0op[opcode_num]
    elseif form == "1op" then
        handler = handlers_1op[opcode_num]
    elseif form == "2op" then
        handler = handlers_2op[opcode_num]
    elseif form == "var" then
        handler = handlers_var[opcode_num]
    elseif form == "ext" then
        handler = handlers_ext[opcode_num]
    end

    if handler then
        handler(operands)
    else
        error(string.format("Unimplemented opcode: %s:%d at PC=%04X", form, opcode_num, vm.pc - 1))
    end
end

-- ============================================================
-- Variable access
-- ============================================================

-- Get variable value (0=stack, 1-15=locals, 16-255=globals)
function vm.get_variable(var)
    if var == 0 then
        return vm.pop()
    elseif var <= 15 then
        local frame = vm.call_stack[#vm.call_stack]
        if frame then
            return frame.locals[var] or 0
        end
        return 0
    else
        local globals_base = vm.mem.get_globals()
        return vm.mem.read_word(globals_base + (var - 16) * 2)
    end
end

-- Set variable value
function vm.set_variable(var, value)
    value = value & 0xFFFF

    if var == 0 then
        vm.push(value)
    elseif var <= 15 then
        local frame = vm.call_stack[#vm.call_stack]
        if frame then
            frame.locals[var] = value
        end
    else
        local globals_base = vm.mem.get_globals()
        vm.mem.write_word(globals_base + (var - 16) * 2, value)
    end
end

-- ============================================================
-- Stack operations
-- ============================================================

function vm.push(value)
    table.insert(vm.stack, value & 0xFFFF)
end

function vm.pop()
    if #vm.stack == 0 then
        error("Stack underflow")
    end
    return table.remove(vm.stack)
end

function vm.peek()
    if #vm.stack == 0 then
        return 0
    end
    return vm.stack[#vm.stack]
end

-- ============================================================
-- Call/return
-- ============================================================

-- Call a routine
function vm.call(packed_addr, args, store_result)
    if packed_addr == 0 then
        -- Call to address 0 returns 0
        if store_result then
            vm.read_store_and_store(0)
        end
        return
    end

    local addr = vm.mem.pack_routine_addr(packed_addr, vm.version)

    -- Read number of locals
    local num_locals = vm.mem.read_byte(addr)
    addr = addr + 1

    -- Read store variable BEFORE setting return_pc
    local store_var = nil
    if store_result then
        store_var = vm.mem.read_byte(vm.pc)
        vm.pc = vm.pc + 1  -- Skip store variable
    end

    -- Create call frame (return_pc is now correct - after store variable)
    local frame = {
        return_pc = vm.pc,
        stack_ptr = #vm.stack,
        locals = {},
        store_result = store_result,
        store_var = store_var,
        num_args = #args
    }

    -- Initialize locals
    if vm.version <= 4 then
        -- V1-4: Locals initialized from routine header
        for i = 1, num_locals do
            frame.locals[i] = vm.mem.read_word(addr)
            addr = addr + 2
        end
    else
        -- V5+: Locals initialized to 0
        for i = 1, num_locals do
            frame.locals[i] = 0
        end
    end

    -- Copy arguments to locals
    for i, arg in ipairs(args) do
        if i <= num_locals then
            frame.locals[i] = arg
        end
    end

    table.insert(vm.call_stack, frame)
    vm.pc = addr
end

-- Return from routine
function vm.ret(value)
    if #vm.call_stack == 0 then
        vm.running = false
        return
    end

    local frame = table.remove(vm.call_stack)

    -- Restore stack pointer
    while #vm.stack > frame.stack_ptr do
        table.remove(vm.stack)
    end

    -- Restore PC
    vm.pc = frame.return_pc

    -- Store result if needed
    if frame.store_result then
        vm.set_variable(frame.store_var, value)
    end
end

-- Get number of arguments to current routine
function vm.get_arg_count()
    if #vm.call_stack == 0 then
        return 0
    end
    return vm.call_stack[#vm.call_stack].num_args
end

-- Get call frame count (for catch/throw)
function vm.get_frame_count()
    return #vm.call_stack
end

-- Throw to a specific frame
function vm.throw(value, frame_num)
    while #vm.call_stack > frame_num do
        table.remove(vm.call_stack)
    end
    vm.ret(value)
end

-- ============================================================
-- Branching and storing
-- ============================================================

-- Read store variable and store a value
function vm.read_store_and_store(value)
    local var = vm.mem.read_byte(vm.pc)
    vm.pc = vm.pc + 1
    vm.set_variable(var, value)
end

-- Store result (for opcodes that store)
function vm.store(value)
    vm.read_store_and_store(value)
end

-- Handle branch (for opcodes that branch)
function vm.branch(condition)
    local branch_byte = vm.mem.read_byte(vm.pc)
    vm.pc = vm.pc + 1

    local branch_on_true = (branch_byte & 0x80) ~= 0
    local offset

    if (branch_byte & 0x40) ~= 0 then
        -- Single byte offset (0-63)
        offset = branch_byte & 0x3F
    else
        -- Two byte offset (signed 14-bit)
        local second_byte = vm.mem.read_byte(vm.pc)
        vm.pc = vm.pc + 1
        offset = ((branch_byte & 0x3F) << 8) + second_byte
        -- Sign extend
        if offset >= 0x2000 then
            offset = offset - 0x4000
        end
    end

    -- Should we take the branch?
    if condition == branch_on_true then
        if offset == 0 then
            vm.ret(0)
        elseif offset == 1 then
            vm.ret(1)
        else
            vm.pc = vm.pc + offset - 2
        end
    end
end

-- ============================================================
-- Input parsing (tokenization)
-- ============================================================

function vm.tokenize(input, text_buf, parse_buf, dict_addr, preserve)
    dict_addr = dict_addr or vm.mem.get_dictionary()

    -- Read dictionary structure
    local n_seps = vm.mem.read_byte(dict_addr)
    local separators = {}
    for i = 1, n_seps do
        separators[string.char(vm.mem.read_byte(dict_addr + i))] = true
    end

    local entry_len = vm.mem.read_byte(dict_addr + n_seps + 1)
    local num_entries = vm.mem.read_word(dict_addr + n_seps + 2)
    local entries_addr = dict_addr + n_seps + 4

    -- Parse input into words
    local words = {}
    local word_start = nil
    local pos = 1

    local function add_word(start_pos, end_pos)
        local word = input:sub(start_pos, end_pos)
        table.insert(words, {text = word, start = start_pos, len = end_pos - start_pos + 1})
    end

    while pos <= #input do
        local c = input:sub(pos, pos)

        if c == " " then
            if word_start then
                add_word(word_start, pos - 1)
                word_start = nil
            end
        elseif separators[c] then
            if word_start then
                add_word(word_start, pos - 1)
                word_start = nil
            end
            add_word(pos, pos)  -- Separator is its own word
        else
            if not word_start then
                word_start = pos
            end
        end

        pos = pos + 1
    end

    if word_start then
        add_word(word_start, #input)
    end

    -- Look up words in dictionary
    local max_words = vm.mem.read_byte(parse_buf)
    local word_resolution = (vm.version <= 3) and 6 or 9
    local words_per_entry = (vm.version <= 3) and 2 or 3

    if not preserve then
        -- Clear parse buffer
        vm.mem.write_byte(parse_buf + 1, 0)
    end

    local parsed_count = vm.mem.read_byte(parse_buf + 1)

    for i, w in ipairs(words) do
        if parsed_count >= max_words then
            break
        end

        -- Encode word for dictionary lookup
        local encoded = vm.txt.encode_for_dictionary(w.text, vm.version)

        -- Binary search dictionary
        local dict_entry = 0
        local lo, hi = 0, num_entries - 1

        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local entry_addr = entries_addr + mid * entry_len

            -- Compare encoded words
            local cmp = 0
            for j = 1, words_per_entry do
                local dict_word = vm.mem.read_word(entry_addr + (j - 1) * 2)
                local enc_word = encoded[j] or 0x14A5  -- Padding
                if enc_word < dict_word then
                    cmp = -1
                    break
                elseif enc_word > dict_word then
                    cmp = 1
                    break
                end
            end

            if cmp == 0 then
                dict_entry = entry_addr
                break
            elseif cmp < 0 then
                hi = mid - 1
            else
                lo = mid + 1
            end
        end

        -- Store parse result
        local parse_entry = parse_buf + 2 + parsed_count * 4
        vm.mem.write_word(parse_entry, dict_entry)

        -- Calculate text position
        local text_offset
        if vm.version >= 5 then
            text_offset = w.start + 1  -- After length byte
        else
            text_offset = w.start
        end

        vm.mem.write_byte(parse_entry + 2, w.len)
        vm.mem.write_byte(parse_entry + 3, text_offset)

        parsed_count = parsed_count + 1
    end

    vm.mem.write_byte(parse_buf + 1, parsed_count)
end

-- ============================================================
-- Status line (V3)
-- ============================================================

function vm.update_status_line()
    if vm.version > 3 then
        return
    end

    -- Get current location object (global 0)
    local loc_obj = vm.get_variable(16)  -- Global 0 = var 16
    local location = loc_obj ~= 0 and vm.obj.get_name(loc_obj) or ""

    -- Check if time game (bit 1 of flags1)
    local flags1 = vm.mem.read_byte(vm.mem.HDR_FLAGS1)
    local is_time = (flags1 & 0x02) ~= 0

    local val1 = vm.get_variable(17)  -- Global 1 = score or hours
    local val2 = vm.get_variable(18)  -- Global 2 = moves or minutes
    -- a score can go below zero
    if not is_time and val1 >= 0x8000 then val1 = val1 - 0x10000 end

    vm.zio.draw_status_line(location, val1, val2, is_time)
end

-- ============================================================
-- Save/Restore
-- ============================================================

-- asks for a file name; returns nil if the player gives none
local function ask_filename(prompt)
    vm.zio.print("\n" .. prompt)
    local filename = vm.zio.read_line(64)
    if filename == "" then
        return nil
    end
    if not filename:match("%.sav$") then
        filename = filename .. ".sav"
    end
    return filename
end

function vm.save_game()
    local filename = ask_filename("Save filename: ")
    if not filename then
        return false
    end

    local ok, err = pcall(function()
        local data = require("lua/zmachine/quetzal").encode(vm)
        local file = fs.open(filename, "w")
        file:write(data)
        file:close()
    end)

    if not ok then
        -- a partly written file would pass for a save
        pcall(fs.delete, filename)
        vm.zio.print("Cannot save: " .. tostring(err) .. "\n")
        return false
    end
    return true
end

function vm.restore_game()
    local filename = ask_filename("Restore filename: ")
    if not filename then
        return false
    end

    if not fs.exists(filename) then
        vm.zio.print("Save file not found.\n")
        return false
    end

    -- a restored header carries the saving interpreter's settings; this one's replace them below
    local flags2 = vm.mem.read_word(vm.mem.HDR_FLAGS2)

    local ok, done, err = pcall(function()
        local file = fs.open(filename, "r")
        -- checked before the rest is read, as some other file could be far too large to hold
        local data = file:read(12) or ""
        if data:sub(1, 4) == "FORM" and data:sub(9, 12) == "IFZS" then
            data = data .. (file:read(fs.getSize(filename)) or "")
        end
        file:close()
        return require("lua/zmachine/quetzal").decode(vm, data)
    end)

    if not ok or not done then
        vm.zio.print("Cannot restore: " .. tostring(ok and err or done) .. "\n")
        return false
    end

    vm.mem.write_word(vm.mem.HDR_FLAGS2, flags2)
    vm.setup_header()
    -- the standard has a V3 restore collapse the upper window
    if vm.version <= 3 then vm.zio.split_window(0) end
    return true
end

function vm.save_undo()
    vm.undo_state = {
        pc = vm.pc,
        stack = {},
        call_stack = {},
        dynamic = vm.mem.get_dynamic_snapshot()
    }

    for i, v in ipairs(vm.stack) do
        vm.undo_state.stack[i] = v
    end

    for i, frame in ipairs(vm.call_stack) do
        vm.undo_state.call_stack[i] = {
            return_pc = frame.return_pc,
            stack_ptr = frame.stack_ptr,
            store_result = frame.store_result,
            store_var = frame.store_var,
            num_args = frame.num_args,
            locals = {}
        }
        for j, v in pairs(frame.locals) do
            vm.undo_state.call_stack[i].locals[j] = v
        end
    end

    return true
end

function vm.restore_undo()
    if not vm.undo_state then
        return false
    end

    vm.pc = vm.undo_state.pc
    vm.stack = vm.undo_state.stack
    vm.call_stack = vm.undo_state.call_stack
    vm.mem.restore_dynamic(vm.undo_state.dynamic)
    vm.undo_state = nil

    return true
end

-- Restart the game
function vm.restart()
    -- Reset dynamic memory to original state
    vm.mem.reset_dynamic()

    -- Reset state
    vm.pc = vm.mem.get_initial_pc()
    vm.stack = {}
    vm.call_stack = {}
    vm.undo_state = nil

    vm.setup_header()
    vm.zio.reset()
end

return vm
