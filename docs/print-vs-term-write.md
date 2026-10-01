# Analysis: print() vs term.write() in PicoCalc Lua

## Executive Summary

**Both functions serve different purposes:**
- `print()` - Standard Lua output with convenience features (multi-arg, auto-newline, type coercion)
- `term.write()` - Direct terminal output with lower overhead (single string, no newline, no conversion)

For memory-constrained PicoCalc, `term.write()` is more efficient for high-volume or performance-critical output, while `print()` is better for convenience and debugging.

## Implementation Details

### Call Chain

```
print()
  → luaL_tolstring() for each argument (memory allocation)
  → lua_writestring() macro
  → fwrite() to stdout
  → Pico stdio driver
  → stdio_picocalc_out_chars()
  → ANSI parser + LCD rendering

term.write()
  → directly calls stdio_picocalc_out_chars()
  → ANSI parser + LCD rendering
```

### Feature Comparison

| Feature | print() | term.write() |
|---------|---------|-------------|
| Multiple arguments | Yes (tab-separated) | No |
| Automatic newline | Yes | No |
| Type coercion | Yes (numbers, tables, etc.) | No (string only) |
| Memory allocations | Multiple (per argument) | Zero (caller's string) |
| Calls to output driver | Multiple | Single |
| ANSI escape codes | Supported | Supported |

### Performance Analysis

**print() overhead:**
- Iterates through all arguments
- Allocates strings via `luaL_tolstring()` for each argument
- Calls `lua_writestring()` multiple times (once per arg + newline)
- Higher GC pressure from intermediate strings

**term.write() efficiency:**
- Single string argument, no iteration
- No memory allocation (uses caller's string)
- One direct call to `stdio_picocalc_out_chars()`
- Lower GC pressure

### When to Use Each

**Use print() when:**
- Debugging (quick output of multiple values)
- REPL interaction
- Simple scripts where convenience matters
- Need automatic newlines

**Use term.write() when:**
- Performance-critical code (loops, frequent output)
- Need precise control over newlines
- Using ANSI colors inline
- Memory is tight (avoiding intermediate allocations)
- Building shell/UI components

## Files Analyzed

| File | Purpose |
|------|---------|
| `submodules/lua-5.4.8/lbaselib.c:24-37` | Lua print() implementation |
| `picolua-api/term.c:97-102` | term.write() Lua binding |
| `drivers/term.c:290-384` | stdio_picocalc_out_chars() core output |
| `sd_files/shell.lua` | Usage examples |
| `sd_files/main.lua` | Usage examples |
