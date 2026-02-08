/*
 * Wi-Fi driver implementation for PicoCalc
 * wraps the cyw43 driver for Pico W boards
 */
#include "wifi.h"

#include "pico/stdlib.h"
#include "pico/cyw43_arch.h"

#include <string.h>
#include <stdlib.h>

// state tracking
static bool wifi_initialized = false;
static wifi_scan_result_t* scan_results = NULL;
static int scan_count = 0;
static volatile bool scan_in_progress = false;
static char connected_ssid[33] = {0};

// max number of scan results to store
#define MAX_SCAN_RESULTS 64

// scan callback for cyw43
static int wifi_scan_callback(void *env, const cyw43_ev_scan_result_t *result) {
    (void)env;

    if (result == NULL) {
        return 0;
    }

    if (scan_count >= MAX_SCAN_RESULTS) {
        return 0;
    }

    // skip empty SSIDs
    if (result->ssid_len == 0) {
        return 0;
    }

    // check for dupe SSIDs (keep the one with stronger signal)
    for (int i = 0; i < scan_count; i++) {
        if (strncmp(scan_results[i].ssid, (const char*)result->ssid, result->ssid_len) == 0 &&
            scan_results[i].ssid[result->ssid_len] == '\0') {
            // dupe found - update if this one has stronger signal
            if (result->rssi > scan_results[i].rssi) {
                scan_results[i].rssi = result->rssi;
                scan_results[i].channel = result->channel;
                memcpy(scan_results[i].bssid, result->bssid, 6);
                scan_results[i].auth_mode = result->auth_mode;
            }
            return 0;
        }
    }

    // allocate/expand results array
    wifi_scan_result_t* new_results = realloc(scan_results, (scan_count + 1) * sizeof(wifi_scan_result_t));
    if (new_results == NULL) {
        return 0;
    }
    scan_results = new_results;

    // store result
    wifi_scan_result_t* r = &scan_results[scan_count];
    memset(r, 0, sizeof(wifi_scan_result_t));

    // copy ssid
    size_t ssid_len = result->ssid_len;
    if (ssid_len > 32) ssid_len = 32;
    memcpy(r->ssid, result->ssid, ssid_len);
    r->ssid[ssid_len] = '\0';

    // copy other fields
    memcpy(r->bssid, result->bssid, 6);
    r->rssi = result->rssi;
    r->channel = result->channel;
    r->auth_mode = result->auth_mode;

    scan_count++;
    return 0;
}

bool wifi_init(void) {
    if (wifi_initialized) {
        return true;
    }

    if (cyw43_arch_init() != 0) {
        return false;
    }

    cyw43_arch_enable_sta_mode();
    wifi_initialized = true;
    return true;
}

bool wifi_init_with_country(const char* country) {
    if (wifi_initialized) {
        return true;
    }

    if (country == NULL || strlen(country) < 2) {
        return wifi_init();
    }

    // convert country string to cyw43 country code
    uint32_t country_code = CYW43_COUNTRY(country[0], country[1], 0);

    if (cyw43_arch_init_with_country(country_code) != 0) {
        return false;
    }

    cyw43_arch_enable_sta_mode();
    wifi_initialized = true;
    return true;
}

void wifi_deinit(void) {
    if (!wifi_initialized) {
        return;
    }

    wifi_scan_free();
    wifi_disconnect();
    cyw43_arch_deinit();
    wifi_initialized = false;
}

bool wifi_is_initialized(void) {
    return wifi_initialized;
}

int wifi_scan_start(void) {
    if (!wifi_initialized) {
        return -1;
    }

    // free any previous results
    wifi_scan_free();

    scan_in_progress = true;

    // start scan
    cyw43_wifi_scan_options_t scan_options = {0};
    int err = cyw43_wifi_scan(&cyw43_state, &scan_options, NULL, wifi_scan_callback);
    if (err != 0) {
        scan_in_progress = false;
        return err;
    }

    // block until scan completes 
    while (cyw43_wifi_scan_active(&cyw43_state)) {
        cyw43_arch_poll();
        sleep_ms(10);
    }

    scan_in_progress = false;
    return 0;
}

int wifi_scan_get_count(void) {
    return scan_count;
}

wifi_scan_result_t* wifi_scan_get_result(int index) {
    if (index < 0 || index >= scan_count || scan_results == NULL) {
        return NULL;
    }
    return &scan_results[index];
}

void wifi_scan_free(void) {
    if (scan_results != NULL) {
        free(scan_results);
        scan_results = NULL;
    }
    scan_count = 0;
}

int wifi_connect(const char* ssid, const char* password, wifi_auth_t auth, uint32_t timeout_ms) {
    if (!wifi_initialized) {
        return WIFI_STATUS_FAIL;
    }

    if (ssid == NULL) {
        return WIFI_STATUS_FAIL;
    }

    // map our auth enum to cyw43 auth type
    uint32_t cyw_auth;
    switch (auth) {
        case WIFI_AUTH_OPEN:
            cyw_auth = CYW43_AUTH_OPEN;
            break;
        case WIFI_AUTH_WPA2:
            cyw_auth = CYW43_AUTH_WPA2_AES_PSK;
            break;
        case WIFI_AUTH_WPA3:
            cyw_auth = CYW43_AUTH_WPA3_SAE_AES_PSK;
            break;
        default:
            cyw_auth = CYW43_AUTH_WPA2_AES_PSK;
            break;
    }

    // handle null/empty password for open networks
    const char* pw = (password != NULL) ? password : "";

    // use timeout if specified, otherwise blocking
    int result;
    if (timeout_ms > 0) {
        result = cyw43_arch_wifi_connect_timeout_ms(ssid, pw, cyw_auth, timeout_ms);
    } else {
        result = cyw43_arch_wifi_connect_blocking(ssid, pw, cyw_auth);
    }

    // the SDK can return spurious errors (like ERR_WOULDBLOCK/-7) even when
    // connection is in progress or failing, so we need to wait for it
   // to finalize
    wifi_status_t status = wifi_get_status();

    // if status is already a definite failure, return it immediately
    if (status == WIFI_STATUS_FAIL ||
        status == WIFI_STATUS_NONET ||
        status == WIFI_STATUS_BADAUTH) {
        connected_ssid[0] = '\0';
        return (int)status;
    }

    // this handles cases where auth failure hasn't propagated to status yet
    if (result != 0 && status != WIFI_STATUS_JOIN && status != WIFI_STATUS_NOIP) {
        // wait up to 2 seconds for status to update with the real error
        absolute_time_t settle_deadline = make_timeout_time_ms(2000);
        while (!time_reached(settle_deadline)) {
            cyw43_arch_poll();
            sleep_ms(100);
            status = wifi_get_status();

            // check for definite failure states
            if (status == WIFI_STATUS_FAIL ||
                status == WIFI_STATUS_NONET ||
                status == WIFI_STATUS_BADAUTH) {
                connected_ssid[0] = '\0';
                return (int)status;
            }
            // check if connection actually succeeded
            if (status == WIFI_STATUS_UP) {
                result = 0;
                break;
            }
            // if we transitioned to JOIN/NOIP, break out to main wait loop
            if (status == WIFI_STATUS_JOIN || status == WIFI_STATUS_NOIP) {
                break;
            }
        }
    }

    // if SDK reported success or we're in an intermediate connected state,
    // wait for full connection (STATUS_UP) or definite failure
    if (result == 0 || status == WIFI_STATUS_JOIN || status == WIFI_STATUS_NOIP) {
        // calculate remaining timeout for DHCP wait
        uint32_t dhcp_timeout_ms = (timeout_ms > 10000) ? 10000 : 5000;
        absolute_time_t deadline = make_timeout_time_ms(dhcp_timeout_ms);

        while (!time_reached(deadline)) {
            cyw43_arch_poll();
            status = wifi_get_status();

            if (status == WIFI_STATUS_UP) {
                // fully connected with IP address
                result = 0;
                break;
            } else if (status == WIFI_STATUS_FAIL ||
                       status == WIFI_STATUS_NONET ||
                       status == WIFI_STATUS_BADAUTH) {
                // definite failure
                result = (int)status;
                break;
            }
            // still in JOIN or NOIP state, keep waiting
            sleep_ms(100);
        }

        // final status check after loop
        status = wifi_get_status();
        if (status == WIFI_STATUS_UP) {
            result = 0;
        } else if (status == WIFI_STATUS_FAIL ||
                   status == WIFI_STATUS_NONET ||
                   status == WIFI_STATUS_BADAUTH) {
            result = (int)status;
        } else if (status == WIFI_STATUS_JOIN || status == WIFI_STATUS_NOIP) {
            // timed out waiting for dhcp but wifi is associated
            result = WIFI_STATUS_FAIL;
        }
    }

    // store ssid on success, clear on failure
    if (result == 0) {
        strncpy(connected_ssid, ssid, sizeof(connected_ssid) - 1);
        connected_ssid[sizeof(connected_ssid) - 1] = '\0';
    } else {
        connected_ssid[0] = '\0';
    }

    return result;
}

void wifi_disconnect(void) {
    if (!wifi_initialized) {
        return;
    }
    cyw43_wifi_leave(&cyw43_state, CYW43_ITF_STA);
    connected_ssid[0] = '\0';
}

wifi_status_t wifi_get_status(void) {
    if (!wifi_initialized) {
        return WIFI_STATUS_DOWN;
    }
    return (wifi_status_t)cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA);
}

bool wifi_get_ip(char* ip_out, size_t ip_len) {
    if (!wifi_initialized || ip_out == NULL || ip_len == 0) {
        return false;
    }

    struct netif* netif = &cyw43_state.netif[CYW43_ITF_STA];
    if (!netif_is_up(netif)) {
        return false;
    }

    const ip4_addr_t* addr = netif_ip4_addr(netif);
    if (ip4_addr_isany_val(*addr)) {
        return false;
    }

    snprintf(ip_out, ip_len, "%s", ip4addr_ntoa(addr));
    return true;
}

bool wifi_get_gateway(char* gw_out, size_t gw_len) {
    if (!wifi_initialized || gw_out == NULL || gw_len == 0) {
        return false;
    }

    struct netif* netif = &cyw43_state.netif[CYW43_ITF_STA];
    if (!netif_is_up(netif)) {
        return false;
    }

    const ip4_addr_t* gw = netif_ip4_gw(netif);
    if (ip4_addr_isany_val(*gw)) {
        return false;
    }

    snprintf(gw_out, gw_len, "%s", ip4addr_ntoa(gw));
    return true;
}

bool wifi_get_netmask(char* nm_out, size_t nm_len) {
    if (!wifi_initialized || nm_out == NULL || nm_len == 0) {
        return false;
    }

    struct netif* netif = &cyw43_state.netif[CYW43_ITF_STA];
    if (!netif_is_up(netif)) {
        return false;
    }

    const ip4_addr_t* nm = netif_ip4_netmask(netif);
    snprintf(nm_out, nm_len, "%s", ip4addr_ntoa(nm));
    return true;
}

bool wifi_get_ssid(char* ssid_out, size_t ssid_len) {
    if (!wifi_initialized || ssid_out == NULL || ssid_len == 0) {
        return false;
    }

    if (connected_ssid[0] == '\0') {
        return false;
    }

    snprintf(ssid_out, ssid_len, "%s", connected_ssid);
    return true;
}

void wifi_poll(void) {
    if (wifi_initialized) {
        cyw43_arch_poll();
    }
}
