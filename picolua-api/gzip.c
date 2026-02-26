#include <stdlib.h>
#include <stddef.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "../pico_fatfs/fatfs/ff.h"
#include "uzlib.h"

#define GZIP_READER    "GzipReader"
#define GZIP_INBUF_SIZE 1024
#define GZIP_DICT_SIZE  32768
#define GZIP_SKIP_BUF   512

typedef struct {
    FIL file;
    struct uzlib_uncomp uncomp;
    uint8_t *dict;
    uint8_t inbuf[GZIP_INBUF_SIZE];
    bool finished;
    bool closed;
} GzipReader;

/* Source read callback for uzlib.
   Reads more compressed data from the FatFS file into inbuf. */
static int gzip_source_cb(struct uzlib_uncomp *d) {
    GzipReader *gz = (GzipReader *)((char *)d - offsetof(GzipReader, uncomp));
    UINT n;
    FRESULT res = f_read(&gz->file, gz->inbuf, GZIP_INBUF_SIZE, &n);
    if (res != FR_OK || n == 0) return -1;
    d->source = gz->inbuf + 1;
    d->source_limit = gz->inbuf + n;
    return gz->inbuf[0];
}

/* gzip.open(path) -> GzipReader */
static int l_gzip_open(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    GzipReader *gz = lua_newuserdata(L, sizeof(GzipReader));
    memset(gz, 0, sizeof(GzipReader));
    luaL_getmetatable(L, GZIP_READER);
    lua_setmetatable(L, -2);

    /* Open the compressed file */
    FRESULT res = f_open(&gz->file, path, FA_READ);
    if (res != FR_OK) {
        return luaL_error(L, "gzip: cannot open '%s'", path);
    }

    /* Allocate dictionary from C heap (not Lua heap) to avoid
       needing a single 32KB contiguous block in the Lua arena */
    gz->dict = malloc(GZIP_DICT_SIZE);
    if (!gz->dict) {
        f_close(&gz->file);
        return luaL_error(L, "gzip: out of memory for dictionary");
    }

    /* Initialize decompressor */
    uzlib_uncompress_init(&gz->uncomp, gz->dict, GZIP_DICT_SIZE);

    /* Read initial compressed data into inbuf */
    UINT n;
    res = f_read(&gz->file, gz->inbuf, GZIP_INBUF_SIZE, &n);
    if (res != FR_OK || n == 0) {
        free(gz->dict);
        gz->dict = NULL;
        f_close(&gz->file);
        return luaL_error(L, "gzip: cannot read '%s'", path);
    }
    gz->uncomp.source = gz->inbuf;
    gz->uncomp.source_limit = gz->inbuf + n;

    /* Parse and validate gzip header */
    int hres = uzlib_gzip_parse_header(&gz->uncomp);
    if (hres != TINF_OK) {
        free(gz->dict);
        gz->dict = NULL;
        f_close(&gz->file);
        return luaL_error(L, "gzip: invalid gzip header");
    }

    /* Set the streaming source callback for subsequent reads */
    gz->uncomp.source_read_cb = gzip_source_cb;

    return 1;
}

static GzipReader *check_reader(lua_State *L) {
    void *ud = luaL_checkudata(L, 1, GZIP_READER);
    luaL_argcheck(L, ud != NULL, 1, "'" GZIP_READER "' expected");
    return (GzipReader *)ud;
}

/* reader:read(n) -> string | nil */
static int l_gzip_read(lua_State *L) {
    GzipReader *gz = check_reader(L);
    if (gz->closed || gz->finished) {
        lua_pushnil(L);
        return 1;
    }

    int n = (int)luaL_checkinteger(L, 2);
    if (n <= 0) {
        lua_pushliteral(L, "");
        return 1;
    }

    /* Use luaL_Buffer so the decompressed data goes directly into the
       Lua string being built — avoids malloc + lua_pushlstring double
       allocation that can OOM on large files. */
    luaL_Buffer b;
    uint8_t *outbuf = (uint8_t *)luaL_buffinitsize(L, &b, (size_t)n);

    gz->uncomp.dest_start = outbuf;
    gz->uncomp.dest = outbuf;
    gz->uncomp.dest_limit = outbuf + n;

    int res = uzlib_uncompress_chksum(&gz->uncomp);

    if (res == TINF_DONE) {
        gz->finished = true;
    } else if (res != TINF_OK) {
        return luaL_error(L, "gzip: decompression error (%d)", res);
    }

    size_t produced = gz->uncomp.dest - outbuf;
    if (produced > 0) {
        luaL_pushresultsize(&b, produced);
    } else {
        lua_pushnil(L);
    }

    return 1;
}

/* reader:seek(whence, offset) -> 0
   Only supports forward seek ("cur" with positive offset). */
static int l_gzip_seek(lua_State *L) {
    GzipReader *gz = check_reader(L);

    /* Accept same calling conventions as fs.seek */
    int offset = 0;
    if (lua_type(L, 2) == LUA_TNUMBER) {
        offset = (int)luaL_checkinteger(L, 2);
    } else {
        const char *whence = luaL_optstring(L, 2, "cur");
        if (strcmp(whence, "cur") != 0) {
            return luaL_error(L, "gzip: only 'cur' seek is supported");
        }
        offset = (int)luaL_optinteger(L, 3, 0);
    }

    if (offset < 0) {
        return luaL_error(L, "gzip: cannot seek backwards");
    }

    if (offset > 0 && !gz->closed && !gz->finished) {
        uint8_t skipbuf[GZIP_SKIP_BUF];
        int remaining = offset;

        while (remaining > 0 && !gz->finished) {
            int chunk = remaining < GZIP_SKIP_BUF ? remaining : GZIP_SKIP_BUF;
            gz->uncomp.dest_start = skipbuf;
            gz->uncomp.dest = skipbuf;
            gz->uncomp.dest_limit = skipbuf + chunk;

            int res = uzlib_uncompress_chksum(&gz->uncomp);
            if (res == TINF_DONE) {
                gz->finished = true;
            } else if (res != TINF_OK) {
                return luaL_error(L, "gzip: decompression error during seek (%d)", res);
            }

            remaining -= (int)(gz->uncomp.dest - skipbuf);
        }
    }

    lua_pushinteger(L, 0);
    return 1;
}

/* Internal close helper */
static void gzip_close_internal(GzipReader *gz) {
    if (gz->closed) return;
    f_close(&gz->file);
    if (gz->dict) {
        free(gz->dict);
        gz->dict = NULL;
    }
    gz->closed = true;
}

/* reader:close() */
static int l_gzip_close(lua_State *L) {
    GzipReader *gz = check_reader(L);
    gzip_close_internal(gz);
    return 0;
}

/* __gc / __close metamethod — safety net */
static int l_gzip_gc(lua_State *L) {
    GzipReader *gz = (GzipReader *)luaL_checkudata(L, 1, GZIP_READER);
    if (gz) gzip_close_internal(gz);
    return 0;
}

int luaopen_gzip(lua_State *L) {
    /* Initialize uzlib lookup tables (must be called once) */
    uzlib_init();

    /* Module functions */
    static const luaL_Reg gzip_funcs[] = {
        {"open", l_gzip_open},
        {NULL, NULL}
    };

    /* GzipReader methods */
    static const luaL_Reg reader_methods[] = {
        {"read",    l_gzip_read},
        {"seek",    l_gzip_seek},
        {"close",   l_gzip_close},
        {"__gc",    l_gzip_gc},
        {"__close", l_gzip_gc},
        {NULL, NULL}
    };

    /* Create module table */
    luaL_newlib(L, gzip_funcs);

    /* Create GzipReader metatable */
    luaL_newmetatable(L, GZIP_READER);
    luaL_setfuncs(L, reader_methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    /* Store metatable as a field of module (same pattern as fs.c) */
    lua_setfield(L, -2, GZIP_READER);

    return 1;
}
