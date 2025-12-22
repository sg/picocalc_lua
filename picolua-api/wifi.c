/*
 * Wi-Fi Lua bindings for PicoCalc
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "../drivers/wifi.h"
#include "modules.h"

// ============================================================
// Initialization Functions
// ============================================================

// wifi.init([country]) -> boolean
// Initialize the Wi-Fi hardware. Optional 2-letter country code (e.g., "US", "GB").
static int l_wifi_init(lua_State* L) {
    const char* country = luaL_optstring(L, 1, NULL);
    bool result;

    if (country != NULL && strlen(country) >= 2) {
        result = wifi_init_with_country(country);
    } else {
        result = wifi_init();
    }

    lua_pushboolean(L, result);
    return 1;
}

// wifi.deinit() -> nil
// Shutdown Wi-Fi hardware and free resources.
static int l_wifi_deinit(lua_State* L) {
    (void)L;
    wifi_deinit();
    return 0;
}

// wifi.isInitialized() -> boolean
// Check if Wi-Fi is initialized.
static int l_wifi_is_initialized(lua_State* L) {
    lua_pushboolean(L, wifi_is_initialized());
    return 1;
}

// ============================================================
// Scanning Functions
// ============================================================

// wifi.scan() -> table|nil, string
// Perform a blocking scan for available networks.
// Returns a table of networks: {{ssid="...", rssi=-50, channel=6, secure=true, authMode=4, bssid="AA:BB:CC:DD:EE:FF"}, ...}
// Returns nil, error_message on failure.
static int l_wifi_scan(lua_State* L) {
    if (!wifi_is_initialized()) {
        lua_pushnil(L);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    int err = wifi_scan_start();
    if (err != 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "scan failed with error %d", err);
        return 2;
    }

    int count = wifi_scan_get_count();

    // Create results table
    lua_createtable(L, count, 0);

    for (int i = 0; i < count; i++) {
        wifi_scan_result_t* r = wifi_scan_get_result(i);
        if (r != NULL) {
            // Create table for this network
            lua_createtable(L, 0, 6);

            // ssid
            lua_pushstring(L, r->ssid);
            lua_setfield(L, -2, "ssid");

            // rssi (signal strength)
            lua_pushinteger(L, r->rssi);
            lua_setfield(L, -2, "rssi");

            // channel
            lua_pushinteger(L, r->channel);
            lua_setfield(L, -2, "channel");

            // secure (boolean - true if any authentication required)
            lua_pushboolean(L, r->auth_mode != 0);
            lua_setfield(L, -2, "secure");

            // authMode (raw value)
            lua_pushinteger(L, r->auth_mode);
            lua_setfield(L, -2, "authMode");

            // bssid (MAC address as string)
            char bssid_str[18];
            snprintf(bssid_str, sizeof(bssid_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                r->bssid[0], r->bssid[1], r->bssid[2],
                r->bssid[3], r->bssid[4], r->bssid[5]);
            lua_pushstring(L, bssid_str);
            lua_setfield(L, -2, "bssid");

            // Add to results array (1-indexed)
            lua_rawseti(L, -2, i + 1);
        }
    }

    // Free scan results after converting to Lua table
    wifi_scan_free();

    return 1;
}

// ============================================================
// Connection Functions
// ============================================================

// wifi.connect(ssid, password, [auth], [timeout_ms]) -> boolean, string|nil
// Connect to a Wi-Fi network (blocking).
// auth: wifi.AUTH_OPEN, wifi.AUTH_WPA2 (default), wifi.AUTH_WPA3
// timeout_ms: connection timeout in milliseconds (default: 30000)
static int l_wifi_connect(lua_State* L) {
    const char* ssid = luaL_checkstring(L, 1);
    const char* password = luaL_optstring(L, 2, "");
    wifi_auth_t auth = (wifi_auth_t)luaL_optinteger(L, 3, WIFI_AUTH_WPA2);
    uint32_t timeout = (uint32_t)luaL_optinteger(L, 4, 30000);

    if (!wifi_is_initialized()) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "Wi-Fi not initialized");
        return 2;
    }

    int result = wifi_connect(ssid, password, auth, timeout);

    if (result == 0) {
        lua_pushboolean(L, true);
        return 1;
    } else {
        lua_pushboolean(L, false);
        // Provide descriptive error message based on result code
        switch (result) {
            case -1:
                lua_pushstring(L, "connection failed");
                break;
            case -2:
                lua_pushstring(L, "network not found");
                break;
            case -3:
                lua_pushstring(L, "authentication failed");
                break;
            default:
                lua_pushfstring(L, "error code %d", result);
                break;
        }
        return 2;
    }
}

// wifi.disconnect() -> nil
// Disconnect from the current Wi-Fi network.
static int l_wifi_disconnect(lua_State* L) {
    (void)L;
    wifi_disconnect();
    return 0;
}

// wifi.status() -> integer
// Get current connection status code.
// Returns wifi.STATUS_DOWN, STATUS_JOIN, STATUS_NOIP, STATUS_UP, etc.
static int l_wifi_status(lua_State* L) {
    lua_pushinteger(L, (int)wifi_get_status());
    return 1;
}

// wifi.isConnected() -> boolean
// Returns true if connected and have an IP address.
static int l_wifi_is_connected(lua_State* L) {
    lua_pushboolean(L, wifi_get_status() == WIFI_STATUS_UP);
    return 1;
}

// ============================================================
// Network Information Functions
// ============================================================

// wifi.getIP() -> string|nil
// Get the current IP address, or nil if not connected.
static int l_wifi_get_ip(lua_State* L) {
    char ip[16];
    if (wifi_get_ip(ip, sizeof(ip))) {
        lua_pushstring(L, ip);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// wifi.getGateway() -> string|nil
// Get the gateway address, or nil if not connected.
static int l_wifi_get_gateway(lua_State* L) {
    char gw[16];
    if (wifi_get_gateway(gw, sizeof(gw))) {
        lua_pushstring(L, gw);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// wifi.getNetmask() -> string|nil
// Get the subnet mask, or nil if not connected.
static int l_wifi_get_netmask(lua_State* L) {
    char nm[16];
    if (wifi_get_netmask(nm, sizeof(nm))) {
        lua_pushstring(L, nm);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// wifi.getInfo() -> table|nil
// Returns a table with all network info: {ip="...", gateway="...", netmask="..."}
// Returns nil if not connected.
static int l_wifi_get_info(lua_State* L) {
    if (wifi_get_status() != WIFI_STATUS_UP) {
        lua_pushnil(L);
        return 1;
    }

    char ip[16], gw[16], nm[16];

    lua_createtable(L, 0, 3);

    if (wifi_get_ip(ip, sizeof(ip))) {
        lua_pushstring(L, ip);
        lua_setfield(L, -2, "ip");
    }

    if (wifi_get_gateway(gw, sizeof(gw))) {
        lua_pushstring(L, gw);
        lua_setfield(L, -2, "gateway");
    }

    if (wifi_get_netmask(nm, sizeof(nm))) {
        lua_pushstring(L, nm);
        lua_setfield(L, -2, "netmask");
    }

    return 1;
}

// ============================================================
// Module Registration
// ============================================================

int luaopen_wifi(lua_State *L) {
    static const luaL_Reg wifilib_f[] = {
        // Initialization
        {"init", l_wifi_init},
        {"deinit", l_wifi_deinit},
        {"isInitialized", l_wifi_is_initialized},

        // Scanning
        {"scan", l_wifi_scan},

        // Connection
        {"connect", l_wifi_connect},
        {"disconnect", l_wifi_disconnect},
        {"status", l_wifi_status},
        {"isConnected", l_wifi_is_connected},

        // Network info
        {"getIP", l_wifi_get_ip},
        {"getGateway", l_wifi_get_gateway},
        {"getNetmask", l_wifi_get_netmask},
        {"getInfo", l_wifi_get_info},

        {NULL, NULL}
    };

    luaL_newlib(L, wifilib_f);

    // Authentication mode constants
    lua_pushintegerconstant(L, "AUTH_OPEN", WIFI_AUTH_OPEN);
    lua_pushintegerconstant(L, "AUTH_WPA2", WIFI_AUTH_WPA2);
    lua_pushintegerconstant(L, "AUTH_WPA3", WIFI_AUTH_WPA3);

    // Status constants
    lua_pushintegerconstant(L, "STATUS_DOWN", WIFI_STATUS_DOWN);
    lua_pushintegerconstant(L, "STATUS_JOIN", WIFI_STATUS_JOIN);
    lua_pushintegerconstant(L, "STATUS_NOIP", WIFI_STATUS_NOIP);
    lua_pushintegerconstant(L, "STATUS_UP", WIFI_STATUS_UP);
    lua_pushintegerconstant(L, "STATUS_FAIL", WIFI_STATUS_FAIL);
    lua_pushintegerconstant(L, "STATUS_NONET", WIFI_STATUS_NONET);
    lua_pushintegerconstant(L, "STATUS_BADAUTH", WIFI_STATUS_BADAUTH);

    return 1;
}
