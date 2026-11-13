#pragma once

#include <lua.h>
#include <lauxlib.h>

const char *start_editor(lua_State* L, const char* filename);