# Research: PSRAM Usage Options for Pimoroni Pico Plus 2W

## Executive Summary

The Pimoroni Pico Plus 2W has 8MB of external PSRAM that can be leveraged in multiple ways. This research covers the current SPI-based implementation, the possibility of XIP (Execute in Place) memory-mapped access, using PSRAM as additional heap, and specific use cases for this Lua implementation.

---

## Current Implementation

The project already has a working PSRAM module using **SPI-based access** via the `rp2040-psram` library:

| Aspect | Current State |
|--------|---------------|
| Access Method | PIO-based SPI with DMA |
| Pin Configuration | CS=GPIO20, SCK=GPIO21, MOSI=GPIO2, MISO=GPIO3 |
| Memory Mapping | NOT memory-mapped; explicit read/write calls required |
| Lua API | Full API: `psram.alloc()`, `psram.read()`, `psram.write()`, etc. |
| Allocator | Simple first-fit with 32 allocation slots |
| LCD Integration | Optional framebuffer mode (reserves 204KB) |

### Current Limitations
- Data must be explicitly copied between PSRAM and main RAM
- Cannot use standard `malloc()` for PSRAM allocations
- Cannot execute code from PSRAM
- Chunk-based access (20 bytes at a time due to PIO limits)

---

## Option 1: XIP Memory-Mapped PSRAM

### What is XIP PSRAM?

The RP2350's QMI (QSPI Memory Interface) controller can memory-map external PSRAM, making it appear as regular RAM at address `0x11000000`. This enables:

- **Direct pointer access** - Read/write PSRAM like normal memory
- **Execute in Place** - Run code directly from PSRAM
- **Standard allocation** - Can integrate with malloc/heap

### Hardware Requirements

The Pimoroni Pico Plus 2W connects PSRAM via:
- **GPIO 47** - Directly connected to QMI CS1 (QSPI chip select 1)
- This is the native XIP interface, NOT the current SPI pins

**Important:** The current implementation uses GPIO 20/21/2/3 for SPI access. XIP would use GPIO 47 and the dedicated QSPI pins (shared with flash).

### Enabling XIP PSRAM

Basic initialization (from Raspberry Pi Forums):
```c
#include "hardware/structs/qmi.h"
#include "hardware/structs/xip_ctrl.h"

// Enable PSRAM chip select on GPIO 47
gpio_set_function(47, GPIO_FUNC_XIP_CS1);

// Enable writes to memory window 1 (PSRAM)
xip_ctrl_hw->ctrl |= XIP_CTRL_WRITABLE_M1_BITS;

// PSRAM now accessible at 0x11000000
volatile uint8_t* psram = (volatile uint8_t*)0x11000000;
```

### Memory Addresses

| Address Range | Access Type |
|---------------|-------------|
| `0x11000000` - `0x117FFFFF` | Cached XIP (8MB) |
| `0x15000000` - `0x157FFFFF` | Uncached XIP |
| `0x1D000000` - `0x1D7FFFFF` | Uncached, untranslated |

### Performance Optimization

Basic SPI mode is slow. For good performance, configure QSPI Quad mode:
```c
// Configure timing for AP Memory PSRAM
qmi_hw->m[1].timing = QMI_M1_TIMING_COOLDOWN_VALUE(1) |
                       QMI_M1_TIMING_RXDELAY_VALUE(1) |
                       QMI_M1_TIMING_CLKDIV_VALUE(2);  // ~70MHz at 140MHz sys

// Configure read format for Quad mode
qmi_hw->m[1].rfmt = QMI_M1_RFMT_PREFIX_WIDTH_VALUE(QMI_M1_RFMT_PREFIX_WIDTH_VALUE_Q) |
                    QMI_M1_RFMT_ADDR_WIDTH_VALUE(QMI_M1_RFMT_ADDR_WIDTH_VALUE_Q) |
                    QMI_M1_RFMT_SUFFIX_WIDTH_VALUE(QMI_M1_RFMT_SUFFIX_WIDTH_VALUE_Q) |
                    QMI_M1_RFMT_DUMMY_WIDTH_VALUE(QMI_M1_RFMT_DUMMY_WIDTH_VALUE_Q) |
                    QMI_M1_RFMT_DATA_WIDTH_VALUE(QMI_M1_RFMT_DATA_WIDTH_VALUE_Q) |
                    QMI_M1_RFMT_DUMMY_LEN_VALUE(6);

// Configure read command (0xEB = Quad I/O Read)
qmi_hw->m[1].rcmd = 0xEB;
```

### Performance Benchmarks (from community testing)

| Operation | Speed |
|-----------|-------|
| Sequential read (Quad, cached) | ~25-33 MB/s |
| Sequential write (Quad) | ~10-15 MB/s |
| Random access | Much slower due to cache misses |

### Caveats

1. **Flash Write Conflicts**: Flash operations corrupt QMI registers. Workaround: save/restore QMI config around flash writes.
2. **Cache Coherency**: Must flush cache before flash operations.
3. **Not SDK-supported**: No official Pico SDK support yet (planned for 2.3.0).
4. **Linker Script Changes**: Needed for code/data placement in PSRAM.

---

## Option 2: PSRAM as Additional Heap

### Current SDK Support

**No native support** as of Pico SDK 2.x. From GitHub issue #1815:
> "not currently" - Graham Sanderson (Raspberry Pi)

### Community Solutions

#### SparkFun Approach
Replace default allocator with one that manages both SRAM and PSRAM:
```cmake
# CMakeLists.txt
set(SKIP_PICO_MALLOC 1)
set(SFE_PICO_ALLOC_WRAP 1)
add_definitions(-DSFE_PICO_ALLOC_WRAP)
```

This wraps `malloc()`/`free()` to:
1. Try SRAM first
2. Fall back to PSRAM if SRAM exhausted
3. Track which heap each allocation came from

#### Arduino-Pico Approach
Provides separate functions:
```c
void* pmalloc(size_t size);   // Allocate from PSRAM
void* pcalloc(size_t n, size_t size);
// free() and realloc() auto-detect memory region
```

### Implementing for This Project

Create a unified allocator:
```c
// psram_heap.h
void* psram_malloc(size_t size);
void* psram_calloc(size_t n, size_t size);
void* psram_realloc(void* ptr, size_t size);
void psram_free(void* ptr);

// Check if pointer is in PSRAM
bool is_psram_ptr(void* ptr);
```

---

## Option 3: Lua-Specific Use Cases

### 3.1 Large File Buffers (Addresses OOM Issue)

Modify `l_fs_read()` to use PSRAM for large reads:
```c
static int l_fs_read(lua_State* L) {
    FIL* fp = checkfile(L);
    UINT to_read = luaL_optinteger(L, 2, 1);

    if (to_read > 4096) {
        // Use PSRAM for large reads
        uint32_t psram_addr = psram_c_alloc(to_read);
        if (psram_addr != PSRAM_ALLOC_FAILED) {
            // Read directly to PSRAM, then chunk to Lua string
            // ... (avoids large heap allocation)
        }
    }
    // Fall back to existing implementation for small reads
}
```

### 3.2 Lua String Pool in PSRAM

Store large Lua strings in PSRAM with lazy loading:
```lua
-- Create a PSRAM-backed string
local handle = psram.alloc(1000000, "big_data")
psram.write(handle, 0, large_data)

-- Read chunks as needed
local chunk = psram.read(handle, offset, 4096)
```

### 3.3 HTTP Response Streaming

Already partially implemented - download large files directly to PSRAM:
```lua
local buf = psram.alloc(1024 * 1024, "download")
http.get(url, {
    psram_buffer = buf,
    chunk_callback = function(chunk, offset)
        -- Data written directly to PSRAM
    end
})
```

### 3.4 Image/Graphics Buffer

Use PSRAM for image manipulation:
```lua
local img = psram.alloc(320 * 240 * 2, "image")
-- Load/manipulate image in PSRAM
-- Blit to LCD in chunks
```

### 3.5 Lua Bytecode Cache

Store compiled Lua bytecode in PSRAM to avoid recompilation:
```c
// In C: cache compiled chunks in PSRAM
// Key: hash of source code
// Value: compiled bytecode
```

---

## Option 4: Execute in Place (XIP) - Running Code from PSRAM

### What's Possible

With XIP enabled, code can execute directly from PSRAM:
- Overflow large Lua modules to PSRAM
- Store infrequently-used functions in PSRAM
- Free up flash for more data storage

### Linker Script Configuration

```ld
MEMORY {
    FLASH(rx) : ORIGIN = 0x10000000, LENGTH = 2M
    RAM(rwx) : ORIGIN = 0x20000000, LENGTH = 264K
    SCRATCH_X(rwx) : ORIGIN = 0x20040000, LENGTH = 4K
    SCRATCH_Y(rwx) : ORIGIN = 0x20041000, LENGTH = 4K
    PSRAM(rwx) : ORIGIN = 0x11000000, LENGTH = 8M
}

SECTIONS {
    .psram_code : {
        *(.psram_code*)
    } > PSRAM

    .psram_data (NOLOAD) : {
        *(.psram_data*)
    } > PSRAM
}
```

### Placing Code in PSRAM

```c
__attribute__((section(".psram_code")))
void slow_but_large_function(void) {
    // This function lives in PSRAM
}
```

### Performance Impact

Code in PSRAM runs **~3-5x slower** than flash due to:
- QSPI interface overhead
- Cache miss penalty
- No XIP caching for PSRAM (unlike flash)

**Best for:** Large, infrequently-called functions

---

## Recommendations for This Project

### Immediate (Low Effort, High Value)

1. **Keep current SPI implementation** - It works and is well-tested
2. **Add `psram.readToString()` helper** - Efficiently read PSRAM to Lua string
3. **Use PSRAM for large file operations** - Modify `cp` command to use `psram.alloc()` for buffer

### Medium-Term (Moderate Effort)

4. **Investigate XIP mode** - The hardware supports it via GPIO 47
5. **Create PSRAM heap wrapper** - `psram_malloc()`/`psram_free()` for C code
6. **HTTP streaming to PSRAM** - Already partially implemented

### Long-Term (Higher Effort, Architectural)

7. **Switch to XIP memory-mapped mode** - Major change but simplifies programming model
8. **Unified allocator** - Single `malloc()` that spans SRAM+PSRAM
9. **Lua bytecode caching** - Store compiled scripts in PSRAM

---

## Key Files to Modify

| File | Purpose |
|------|---------|
| `picolua-api/psram.c` | Current PSRAM Lua module |
| `picolua-api/psram.h` | PSRAM API header |
| `picolua-api/fs.c` | File operations (for PSRAM buffers) |
| `submodules/rp2040-psram/` | Low-level SPI library |
| `CMakeLists.txt` | Build configuration |
| `lwipopts.h` | (Already modified) lwIP memory settings |

---

## References

- [Arduino-Pico PSRAM Documentation](https://arduino-pico.readthedocs.io/en/latest/psram.html)
- [RP2350 XIP PSRAM Forum Thread](https://forums.raspberrypi.com/viewtopic.php?t=375109)
- [Pico SDK PSRAM Heap Issue #1815](https://github.com/raspberrypi/pico-sdk/issues/1815)
- [Dmitry.GR RP2350 Analysis](https://dmitry.gr/?r=06.+Thoughts&proj=11.+RP2350)
- [SparkFun PSRAM Library](https://github.com/sparkfun/sparkfun-pico)
- [PSRAM + Flash Cache Issues](https://forums.raspberrypi.com/viewtopic.php?t=375845)
