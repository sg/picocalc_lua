-- Z-Machine Opcodes Module
-- Implements all Z-machine instruction handlers

local opcodes = {}
opcodes.VERSION = "1.0"

-- Module references (set by init)
local vm = nil
local mem = nil
local txt = nil
local obj = nil
local zio = nil

-- Initialize with VM reference
function opcodes.init(vm_module)
    vm = vm_module
    mem = vm.mem
    txt = vm.txt
    obj = vm.obj
    zio = vm.zio
end

-- Helper: signed 16-bit
local function signed16(val)
    if val >= 0x8000 then
        return val - 0x10000
    end
    return val
end

-- Helper: unsigned 16-bit
local function unsigned16(val)
    return val & 0xFFFF
end

-- ============================================================
-- 2OP opcodes (opcodes 1-127 or with operand types)
-- ============================================================

opcodes.op2 = {}

-- 2OP:1 je a b ?(label)
function opcodes.op2.je(ops)
    local a = ops[1]
    for i = 2, #ops do
        if a == ops[i] then
            return vm.branch(true)
        end
    end
    return vm.branch(false)
end

-- 2OP:2 jl a b ?(label)
function opcodes.op2.jl(ops)
    return vm.branch(signed16(ops[1]) < signed16(ops[2]))
end

-- 2OP:3 jg a b ?(label)
function opcodes.op2.jg(ops)
    return vm.branch(signed16(ops[1]) > signed16(ops[2]))
end

-- 2OP:4 dec_chk (variable) value ?(label)
function opcodes.op2.dec_chk(ops)
    local var = ops[1]
    local val = signed16(vm.get_variable(var)) - 1
    vm.set_variable(var, unsigned16(val))
    return vm.branch(val < signed16(ops[2]))
end

-- 2OP:5 inc_chk (variable) value ?(label)
function opcodes.op2.inc_chk(ops)
    local var = ops[1]
    local val = signed16(vm.get_variable(var)) + 1
    vm.set_variable(var, unsigned16(val))
    return vm.branch(val > signed16(ops[2]))
end

-- 2OP:6 jin obj1 obj2 ?(label)
function opcodes.op2.jin(ops)
    return vm.branch(obj.get_parent(ops[1]) == ops[2])
end

-- 2OP:7 test bitmap flags ?(label)
function opcodes.op2.test(ops)
    return vm.branch((ops[1] & ops[2]) == ops[2])
end

-- 2OP:8 or a b -> (result)
function opcodes.op2.bor(ops)
    vm.store(ops[1] | ops[2])
end

-- 2OP:9 and a b -> (result)
function opcodes.op2.band(ops)
    vm.store(ops[1] & ops[2])
end

-- 2OP:10 test_attr object attribute ?(label)
function opcodes.op2.test_attr(ops)
    return vm.branch(obj.test_attr(ops[1], ops[2]))
end

-- 2OP:11 set_attr object attribute
function opcodes.op2.set_attr(ops)
    obj.set_attr(ops[1], ops[2])
end

-- 2OP:12 clear_attr object attribute
function opcodes.op2.clear_attr(ops)
    obj.clear_attr(ops[1], ops[2])
end

-- 2OP:13 store (variable) value
function opcodes.op2.store(ops)
    vm.set_variable(ops[1], ops[2])
end

-- 2OP:14 insert_obj object destination
function opcodes.op2.insert_obj(ops)
    obj.insert_obj(ops[1], ops[2])
end

-- 2OP:15 loadw array word-index -> (result)
function opcodes.op2.loadw(ops)
    local addr = ops[1] + ops[2] * 2
    vm.store(mem.read_word(addr))
end

-- 2OP:16 loadb array byte-index -> (result)
function opcodes.op2.loadb(ops)
    local addr = ops[1] + ops[2]
    vm.store(mem.read_byte(addr))
end

-- 2OP:17 get_prop object property -> (result)
function opcodes.op2.get_prop(ops)
    local val = obj.get_prop(ops[1], ops[2])
    vm.store(val)
end

-- 2OP:18 get_prop_addr object property -> (result)
function opcodes.op2.get_prop_addr(ops)
    local addr = obj.get_prop_addr(ops[1], ops[2])
    vm.store(addr)
end

-- 2OP:19 get_next_prop object property -> (result)
function opcodes.op2.get_next_prop(ops)
    vm.store(obj.get_next_prop(ops[1], ops[2]))
end

-- 2OP:20 add a b -> (result)
function opcodes.op2.add(ops)
    vm.store(unsigned16(signed16(ops[1]) + signed16(ops[2])))
end

-- 2OP:21 sub a b -> (result)
function opcodes.op2.sub(ops)
    vm.store(unsigned16(signed16(ops[1]) - signed16(ops[2])))
end

-- 2OP:22 mul a b -> (result)
function opcodes.op2.mul(ops)
    vm.store(unsigned16(signed16(ops[1]) * signed16(ops[2])))
end

-- 2OP:23 div a b -> (result)
function opcodes.op2.div(ops)
    if ops[2] == 0 then
        error("Division by zero")
    end
    local a = signed16(ops[1])
    local b = signed16(ops[2])
    local result = math.floor(a / b)
    if (a < 0) ~= (b < 0) and a % b ~= 0 then
        result = result + 1  -- Truncate toward zero
    end
    vm.store(unsigned16(result))
end

-- 2OP:24 mod a b -> (result)
function opcodes.op2.mod(ops)
    if ops[2] == 0 then
        error("Division by zero")
    end
    local a = signed16(ops[1])
    local b = signed16(ops[2])
    local result = a % b
    -- Z-machine mod has same sign as dividend
    if a < 0 and result > 0 then
        result = result - math.abs(b)
    elseif a > 0 and result < 0 then
        result = result + math.abs(b)
    end
    vm.store(unsigned16(result))
end

-- 2OP:25 call_2s routine arg1 -> (result) (V4+)
function opcodes.op2.call_2s(ops)
    vm.call(ops[1], {ops[2]}, true)
end

-- 2OP:26 call_2n routine arg1 (V5+)
function opcodes.op2.call_2n(ops)
    vm.call(ops[1], {ops[2]}, false)
end

-- 2OP:27 set_colour foreground background (V5+)
function opcodes.op2.set_colour(ops)
    -- Color not fully supported on terminal
end

-- 2OP:28 throw value stack-frame (V5+)
function opcodes.op2.throw(ops)
    vm.throw(ops[1], ops[2])
end

-- ============================================================
-- 1OP opcodes
-- ============================================================

opcodes.op1 = {}

-- 1OP:0 jz a ?(label)
function opcodes.op1.jz(ops)
    return vm.branch(ops[1] == 0)
end

-- 1OP:1 get_sibling object -> (result) ?(label)
function opcodes.op1.get_sibling(ops)
    local sib = obj.get_sibling(ops[1])
    vm.store(sib)
    return vm.branch(sib ~= 0)
end

-- 1OP:2 get_child object -> (result) ?(label)
function opcodes.op1.get_child(ops)
    local child = obj.get_child(ops[1])
    vm.store(child)
    return vm.branch(child ~= 0)
end

-- 1OP:3 get_parent object -> (result)
function opcodes.op1.get_parent(ops)
    vm.store(obj.get_parent(ops[1]))
end

-- 1OP:4 get_prop_len property-address -> (result)
function opcodes.op1.get_prop_len(ops)
    vm.store(obj.get_prop_len(ops[1]))
end

-- 1OP:5 inc (variable)
function opcodes.op1.inc(ops)
    local val = signed16(vm.get_variable(ops[1])) + 1
    vm.set_variable(ops[1], unsigned16(val))
end

-- 1OP:6 dec (variable)
function opcodes.op1.dec(ops)
    local val = signed16(vm.get_variable(ops[1])) - 1
    vm.set_variable(ops[1], unsigned16(val))
end

-- 1OP:7 print_addr byte-address
function opcodes.op1.print_addr(ops)
    zio.print_addr(ops[1])
end

-- 1OP:8 call_1s routine -> (result) (V4+)
function opcodes.op1.call_1s(ops)
    vm.call(ops[1], {}, true)
end

-- 1OP:9 remove_obj object
function opcodes.op1.remove_obj(ops)
    obj.remove_obj(ops[1])
end

-- 1OP:10 print_obj object
function opcodes.op1.print_obj(ops)
    zio.print_obj(ops[1])
end

-- 1OP:11 ret value
function opcodes.op1.ret(ops)
    vm.ret(ops[1])
end

-- 1OP:12 jump ?(label) - unconditional
function opcodes.op1.jump(ops)
    local offset = signed16(ops[1])
    vm.pc = vm.pc + offset - 2
end

-- 1OP:13 print_paddr packed-address
function opcodes.op1.print_paddr(ops)
    zio.print_paddr(ops[1])
end

-- 1OP:14 load (variable) -> (result)
function opcodes.op1.load(ops)
    local val = vm.get_variable(ops[1])
    vm.store(val)
end

-- 1OP:15 not value -> (result) (V1-4) / call_1n (V5+)
function opcodes.op1.lnot(ops)
    if vm.version >= 5 then
        -- call_1n
        vm.call(ops[1], {}, false)
    else
        vm.store((~ops[1]) & 0xFFFF)
    end
end

-- ============================================================
-- 0OP opcodes
-- ============================================================

opcodes.op0 = {}

-- 0OP:0 rtrue
function opcodes.op0.rtrue()
    vm.ret(1)
end

-- 0OP:1 rfalse
function opcodes.op0.rfalse()
    vm.ret(0)
end

-- 0OP:2 print (literal-string)
function opcodes.op0.print()
    local text_str, len = txt.decode(vm.pc)
    zio.print(text_str)
    vm.pc = vm.pc + len
end

-- 0OP:3 print_ret (literal-string)
function opcodes.op0.print_ret()
    local text_str, len = txt.decode(vm.pc)
    zio.print(text_str)
    zio.newline()
    vm.pc = vm.pc + len
    vm.ret(1)
end

-- 0OP:4 nop
function opcodes.op0.nop()
    -- Do nothing
end

-- 0OP:5 save ?(label) (V1-3) / save -> (result) (V4)
function opcodes.op0.save()
    local success = vm.save_game()
    if vm.version <= 3 then
        return vm.branch(success)
    else
        vm.store(success and 1 or 0)
    end
end

-- 0OP:6 restore ?(label) (V1-3) / restore -> (result) (V4)
function opcodes.op0.restore()
    local success = vm.restore_game()
    if vm.version <= 3 then
        return vm.branch(success)
    else
        vm.store(success and 2 or 0)
    end
end

-- 0OP:7 restart
function opcodes.op0.restart()
    vm.restart()
end

-- 0OP:8 ret_popped
function opcodes.op0.ret_popped()
    vm.ret(vm.pop())
end

-- 0OP:9 pop (V1-4) / catch -> (result) (V5+)
function opcodes.op0.pop()
    if vm.version >= 5 then
        -- catch
        vm.store(vm.get_frame_count())
    else
        vm.pop()
    end
end

-- 0OP:10 quit
function opcodes.op0.quit()
    vm.running = false
end

-- 0OP:11 new_line
function opcodes.op0.new_line()
    zio.newline()
end

-- 0OP:12 show_status (V3)
function opcodes.op0.show_status()
    if vm.version <= 3 then
        vm.update_status_line()
    end
end

-- 0OP:13 verify ?(label)
function opcodes.op0.verify()
    -- For now, always succeed
    return vm.branch(true)
end

-- 0OP:14 [extended opcode prefix] (V5+)
-- Handled specially in decoder

-- 0OP:15 piracy ?(label) (V5+)
function opcodes.op0.piracy()
    return vm.branch(true)  -- We're legitimate!
end

-- ============================================================
-- VAR opcodes
-- ============================================================

opcodes.var = {}

-- VAR:0 call routine ...args -> (result) (V1-3) / call_vs (V4+)
function opcodes.var.call(ops)
    local routine = ops[1]
    local args = {}
    for i = 2, #ops do
        args[i - 1] = ops[i]
    end
    vm.call(routine, args, true)
end

-- VAR:1 storew array word-index value
function opcodes.var.storew(ops)
    local addr = ops[1] + ops[2] * 2
    mem.write_word(addr, ops[3])
end

-- VAR:2 storeb array byte-index value
function opcodes.var.storeb(ops)
    local addr = ops[1] + ops[2]
    mem.write_byte(addr, ops[3])
end

-- VAR:3 put_prop object property value
function opcodes.var.put_prop(ops)
    obj.put_prop(ops[1], ops[2], ops[3])
end

-- VAR:4 sread/aread text parse (V1-4) / aread text parse time routine -> (result) (V5+)
function opcodes.var.sread(ops)
    zio.flush()

    -- Update status line (V1-3)
    if vm.version <= 3 then
        vm.update_status_line()
    end

    -- Read text buffer info
    local text_buf = ops[1]
    local parse_buf = ops[2]

    local max_chars
    if vm.version >= 5 then
        max_chars = mem.read_byte(text_buf)
    else
        max_chars = mem.read_byte(text_buf) - 1  -- V1-4: includes terminator
    end

    -- Get existing text (V5+ only)
    local initial = ""
    if vm.version >= 5 then
        local existing_len = mem.read_byte(text_buf + 1)
        for i = 1, existing_len do
            initial = initial .. string.char(mem.read_byte(text_buf + 2 + i - 1))
        end
    end

    -- Read input
    local input = zio.read_line(max_chars, initial)

    -- Store in text buffer
    if vm.version >= 5 then
        mem.write_byte(text_buf + 1, #input)
        for i = 1, #input do
            mem.write_byte(text_buf + 1 + i, string.byte(input, i))
        end
    else
        for i = 1, #input do
            mem.write_byte(text_buf + i, string.byte(input, i))
        end
        mem.write_byte(text_buf + #input + 1, 0)  -- Null terminator
    end

    -- Tokenize (parse) if parse buffer provided
    if parse_buf ~= 0 then
        vm.tokenize(input, text_buf, parse_buf)
    end

    -- V5+: store terminating character
    if vm.version >= 5 then
        vm.store(13)  -- Enter key
    end
end

-- VAR:5 print_char output-character-code
function opcodes.var.print_char(ops)
    local char = txt.zscii_to_char(ops[1])
    zio.print(char)
end

-- VAR:6 print_num value
function opcodes.var.print_num(ops)
    zio.print_num(signed16(ops[1]))
end

-- VAR:7 random range -> (result)
function opcodes.var.random(ops)
    local range = signed16(ops[1])
    if range <= 0 then
        -- Seed random number generator
        if range == 0 then
            math.randomseed(os.time())
        else
            math.randomseed(-range)
        end
        vm.store(0)
    else
        vm.store(math.random(1, range))
    end
end

-- VAR:8 push value
function opcodes.var.push(ops)
    vm.push(ops[1])
end

-- VAR:9 pull (variable) (V1-5) / pull -> (result) (V6)
function opcodes.var.pull(ops)
    if vm.version == 6 then
        vm.store(vm.pop())
    else
        vm.set_variable(ops[1], vm.pop())
    end
end

-- VAR:10 split_window lines (V3+)
function opcodes.var.split_window(ops)
    zio.split_window(ops[1])
end

-- VAR:11 set_window window (V3+)
function opcodes.var.set_window(ops)
    zio.set_window(ops[1])
end

-- VAR:12 call_vs2 routine ...args -> (result) (V4+)
function opcodes.var.call_vs2(ops)
    local routine = ops[1]
    local args = {}
    for i = 2, #ops do
        args[i - 1] = ops[i]
    end
    vm.call(routine, args, true)
end

-- VAR:13 erase_window window (V4+)
function opcodes.var.erase_window(ops)
    zio.erase_window(signed16(ops[1]))
end

-- VAR:14 erase_line value (V4+)
function opcodes.var.erase_line(ops)
    if ops[1] == 1 then
        zio.erase_line()
    end
end

-- VAR:15 set_cursor line column (V4+)
function opcodes.var.set_cursor(ops)
    zio.set_cursor(ops[1], ops[2] or 1)
end

-- VAR:16 get_cursor array (V4+)
function opcodes.var.get_cursor(ops)
    local x, y = term.getCursorPos()
    mem.write_word(ops[1], y)
    mem.write_word(ops[1] + 2, x)
end

-- VAR:17 set_text_style style (V4+)
function opcodes.var.set_text_style(ops)
    zio.set_style(ops[1])
end

-- VAR:18 buffer_mode flag (V4+)
function opcodes.var.buffer_mode(ops)
    zio.set_buffering(ops[1] ~= 0)
end

-- VAR:19 output_stream stream (V3+)
function opcodes.var.output_stream(ops)
    -- Simplified: we only support stream 1 (screen)
    local stream = signed16(ops[1])
    -- Could implement streams 2 (transcript), 3 (memory), 4 (script)
end

-- VAR:20 input_stream stream (V3+)
function opcodes.var.input_stream(ops)
    -- Only stream 0 (keyboard) supported
end

-- VAR:21 sound_effect number (V3+)
function opcodes.var.sound_effect(ops)
    if ops[1] == 1 then
        zio.beep()  -- High beep
    elseif ops[1] == 2 then
        zio.beep()  -- Low beep
    end
end

-- VAR:22 read_char 1 time routine -> (result) (V4+)
function opcodes.var.read_char(ops)
    local char = zio.read_char()
    vm.store(char)
end

-- VAR:23 scan_table x table len form -> (result) ?(label) (V4+)
function opcodes.var.scan_table(ops)
    local x = ops[1]
    local table_addr = ops[2]
    local len = ops[3]
    local form = ops[4] or 0x82  -- Default: words, field width 2

    local field_len = form & 0x7F
    local is_word = (form & 0x80) ~= 0

    for i = 0, len - 1 do
        local addr = table_addr + i * field_len
        local val = is_word and mem.read_word(addr) or mem.read_byte(addr)
        if val == x then
            vm.store(addr)
            return vm.branch(true)
        end
    end

    vm.store(0)
    return vm.branch(false)
end

-- VAR:24 not value -> (result) (V5+)
function opcodes.var.bnot(ops)
    vm.store((~ops[1]) & 0xFFFF)
end

-- VAR:25 call_vn routine ...args (V5+)
function opcodes.var.call_vn(ops)
    local routine = ops[1]
    local args = {}
    for i = 2, #ops do
        args[i - 1] = ops[i]
    end
    vm.call(routine, args, false)
end

-- VAR:26 call_vn2 routine ...args (V5+)
function opcodes.var.call_vn2(ops)
    opcodes.var.call_vn(ops)
end

-- VAR:27 tokenise text parse dictionary flag (V5+)
function opcodes.var.tokenise(ops)
    local text_buf = ops[1]
    local parse_buf = ops[2]
    local dict = ops[3] or 0
    local flag = ops[4] or 0

    -- Read text from buffer
    local len = mem.read_byte(text_buf + 1)
    local input = ""
    for i = 1, len do
        input = input .. string.char(mem.read_byte(text_buf + 1 + i))
    end

    vm.tokenize(input, text_buf, parse_buf, dict, flag ~= 0)
end

-- VAR:28 encode_text zscii-text length from coded-text (V5+)
function opcodes.var.encode_text(ops)
    local src = ops[1]
    local len = ops[2]
    local from = ops[3]
    local dest = ops[4]

    -- Read text
    local text_str = ""
    for i = 0, len - 1 do
        text_str = text_str .. string.char(mem.read_byte(src + from + i))
    end

    -- Encode
    local words = txt.encode_for_dictionary(text_str, vm.version)

    -- Store
    for i, word in ipairs(words) do
        mem.write_word(dest + (i - 1) * 2, word)
    end
end

-- VAR:29 copy_table first second size (V5+)
function opcodes.var.copy_table(ops)
    local first = ops[1]
    local second = ops[2]
    local size = signed16(ops[3])

    if second == 0 then
        -- Zero first table
        for i = 0, math.abs(size) - 1 do
            mem.write_byte(first + i, 0)
        end
    elseif size < 0 then
        -- Copy forwards (required)
        size = -size
        for i = 0, size - 1 do
            mem.write_byte(second + i, mem.read_byte(first + i))
        end
    else
        -- Copy backwards (for overlapping)
        for i = size - 1, 0, -1 do
            mem.write_byte(second + i, mem.read_byte(first + i))
        end
    end
end

-- VAR:30 print_table zscii-text width height skip (V5+)
function opcodes.var.print_table(ops)
    local addr = ops[1]
    local width = ops[2]
    local height = ops[3] or 1
    local skip = ops[4] or 0

    local x, y = term.getCursorPos()

    for row = 1, height do
        for col = 1, width do
            local c = mem.read_byte(addr)
            zio.print(txt.zscii_to_char(c))
            addr = addr + 1
        end
        addr = addr + skip
        if row < height then
            y = y + 1
            term.setCursorPos(x, y)
        end
    end
end

-- VAR:31 check_arg_count argument-number ?(label) (V5+)
function opcodes.var.check_arg_count(ops)
    return vm.branch(ops[1] <= vm.get_arg_count())
end

-- ============================================================
-- EXT opcodes (V5+)
-- ============================================================

opcodes.ext = {}

-- EXT:0 save table bytes name -> (result) (V5+)
function opcodes.ext.save(ops)
    -- Extended save not implemented, fall back to regular
    local success = vm.save_game()
    vm.store(success and 1 or 0)
end

-- EXT:1 restore table bytes name -> (result) (V5+)
function opcodes.ext.restore(ops)
    local success = vm.restore_game()
    vm.store(success and 2 or 0)
end

-- EXT:2 log_shift number places -> (result) (V5+)
function opcodes.ext.log_shift(ops)
    local num = ops[1]
    local places = signed16(ops[2])
    if places >= 0 then
        vm.store((num << places) & 0xFFFF)
    else
        vm.store(num >> (-places))
    end
end

-- EXT:3 art_shift number places -> (result) (V5+)
function opcodes.ext.art_shift(ops)
    local num = signed16(ops[1])
    local places = signed16(ops[2])
    if places >= 0 then
        vm.store(unsigned16(num << places))
    else
        -- Arithmetic right shift: preserve sign bit
        local shifted = num >> (-places)
        vm.store(unsigned16(shifted))
    end
end

-- EXT:4 set_font font -> (result) (V5+)
function opcodes.ext.set_font(ops)
    -- Font 1 (normal) always available
    if ops[1] == 1 or ops[1] == 4 then
        vm.store(1)
    else
        vm.store(0)
    end
end

-- EXT:9 save_undo -> (result) (V5+)
function opcodes.ext.save_undo(ops)
    local success = vm.save_undo()
    vm.store(success and 1 or 0)
end

-- EXT:10 restore_undo -> (result) (V5+)
function opcodes.ext.restore_undo(ops)
    local success = vm.restore_undo()
    vm.store(success and 2 or 0)
end

-- EXT:11 print_unicode char-number (V5+)
function opcodes.ext.print_unicode(ops)
    -- Map to ASCII approximations
    local char = ops[1]
    if char < 128 then
        zio.print(string.char(char))
    else
        zio.print("?")
    end
end

-- EXT:12 check_unicode char-number -> (result) (V5+)
function opcodes.ext.check_unicode(ops)
    -- Report ASCII as available for input and output
    if ops[1] < 128 then
        vm.store(3)  -- Bits 0,1: can print and read
    else
        vm.store(0)
    end
end

-- EXT:13 set_true_colour foreground background (V5+)
function opcodes.ext.set_true_colour(ops)
    -- Not supported
end

return opcodes
