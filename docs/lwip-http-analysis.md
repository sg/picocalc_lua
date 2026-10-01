# Analysis: lwIP Native C HTTP vs Lua HTTP Implementation

## Executive Summary

**Recommendation: Keep the current Lua HTTP implementation.**

After thorough analysis of lwIP's native `httpc` module versus the existing `sd_files/lua/modules/http.lua`, the Lua implementation is more capable and better suited for PicoCalc's needs.

## Capability Comparison

| Feature | lwIP httpc (C) | Lua http.lua | Winner |
|---------|---------------|--------------|--------|
| GET requests | Yes | Yes | Tie |
| POST requests | **No** | Yes | **Lua** |
| Chunked transfer-encoding | **No** | Yes | **Lua** |
| Redirect following | **No** | Yes (301/302/303/307/308) | **Lua** |
| HTTPS support | Via altcp_tls | Via socket.tls() | Tie |
| Streaming large responses | No (must buffer) | Yes (to file/console) | **Lua** |
| Max response size | Limited by pbufs (~32KB) | 32KB buffered, unlimited streaming | **Lua** |
| URL encoding utilities | No | Yes | **Lua** |
| Debug logging | No | Yes (file and console) | **Lua** |
| Memory optimization | Callback/pbuf based | Streaming + periodic GC | **Lua** |

## Why lwIP httpc Falls Short

### 1. GET-Only Limitation
lwIP's `httpc` only supports GET requests. The API provides:
```c
httpc_get_file_dns(host, port, uri, settings, recv_fn, arg, connection);
```
There is no `httpc_post_*` equivalent. This means:
- Cannot submit forms
- Cannot use REST APIs requiring POST/PUT/DELETE
- Cannot upload data

### 2. No Chunked Transfer-Encoding
Many modern web servers use `Transfer-Encoding: chunked`. lwIP httpc requires `Content-Length` header. Requests to servers using chunked encoding will fail or return incomplete data.

### 3. No Redirect Following
lwIP httpc does not follow HTTP redirects. The Lua implementation handles 301, 302, 303, 307, and 308 redirects automatically with a configurable limit.

### 4. Callback-to-Synchronous Complexity
lwIP httpc is callback-based (async), but Lua expects synchronous returns. Converting between these paradigms requires:
- Polling loops that block the Lua thread
- State management across callbacks
- Careful timeout handling
- Risk of deadlocks if callbacks don't fire

### 5. No Streaming Support
lwIP httpc buffers the entire response before completion. The Lua implementation can stream responses larger than RAM directly to files via `output_file` option or to console via `stream_to_console`.

## Memory Analysis

### Current Memory Budget
- RP2350 SRAM: 528 KB
- Available Heap: ~400-450 KB
- lwIP Static Pools: ~50-60 KB (configured in lwipopts.h)
- Remaining for operations: ~320-370 KB

### Cost of Adding lwIP httpc
| Addition | Impact |
|----------|--------|
| Code size (flash) | +4-6 KB |
| Runtime memory | Neutral to slightly worse |
| Peak memory during request | Same (buffering required either way) |

Adding C httpc would **increase** total code size without removing the Lua module (still needed for POST, chunked, redirects).

## What the Lua Implementation Does Well

The current `http.lua` is already well-optimized for PicoCalc:

1. **Streaming downloads** - Files larger than RAM work via `output_file`
2. **Memory-conscious** - Reads in 1KB chunks, periodic `collectgarbage()`
3. **Chunked decoding** - Properly handles `Transfer-Encoding: chunked`
4. **Redirect handling** - Follows redirects with loop detection
5. **Debug capability** - `http.DEBUG` and `http.DEBUG_FILE` for troubleshooting
6. **Full HTTP/1.1** - Proper headers, Connection: close

## If Integration Were Required

If requirements changed to require native C HTTP, here's what would be needed:

### lwipopts.h Changes
```c
#define LWIP_HTTPC              1
#define HTTPC_CLIENT_AGENT      "picocalc/1.0"
```

### New Files Required
- `drivers/httpc.c` - C driver wrapping lwIP httpc with sync API
- `drivers/httpc.h` - Header file
- `picolua-api/httpc.c` - Lua bindings

### Pattern to Follow
The existing `drivers/socket.c` and `drivers/tls.c` show how to:
- Wrap callback-based lwIP APIs into synchronous calls
- Use `cyw43_arch_lwip_begin/end()` for thread safety
- Poll with `cyw43_arch_poll()` while waiting

## Alternative Improvements to Consider

Instead of adding C HTTP, consider these optimizations:

1. **PSRAM streaming** - Write HTTP responses directly to PSRAM buffer
2. **Pre-compiled Lua** - Ship http.lua as bytecode to reduce parse time
3. **Connection pooling** - Reuse TCP connections for multiple requests (HTTP/1.1 keep-alive)

## Conclusion

The Lua HTTP implementation is the right choice for PicoCalc because:
- It's **more capable** (POST, chunked, redirects)
- It's **more memory-efficient** (streaming support)
- It's **already working and tested**
- Adding C httpc would **increase complexity** without removing Lua code

**Recommendation: Continue using the Lua HTTP module.**

## Files Analyzed

| File | Purpose |
|------|---------|
| `pico-sdk/lib/lwip/src/apps/http/http_client.c` | lwIP HTTP client source |
| `pico-sdk/lib/lwip/src/include/lwip/apps/http_client.h` | lwIP HTTP client API |
| `sd_files/lua/modules/http.lua` | Current Lua HTTP implementation |
| `lwipopts.h` | lwIP configuration |
| `picolua-api/socket.c` | Socket Lua bindings (pattern reference) |
| `drivers/tls.c` | TLS driver (altcp pattern reference) |
