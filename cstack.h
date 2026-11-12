#pragma once

// Lua runs on core 1, whose stack starts at the top of SCRATCH_X. That region holds 4 KB and Lua needs
// several times as much, so the stack carries on down through this much of what the SDK would give the heap.
#define LUA_CSTACK_BELOW_SCRATCH (12 * 1024)

// what the stack is filled with at start, so that how far it has ever reached can be read back
#define LUA_CSTACK_PAINT 0xA5

char* lua_cstack_bottom(void);
char* lua_cstack_top(void);
