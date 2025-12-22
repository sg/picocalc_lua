/*
 * Socket driver implementation for PicoCalc
 * Uses raw lwIP API for TCP/UDP communication (NO_SYS=1 compatible)
 */
#include "socket.h"
#include "wifi.h"

#include "pico/stdlib.h"
#include "pico/cyw43_arch.h"

#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/dns.h"
#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"

#include <stdlib.h>
#include <string.h>

// Helper to copy data into circular buffer
static size_t recv_buf_write(socket_handle_t* sock, const uint8_t* data, size_t len) {
    size_t written = 0;
    while (written < len && sock->recv_len < SOCKET_RECV_BUF_SIZE) {
        sock->recv_buf[sock->recv_head] = data[written];
        sock->recv_head = (sock->recv_head + 1) % SOCKET_RECV_BUF_SIZE;
        sock->recv_len++;
        written++;
    }
    return written;
}

// Helper to read data from circular buffer
static size_t recv_buf_read(socket_handle_t* sock, uint8_t* data, size_t maxlen) {
    size_t read = 0;
    while (read < maxlen && sock->recv_len > 0) {
        data[read] = sock->recv_buf[sock->recv_tail];
        sock->recv_tail = (sock->recv_tail + 1) % SOCKET_RECV_BUF_SIZE;
        sock->recv_len--;
        read++;
    }
    return read;
}

// TCP receive callback
static err_t tcp_recv_callback(void* arg, struct tcp_pcb* tpcb, struct pbuf* p, err_t err) {
    socket_handle_t* sock = (socket_handle_t*)arg;

    if (p == NULL) {
        // Connection closed by remote
        sock->connected = false;
        sock->last_error = SOCKET_ERR_CLOSED;
        return ERR_OK;
    }

    if (err != ERR_OK) {
        pbuf_free(p);
        sock->last_error = SOCKET_ERR_FAILED;
        return err;
    }

    // Copy data to receive buffer
    struct pbuf* q = p;
    size_t total_copied = 0;
    while (q != NULL) {
        size_t copied = recv_buf_write(sock, (uint8_t*)q->payload, q->len);
        total_copied += copied;
        if (copied < q->len) {
            // Buffer full, can't accept more
            break;
        }
        q = q->next;
    }

    // Acknowledge received data
    tcp_recved(tpcb, total_copied);
    pbuf_free(p);

    return ERR_OK;
}

// TCP error callback
static void tcp_err_callback(void* arg, err_t err) {
    socket_handle_t* sock = (socket_handle_t*)arg;

    sock->connected = false;
    sock->pcb.tcp = NULL;  // PCB is already freed by lwIP on error

    switch (err) {
        case ERR_ABRT:
            sock->last_error = SOCKET_ERR_ABORTED;
            break;
        case ERR_RST:
            sock->last_error = SOCKET_ERR_RST;
            break;
        case ERR_CONN:
            sock->last_error = SOCKET_ERR_REFUSED;
            break;
        default:
            sock->last_error = SOCKET_ERR_FAILED;
            break;
    }

    sock->op_complete = true;
}

// TCP connected callback
static err_t tcp_connected_callback(void* arg, struct tcp_pcb* tpcb, err_t err) {
    socket_handle_t* sock = (socket_handle_t*)arg;

    if (err == ERR_OK) {
        sock->connected = true;
        sock->last_error = SOCKET_OK;
    } else {
        sock->last_error = SOCKET_ERR_FAILED;
    }

    sock->op_complete = true;
    return ERR_OK;
}

// TCP accept callback for listening sockets
static err_t tcp_accept_callback(void* arg, struct tcp_pcb* newpcb, err_t err) {
    socket_handle_t* listen_sock = (socket_handle_t*)arg;

    if (err != ERR_OK || newpcb == NULL) {
        return ERR_VAL;
    }

    // Create new socket handle for accepted connection
    socket_handle_t* client = calloc(1, sizeof(socket_handle_t));
    if (client == NULL) {
        tcp_abort(newpcb);
        return ERR_MEM;
    }

    client->type = SOCKET_TYPE_TCP;
    client->pcb.tcp = newpcb;
    client->connected = true;
    client->bound = false;
    client->listening = false;
    client->recv_head = 0;
    client->recv_tail = 0;
    client->recv_len = 0;
    client->last_error = SOCKET_OK;
    client->op_complete = false;
    client->timeout_ms = 0;
    client->accept_queue = NULL;
    client->next_pending = NULL;

    // Set up callbacks for new connection
    tcp_arg(newpcb, client);
    tcp_recv(newpcb, tcp_recv_callback);
    tcp_err(newpcb, tcp_err_callback);

    // Add to accept queue
    client->next_pending = listen_sock->accept_queue;
    listen_sock->accept_queue = client;

    return ERR_OK;
}

// UDP receive callback
static void udp_recv_callback(void* arg, struct udp_pcb* upcb, struct pbuf* p,
                              const ip_addr_t* addr, u16_t port) {
    socket_handle_t* sock = (socket_handle_t*)arg;

    if (p == NULL) {
        return;
    }

    // Store sender info
    sock->last_recv_ip = ip4_addr_get_u32(ip_2_ip4(addr));
    sock->last_recv_port = port;

    // Copy data to receive buffer
    struct pbuf* q = p;
    while (q != NULL) {
        recv_buf_write(sock, (uint8_t*)q->payload, q->len);
        q = q->next;
    }

    pbuf_free(p);
}

socket_handle_t* socket_tcp_create(void) {
    if (!wifi_is_initialized()) {
        return NULL;
    }

    socket_handle_t* sock = calloc(1, sizeof(socket_handle_t));
    if (sock == NULL) {
        return NULL;
    }

    cyw43_arch_lwip_begin();
    sock->pcb.tcp = tcp_new();
    cyw43_arch_lwip_end();

    if (sock->pcb.tcp == NULL) {
        free(sock);
        return NULL;
    }

    sock->type = SOCKET_TYPE_TCP;
    sock->connected = false;
    sock->bound = false;
    sock->listening = false;
    sock->recv_head = 0;
    sock->recv_tail = 0;
    sock->recv_len = 0;
    sock->last_error = SOCKET_OK;
    sock->op_complete = false;
    sock->timeout_ms = 0;
    sock->accept_queue = NULL;
    sock->next_pending = NULL;

    // Set callbacks
    cyw43_arch_lwip_begin();
    tcp_arg(sock->pcb.tcp, sock);
    tcp_recv(sock->pcb.tcp, tcp_recv_callback);
    tcp_err(sock->pcb.tcp, tcp_err_callback);
    cyw43_arch_lwip_end();

    return sock;
}

socket_handle_t* socket_udp_create(void) {
    if (!wifi_is_initialized()) {
        return NULL;
    }

    socket_handle_t* sock = calloc(1, sizeof(socket_handle_t));
    if (sock == NULL) {
        return NULL;
    }

    cyw43_arch_lwip_begin();
    sock->pcb.udp = udp_new();
    cyw43_arch_lwip_end();

    if (sock->pcb.udp == NULL) {
        free(sock);
        return NULL;
    }

    sock->type = SOCKET_TYPE_UDP;
    sock->connected = false;
    sock->bound = false;
    sock->listening = false;
    sock->recv_head = 0;
    sock->recv_tail = 0;
    sock->recv_len = 0;
    sock->last_recv_ip = 0;
    sock->last_recv_port = 0;
    sock->last_error = SOCKET_OK;
    sock->op_complete = false;
    sock->timeout_ms = 0;
    sock->accept_queue = NULL;
    sock->next_pending = NULL;

    // Set callback
    cyw43_arch_lwip_begin();
    udp_recv(sock->pcb.udp, udp_recv_callback, sock);
    cyw43_arch_lwip_end();

    return sock;
}

void socket_close(socket_handle_t* sock) {
    if (sock == NULL) {
        return;
    }

    cyw43_arch_lwip_begin();

    if (sock->type == SOCKET_TYPE_TCP) {
        // Clean up accept queue for listening sockets
        while (sock->accept_queue != NULL) {
            socket_handle_t* pending = sock->accept_queue;
            sock->accept_queue = pending->next_pending;
            if (pending->pcb.tcp != NULL) {
                tcp_abort(pending->pcb.tcp);
            }
            free(pending);
        }

        if (sock->pcb.tcp != NULL) {
            tcp_arg(sock->pcb.tcp, NULL);
            tcp_recv(sock->pcb.tcp, NULL);
            tcp_err(sock->pcb.tcp, NULL);

            if (sock->connected || sock->listening) {
                tcp_close(sock->pcb.tcp);
            } else {
                tcp_abort(sock->pcb.tcp);
            }
        }
    } else if (sock->type == SOCKET_TYPE_UDP) {
        if (sock->pcb.udp != NULL) {
            udp_remove(sock->pcb.udp);
        }
    }

    cyw43_arch_lwip_end();

    free(sock);
}

int socket_connect(socket_handle_t* sock, const char* host, uint16_t port, uint32_t timeout_ms) {
    if (sock == NULL || host == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_TCP) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->pcb.tcp == NULL) {
        return SOCKET_ERR_FAILED;
    }

    // Resolve hostname
    char ip_str[16];
    ip_addr_t addr;

    // Check if already an IP address
    if (ip4addr_aton(host, ip_2_ip4(&addr))) {
        // Valid IP address
    } else {
        // Try DNS resolution
        int err = socket_dns_resolve(host, ip_str, sizeof(ip_str));
        if (err != SOCKET_OK) {
            return err;
        }
        ip4addr_aton(ip_str, ip_2_ip4(&addr));
    }

    // Reset operation state
    sock->op_complete = false;
    sock->last_error = SOCKET_OK;

    // Initiate connection
    cyw43_arch_lwip_begin();
    err_t err = tcp_connect(sock->pcb.tcp, &addr, port, tcp_connected_callback);
    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return SOCKET_ERR_FAILED;
    }

    // Wait for connection with timeout
    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : 30000;  // Default 30s

    while (!sock->op_complete) {
        cyw43_arch_poll();
        sleep_ms(1);

        if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
            // Timeout - abort connection attempt
            cyw43_arch_lwip_begin();
            tcp_abort(sock->pcb.tcp);
            sock->pcb.tcp = NULL;
            cyw43_arch_lwip_end();
            return SOCKET_ERR_TIMEOUT;
        }
    }

    return sock->last_error;
}

int socket_send(socket_handle_t* sock, const void* data, size_t len) {
    if (sock == NULL || data == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_TCP) {
        return SOCKET_ERR_INVAL;
    }

    if (!sock->connected || sock->pcb.tcp == NULL) {
        return SOCKET_ERR_NOTCONN;
    }

    cyw43_arch_lwip_begin();

    // Check available send buffer
    u16_t available = tcp_sndbuf(sock->pcb.tcp);
    if (available == 0) {
        cyw43_arch_lwip_end();
        return SOCKET_ERR_WOULDBLOCK;
    }

    // Limit to available buffer
    size_t to_send = len;
    if (to_send > available) {
        to_send = available;
    }

    // Write data
    err_t err = tcp_write(sock->pcb.tcp, data, to_send, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK) {
        cyw43_arch_lwip_end();
        if (err == ERR_MEM) {
            return SOCKET_ERR_NOMEM;
        }
        return SOCKET_ERR_FAILED;
    }

    // Flush output
    err = tcp_output(sock->pcb.tcp);
    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return SOCKET_ERR_FAILED;
    }

    return (int)to_send;
}

int socket_receive(socket_handle_t* sock, void* buf, size_t maxlen, uint32_t timeout_ms) {
    if (sock == NULL || buf == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_TCP) {
        return SOCKET_ERR_INVAL;
    }

    if (!sock->connected && sock->recv_len == 0) {
        return SOCKET_ERR_NOTCONN;
    }

    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : sock->timeout_ms;

    // Wait for data
    while (sock->recv_len == 0) {
        if (!sock->connected) {
            // Check if there was an error
            if (sock->last_error != SOCKET_OK) {
                return sock->last_error;
            }
            return SOCKET_ERR_CLOSED;
        }

        cyw43_arch_poll();
        sleep_ms(1);

        if (effective_timeout > 0) {
            if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
                return SOCKET_ERR_TIMEOUT;
            }
        }
    }

    // Read from buffer
    size_t read = recv_buf_read(sock, (uint8_t*)buf, maxlen);
    return (int)read;
}

int socket_bind(socket_handle_t* sock, uint16_t port, const char* address) {
    if (sock == NULL) {
        return SOCKET_ERR_INVAL;
    }

    ip_addr_t bind_addr;
    if (address != NULL && strlen(address) > 0) {
        ip4addr_aton(address, ip_2_ip4(&bind_addr));
    } else {
        ip_addr_set_any(false, &bind_addr);
    }

    err_t err;
    cyw43_arch_lwip_begin();

    if (sock->type == SOCKET_TYPE_TCP) {
        if (sock->pcb.tcp == NULL) {
            cyw43_arch_lwip_end();
            return SOCKET_ERR_FAILED;
        }
        err = tcp_bind(sock->pcb.tcp, &bind_addr, port);
    } else {
        if (sock->pcb.udp == NULL) {
            cyw43_arch_lwip_end();
            return SOCKET_ERR_FAILED;
        }
        err = udp_bind(sock->pcb.udp, &bind_addr, port);
    }

    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return SOCKET_ERR_FAILED;
    }

    sock->bound = true;
    return SOCKET_OK;
}

int socket_listen(socket_handle_t* sock, int backlog) {
    if (sock == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_TCP) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->pcb.tcp == NULL) {
        return SOCKET_ERR_FAILED;
    }

    if (!sock->bound) {
        return SOCKET_ERR_INVAL;
    }

    if (backlog <= 0) {
        backlog = 4;
    }

    cyw43_arch_lwip_begin();

    // tcp_listen_with_backlog replaces the PCB
    struct tcp_pcb* listen_pcb = tcp_listen_with_backlog(sock->pcb.tcp, backlog);
    if (listen_pcb == NULL) {
        cyw43_arch_lwip_end();
        return SOCKET_ERR_NOMEM;
    }

    sock->pcb.tcp = listen_pcb;
    tcp_arg(sock->pcb.tcp, sock);
    tcp_accept(sock->pcb.tcp, tcp_accept_callback);

    cyw43_arch_lwip_end();

    sock->listening = true;
    return SOCKET_OK;
}

socket_handle_t* socket_accept(socket_handle_t* sock, uint32_t timeout_ms) {
    if (sock == NULL) {
        return NULL;
    }

    if (sock->type != SOCKET_TYPE_TCP || !sock->listening) {
        return NULL;
    }

    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : sock->timeout_ms;

    // Wait for connection
    while (sock->accept_queue == NULL) {
        cyw43_arch_poll();
        sleep_ms(1);

        if (effective_timeout > 0) {
            if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
                return NULL;
            }
        }
    }

    // Pop from accept queue
    cyw43_arch_lwip_begin();
    socket_handle_t* client = sock->accept_queue;
    sock->accept_queue = client->next_pending;
    client->next_pending = NULL;
    cyw43_arch_lwip_end();

    return client;
}

int socket_sendto(socket_handle_t* sock, const void* data, size_t len,
                  const char* host, uint16_t port) {
    if (sock == NULL || data == NULL || host == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_UDP) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->pcb.udp == NULL) {
        return SOCKET_ERR_FAILED;
    }

    // Resolve hostname
    char ip_str[16];
    ip_addr_t addr;

    if (ip4addr_aton(host, ip_2_ip4(&addr))) {
        // Valid IP
    } else {
        int err = socket_dns_resolve(host, ip_str, sizeof(ip_str));
        if (err != SOCKET_OK) {
            return err;
        }
        ip4addr_aton(ip_str, ip_2_ip4(&addr));
    }

    // Create pbuf
    cyw43_arch_lwip_begin();

    struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (p == NULL) {
        cyw43_arch_lwip_end();
        return SOCKET_ERR_NOMEM;
    }

    memcpy(p->payload, data, len);

    err_t err = udp_sendto(sock->pcb.udp, p, &addr, port);
    pbuf_free(p);

    cyw43_arch_lwip_end();

    if (err != ERR_OK) {
        return SOCKET_ERR_FAILED;
    }

    return (int)len;
}

int socket_receivefrom(socket_handle_t* sock, void* buf, size_t maxlen,
                       char* from_ip, size_t from_ip_len, uint16_t* from_port,
                       uint32_t timeout_ms) {
    if (sock == NULL || buf == NULL) {
        return SOCKET_ERR_INVAL;
    }

    if (sock->type != SOCKET_TYPE_UDP) {
        return SOCKET_ERR_INVAL;
    }

    uint32_t start = to_ms_since_boot(get_absolute_time());
    uint32_t effective_timeout = timeout_ms > 0 ? timeout_ms : sock->timeout_ms;

    // Wait for data
    while (sock->recv_len == 0) {
        cyw43_arch_poll();
        sleep_ms(1);

        if (effective_timeout > 0) {
            if (to_ms_since_boot(get_absolute_time()) - start > effective_timeout) {
                return SOCKET_ERR_TIMEOUT;
            }
        }
    }

    // Read from buffer
    size_t read = recv_buf_read(sock, (uint8_t*)buf, maxlen);

    // Return sender info
    if (from_ip != NULL && from_ip_len > 0) {
        ip_addr_t addr;
        ip4_addr_set_u32(ip_2_ip4(&addr), sock->last_recv_ip);
        const char* addr_str = ip4addr_ntoa(ip_2_ip4(&addr));
        strncpy(from_ip, addr_str, from_ip_len - 1);
        from_ip[from_ip_len - 1] = '\0';
    }

    if (from_port != NULL) {
        *from_port = sock->last_recv_port;
    }

    return (int)read;
}

void socket_settimeout(socket_handle_t* sock, uint32_t timeout_ms) {
    if (sock == NULL) {
        return;
    }
    sock->timeout_ms = timeout_ms;
}

// DNS resolution callback state
typedef struct {
    volatile bool done;
    volatile bool success;
    ip_addr_t resolved_addr;
} dns_callback_state_t;

static void dns_callback(const char* name, const ip_addr_t* ipaddr, void* arg) {
    dns_callback_state_t* state = (dns_callback_state_t*)arg;
    if (ipaddr != NULL) {
        state->resolved_addr = *ipaddr;
        state->success = true;
    } else {
        state->success = false;
    }
    state->done = true;
}

int socket_dns_resolve(const char* hostname, char* ip_out, size_t ip_len) {
    if (hostname == NULL || ip_out == NULL || ip_len == 0) {
        return SOCKET_ERR_INVAL;
    }

    if (!wifi_is_initialized()) {
        return SOCKET_ERR_FAILED;
    }

    // Check if already an IP address
    ip_addr_t addr;
    if (ip4addr_aton(hostname, ip_2_ip4(&addr))) {
        strncpy(ip_out, hostname, ip_len - 1);
        ip_out[ip_len - 1] = '\0';
        return SOCKET_OK;
    }

    dns_callback_state_t state = {
        .done = false,
        .success = false
    };

    ip_addr_t cached_addr;
    err_t err;

    cyw43_arch_lwip_begin();
    err = dns_gethostbyname(hostname, &cached_addr, dns_callback, &state);
    cyw43_arch_lwip_end();

    if (err == ERR_OK) {
        // Result was cached
        const char* addr_str = ip4addr_ntoa(ip_2_ip4(&cached_addr));
        strncpy(ip_out, addr_str, ip_len - 1);
        ip_out[ip_len - 1] = '\0';
        return SOCKET_OK;
    } else if (err == ERR_INPROGRESS) {
        // Wait for callback with timeout
        uint32_t start = to_ms_since_boot(get_absolute_time());
        while (!state.done) {
            cyw43_arch_poll();
            sleep_ms(10);

            // 10 second timeout
            if (to_ms_since_boot(get_absolute_time()) - start > 10000) {
                return SOCKET_ERR_TIMEOUT;
            }
        }

        if (state.success) {
            const char* addr_str = ip4addr_ntoa(ip_2_ip4(&state.resolved_addr));
            strncpy(ip_out, addr_str, ip_len - 1);
            ip_out[ip_len - 1] = '\0';
            return SOCKET_OK;
        } else {
            return SOCKET_ERR_DNS;
        }
    }

    return SOCKET_ERR_DNS;
}

size_t socket_available(socket_handle_t* sock) {
    if (sock == NULL) {
        return 0;
    }
    return sock->recv_len;
}

const char* socket_strerror(int err) {
    switch (err) {
        case SOCKET_OK:           return "success";
        case SOCKET_ERR_FAILED:   return "operation failed";
        case SOCKET_ERR_TIMEOUT:  return "timeout";
        case SOCKET_ERR_CLOSED:   return "connection closed";
        case SOCKET_ERR_REFUSED:  return "connection refused";
        case SOCKET_ERR_NOMEM:    return "out of memory";
        case SOCKET_ERR_INVAL:    return "invalid argument";
        case SOCKET_ERR_NOTCONN:  return "not connected";
        case SOCKET_ERR_DNS:      return "DNS resolution failed";
        case SOCKET_ERR_ABORTED:  return "connection aborted";
        case SOCKET_ERR_RST:      return "connection reset";
        case SOCKET_ERR_WOULDBLOCK: return "would block";
        default:                  return "unknown error";
    }
}
