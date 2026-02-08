-- Z-Machine Object Table Module
-- Handles object tree, attributes, and properties

local objects = {}
objects.VERSION = "1.0"

-- Memory and text module references
local mem = nil
local txt = nil
local version = 3

-- Object table constants (vary by version)
local ATTR_BYTES = 4        -- V1-3: 4 bytes (32 attrs), V4+: 6 bytes (48 attrs)
local RELATION_BYTES = 3    -- V1-3: 1 byte each, V4+: 2 bytes each
local ENTRY_SIZE = 9        -- V1-3: 9 bytes, V4+: 14 bytes
local MAX_OBJECTS = 255     -- V1-3: 255, V4+: 65535

local PARENT_OFFSET = 4
local SIBLING_OFFSET = 5
local CHILD_OFFSET = 6
local PROPS_OFFSET = 7

-- Initialize with memory module reference
function objects.init(memory_module, text_module, ver)
    mem = memory_module
    txt = text_module
    version = ver or 3

    -- Set version-specific constants
    if version >= 4 then
        ATTR_BYTES = 6
        RELATION_BYTES = 6
        ENTRY_SIZE = 14
        MAX_OBJECTS = 65535
        PARENT_OFFSET = 6
        SIBLING_OFFSET = 8
        CHILD_OFFSET = 10
        PROPS_OFFSET = 12
    else
        ATTR_BYTES = 4
        RELATION_BYTES = 3
        ENTRY_SIZE = 9
        MAX_OBJECTS = 255
        PARENT_OFFSET = 4
        SIBLING_OFFSET = 5
        CHILD_OFFSET = 6
        PROPS_OFFSET = 7
    end
end

-- Get base address of object table
local function object_table_base()
    return mem.get_object_table()
end

-- Get address of default properties (before object entries)
local function defaults_addr()
    return object_table_base()
end

-- Get number of default property values
local function num_defaults()
    return (version >= 4) and 63 or 31
end

-- Get address of object entries (after defaults)
local function objects_addr()
    return object_table_base() + (num_defaults() * 2)
end

-- Get address of a specific object entry
local function object_addr(obj)
    if obj < 1 or obj > MAX_OBJECTS then
        error("Invalid object number: " .. obj)
    end
    return objects_addr() + (obj - 1) * ENTRY_SIZE
end

-- Test an attribute on an object
function objects.test_attr(obj, attr)
    if attr < 0 or attr >= (ATTR_BYTES * 8) then
        return false
    end

    local addr = object_addr(obj)
    local byte_num = math.floor(attr / 8)
    local bit_num = 7 - (attr % 8)

    local byte_val = mem.read_byte(addr + byte_num)
    return (byte_val & (1 << bit_num)) ~= 0
end

-- Set an attribute on an object
function objects.set_attr(obj, attr)
    if attr < 0 or attr >= (ATTR_BYTES * 8) then
        return
    end

    local addr = object_addr(obj)
    local byte_num = math.floor(attr / 8)
    local bit_num = 7 - (attr % 8)

    local byte_val = mem.read_byte(addr + byte_num)
    byte_val = byte_val | (1 << bit_num)
    mem.write_byte(addr + byte_num, byte_val)
end

-- Clear an attribute on an object
function objects.clear_attr(obj, attr)
    if attr < 0 or attr >= (ATTR_BYTES * 8) then
        return
    end

    local addr = object_addr(obj)
    local byte_num = math.floor(attr / 8)
    local bit_num = 7 - (attr % 8)

    local byte_val = mem.read_byte(addr + byte_num)
    byte_val = byte_val & (~(1 << bit_num))
    mem.write_byte(addr + byte_num, byte_val)
end

-- Get parent of object
function objects.get_parent(obj)
    local addr = object_addr(obj) + PARENT_OFFSET
    if version >= 4 then
        return mem.read_word(addr)
    else
        return mem.read_byte(addr)
    end
end

-- Get sibling of object
function objects.get_sibling(obj)
    local addr = object_addr(obj) + SIBLING_OFFSET
    if version >= 4 then
        return mem.read_word(addr)
    else
        return mem.read_byte(addr)
    end
end

-- Get child of object
function objects.get_child(obj)
    local addr = object_addr(obj) + CHILD_OFFSET
    if version >= 4 then
        return mem.read_word(addr)
    else
        return mem.read_byte(addr)
    end
end

-- Set parent of object
local function set_parent(obj, parent)
    local addr = object_addr(obj) + PARENT_OFFSET
    if version >= 4 then
        mem.write_word(addr, parent)
    else
        mem.write_byte(addr, parent)
    end
end

-- Set sibling of object
local function set_sibling(obj, sibling)
    local addr = object_addr(obj) + SIBLING_OFFSET
    if version >= 4 then
        mem.write_word(addr, sibling)
    else
        mem.write_byte(addr, sibling)
    end
end

-- Set child of object
local function set_child(obj, child)
    local addr = object_addr(obj) + CHILD_OFFSET
    if version >= 4 then
        mem.write_word(addr, child)
    else
        mem.write_byte(addr, child)
    end
end

-- Remove object from its parent's child list
function objects.remove_obj(obj)
    local parent = objects.get_parent(obj)
    if parent == 0 then
        return  -- Already orphan
    end

    -- Find obj in parent's child list
    local child = objects.get_child(parent)
    if child == obj then
        -- obj is first child, update parent's child to obj's sibling
        set_child(parent, objects.get_sibling(obj))
    else
        -- Find previous sibling
        while child ~= 0 do
            local next_sib = objects.get_sibling(child)
            if next_sib == obj then
                -- Link previous sibling to obj's sibling
                set_sibling(child, objects.get_sibling(obj))
                break
            end
            child = next_sib
        end
    end

    -- Clear obj's parent and sibling
    set_parent(obj, 0)
    set_sibling(obj, 0)
end

-- Insert object as first child of destination
function objects.insert_obj(obj, dest)
    -- First remove from current location
    objects.remove_obj(obj)

    if dest == 0 then
        return  -- Just orphan it
    end

    -- Make obj the first child of dest
    local old_child = objects.get_child(dest)
    set_sibling(obj, old_child)
    set_child(dest, obj)
    set_parent(obj, dest)
end

-- Get address of property table for object
local function props_table_addr(obj)
    local addr = object_addr(obj) + PROPS_OFFSET
    return mem.read_word(addr)
end

-- Get object short name (from property table header)
function objects.get_name(obj)
    local props_addr = props_table_addr(obj)
    local name_len = mem.read_byte(props_addr)  -- Length in words

    if name_len == 0 then
        return ""
    end

    local name, _ = txt.decode(props_addr + 1)
    return name
end

-- Get a property value
-- Returns value, size (or nil if not found)
function objects.get_prop(obj, prop)
    local addr = props_table_addr(obj)

    -- Skip short name
    local name_len = mem.read_byte(addr)
    addr = addr + 1 + (name_len * 2)

    -- Iterate through properties
    while true do
        local size_byte = mem.read_byte(addr)
        if size_byte == 0 then
            break  -- End of properties
        end

        local prop_num, prop_size

        if version >= 4 then
            prop_num = size_byte & 0x3F
            if (size_byte & 0x80) ~= 0 then
                -- Next byte gives size
                local size_byte2 = mem.read_byte(addr + 1)
                prop_size = size_byte2 & 0x3F
                if prop_size == 0 then
                    prop_size = 64  -- Size 0 means 64
                end
                addr = addr + 2
            else
                -- Size in high bit
                prop_size = (size_byte & 0x40) ~= 0 and 2 or 1
                addr = addr + 1
            end
        else
            -- V1-3: size and number packed
            prop_num = size_byte & 0x1F
            prop_size = (size_byte >> 5) + 1
            addr = addr + 1
        end

        if prop_num == prop then
            -- Found it - read value
            if prop_size == 1 then
                return mem.read_byte(addr), 1
            elseif prop_size == 2 then
                return mem.read_word(addr), 2
            else
                -- Return address for larger properties
                return addr, prop_size
            end
        end

        if prop_num < prop then
            -- Properties are in descending order, we've passed it
            break
        end

        addr = addr + prop_size
    end

    -- Not found, return default
    return objects.get_default_prop(prop), 2
end

-- Get default property value
function objects.get_default_prop(prop)
    if prop < 1 or prop > num_defaults() then
        return 0
    end
    local addr = defaults_addr() + (prop - 1) * 2
    return mem.read_word(addr)
end

-- Get address of a property (for put_prop)
function objects.get_prop_addr(obj, prop)
    local addr = props_table_addr(obj)

    -- Skip short name
    local name_len = mem.read_byte(addr)
    addr = addr + 1 + (name_len * 2)

    -- Iterate through properties
    while true do
        local size_byte = mem.read_byte(addr)
        if size_byte == 0 then
            break
        end

        local prop_num, prop_size, data_addr

        if version >= 4 then
            prop_num = size_byte & 0x3F
            if (size_byte & 0x80) ~= 0 then
                local size_byte2 = mem.read_byte(addr + 1)
                prop_size = size_byte2 & 0x3F
                if prop_size == 0 then
                    prop_size = 64
                end
                data_addr = addr + 2
            else
                prop_size = (size_byte & 0x40) ~= 0 and 2 or 1
                data_addr = addr + 1
            end
        else
            prop_num = size_byte & 0x1F
            prop_size = (size_byte >> 5) + 1
            data_addr = addr + 1
        end

        if prop_num == prop then
            return data_addr, prop_size
        end

        if prop_num < prop then
            break
        end

        addr = data_addr + prop_size
    end

    return 0, 0  -- Not found
end

-- Set a property value
function objects.put_prop(obj, prop, value)
    local addr, size = objects.get_prop_addr(obj, prop)

    if addr == 0 then
        error("Property " .. prop .. " not found in object " .. obj)
    end

    if size == 1 then
        mem.write_byte(addr, value & 0xFF)
    elseif size == 2 then
        mem.write_word(addr, value & 0xFFFF)
    else
        error("Cannot put_prop on property of size " .. size)
    end
end

-- Get next property number (for property iteration)
function objects.get_next_prop(obj, prop)
    local addr = props_table_addr(obj)

    -- Skip short name
    local name_len = mem.read_byte(addr)
    addr = addr + 1 + (name_len * 2)

    if prop == 0 then
        -- Return first property
        local size_byte = mem.read_byte(addr)
        if size_byte == 0 then
            return 0
        end
        if version >= 4 then
            return size_byte & 0x3F
        else
            return size_byte & 0x1F
        end
    end

    -- Find the property, then return the next one
    while true do
        local size_byte = mem.read_byte(addr)
        if size_byte == 0 then
            break
        end

        local prop_num, prop_size

        if version >= 4 then
            prop_num = size_byte & 0x3F
            if (size_byte & 0x80) ~= 0 then
                local size_byte2 = mem.read_byte(addr + 1)
                prop_size = size_byte2 & 0x3F
                if prop_size == 0 then
                    prop_size = 64
                end
                addr = addr + 2
            else
                prop_size = (size_byte & 0x40) ~= 0 and 2 or 1
                addr = addr + 1
            end
        else
            prop_num = size_byte & 0x1F
            prop_size = (size_byte >> 5) + 1
            addr = addr + 1
        end

        if prop_num == prop then
            -- Found it, return next
            addr = addr + prop_size
            local next_byte = mem.read_byte(addr)
            if next_byte == 0 then
                return 0
            end
            if version >= 4 then
                return next_byte & 0x3F
            else
                return next_byte & 0x1F
            end
        end

        addr = addr + prop_size
    end

    error("Property " .. prop .. " not found in object " .. obj)
end

-- Get property length given address
function objects.get_prop_len(prop_addr)
    if prop_addr == 0 then
        return 0
    end

    -- The size byte is before the data address
    local size_byte = mem.read_byte(prop_addr - 1)

    if version >= 4 then
        if (size_byte & 0x80) ~= 0 then
            local prop_size = size_byte & 0x3F
            if prop_size == 0 then
                prop_size = 64
            end
            return prop_size
        else
            return (size_byte & 0x40) ~= 0 and 2 or 1
        end
    else
        return (size_byte >> 5) + 1
    end
end

return objects
