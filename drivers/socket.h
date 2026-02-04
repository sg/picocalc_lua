/*
 * TCP/UDP sockets driver for PicoCalc
 * uses lwIP API 
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// socket types
#define SOCKET_TYPE_TCP     0
#define SOCKET_TYPE_UDP     1

// socket errors
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

// receive buffer size
#define SOCKET_RECV_BUF_SIZE  4096

// forward declaration for lwIP types
struct tcp_pcb;
struct udp_pcb;
struct pbuf;

// socket handle structure
typedef struct socket_handle {
    int type; // SOCKET_TYPE_TCP or SOCKET_TYPE_UDP
    union {
        struct tcp_pcb* tcp; // tcp protocol control block
        struct udp_pcb* udp; // udp protocol control block
    } pcb;

    // connection state
    bool connected;
    bool bound;
    bool listening;

    // receive buffer (circular)
    uint8_t recv_buf[SOCKET_RECV_BUF_SIZE];
    volatile size_t recv_head;  // write position
    volatile size_t recv_tail;  // read position
    volatile size_t recv_len;   // data available

    // for udp, store last received packet source
    uint32_t last_recv_ip;
    uint16_t last_recv_port;

    // connection/operation status
    volatile int last_error;
    volatile bool op_complete;

    // timeout
    uint32_t timeout_ms;

    // accept queue for tcp servers
    struct socket_handle* accept_queue;
    struct socket_handle* next_pending; // linked list for pending connections
} socket_handle_t;

// socket creation and destruction
socket_handle_t* socket_tcp_create(void);
socket_handle_t* socket_udp_create(void);
void socket_close(socket_handle_t* sock);

// tcp client functions
int socket_connect(socket_handle_t* sock, const char* host, uint16_t port, uint32_t timeout_ms);
int socket_send(socket_handle_t* sock, const void* data, size_t len);
int socket_receive(socket_handle_t* sock, void* buf, size_t maxlen, uint32_t timeout_ms);

// tcp server functons
int socket_bind(socket_handle_t* sock, uint16_t port, const char* address);
int socket_listen(socket_handle_t* sock, int backlog);
socket_handle_t* socket_accept(socket_handle_t* sock, uint32_t timeout_ms);

// udp functions
int socket_sendto(socket_handle_t* sock, const void* data, size_t len,
                  const char* host, uint16_t port);
int socket_receivefrom(socket_handle_t* sock, void* buf, size_t maxlen,
                       char* from_ip, size_t from_ip_len, uint16_t* from_port,
                       uint32_t timeout_ms);

// socket config
void socket_settimeout(socket_handle_t* sock, uint32_t timeout_ms);

// dns resolution
int socket_dns_resolve(const char* hostname, char* ip_out, size_t ip_len);

// error string
const char* socket_strerror(int err);

// check if data is available
size_t socket_available(socket_handle_t* sock);

// icmp echo request (ping) 
typedef struct {
    bool success;
    uint32_t time_ms;
    int ttl;
    char ip[16];
} ping_result_t;

// send icmp echo request and wait for reply
int socket_ping(const char* host, uint32_t timeout_ms, ping_result_t* result);
