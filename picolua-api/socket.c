/*
 * socket bindings for picocalc_lua
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "../drivers/socket.h"
#include "../drivers/tls.h"
#include "../drivers/wifi.h"
#include "modules.h"

#define SOCKET_HANDLE "Socket"
#define TLS_SOCKET_HANDLE "TLSSocket"
#define SOCKET_VERSION "2.0"

#define DEFAULT_RECV_SIZE 1024
#define MAX_RECV_SIZE 8192

// standard socket
typedef struct {
    socket_handle_t* handle;
} lua_socket_t;

// tls socket
typedef struct {
    tls_socket_t* handle;
} lua_tls_socket_t;


static lua_socket_t* checksocket(lua_State* L, int index) {
    lua_socket_t* sock = (lua_socket_t*)luaL_checkudata(L, index, SOCKET_HANDLE);
    if (sock->handle == NULL) {
        luaL_error(L, "attempt to use a closed socket");
    }
    return sock;
}

static lua_socket_t* tosocket(lua_State* L, int index) {
    return (lua_socket_t*)luaL_checkudata(L, index, SOCKET_HANDLE);
}

static int push_socket_error(lua_State* L, int err) {
    lua_pushnil(L);
    lua_pushstring(L, socket_strerror(err));
    return 2;
}

// socket creation 

// socket.tcp() -> Socket
static int l_socket_tcp(lua_State* L) {
    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    socket_handle_t* handle = socket_tcp_create();
    if (handle == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "failed to create TCP socket");
        return 2;
    }

    lua_socket_t* sock = (lua_socket_t*)lua_newuserdata(L, sizeof(lua_socket_t));
    sock->handle = handle;

    luaL_getmetatable(L, SOCKET_HANDLE);
    lua_setmetatable(L, -2);

    return 1;
}

// socket.udp() -> Socket
static int l_socket_udp(lua_State* L) {
    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    socket_handle_t* handle = socket_udp_create();
    if (handle == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "failed to create UDP socket");
        return 2;
    }

    lua_socket_t* sock = (lua_socket_t*)lua_newuserdata(L, sizeof(lua_socket_t));
    sock->handle = handle;

    luaL_getmetatable(L, SOCKET_HANDLE);
    lua_setmetatable(L, -2);

    return 1;
}

// socket methods

// sock:connect(host, port, [timeout]) -> boolean, err
static int l_socket_connect(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    const char* host = luaL_checkstring(L, 2);
    int port = luaL_checkinteger(L, 3);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 4, 30000);

    if (port < 1 || port > 65535) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "invalid port number");
        return 2;
    }

    int err = socket_connect(sock->handle, host, (uint16_t)port, timeout);
    if (err != SOCKET_OK) {
        lua_pushboolean(L, false);
        lua_pushstring(L, socket_strerror(err));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

// sock:send(data) -> number, err
static int l_socket_send(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    size_t len;
    const char* data = luaL_checklstring(L, 2, &len);

    int sent = socket_send(sock->handle, data, len);
    if (sent < 0) {
        return push_socket_error(L, sent);
    }

    lua_pushinteger(L, sent);
    return 1;
}

// sock:receive([size], [timeout]) -> string, err
static int l_socket_receive(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    int size = luaL_optinteger(L, 2, DEFAULT_RECV_SIZE);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 3, sock->handle->timeout_ms);

    if (size < 1) size = DEFAULT_RECV_SIZE;
    if (size > MAX_RECV_SIZE) size = MAX_RECV_SIZE;

    char* buf = malloc(size);
    if (buf == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }

    int received = socket_receive(sock->handle, buf, size, timeout);

    if (received < 0) {
        free(buf);
        return push_socket_error(L, received);
    }

    lua_pushlstring(L, buf, received);
    free(buf);
    return 1;
}

// sock:close() -> nil
static int l_socket_close(lua_State* L) {
    lua_socket_t* sock = tosocket(L, 1);
    if (sock->handle != NULL) {
        socket_close(sock->handle);
        sock->handle = NULL;
    }
    return 0;
}

// sock:settimeout(seconds) -> nil
static int l_socket_settimeout(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    lua_Number seconds = luaL_checknumber(L, 2);

    uint32_t timeout_ms = (uint32_t)(seconds * 1000);
    socket_settimeout(sock->handle, timeout_ms);

    return 0;
}

// sock:available() -> number
static int l_socket_available(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    size_t available = socket_available(sock->handle);
    lua_pushinteger(L, available);
    return 1;
}

// sock:isconnected() -> boolean
static int l_socket_isconnected(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    lua_pushboolean(L, sock->handle->connected);
    return 1;
}

// tcp server methods

// sock:bind(port, [address]) -> boolean, err
static int l_socket_bind(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    int port = luaL_checkinteger(L, 2);
    const char* address = luaL_optstring(L, 3, NULL);

    if (port < 1 || port > 65535) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "invalid port number");
        return 2;
    }

    int err = socket_bind(sock->handle, (uint16_t)port, address);
    if (err != SOCKET_OK) {
        lua_pushboolean(L, false);
        lua_pushstring(L, socket_strerror(err));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

// sock:listen([backlog]) -> boolean, err
static int l_socket_listen(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    int backlog = luaL_optinteger(L, 2, 5);

    int err = socket_listen(sock->handle, backlog);
    if (err != SOCKET_OK) {
        lua_pushboolean(L, false);
        lua_pushstring(L, socket_strerror(err));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

// sock:accept([timeout]) -> Socket, err
static int l_socket_accept(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 2, 0);

    socket_handle_t* client = socket_accept(sock->handle, timeout);
    if (client == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "accept failed or timeout");
        return 2;
    }

    lua_socket_t* client_sock = (lua_socket_t*)lua_newuserdata(L, sizeof(lua_socket_t));
    client_sock->handle = client;

    luaL_getmetatable(L, SOCKET_HANDLE);
    lua_setmetatable(L, -2);

    return 1;
}

// udp methods

// sock:sendto(data, host, port) -> number, err
static int l_socket_sendto(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    size_t len;
    const char* data = luaL_checklstring(L, 2, &len);
    const char* host = luaL_checkstring(L, 3);
    int port = luaL_checkinteger(L, 4);

    if (port < 1 || port > 65535) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid port number");
        return 2;
    }

    int sent = socket_sendto(sock->handle, data, len, host, (uint16_t)port);
    if (sent < 0) {
        return push_socket_error(L, sent);
    }

    lua_pushinteger(L, sent);
    return 1;
}

// sock:receivefrom([size], [timeout]) -> data, ip, port | nil, err
static int l_socket_receivefrom(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);
    int size = luaL_optinteger(L, 2, DEFAULT_RECV_SIZE);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 3, sock->handle->timeout_ms);

    if (size < 1) size = DEFAULT_RECV_SIZE;
    if (size > MAX_RECV_SIZE) size = MAX_RECV_SIZE;

    char* buf = malloc(size);
    if (buf == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }

    char from_ip[16];
    uint16_t from_port;

    int received = socket_receivefrom(sock->handle, buf, size,
                                       from_ip, sizeof(from_ip), &from_port,
                                       timeout);

    if (received < 0) {
        free(buf);
        return push_socket_error(L, received);
    }

    lua_pushlstring(L, buf, received);
    lua_pushstring(L, from_ip);
    lua_pushinteger(L, from_port);

    free(buf);
    return 3;
}

// icmp ping 

// socket.ping(host, [timeout_ms]) -> result table or nil, err
static int l_socket_ping(lua_State* L) {
    const char* host = luaL_checkstring(L, 1);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 2, 5000);

    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    ping_result_t result;
    int err = socket_ping(host, timeout, &result);

    if (err != SOCKET_OK) {
        lua_pushnil(L);
        lua_pushstring(L, socket_strerror(err));
        return 2;
    }

    // return result table
    lua_newtable(L);
    lua_pushboolean(L, result.success);
    lua_setfield(L, -2, "success");
    lua_pushinteger(L, result.time_ms);
    lua_setfield(L, -2, "time");
    lua_pushinteger(L, result.ttl);
    lua_setfield(L, -2, "ttl");
    lua_pushstring(L, result.ip);
    lua_setfield(L, -2, "ip");

    return 1;
}

// dns resolver

// socket.dns.resolve(hostname) -> ip, err
static int l_socket_dns_resolve(lua_State* L) {
    const char* hostname = luaL_checkstring(L, 1);

    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    char ip[16];
    int err = socket_dns_resolve(hostname, ip, sizeof(ip));
    if (err != SOCKET_OK) {
        return push_socket_error(L, err);
    }

    lua_pushstring(L, ip);
    return 1;
}


// sock:type() -> string ("tcp" or "udp")
static int l_socket_type(lua_State* L) {
    lua_socket_t* sock = checksocket(L, 1);

    if (sock->handle->type == SOCKET_TYPE_TCP) {
        lua_pushstring(L, "tcp");
    } else {
        lua_pushstring(L, "udp");
    }
    return 1;
}

static int l_socket_gc(lua_State* L) {
    lua_socket_t* sock = tosocket(L, 1);
    if (sock->handle != NULL) {
        socket_close(sock->handle);
        sock->handle = NULL;
    }
    return 0;
}

static int l_socket_tostring(lua_State* L) {
    lua_socket_t* sock = tosocket(L, 1);
    if (sock->handle == NULL) {
        lua_pushstring(L, "Socket (closed)");
    } else if (sock->handle->type == SOCKET_TYPE_TCP) {
        if (sock->handle->connected) {
            lua_pushstring(L, "Socket (TCP, connected)");
        } else if (sock->handle->listening) {
            lua_pushstring(L, "Socket (TCP, listening)");
        } else {
            lua_pushstring(L, "Socket (TCP)");
        }
    } else {
        if (sock->handle->bound) {
            lua_pushstring(L, "Socket (UDP, bound)");
        } else {
            lua_pushstring(L, "Socket (UDP)");
        }
    }
    return 1;
}

// tls socket methods

static lua_tls_socket_t* checktlssocket(lua_State* L, int index) {
    lua_tls_socket_t* sock = (lua_tls_socket_t*)luaL_checkudata(L, index, TLS_SOCKET_HANDLE);
    if (sock->handle == NULL) {
        luaL_error(L, "attempt to use a closed TLS socket");
    }
    return sock;
}

static lua_tls_socket_t* totlssocket(lua_State* L, int index) {
    return (lua_tls_socket_t*)luaL_checkudata(L, index, TLS_SOCKET_HANDLE);
}

static int push_tls_error(lua_State* L, int err) {
    lua_pushnil(L);
    lua_pushstring(L, tls_strerror(err));
    return 2;
}

// socket.tls() -> TLSSocket
static int l_socket_tls(lua_State* L) {
    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    tls_socket_t* handle = tls_socket_create();
    if (handle == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "failed to create TLS socket");
        return 2;
    }

    lua_tls_socket_t* sock = (lua_tls_socket_t*)lua_newuserdata(L, sizeof(lua_tls_socket_t));
    sock->handle = handle;

    luaL_getmetatable(L, TLS_SOCKET_HANDLE);
    lua_setmetatable(L, -2);

    return 1;
}

// tlssock:connect(host, port, [timeout]) -> boolean, err
static int l_tls_socket_connect(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    const char* host = luaL_checkstring(L, 2);
    int port = luaL_checkinteger(L, 3);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 4, 30000);

    if (port < 1 || port > 65535) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "invalid port number");
        return 2;
    }

    int err = tls_socket_connect(sock->handle, host, (uint16_t)port, timeout);
    if (err != TLS_OK) {
        lua_pushboolean(L, false);
        lua_pushstring(L, tls_strerror(err));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

// tlssock:send(data) -> number, err
static int l_tls_socket_send(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    size_t len;
    const char* data = luaL_checklstring(L, 2, &len);

    int sent = tls_socket_send(sock->handle, data, len);
    if (sent < 0) {
        return push_tls_error(L, sent);
    }

    lua_pushinteger(L, sent);
    return 1;
}

// tlssock:receive([size], [timeout]) -> string, err
static int l_tls_socket_receive(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    int size = luaL_optinteger(L, 2, DEFAULT_RECV_SIZE);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 3, sock->handle->timeout_ms);

    if (size < 1) size = DEFAULT_RECV_SIZE;
    if (size > MAX_RECV_SIZE) size = MAX_RECV_SIZE;

    char* buf = malloc(size);
    if (buf == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }

    int received = tls_socket_receive(sock->handle, buf, size, timeout);

    if (received < 0) {
        free(buf);
        return push_tls_error(L, received);
    }

    lua_pushlstring(L, buf, received);
    free(buf);
    return 1;
}

// tlssock:close() -> nil
static int l_tls_socket_close(lua_State* L) {
    lua_tls_socket_t* sock = totlssocket(L, 1);
    if (sock->handle != NULL) {
        tls_socket_close(sock->handle);
        sock->handle = NULL;
    }
    return 0;
}

// tlssock:settimeout(seconds) -> nil
static int l_tls_socket_settimeout(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    lua_Number seconds = luaL_checknumber(L, 2);

    uint32_t timeout_ms = (uint32_t)(seconds * 1000);
    tls_socket_settimeout(sock->handle, timeout_ms);

    return 0;
}

// tlssock:available() -> number
static int l_tls_socket_available(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    size_t available = tls_socket_available(sock->handle);
    lua_pushinteger(L, available);
    return 1;
}

// tlssock:isconnected() -> boolean
static int l_tls_socket_isconnected(lua_State* L) {
    lua_tls_socket_t* sock = checktlssocket(L, 1);
    lua_pushboolean(L, tls_socket_isconnected(sock->handle));
    return 1;
}

static int l_tls_socket_gc(lua_State* L) {
    lua_tls_socket_t* sock = totlssocket(L, 1);
    if (sock->handle != NULL) {
        tls_socket_close(sock->handle);
        sock->handle = NULL;
    }
    return 0;
}

static int l_tls_socket_tostring(lua_State* L) {
    lua_tls_socket_t* sock = totlssocket(L, 1);
    if (sock->handle == NULL) {
        lua_pushstring(L, "TLSSocket (closed)");
    } else if (tls_socket_isconnected(sock->handle)) {
        lua_pushstring(L, "TLSSocket (connected)");
    } else {
        lua_pushstring(L, "TLSSocket");
    }
    return 1;
}

// module registration

static const luaL_Reg tls_socket_methods[] = {
    // tls sockers
    {"connect", l_tls_socket_connect},
    {"send", l_tls_socket_send},
    {"receive", l_tls_socket_receive},
    {"close", l_tls_socket_close},
    {"settimeout", l_tls_socket_settimeout},
    {"available", l_tls_socket_available},
    {"isconnected", l_tls_socket_isconnected},

    {"__gc", l_tls_socket_gc},
    {"__close", l_tls_socket_gc},
    {"__tostring", l_tls_socket_tostring},

    {NULL, NULL}
};

static const luaL_Reg socket_methods[] = {
    // tcp & udp sockets
    {"connect", l_socket_connect},
    {"send", l_socket_send},
    {"receive", l_socket_receive},
    {"close", l_socket_close},
    {"settimeout", l_socket_settimeout},
    {"available", l_socket_available},
    {"isconnected", l_socket_isconnected},
    {"type", l_socket_type},

    // tcp server
    {"bind", l_socket_bind},
    {"listen", l_socket_listen},
    {"accept", l_socket_accept},

    // udp 
    {"sendto", l_socket_sendto},
    {"receivefrom", l_socket_receivefrom},

    {"__gc", l_socket_gc},
    {"__close", l_socket_gc},
    {"__tostring", l_socket_tostring},

    {NULL, NULL}
};

static const luaL_Reg socket_funcs[] = {
    {"tcp", l_socket_tcp},
    {"udp", l_socket_udp},
    {"tls", l_socket_tls},
    {"ping", l_socket_ping},
    {NULL, NULL}
};

static const luaL_Reg socket_dns_funcs[] = {
    {"resolve", l_socket_dns_resolve},
    {NULL, NULL}
};

// create metatables and module tables
int luaopen_socket(lua_State* L) {
    luaL_newmetatable(L, SOCKET_HANDLE);
    luaL_setfuncs(L, socket_methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newmetatable(L, TLS_SOCKET_HANDLE);
    luaL_setfuncs(L, tls_socket_methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newlib(L, socket_funcs);

    luaL_newlib(L, socket_dns_funcs);
    lua_setfield(L, -2, "dns");

    lua_pushintegerconstant(L, "TCP", SOCKET_TYPE_TCP);
    lua_pushintegerconstant(L, "UDP", SOCKET_TYPE_UDP);

    lua_pushstring(L, SOCKET_VERSION);
    lua_setfield(L, -2, "_VERSION");

    return 1;
}
