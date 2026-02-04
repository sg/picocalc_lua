/*
 * TLS socket driver for PicoCalc
 * uses lwIP altcp_tls with mbedTLS for https support
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// tls socket errors (same as socket errors for consistency)
#define TLS_OK              0
#define TLS_ERR_FAILED      -1
#define TLS_ERR_TIMEOUT     -2
#define TLS_ERR_CLOSED      -3
#define TLS_ERR_HANDSHAKE   -4
#define TLS_ERR_NOMEM       -5
#define TLS_ERR_INVAL       -6
#define TLS_ERR_NOTCONN     -7
#define TLS_ERR_DNS         -8
#define TLS_ERR_WOULDBLOCK  -11

// receive buffer size
#define TLS_RECV_BUF_SIZE   16382

// forward declarations
struct altcp_pcb;
struct altcp_tls_config;

// tls socket handle
typedef struct tls_socket {
    struct altcp_pcb* pcb; // altcp pcb (wraps tcp with tls)
    struct altcp_tls_config* tls_cfg; // tls config

    // connection state
    bool connected;
    bool handshake_done;

    // receive buffer (circular)
    uint8_t recv_buf[TLS_RECV_BUF_SIZE];
    volatile size_t recv_head;
    volatile size_t recv_tail;
    volatile size_t recv_len;

    // operation status
    volatile int last_error;
    volatile bool op_complete;

    // timeout
    uint32_t timeout_ms;
} tls_socket_t;

// tls initialization (call once at startup)
int tls_init(void);
void tls_deinit(void);

// tls socket creation and destruction
tls_socket_t* tls_socket_create(void);
void tls_socket_close(tls_socket_t* sock);

// tls connection
int tls_socket_connect(tls_socket_t* sock, const char* host, uint16_t port, uint32_t timeout_ms);

// tls send/receive
int tls_socket_send(tls_socket_t* sock, const void* data, size_t len);
int tls_socket_receive(tls_socket_t* sock, void* buf, size_t maxlen, uint32_t timeout_ms);

// configuration
void tls_socket_settimeout(tls_socket_t* sock, uint32_t timeout_ms);

// status
size_t tls_socket_available(tls_socket_t* sock);
bool tls_socket_isconnected(tls_socket_t* sock);

// error string
const char* tls_strerror(int err);
