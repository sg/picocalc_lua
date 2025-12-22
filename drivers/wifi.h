/*
 * Wi-Fi driver interface for PicoCalc
 * Wraps the CYW43 driver for Pico W boards
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// Wi-Fi status codes (maps to CYW43 link status)
typedef enum {
    WIFI_STATUS_DOWN    = 0,   // Link down
    WIFI_STATUS_JOIN    = 1,   // Connected to WiFi
    WIFI_STATUS_NOIP    = 2,   // Connected but no IP yet
    WIFI_STATUS_UP      = 3,   // Connected with IP address
    WIFI_STATUS_FAIL    = -1,  // Connection failed
    WIFI_STATUS_NONET   = -2,  // SSID not found
    WIFI_STATUS_BADAUTH = -3   // Authentication failed
} wifi_status_t;

// Authentication modes
typedef enum {
    WIFI_AUTH_OPEN = 0,
    WIFI_AUTH_WPA2 = 1,
    WIFI_AUTH_WPA3 = 2
} wifi_auth_t;

// Scan result entry
typedef struct {
    char ssid[33];        // Max SSID length (32) + null terminator
    uint8_t bssid[6];     // MAC address
    int16_t rssi;         // Signal strength (dBm)
    uint8_t channel;      // Wi-Fi channel
    uint8_t auth_mode;    // 0=open, non-zero=secured
} wifi_scan_result_t;

// Initialization and shutdown
bool wifi_init(void);
bool wifi_init_with_country(const char* country);
void wifi_deinit(void);
bool wifi_is_initialized(void);

// Scanning
int wifi_scan_start(void);
int wifi_scan_get_count(void);
wifi_scan_result_t* wifi_scan_get_result(int index);
void wifi_scan_free(void);

// Connection management
int wifi_connect(const char* ssid, const char* password, wifi_auth_t auth, uint32_t timeout_ms);
void wifi_disconnect(void);
wifi_status_t wifi_get_status(void);

// Network information
bool wifi_get_ip(char* ip_out, size_t ip_len);
bool wifi_get_gateway(char* gw_out, size_t gw_len);
bool wifi_get_netmask(char* nm_out, size_t nm_len);

// Background processing (call from main loop)
void wifi_poll(void);
