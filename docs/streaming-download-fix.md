# Fix: Inconsistent byte counts when streaming large HTTP downloads

## Problem

When using `fetch <url> <file>` to download large files (~2MB), the number
of bytes written to disk varied between attempts -- sometimes getting most
of the data, sometimes dramatically less. Binary files (like .uf2 firmware)
were particularly affected.

## Root cause

Data loss in the C socket driver's `tcp_recv_callback`. When lwIP delivers
received TCP data, the callback copies it into a circular buffer. When the
buffer fills, the old code freed the entire pbuf -- permanently discarding
any bytes that didn't fit. Since lwIP had already ACK'd the data at the TCP
level, those bytes were never retransmitted.

The amount of loss varied per run because it depended on timing: network
speed, Lua GC pauses, SD card write latency, and heap fragmentation all
affected how quickly the buffer was drained vs how fast new data arrived.

## Changes

### drivers/socket.h

- Increased `SOCKET_RECV_BUF_SIZE` from 4096 to 8192 (now larger than
  `TCP_WND` of 5840, reducing overflow frequency).
- Added `pending_pbuf` and `pending_pbuf_offset` fields to
  `socket_handle_t` for retaining overflow data.

### drivers/socket.c

**New function: `drain_pending_pbuf()`**

Walks the retained pbuf chain using `pbuf_skip`, copies data into the
circular buffer segment by segment, frees the pbuf when fully consumed,
and calls `tcp_recved` to reopen the TCP window for the drained bytes.

**Fixed `tcp_recv_callback()`**

- When the circular buffer fills mid-copy, the pbuf is retained (with a
  byte offset) instead of being freed. Only the copied portion is ACK'd,
  applying TCP backpressure so the sender slows down.
- When a new pbuf arrives while a previous one is still pending, it is
  chained on with `pbuf_cat` and a drain is attempted.

**Fixed `socket_receive()`**

- Drains pending pbuf *before* checking connection/buffer state. This
  prevents the edge case where the server closes the connection while
  overflow data is sitting in the pending pbuf but the circular buffer
  is empty -- previously this returned `SOCKET_ERR_NOTCONN` and silently
  abandoned the pending data.
- Holds the lwIP lock (`cyw43_arch_lwip_begin/end`) around both
  `recv_buf_read` and `drain_pending_pbuf`. On RP2040 with
  `threadsafe_background`, the callback fires from a timer IRQ.
  Without locking, the IRQ can preempt a `recv_len--` mid-operation
  and clobber the callback's `recv_len++`, causing the byte count to
  drift over many iterations.

**Fixed `socket_close()`**

- Frees any pending pbuf on the socket and on queued accepted connections
  to prevent memory leaks.

**Initialization**

- `pending_pbuf` and `pending_pbuf_offset` initialized to NULL/0 in
  `socket_tcp_create()` and `tcp_accept_callback()`.

### sd_files/lua/modules/http.lua

Three changes in the streaming download loop:

1. **Larger receive size**: `sock:receive(1024)` changed to
   `sock:receive(4096)`. Drains the C buffer 4x faster, reducing the
   window for overflow.

2. **Reliable GC scheduling**: The old condition `bytes_written % 8192 == 0`
   almost never triggered because `receive()` returns variable-length
   chunks that rarely align to 8192. Replaced with a simple chunk counter
   (`gc_counter`) that triggers `collectgarbage()` every 8 chunks.

3. **More streaming retries**: Increased from 3 to 5 for the streaming path,
   since larger files over WiFi are more likely to experience momentary
   stalls.

4. **Binary file mode**: Output file opened with `"wb"` instead of `"w"` to
   prevent any text-mode byte translation when downloading binary content.

## Verification

1. Download the same large file multiple times with `fetch <url> <file>`.
2. File sizes should be identical and match the source Content-Length.
3. With debug enabled (`fetch -d <url> <file>`), `bytes_written` should
   equal `content_length` at stream completion with no "stream ended" or
   "giving up" messages in the log.
