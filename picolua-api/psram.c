/*
 * PSRAM buffer module for Lua
 * Provides access to PSRAM for storing large data buffers
 */
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "modules.h"
#include "psram.h"
#ifdef PICOCALC_QSPI_PSRAM
#include "../drivers/psram_qspi.h"
#else
#include "psram_spi.h"
// External reference to PSRAM SPI instance (defined in lcd.c)
extern psram_spi_inst_t psram_spi;
#endif
#include "../drivers/lcd.h"

// External reference to LCD framebuffer mode (defined in lcd.c)
extern int framebuffer_mode;

// Get start address based on LCD mode
// If LCD is using PSRAM buffer mode, reserve space for it
uint32_t psram_get_start_addr(void) {
    if (framebuffer_mode == LCD_BUFFERMODE_PSRAM) {
        return PSRAM_LCD_RESERVE;  // Reserve space for LCD
    }
    return 0;  // LCD not using PSRAM, start from beginning
}

// Get available PSRAM based on LCD mode
uint32_t psram_get_available(void) {
    return PSRAM_TOTAL_SIZE - psram_get_start_addr();
}

// Allocation tracking
static psram_alloc_t allocations[PSRAM_MAX_ALLOCS] = {0};
static bool psram_initialized = false;

// Initialize allocation tracking
static void psram_init_allocator(void) {
    if (!psram_initialized) {
        for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
            allocations[i].in_use = false;
        }
        psram_initialized = true;
    }
}

// Find a free slot in allocation table
static int find_free_slot(void) {
    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (!allocations[i].in_use) {
            return i;
        }
    }
    return -1;
}

// Find allocation by address
static int find_alloc_by_addr(uint32_t addr) {
    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use && allocations[i].addr == addr) {
            return i;
        }
    }
    return -1;
}

// Find allocation by name (returns -1 if not found or name is empty)
static int find_alloc_by_name(const char* name) {
    if (name == NULL || name[0] == '\0') {
        return -1;
    }
    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use && strcmp(allocations[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

// Simple first-fit allocator
// Returns address or PSRAM_ALLOC_FAILED on failure
// Note: 0 is a valid address when LCD is not using PSRAM mode
#define PSRAM_ALLOC_FAILED UINT32_MAX

uint32_t psram_c_alloc(uint32_t size) {
    psram_init_allocator();

    uint32_t available = psram_get_available();
    if (size == 0 || size > available) {
        return PSRAM_ALLOC_FAILED;
    }

    int slot = find_free_slot();
    if (slot < 0) {
        return PSRAM_ALLOC_FAILED;  // No free slots
    }

    // Align size to 4 bytes
    size = (size + 3) & ~3;

    // Build sorted list of allocations by address
    uint32_t sorted_addrs[PSRAM_MAX_ALLOCS];
    uint32_t sorted_sizes[PSRAM_MAX_ALLOCS];
    int count = 0;

    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use) {
            // Insert sorted
            int j = count;
            while (j > 0 && sorted_addrs[j-1] > allocations[i].addr) {
                sorted_addrs[j] = sorted_addrs[j-1];
                sorted_sizes[j] = sorted_sizes[j-1];
                j--;
            }
            sorted_addrs[j] = allocations[i].addr;
            sorted_sizes[j] = allocations[i].size;
            count++;
        }
    }

    // Find first gap that fits
    uint32_t search_addr = psram_get_start_addr();

    for (int i = 0; i < count; i++) {
        uint32_t gap = sorted_addrs[i] - search_addr;
        if (gap >= size) {
            // Found a gap
            allocations[slot].addr = search_addr;
            allocations[slot].size = size;
            allocations[slot].in_use = true;
            return search_addr;
        }
        search_addr = sorted_addrs[i] + sorted_sizes[i];
    }

    // Check space after last allocation
    if (PSRAM_TOTAL_SIZE - search_addr >= size) {
        allocations[slot].addr = search_addr;
        allocations[slot].size = size;
        allocations[slot].in_use = true;
        return search_addr;
    }

    return PSRAM_ALLOC_FAILED;  // No space found
}

// Returns true if freed, false if address was not a valid allocation
bool psram_c_free(uint32_t addr) {
    int slot = find_alloc_by_addr(addr);
    if (slot >= 0) {
        allocations[slot].in_use = false;
        return true;
    }
    return false;
}

void psram_c_write(uint32_t addr, const uint8_t* data, uint32_t len) {
#ifdef PICOCALC_QSPI_PSRAM
    memcpy((void *)(PSRAM_QSPI_BASE + addr), data, len);
#else
    // Write in chunks - PSRAM library uses uint8_t for bit count
    // write_command[0] = (4 + count) * 8, so max count = (255/8) - 4 = 27 bytes
    // Use 20 bytes to match LCD driver and stay safe
    const uint32_t chunk_size = 20;
    while (len > 0) {
        uint32_t to_write = (len > chunk_size) ? chunk_size : len;
        psram_write(&psram_spi, addr, data, to_write);
        addr += to_write;
        data += to_write;
        len -= to_write;
    }
#endif
}

void psram_c_read(uint32_t addr, uint8_t* data, uint32_t len) {
#ifdef PICOCALC_QSPI_PSRAM
    memcpy(data, (void *)(PSRAM_QSPI_BASE + addr), len);
#else
    // Read in chunks - PSRAM library uses uint8_t for bit count
    // read_command[1] = count * 8, so max count = 255/8 = 31 bytes
    // Use 20 bytes to match LCD driver and stay safe
    const uint32_t chunk_size = 20;
    while (len > 0) {
        uint32_t to_read = (len > chunk_size) ? chunk_size : len;
        psram_read(&psram_spi, addr, data, to_read);
        addr += to_read;
        data += to_read;
        len -= to_read;
    }
#endif
}

// Get size of allocation
static uint32_t psram_c_get_size(uint32_t addr) {
    int slot = find_alloc_by_addr(addr);
    if (slot >= 0) {
        return allocations[slot].size;
    }
    return 0;
}

// ============================================================================
// Lua API
// ============================================================================

// psram.alloc(size [, name]) -> handle (address) or nil, error
static int l_psram_alloc(lua_State* L) {
    uint32_t size = (uint32_t)luaL_checkinteger(L, 1);
    const char* name = luaL_optstring(L, 2, NULL);

    // Check for name collision if name provided
    if (name != NULL && name[0] != '\0') {
        if (strlen(name) > PSRAM_NAME_MAX_LEN) {
            lua_pushnil(L);
            lua_pushfstring(L, "name too long (max %d characters)", PSRAM_NAME_MAX_LEN);
            return 2;
        }
        if (find_alloc_by_name(name) >= 0) {
            lua_pushnil(L);
            lua_pushfstring(L, "name '%s' already in use", name);
            return 2;
        }
    }

    uint32_t addr = psram_c_alloc(size);
    if (addr == PSRAM_ALLOC_FAILED) {
        lua_pushnil(L);
        lua_pushstring(L, "allocation failed (out of memory or no free slots)");
        return 2;
    }

    // Set the name for this allocation
    int slot = find_alloc_by_addr(addr);
    if (slot >= 0) {
        if (name != NULL && name[0] != '\0') {
            strncpy(allocations[slot].name, name, PSRAM_NAME_MAX_LEN);
            allocations[slot].name[PSRAM_NAME_MAX_LEN] = '\0';
        } else {
            allocations[slot].name[0] = '\0';  // No name
        }
    }

    lua_pushinteger(L, addr);
    return 1;
}

// psram.free(handle_or_name) -> true on success, nil + error on failure
// handle_or_name can be an address (number) or buffer name (string)
static int l_psram_free(lua_State* L) {
    int slot = -1;

    if (lua_type(L, 1) == LUA_TSTRING) {
        // Lookup by name
        const char* name = lua_tostring(L, 1);
        slot = find_alloc_by_name(name);
        if (slot < 0) {
            lua_pushnil(L);
            lua_pushfstring(L, "no allocation found with name '%s'", name);
            return 2;
        }
    } else if (lua_type(L, 1) == LUA_TNUMBER) {
        // Lookup by address
        uint32_t addr = (uint32_t)lua_tointeger(L, 1);
        slot = find_alloc_by_addr(addr);
        if (slot < 0) {
            lua_pushnil(L);
            lua_pushfstring(L, "invalid handle: %d is not an allocated address", (int)addr);
            return 2;
        }
    } else {
        lua_pushnil(L);
        lua_pushstring(L, "expected address (number) or name (string)");
        return 2;
    }

    allocations[slot].in_use = false;
    allocations[slot].name[0] = '\0';  // Clear the name
    lua_pushboolean(L, true);
    return 1;
}

// psram.find(name) -> handle (address) or nil, error
static int l_psram_find(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);

    if (name[0] == '\0') {
        lua_pushnil(L);
        lua_pushstring(L, "name cannot be empty");
        return 2;
    }

    int slot = find_alloc_by_name(name);
    if (slot < 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "no allocation found with name '%s'", name);
        return 2;
    }

    lua_pushinteger(L, allocations[slot].addr);
    return 1;
}

// psram.getName(handle) -> name or nil if unnamed/invalid
static int l_psram_getname(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);

    int slot = find_alloc_by_addr(addr);
    if (slot < 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    if (allocations[slot].name[0] == '\0') {
        lua_pushnil(L);  // No name set
        return 1;
    }

    lua_pushstring(L, allocations[slot].name);
    return 1;
}

// psram.setName(handle, name) -> true or nil, error
static int l_psram_setname(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);
    const char* name = luaL_optstring(L, 2, NULL);

    int slot = find_alloc_by_addr(addr);
    if (slot < 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    // Check for collision if setting a non-empty name
    if (name != NULL && name[0] != '\0') {
        if (strlen(name) > PSRAM_NAME_MAX_LEN) {
            lua_pushnil(L);
            lua_pushfstring(L, "name too long (max %d characters)", PSRAM_NAME_MAX_LEN);
            return 2;
        }
        int existing = find_alloc_by_name(name);
        if (existing >= 0 && existing != slot) {
            lua_pushnil(L);
            lua_pushfstring(L, "name '%s' already in use", name);
            return 2;
        }
        strncpy(allocations[slot].name, name, PSRAM_NAME_MAX_LEN);
        allocations[slot].name[PSRAM_NAME_MAX_LEN] = '\0';
    } else {
        allocations[slot].name[0] = '\0';  // Clear name
    }

    lua_pushboolean(L, true);
    return 1;
}

// psram.write(handle, offset, data) -> bytes_written
static int l_psram_write(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);
    uint32_t offset = (uint32_t)luaL_checkinteger(L, 2);
    size_t len;
    const char* data = luaL_checklstring(L, 3, &len);

    // Verify this is a valid allocation
    uint32_t alloc_size = psram_c_get_size(addr);
    if (alloc_size == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    // Check bounds
    if (offset >= alloc_size) {
        lua_pushnil(L);
        lua_pushstring(L, "offset out of bounds");
        return 2;
    }

    // Clamp length to available space
    if (offset + len > alloc_size) {
        len = alloc_size - offset;
    }

    psram_c_write(addr + offset, (const uint8_t*)data, len);
    lua_pushinteger(L, len);
    return 1;
}

// psram.read(handle, offset, length) -> string or nil
static int l_psram_read(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);
    uint32_t offset = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t len = (uint32_t)luaL_checkinteger(L, 3);

    // Verify this is a valid allocation
    uint32_t alloc_size = psram_c_get_size(addr);
    if (alloc_size == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    // Check bounds
    if (offset >= alloc_size) {
        lua_pushnil(L);
        lua_pushstring(L, "offset out of bounds");
        return 2;
    }

    // Clamp length
    if (offset + len > alloc_size) {
        len = alloc_size - offset;
    }

    // a Lua buffer is collected for and freed on errors, which malloc is not; a larger one
    // becomes the string itself, so it asks for the terminator Lua adds rather than be reallocated
    luaL_Buffer b;
    char* buf = luaL_buffinitsize(L, &b, len > (uint32_t)LUAL_BUFFERSIZE ? (size_t)len + 1 : len);
    psram_c_read(addr + offset, (uint8_t*)buf, len);
    luaL_pushresultsize(&b, len);

    return 1;
}

// psram.size(handle) -> size or nil
static int l_psram_size(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);

    uint32_t size = psram_c_get_size(addr);
    if (size == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    lua_pushinteger(L, size);
    return 1;
}

// psram.fill(handle, offset, length, byte) -> bytes_filled
static int l_psram_fill(lua_State* L) {
    uint32_t addr = (uint32_t)luaL_checkinteger(L, 1);
    uint32_t offset = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t len = (uint32_t)luaL_checkinteger(L, 3);
    uint8_t byte = (uint8_t)luaL_checkinteger(L, 4);

    // Verify this is a valid allocation
    uint32_t alloc_size = psram_c_get_size(addr);
    if (alloc_size == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    // Check bounds
    if (offset >= alloc_size) {
        lua_pushnil(L);
        lua_pushstring(L, "offset out of bounds");
        return 2;
    }

    // Clamp length
    if (offset + len > alloc_size) {
        len = alloc_size - offset;
    }

    // Fill in chunks using a small buffer
    uint8_t fill_buf[64];
    memset(fill_buf, byte, sizeof(fill_buf));

    uint32_t remaining = len;
    uint32_t write_addr = addr + offset;

    while (remaining > 0) {
        uint32_t to_write = (remaining > sizeof(fill_buf)) ? sizeof(fill_buf) : remaining;
        psram_c_write(write_addr, fill_buf, to_write);
        write_addr += to_write;
        remaining -= to_write;
    }

    lua_pushinteger(L, len);
    return 1;
}

// psram.copy(dest_handle, dest_offset, src_handle, src_offset, length) -> bytes_copied
static int l_psram_copy(lua_State* L) {
    uint32_t dest_addr = (uint32_t)luaL_checkinteger(L, 1);
    uint32_t dest_offset = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t src_addr = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t src_offset = (uint32_t)luaL_checkinteger(L, 4);
    uint32_t len = (uint32_t)luaL_checkinteger(L, 5);

    // Verify allocations
    uint32_t dest_size = psram_c_get_size(dest_addr);
    uint32_t src_size = psram_c_get_size(src_addr);

    if (dest_size == 0 || src_size == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid handle");
        return 2;
    }

    // Check bounds
    if (dest_offset >= dest_size || src_offset >= src_size) {
        lua_pushnil(L);
        lua_pushstring(L, "offset out of bounds");
        return 2;
    }

    // Clamp length
    if (dest_offset + len > dest_size) {
        len = dest_size - dest_offset;
    }
    if (src_offset + len > src_size) {
        len = src_size - src_offset;
    }

    // Copy in chunks using a small RAM buffer
    uint8_t copy_buf[64];
    uint32_t remaining = len;
    uint32_t read_addr = src_addr + src_offset;
    uint32_t write_addr = dest_addr + dest_offset;

    while (remaining > 0) {
        uint32_t to_copy = (remaining > sizeof(copy_buf)) ? sizeof(copy_buf) : remaining;
        psram_c_read(read_addr, copy_buf, to_copy);
        psram_c_write(write_addr, copy_buf, to_copy);
        read_addr += to_copy;
        write_addr += to_copy;
        remaining -= to_copy;
    }

    lua_pushinteger(L, len);
    return 1;
}

// psram.stats() -> table with total, available, used, free, allocations
static int l_psram_stats(lua_State* L) {
    psram_init_allocator();

    uint32_t total_allocated = 0;
    int alloc_count = 0;

    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use) {
            total_allocated += allocations[i].size;
            alloc_count++;
        }
    }

    uint32_t available = psram_get_available();
    uint32_t reserved = psram_get_start_addr();

    lua_newtable(L);

    lua_pushinteger(L, PSRAM_TOTAL_SIZE);
    lua_setfield(L, -2, "total");

    lua_pushinteger(L, available);
    lua_setfield(L, -2, "available");

    lua_pushinteger(L, total_allocated);
    lua_setfield(L, -2, "used");

    lua_pushinteger(L, available - total_allocated);
    lua_setfield(L, -2, "free");

    lua_pushinteger(L, alloc_count);
    lua_setfield(L, -2, "allocations");

    lua_pushinteger(L, PSRAM_MAX_ALLOCS);
    lua_setfield(L, -2, "maxAllocations");

    lua_pushinteger(L, reserved);
    lua_setfield(L, -2, "reserved");

    // Also indicate if LCD is using PSRAM
    lua_pushboolean(L, framebuffer_mode == LCD_BUFFERMODE_PSRAM);
    lua_setfield(L, -2, "lcdUsingPsram");

#ifdef PICOCALC_QSPI_PSRAM
    lua_pushboolean(L, true);
#else
    lua_pushboolean(L, false);
#endif
    lua_setfield(L, -2, "qspi");

    return 1;
}

// psram.list() -> table of {addr, size} for each allocation
static int l_psram_list(lua_State* L) {
    psram_init_allocator();

    lua_newtable(L);
    int idx = 1;

    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use) {
            lua_newtable(L);
            lua_pushinteger(L, allocations[i].addr);
            lua_setfield(L, -2, "addr");
            lua_pushinteger(L, allocations[i].size);
            lua_setfield(L, -2, "size");
            if (allocations[i].name[0] != '\0') {
                lua_pushstring(L, allocations[i].name);
            } else {
                lua_pushnil(L);
            }
            lua_setfield(L, -2, "name");
            lua_rawseti(L, -2, idx++);
        }
    }

    return 1;
}

// psram.freeAll() -> count of allocations freed, total bytes freed
static int l_psram_freeall(lua_State* L) {
    psram_init_allocator();

    int count = 0;
    uint32_t total_bytes = 0;

    for (int i = 0; i < PSRAM_MAX_ALLOCS; i++) {
        if (allocations[i].in_use) {
            count++;
            total_bytes += allocations[i].size;
            allocations[i].in_use = false;
        }
    }

    lua_pushinteger(L, count);
    lua_pushinteger(L, total_bytes);
    return 2;
}

// Module registration
int luaopen_psram(lua_State *L) {
    static const luaL_Reg psramlib_f[] = {
        {"alloc", l_psram_alloc},
        {"free", l_psram_free},
        {"find", l_psram_find},
        {"getName", l_psram_getname},
        {"setName", l_psram_setname},
        {"write", l_psram_write},
        {"read", l_psram_read},
        {"size", l_psram_size},
        {"fill", l_psram_fill},
        {"copy", l_psram_copy},
        {"stats", l_psram_stats},
        {"list", l_psram_list},
        {"freeAll", l_psram_freeall},
        {NULL, NULL}
    };

    luaL_newlib(L, psramlib_f);

    // Add constants
    lua_pushintegerconstant(L, "TOTAL_SIZE", PSRAM_TOTAL_SIZE);
    lua_pushintegerconstant(L, "LCD_RESERVE_SIZE", PSRAM_LCD_RESERVE);
    lua_pushintegerconstant(L, "MAX_ALLOCATIONS", PSRAM_MAX_ALLOCS);
    lua_pushintegerconstant(L, "NAME_MAX_LEN", PSRAM_NAME_MAX_LEN);
    // Note: available/reserved are dynamic based on LCD mode - use stats() to get current values

    // Version
    lua_pushstring(L, "1.1");
    lua_setfield(L, -2, "_VERSION");

    return 1;
}
