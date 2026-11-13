# tools

Test runners and helpers that work on the build machine, not on the PicoCalc. Nothing here goes onto the SD card or into the firmware.

## botwarz

Plays BotWarz (`sd_files/lua/botwarz`) under host Lua 5.4 with the device's APIs stubbed.

| Command | What it does |
|---|---|
| `lua5.4 tools/botwarz/tests.lua` | Checks the game's rules one at a time (hits, scans, turning, collisions, limits, script errors) with bots written for each case. Prints each failure and a count. |
| `lua5.4 tools/botwarz/harness.lua` | Plays every bot in `bots/` against every other and checks after each tick that nothing left the arena, overlapped or drew outside it. `PSRAM=0` takes the path without a framebuffer; other settings are listed at the top of the file. |
| `lua5.4 tools/botwarz/limits.lua` | Shows which bots go over an instruction limit of several sizes, and how low each bot's energy falls. |

Run the first two after any change to the game or to a stock bot.

## zmachine

`lua5.4 tools/zmachine/harness.lua sd_files STORY SCRIPT [WORKDIR]` runs the Z-machine interpreter (`sd_files/lua/zmachine`) under host Lua on a story file, typing the lines in SCRIPT, and prints the final screen. Its terminal reports any write that would wrap or scroll. Story files are not kept in this repository.

## gzip

`tools/gzip/check.sh [more.gz ...]` builds uzlib on the host with the gzip window in 4 KB blocks, as the firmware has it, and in one piece, and compares what each decompresses with `gzip -dc`. Run it after touching `submodules/uzlib` or `picolua-api/gzip.c`.

## kilo

`tools/kilo/check.sh` builds the firmware's editor (`submodules/kilo`) for the host with the address and undefined-behaviour sanitizers and runs it from key scripts: the cases in `tools/kilo/cases` must leave the saved file and the screen they expect, then the heap is limited, every allocation is failed in turn, the card is filled, and random keys are typed in heaps of random sizes (`RANDOM_RUNS` and `SEED` set how many and which). Nothing may crash, leak or lose text. Run it after any change to the editor.

`UPDATE=1 tools/kilo/check.sh` rewrites what the cases expect, so read the diff before keeping it. The key script format and the harness's settings are at the top of `harness.c`. Pointers are 8 bytes on the host, so the row table costs twice what it does on the device and the heap figures it prints are high by that much.

## sim

For picocalc-sim, expected in `picocalc_sim` beside this repository.

- `tools/sim/run.sh UF2 SCRIPT [OUTDIR]` builds a card from `sd_files`, boots the firmware without a window, brings up the shell and plays SCRIPT (keys, waits and screenshots). `WIFI=1` joins the simulator's access point first; `PLAIN=1` is for boards without Wi-Fi; `OVERLAY=dir` adds files to the card.
- `tools/sim/sheet.py OUT.png COLUMNS [--crop x0,y0,x1,y1] [--scale K] IN.png...` puts screenshots side by side.
- `tools/sim/card/lua` is copied onto every card the runner builds:
  - `blocks.lua` prints the largest free block and how much memory can be had in 4 KB blocks;
  - `fragment.lua` pins allocations through the free memory, as a long session does;
  - `gzbench.lua` times decompressing `/sd_files-test.tar.gz`;
  - `simwifi.lua` joins the simulator's access point.
