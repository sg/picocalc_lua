# Memory Analysis: OOM Panic in `cp` Command with WiFi Connected

**Date:** January 2026
**Issue:** Out of Memory panic when using 16KB blocks in the shell `cp` command while WiFi is connected

## Executive Summary

The OOM panic is caused by **heap memory fragmentation** combined with **peak allocation demands** that exceed available contiguous memory when the lwIP TCP/IP stack is active. Using 4KB blocks instead of 16KB works because smaller blocks are easier to fit into a fragmented heap.

---

## System Memory Architecture

| Component | Size | Notes |
|-----------|------|-------|
| RP2350 Internal SRAM | 528 KB | On-chip memory |
| Available Heap | ~400-450 KB | After BSS and stack allocation |
| External PSRAM | 8 MB | SPI-accessed, not used for malloc |

The heap size is dynamically determined at runtime:
```c
// From picolua-api/sys.c
uint32_t get_total_memory() {
    extern char __StackLimit, __bss_end__;
    return &__StackLimit - &__bss_end__;
}
```

---

## lwIP TCP/IP Stack Memory Usage

When WiFi is connected, the lwIP stack reserves significant static memory pools.

### Configuration (from `lwipopts.h`)

| Setting | Value | Purpose |
|---------|-------|---------|
| `MEM_SIZE` | 8,192 bytes | lwIP internal heap |
| `PBUF_POOL_SIZE` | 24 | Number of packet buffers |
| `TCP_MSS` | 1,460 bytes | Maximum segment size |
| `TCP_WND` | 8 x TCP_MSS = 11,680 bytes | TCP receive window |
| `TCP_SND_BUF` | 8 x TCP_MSS = 11,680 bytes | TCP send buffer |
| `MEMP_NUM_TCP_PCB` | 8 | Active TCP connections |
| `MEMP_NUM_UDP_PCB` | 8 | UDP control blocks |
| `MEMP_NUM_TCP_SEG` | 32 | Queued TCP segments |

### Memory Consumption Breakdown

| Component | Size | Calculation |
|-----------|------|-------------|
| PBUF Pool | ~38,400 bytes | 24 buffers x ~1,600 bytes each |
| TCP Window + Send Buffer | ~23,360 bytes | Per active connection |
| lwIP Heap | 8,192 bytes | General allocations |
| PCB Pools | ~2,000 bytes | TCP/UDP control blocks |
| **Total (idle)** | **~50-60 KB** | No active connections |
| **Total (1 TCP connection)** | **~75-85 KB** | With active TCP |

---

## The Double-Allocation Problem in `l_fs_read()`

The file read function in `picolua-api/fs.c` lines 67-84:

```c
static int l_fs_read(lua_State* L) {
    FIL* fp = checkfile(L);
    UINT to_read = luaL_optinteger(L, 2, 1);

    char* buffer = malloc(to_read);      // Allocation #1: C heap buffer
    UINT read;

    FRESULT result = f_read(fp, buffer, to_read, &read);
    if (result != FR_OK) {
        free(buffer);
        return luaL_error(L, fs_error_strings[result]);
    }

    if (read > 0) {
        lua_pushlstring(L, buffer, read); // Allocation #2: Lua string copy
    } else {
        lua_pushnil(L);
    }

    free(buffer);
    return 1;
}
```

### Memory Usage Per Read Call

| Block Size | C Buffer | Lua String | Peak Total |
|------------|----------|------------|------------|
| 16 KB | 16,384 bytes | 16,384 bytes | **32,768 bytes** |
| 4 KB | 4,096 bytes | 4,096 bytes | **8,192 bytes** |

The Lua string allocation (`lua_pushlstring`) creates a **copy** of the data in Lua's internal memory, so both allocations exist simultaneously at peak.

---

## The Copy Loop Memory Dynamics

From `shell.lua` lines 704-719:

```lua
local block = sf:read(block_size)    -- Creates 16KB C buffer + 16KB Lua string
local bytes_copied = 0
while block ~= nil do
    df:write(block)
    df:flush()
    bytes_copied = bytes_copied + #block
    -- progress display...
    block = sf:read(block_size)       -- NEW 16KB Lua string created
                                       -- OLD 'block' may not be GC'd yet
end
```

### Garbage Collection Delay

Each loop iteration:
1. Creates a **new** Lua string for `block`
2. The **old** string becomes unreachable but may not be immediately collected
3. Lua's incremental/generational GC doesn't guarantee immediate cleanup
4. Multiple 16KB strings can exist simultaneously before collection

---

## Why Fragmentation Causes OOM

### Memory State When WiFi Connected

```
Available Heap:      ~400-450 KB
- lwIP Static Pools: ~50-60 KB (allocated at connection time)
- Lua VM Overhead:   ~20-30 KB
= Remaining:         ~320-370 KB
```

This **appears sufficient**, but the issue is **fragmentation**:

1. lwIP allocates its pools in specific locations in the heap
2. Lua's internal allocator also fragments the heap
3. After some activity, the heap looks like:

```
[lwIP pool][free 4KB][Lua table][free 8KB][lwIP pool][free 12KB][Lua strings]...
```

4. **malloc(16384)** requires a **contiguous** 16KB block
5. Even with 320KB total free, no single 16KB contiguous region may exist
6. Allocation fails -> OOM panic

### Why 4KB Works

- Smaller blocks fit into fragmented gaps
- 8KB peak is more likely to find contiguous space
- More allocation/free cycles allow memory reuse
- Less likely to hit fragmentation cliff

### Why 16KB Works Without WiFi

- No lwIP memory pools (~50-60KB saved)
- Heap is less fragmented
- More contiguous space available

---

## Solutions and Workarounds

### 1. Current Workaround (Already Implemented)

Using 4KB blocks when WiFi is connected:

```lua
-- From shell.lua cp command
local block_size
if wifi.isConnected() then
    block_size = 4096
else
    block_size = 16384
end
```

**Status:** Effective, currently in use

### 2. Force Garbage Collection Before Copy

Add explicit GC before starting copy operations:

```lua
-- Before starting the copy loop
collectgarbage("collect")  -- Force full GC cycle
local block = sf:read(block_size)
```

This reclaims any pending Lua strings and reduces memory pressure.

### 3. Use Native C Copy Function

The existing `fs.copy()` C implementation (`picolua-api/fs.c:312-336`) is more efficient:

```c
static int l_fs_copy(lua_State* L) {
    // ...
    char buffer[8192];  // Stack allocation - no heap fragmentation!
    // ...
    while(!f_eof(&src)) {
        result = f_read(&src, buffer, sizeof(buffer), &read);
        result = f_write(&tgt, buffer, read, NULL);
    }
    // ...
}
```

Advantages:
- Uses **stack memory**, not heap
- No Lua string creation
- No garbage collection needed
- 8KB fixed buffer size

**Recommendation:** Use `fs.copy(src, dst)` for large file copies instead of Lua-level implementation.

### 4. Reduce lwIP Buffer Sizes

If maximum network throughput isn't critical, reduce lwIP memory:

```c
// Current (optimized for throughput)
#define TCP_WND         (8 * TCP_MSS)    // 11,680 bytes
#define TCP_SND_BUF     (8 * TCP_MSS)    // 11,680 bytes
#define PBUF_POOL_SIZE  24               // ~38,400 bytes

// Reduced (lower memory footprint)
#define TCP_WND         (4 * TCP_MSS)    // 5,840 bytes
#define TCP_SND_BUF     (2 * TCP_MSS)    // 2,920 bytes
#define PBUF_POOL_SIZE  16               // ~25,600 bytes
```

**Potential savings:** ~25-30 KB

### 5. Long-Term: PSRAM-Based Read Buffer

Modify `l_fs_read()` to use PSRAM for large reads:

```c
static int l_fs_read(lua_State* L) {
    FIL* fp = checkfile(L);
    UINT to_read = luaL_optinteger(L, 2, 1);

    char* buffer;
    bool use_psram = (to_read > 4096);  // Threshold

    if (use_psram) {
        // Allocate from PSRAM, read in chunks to Lua
        // ...
    } else {
        buffer = malloc(to_read);
        // ...existing code...
    }
}
```

This keeps large buffers out of main heap entirely.

---

## Key Files

| File | Purpose |
|------|---------|
| `sd_files/shell.lua` | cp command implementation (lines 658-726) |
| `picolua-api/fs.c` | File system bindings, l_fs_read() (lines 67-84) |
| `lwipopts.h` | lwIP memory configuration |
| `picolua-api/sys.c` | Memory query functions |
| `picolua-api/wifi.c` | WiFi Lua bindings |
| `drivers/wifi.c` | WiFi driver (cyw43 wrapper) |

---

## Verification and Debugging

### Monitor Memory During Copy

```lua
local function debug_copy(src, dst)
    print("Before copy - Free memory:", sys.freeMemory())
    collectgarbage("collect")
    print("After GC - Free memory:", sys.freeMemory())

    local sf = fs.open(src, "r")
    local df = fs.open(dst, "w")
    local block_size = wifi.isConnected() and 4096 or 16384

    local block = sf:read(block_size)
    while block do
        df:write(block)
        df:flush()
        if blocks % 10 == 0 then
            print("Free memory:", sys.freeMemory())
        end
        block = sf:read(block_size)
    end

    sf:close()
    df:close()
    print("After copy - Free memory:", sys.freeMemory())
end
```

### Test Native Copy

```lua
-- Use C implementation directly
fs.copy("source.bin", "dest.bin")
```

---

## Conclusion

The OOM panic is a predictable consequence of:
1. lwIP's significant static memory allocation (~50-60 KB)
2. Heap fragmentation making large contiguous allocations fail
3. The double-allocation pattern in `l_fs_read()` (C buffer + Lua string)
4. Lua's non-immediate garbage collection

The 4KB block size workaround is appropriate and effective. For optimal robustness:
1. Add `collectgarbage("collect")` before copy operations
2. Use native `fs.copy()` for large files
3. Consider reducing lwIP buffer sizes if max throughput isn't needed
