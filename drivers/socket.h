/*
 * Socket driver interface for PicoCalc
 * Uses raw lwIP API for TCP/UDP communication (NO_SYS=1 compatible)
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// Socket types
#define SOCKET_TYPE_TCP     0
#define SOCKET_TYPE_UDP     1

// Socket errors
#define SOCKET_OK           0
#define SOCKET_ERR_FAILED   -1
#define SOCKET_ERR_TIMEOUT  -2
#define SOCKET_ERR_CLOSED   -3
#define SOCKET_ERR_REFUSED  -4
#define SOCKET_ERR_NOMEM    -5
#define SOCKET_ERR_INVAL    -6
#define SOCKET_ERR_NOTCONN  -7
#define SOCKET_ERR_DNS      -8
#define SOCKET_ERR_ABORTED  -9
#define SOCKET_ERR_RST      -10
#define SOCKET_ERR_WOULDBLOCK -11

// Receive buffer size
#define SOCKET_RECV_BUF_SIZE  4096

// Forward declaration for lwIP types (opaque to API users)
struct tcp_pcb;
struct udp_pcb;
struct pbuf;

// Socket handle structure
typedef struct socket_handle {
    int type;                   // SOCKET_TYPE_TCP or SOCKET_TYPE_UDP
    union {
        struct tcp_pcb* tcp;    // TCP protocol control block
        struct udp_pcb* udp;    // UDP protocol control block
    } pcb;

    // Connection state
    bool connected;             // TCP connected
    bool bound;                 // Socket bound to local port
    bool listening;             // TCP server listening

    // Receive buffer (circular)
    uint8_t recv_buf[SOCKET_RECV_BUF_SIZE];
    volatile size_t recv_head;  // Write position
    volatile size_t recv_tail;  // Read position
    volatile size_t recv_len;   // Data available

    // For UDP: store last received packet source
    uint32_t last_recv_ip;
    uint16_t last_recv_port;

    // Connection/operation status
    volatile int last_error;    // Last async error (from callbacks)
    volatile bool op_complete;  // Operation completed flag

    // Timeout
    uint32_t timeout_ms;

    // Accept queue for TCP servers
    struct socket_handle* accept_queue;
    struct socket_handle* next_pending;  // Linked list for pending connections
} socket_handle_t;

// Socket creation and destruction
socket_handle_t* socket_tcp_create(void);
socket_handle_t* socket_udp_create(void);
void socket_close(socket_handle_t* sock);

// TCP client operations
int socket_connect(socket_handle_t* sock, const char* host, uint16_t port, uint32_t timeout_ms);
int socket_send(socket_handle_t* sock, const void* data, size_t len);
int socket_receive(socket_handle_t* sock, void* buf, size_t maxlen, uint32_t timeout_ms);

// TCP server operations
int socket_bind(socket_handle_t* sock, uint16_t port, const char* address);
int socket_listen(socket_handle_t* sock, int backlog);
socket_handle_t* socket_accept(socket_handle_t* sock, uint32_t timeout_ms);

// UDP operations
int socket_sendto(socket_handle_t* sock, const void* data, size_t len,
                  const char* host, uint16_t port);
int socket_receivefrom(socket_handle_t* sock, void* buf, size_t maxlen,
                       char* from_ip, size_t from_ip_len, uint16_t* from_port,
                       uint32_t timeout_ms);

// Socket configuration
void socket_settimeout(socket_handle_t* sock, uint32_t timeout_ms);

// DNS resolution
int socket_dns_resolve(const char* hostname, char* ip_out, size_t ip_len);

// Error string
const char* socket_strerror(int err);

// Check if data is available
size_t socket_available(socket_handle_t* sock);
