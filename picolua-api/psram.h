/*
 * PSRAM buffer module for Lua
 * Provides access to PSRAM for storing large data buffers
 */
#pragma once

#include <lua.h>
#include <stdint.h>
#include <stdbool.h>

// PSRAM configuration
#define PSRAM_TOTAL_SIZE    (8 * 1024 * 1024)  // 8MB total PSRAM
#define PSRAM_LCD_RESERVE   (320 * 320 * 2)     // LCD framebuffer size when in PSRAM mode (204800 bytes)

// Dynamic reservation - call psram_get_start_addr() to get actual start address
// which depends on whether LCD is using PSRAM buffer mode
uint32_t psram_get_start_addr(void);
uint32_t psram_get_available(void);

// Maximum number of allocations tracked
#define PSRAM_MAX_ALLOCS    32
#define PSRAM_NAME_MAX_LEN  31  // Max name length (+ null terminator = 32 bytes)

// Allocation block info
typedef struct {
    uint32_t addr;      // Start address in PSRAM
    uint32_t size;      // Size of allocation
    bool in_use;        // Whether this slot is in use
    char name[32];      // Optional name for the allocation
} psram_alloc_t;

// Module functions
int luaopen_psram(lua_State *L);

// Error return value for psram_c_alloc (0 is valid when LCD not using PSRAM)
#define PSRAM_ALLOC_FAILED UINT32_MAX

// C API for other modules (e.g., HTTP) to use
// Returns address on success, PSRAM_ALLOC_FAILED on failure
uint32_t psram_c_alloc(uint32_t size);
bool psram_c_free(uint32_t addr);  // Returns true if freed, false if invalid address
void psram_c_write(uint32_t addr, const uint8_t* data, uint32_t len);
void psram_c_read(uint32_t addr, uint8_t* data, uint32_t len);
