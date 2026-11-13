#pragma once
#include <stdbool.h>
#include <stddef.h>
typedef struct lua_State lua_State;
#define LUA_OK 0
#define LUA_GCCOLLECT 2
int lua_gc(lua_State *L, int what, ...);
int lua_getglobal(lua_State *L, const char *name);
int lua_pcall(lua_State *L, int nargs, int nresults, int msgh);
const char *lua_tostring(lua_State *L, int idx);
