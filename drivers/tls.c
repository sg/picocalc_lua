/*
 * TLS socket driver for PicoCalc
 * uses lwIP altcp_tls with mbedTLS
 */
#include "tls.h"
#include "wifi.h"
#include "socket.h"

#include "pico/stdlib.h"
#include "pico/cyw43_arch.h"

#include "lwip/altcp.h"
#include "lwip/altcp_tls.h"
#include "lwip/dns.h"
#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"

#include <stdlib.h>
#include <string.h>

// global tls config (shared, no cert verification)
static struct altcp_tls_config* g_tls_config = NULL;
static int g_tls_init_count = 0;

// copy data to circular buffer
static size_t tls_recv_buf_write(tls_socket_t* sock, const uint8_t* data, size_t len) {
    size_t written = 0;
    while (written < len && sock->recv_len < TLS_RECV_BUF_SIZE) {
        sock->recv_buf[sock->recv_head] = data[written];
        sock->recv_head = (sock->recv_head + 1) % TLS_RECV_BUF_SIZE;
        sock->recv_len++;
        written++;
    }
    return written;
}

// read data from buffer
static size_t tls_recv_buf_read(tls_socket_t* sock, uint8_t* data, size_t maxlen) {
    size_t rd = 0;
    while (rd < maxlen && sock->recv_len > 0) {
        data[rd] = sock->recv_buf[sock->recv_tail];
        sock->recv_tail = (sock->recv_tail + 1) % TLS_RECV_BUF_SIZE;
        sock->recv_len--;
        rd++;
    }
    return rd;
}

// altcp receive callback
static err_t tls_recv_callback(void* arg, struct altcp_pcb* pcb, struct pbuf* p, err_t err) {
    tls_socket_t* sock = (tls_socket_t*)arg;

    if (p == NULL) {
        // connection closed
        sock->connected = false;
        sock->last_error = TLS_ERR_CLOSED;
        return ERR_OK;
    }

    if (err != ERR_OK) {
        pbuf_free(p);
        sock->last_error = TLS_ERR_FAILED;
        return err;
    }

    // copy data to receive buffer
    struct pbuf* q = p;
    size_t total_copied = 0;
    while (q != NULL) {
        size_t copied = tls_recv_buf_write(sock, (uint8_t*)q->payload, q->len);
        total_copied += copied;
        if (copied < q->len) {
            break;  // buffer full
        }
        q = q->next;
    }

    // ack received data
    altcp_recved(pcb, total_copied);
    pbuf_free(p);

    return ERR_OK;
}

// altcp err callback
static void tls_err_callback(void* arg, err_t err) {
    tls_socket_t* sock = (tls_socket_t*)arg;

    sock->connected = false;
    sock->handshake_done = false;
    sock->pcb = NULL;  // pcb already freed

    switch (err) {
        case ERR_ABRT:
            sock->last_error = TLS_ERR_CLOSED;
            break;
        case ERR_RST:
            sock->last_error = TLS_ERR_CLOSED;
            break;
        case ERR_CLSD:
            sock->last_error = TLS_ERR_CLOSED;
            break;
        default:
            sock->last_error = TLS_ERR_FAILED;
            break;
    }

    sock->op_complete = true;
}

// altcp connected callback
static err_t tls_connected_callback(void* arg, struct altcp_pcb* pcb, err_t err) {
    tls_socket_t* sock = (tls_socket_t*)arg;

    if (err == ERR_OK) {
        sock->connected = true;
        sock->handshake_done = true;
        sock->last_error = TLS_OK;
    } else {
        sock->last_error = TLS_ERR_HANDSHAKE;
    }

    sock->op_complete = true;
    return ERR_OK;
}

// init
int tls_init(void) {
    if (g_tls_init_count > 0) {
        g_tls_init_count++;
        return TLS_OK;
    }

    if (!wifi_is_initialized()) {
        return TLS_ERR_FAILED;
    }

    cyw43_arch_lwip_begin();
    // create client config,  no CA cert = no verification
    g_tls_config = altcp_tls_create_config_client(NULL, 0);
    cyw43_arch_lwip_end();

    if (g_tls_config == NULL) {
        return TLS_ERR_NOMEM;
    }

    g_tls_init_count = 1;
    return TLS_OK;
}

// deinit
void tls_deinit(void) {
    if (g_tls_init_count > 0) {
        g_tls_init_count--;
        if (g_tls_init_count == 0 && g_tls_config != NULL) {
            cyw43_arch_lwip_begin();
            altcp_tls_free_config(g_tls_config);
            cyw43_arch_lwip_end();
            g_tls_config = NULL;
        }
    }
}

tls_socket_t* tls_socket_create(void) {
    if (!wifi_is_initialized()) {
        return NULL;
    }

    // auto-init tls if not done
    if (g_tls_config == NULL) {
        if (tls_init() != TLS_OK) {
            return NULL;
        }
    }

    tls_socket_t* sock = calloc(1, sizeof(tls_socket_t));
    if (sock == NULL) {
        return NULL;
    }

    cyw43_arch_lwip_begin();
    sock->pcb = altcp_tls_new(g_tls_config, IPADDR_TYPE_V4);
    cyw43_arch_lwip_end();

    if (sock->pcb == NULL) {
        free(sock);
        return NULL;
    }

    sock->tls_cfg = g_tls_config;
    sock->connected = false;
    sock->handshake_done = false;
    sock->recv_head = 0;
    sock->recv_tail = 0;
    sock->recv_len = 0;
    sock->last_error = TLS_OK;
    sock->op_complete = false;
    sock->timeout_ms = 0;

    // set callbacks
    cyw43_arch_lwip_begin();
    altcp_arg(sock->pcb, sock);
    altcp_recv(sock->pcb, tls_recv_callback);
    altcp_err(sock->pcb, tls_err_callback);
    cyw43_arch_lwip_end();

    return sock;
}

void tls_socket_close(tls_socket_t* sock) {
    if (sock == NULL) {
        return;
    }

    cyw43_arch_lwip_begin();
    if (sock->pcb != NULL) {
        altcp_arg(sock->pcb, NULL);
        altcp_recv(sock->pcb, NULL);
        altcp_err(sock->pcb, NULL);

        if (sock->connected) {
            altcp_close(sock->pcb);
        } else {
            altcp_abort(sock->pcb);
        }
        sock->pcb = NULL;
    }
    cyw43_arch_lwip_end();

    free(sock);
}

int tls_socket_connect(tls_socket_t* sock, const char* host, uint16_t port, uint32_t timeout_ms) {
    if (sock == NULL || host == NULL) {
        return TLS_ERR_INVAL;
    }

    if (sock->pcb == NULL) {
        return TLS_ERR_FAILED;
    }

    // resolve hostname using socket driver's dns
    char ip_str[16];
    ip_addr_t addr;

    if (ip4addr_aton(host, ip_2_ip4(&addr))) {
        // valid IP address
    } else {
        // try dns resolution
        int err = socket_dns_resolve(host, ip_str, sizeof(ip_str));
        if (err != SOCKET_OK) {
            return TLS_ERR_DNS;
        }
        ip4addr_aton(ip_str, ip_2_ip4(&addr));
    }

    // reset state
    sock->op_complete = false;
    sock->last_error = TLS_OK;

    // initiate connection (includes tls handshake)
    cyw43_arch_lwip_begin();
    err_t err = altcp_connect(sock->pcb, &addr, port, tls_connected_callback);
    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return TLS_ERR_FAILED;
    }

    // wait for connection  nd handshake with timeout
    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : 30000;

    while (!sock->op_complete) {
        cyw43_arch_poll();
        sleep_ms(1);

        if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
            cyw43_arch_lwip_begin();
            altcp_abort(sock->pcb);
            sock->pcb = NULL;
            cyw43_arch_lwip_end();
            return TLS_ERR_TIMEOUT;
        }
    }

    return sock->last_error;
}

int tls_socket_send(tls_socket_t* sock, const void* data, size_t len) {
    if (sock == NULL || data == NULL) {
        return TLS_ERR_INVAL;
    }

    if (!sock->connected || sock->pcb == NULL) {
        return TLS_ERR_NOTCONN;
    }

    cyw43_arch_lwip_begin();

    // check available send buffer
    u16_t available = altcp_sndbuf(sock->pcb);
    if (available == 0) {
        cyw43_arch_lwip_end();
        return TLS_ERR_WOULDBLOCK;
    }

    // limit to available buffer
    size_t to_send = len;
    if (to_send > available) {
        to_send = available;
    }

    // write data
    err_t err = altcp_write(sock->pcb, data, to_send, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK) {
        cyw43_arch_lwip_end();
        if (err == ERR_MEM) {
            return TLS_ERR_NOMEM;
        }
        return TLS_ERR_FAILED;
    }

    // flush output
    err = altcp_output(sock->pcb);
    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return TLS_ERR_FAILED;
    }

    return (int)to_send;
}

int tls_socket_receive(tls_socket_t* sock, void* buf, size_t maxlen, uint32_t timeout_ms) {
    if (sock == NULL || buf == NULL) {
        return TLS_ERR_INVAL;
    }

    if (!sock->connected && sock->recv_len == 0) {
        return TLS_ERR_NOTCONN;
    }

    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : sock->timeout_ms;

    // wait for data
    while (sock->recv_len == 0) {
        if (!sock->connected) {
            if (sock->last_error != TLS_OK) {
                return sock->last_error;
            }
            return TLS_ERR_CLOSED;
        }

        cyw43_arch_poll();
        sleep_ms(1);

        if (effective_timeout > 0) {
            if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
                return TLS_ERR_TIMEOUT;
            }
        }
    }

    // read from buffer
    size_t rd = tls_recv_buf_read(sock, (uint8_t*)buf, maxlen);
    return (int)rd;
}

void tls_socket_settimeout(tls_socket_t* sock, uint32_t timeout_ms) {
    if (sock != NULL) {
        sock->timeout_ms = timeout_ms;
    }
}

size_t tls_socket_available(tls_socket_t* sock) {
    if (sock == NULL) {
        return 0;
    }
    return sock->recv_len;
}

bool tls_socket_isconnected(tls_socket_t* sock) {
    if (sock == NULL) {
        return false;
    }
    return sock->connected && sock->handshake_done;
}

const char* tls_strerror(int err) {
    switch (err) {
        case TLS_OK:            return "success";
        case TLS_ERR_FAILED:    return "operation failed";
        case TLS_ERR_TIMEOUT:   return "timeout";
        case TLS_ERR_CLOSED:    return "connection closed";
        case TLS_ERR_HANDSHAKE: return "TLS handshake failed";
        case TLS_ERR_NOMEM:     return "out of memory";
        case TLS_ERR_INVAL:     return "invalid argument";
        case TLS_ERR_NOTCONN:   return "not connected";
        case TLS_ERR_DNS:       return "DNS resolution failed";
        case TLS_ERR_WOULDBLOCK: return "would block";
        default:                return "unknown error";
    }
}
