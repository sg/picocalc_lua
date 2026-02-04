/*
 * Wi-Fi driver for PicoCalc
 * wraps the cyw43 driver for Pico W boards
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// wifi status codes (maps to cyw43 link status)
typedef enum {
    WIFI_STATUS_DOWN = 0, // link down
    WIFI_STATUS_JOIN = 1, // connected to wifi
    WIFI_STATUS_NOIP = 2, // connected but no IP yet
    WIFI_STATUS_UP = 3, // connected with IP address
    WIFI_STATUS_FAIL = -1, // connection failed
    WIFI_STATUS_NONET = -2, // ssid not found
    WIFI_STATUS_BADAUTH = -3 // authentication failed
} wifi_status_t;

// auth modes
typedef enum {
    WIFI_AUTH_OPEN = 0,
    WIFI_AUTH_WPA2 = 1,
    WIFI_AUTH_WPA3 = 2
} wifi_auth_t;

// scan result entry
typedef struct {
    char ssid[33]; // max ssid length (32) + null terminator
    uint8_t bssid[6]; // mac address
    int16_t rssi; // signal strength (dBm)
    uint8_t channel; // wifi channel
    uint8_t auth_mode; // 0=open, non-zero=secured
} wifi_scan_result_t;

// init and shutdown
bool wifi_init(void);
bool wifi_init_with_country(const char* country);
void wifi_deinit(void);
bool wifi_is_initialized(void);

// scanning
int wifi_scan_start(void);
int wifi_scan_get_count(void);
wifi_scan_result_t* wifi_scan_get_result(int index);
void wifi_scan_free(void);

// connection management
int wifi_connect(const char* ssid, const char* password, wifi_auth_t auth, uint32_t timeout_ms);
void wifi_disconnect(void);
wifi_status_t wifi_get_status(void);

// network info
bool wifi_get_ip(char* ip_out, size_t ip_len);
bool wifi_get_gateway(char* gw_out, size_t gw_len);
bool wifi_get_netmask(char* nm_out, size_t nm_len);
bool wifi_get_ssid(char* ssid_out, size_t ssid_len);

// background processing (call from picolua.c main loop)
void wifi_poll(void);
