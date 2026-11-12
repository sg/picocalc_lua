# PicoCalc Lua Update System

The `update` shell command checks a remote git forge for new releases and can download and install both SD card file updates and firmware `.uf2` files. Before making changes it creates a tar backup of the current installation.

## Quick Start

```
update config          -- show the active config
update check           -- check if an update is available
update                 -- download and install
```

## Requirements

- Wi-Fi connection (`wifi on`)
- Optionally a config file at `/lua/shell/update_config.lua`; without one the built-in defaults are used
- A `/version.txt` file on the SD card (shipped in the SD archive and rewritten after each update)
- Releases published on the configured git forge with tagged versions

## Configuration

The built-in defaults point at the GitHub repository this tree is published from. To change any of them, copy the example config and edit it. Every key is optional and a key left out keeps its default:

```
cp /lua/shell/update_config.lua.example /lua/shell/update_config.lua
edit /lua/shell/update_config.lua
```

The config file returns a Lua table:

```lua
return {
  platform = "github",
  host = "https://api.github.com",
  owner = "your-username",
  repo = "picocalc_lua",
  download_base = "https://github.com/your-username/picocalc_lua/releases/download",
  sd_asset = "sd_files-{tag}.tar.gz",
  uf2_asset = "picolua-{board}-{tag}.uf2",
}
```

### Config Fields

| Field | Description |
|---|---|
| `platform` | `"github"`, `"forgejo"`, or `"gitea"` |
| `host` | API base URL. For GitHub: `https://api.github.com`. For Forgejo/Gitea: `https://your-instance.com` |
| `owner` | Repository owner (username or organization) |
| `repo` | Repository name |
| `download_base` | Base URL for downloading release assets. For GitHub this is `https://github.com/owner/repo/releases/download`. For Forgejo/Gitea: `https://your-instance.com/owner/repo/releases/download` |
| `sd_asset` | Filename pattern for the SD card files archive. `{tag}` is replaced with the release tag |
| `uf2_asset` | Filename pattern for firmware. `{tag}` is replaced with the release tag and `{board}` with the short board name `build.sh` uses (`pico`, `picow`, `pico2`, `pico2w`, `pim2w`), derived from `sys.board` |

## Commands

### `update`

Runs the full update flow:

1. Reads the SD card files' version from `/version.txt` and the running firmware's from `sys.version`
2. Queries the forge for the latest tagged release
3. Compares both versions with it (semver: `vX.Y.Z`)
4. Offers whichever is behind: the SD card files, the firmware, or both
5. If the SD card files are to be updated, checks that enough memory is free, and asks before going on if not
6. If the SD card files are to be updated, creates a backup archive
7. Downloads and extracts SD card files, then updates `/version.txt`
8. Downloads firmware to the uf2-loader directory

### `update check`

Same as `update` but stops after reporting what is behind. Does not download or install anything. Useful for a quick "is there something new?" check.

### `update config`

Displays the active configuration and whether it came from the file or the built-in defaults.

## How It Works

### Version Check

The updater fetches the latest tag from the forge's API:

- **GitHub:** `GET https://api.github.com/repos/{owner}/{repo}/tags?per_page=1`
- **Forgejo/Gitea:** `GET https://{host}/api/v1/repos/{owner}/{repo}/tags?limit=1`

The response is a small JSON array (under 1KB). Only the first tag's `name` field is used. This is compared against the version string in `/version.txt` using semver comparison (`vX.Y.Z` format). A `/version.txt` without an `X.Y.Z` number, which is what an archive built from an untagged commit carries, counts as older than any release.

The running firmware is compared with the same tag, separately from the SD card files. If the SD card files are current but the firmware is older, which is what a failed or declined firmware download leaves behind, `update` reports `Firmware update available!` and offers the firmware alone, with no memory check or backup since nothing else on the card changes. The firmware's version only changes once the uf2-loader has installed the file, so a firmware that is downloaded but not yet installed is still reported: the updater says the file is already in the loader directory, repeats the install steps and asks `Download firmware again? [y/N]`.

A firmware that is already at the latest release is not offered. A firmware whose version has no `X.Y.Z` number (a build from a tree without tags) cannot be compared: it is offered alongside an SD card update, as before, but is never reported as behind on its own.

### Backup

Before installing anything, the updater creates a tar archive of the current installation:

```
/backup/backup-v0.1.0.tar
```

The backup includes:
- `shell.lua` -- the main shell
- `main.lua` -- the startup script
- `lua/` -- all Lua modules, shell commands, and scripts
- `cc/` -- ComputerCraft compatibility modules
- `version.txt` -- the current version marker

If the backup fails, the updater deletes the partial archive, warns and asks whether to continue without a backup.

### SD Card File Update

The SD card files archive (e.g. `sd_files-v0.2.0.tar.gz`) is downloaded to a temporary file at the root of the SD card, then extracted in place. The tar extractor prompts before overwriting existing files -- type `a` at the first prompt to accept all overwrites.

After extraction the temp file is deleted and `/version.txt` is updated to the new version. If the extraction fails the updater stops there: `/version.txt` keeps the old version, no firmware is downloaded, and running `update` again after a reboot repeats the whole update.

### Firmware Update

Firmware `.uf2` files are downloaded to the uf2-loader application directory:

| Board Type | Directory |
|---|---|
| `pico`, `pico_w` (RP2040) | `/pico1-apps/` |
| `pico2`, `pico2_w`, `pimoroni_pico_plus2_w_rp2350` (RP2350) | `/pico2-apps/` |

The board type is detected automatically from `sys.board` and mapped to the short name `build.sh` uses, which replaces the `{board}` placeholder in the `uf2_asset` config field so the correct firmware variant is downloaded.

If the download fails, the updater reports `Update incomplete: no firmware was downloaded.` Run `update` again to retry: the SD card files are then current and only the firmware is offered.

To install the firmware after downloading:

1. Power off or reboot the PicoCalc
2. Hold the **Up Arrow** key while powering on to enter uf2-loader
3. Select the new firmware file from the list

## Example Session

```
[/:> update
Checking https://api.github.com/repos/seclorum/picocalc_lua/tags?per_page=1
Current version: v0.1.0
       Firmware: v0.1.0
 Latest version: v0.2.0

Update available!

Available:
  1. SD card files (sd_files-v0.2.0.tar.gz)
  2. Firmware for pico2_w (picolua-pico2w-v0.2.0.uf2)

Update SD card files? [Y/n]: y
Download firmware update? [y/N]: y

Backing up to /backup/backup-v0.1.0.tar...
  shell.lua
  main.lua
  lua/
  cc/
  version.txt
Created archive: 42 entries
Backup created: /backup/backup-v0.1.0.tar

Downloading sd_files-v0.2.0.tar.gz...
Downloaded 48.2k

Extracting update...
Tip: type 'a' at the overwrite prompt to accept all

  Overwrite shell.lua? [y/n/All]: a
  shell.lua
  main.lua
  lua/modules/http.lua
  ...
Extracted 35 entries

Downloading picolua-pico2w-v0.2.0.uf2...
Firmware saved to /pico2-apps/picolua-pico2w-v0.2.0.uf2 (512.0k)

Update complete!
SD files updated to v0.2.0
Run reload to reload shell commands.

To install firmware:
  1. Reboot while holding Up Arrow to enter uf2-loader
  2. Select picolua-pico2w-v0.2.0.uf2 from /pico2-apps/
```

## Publishing Releases

Pushing a `vX.Y.Z` tag runs the release workflow described in
`release-workflow.md`, which builds every board and stages a draft release
holding exactly the assets the updater expects:

| `sys.board` | Firmware asset |
|---|---|
| `pico` | `picolua-pico-v0.2.0.uf2` |
| `pico_w` | `picolua-picow-v0.2.0.uf2` |
| `pico2` | `picolua-pico2-v0.2.0.uf2` |
| `pico2_w` | `picolua-pico2w-v0.2.0.uf2` |
| `pimoroni_pico_plus2_w_rp2350` | `picolua-pim2w-v0.2.0.uf2` |

plus `sd_files-v0.2.0.tar.gz`, made by `make-sd-archive.sh`, which carries a
`version.txt` so a card installed from it reports its version. Devices see
the tag as soon as it is pushed, so publish the draft promptly or the update
command will report a version it cannot download yet.

To build the same assets by hand:

```bash
./build.sh all v0.2.0
VERSION=v0.2.0 ./make-sd-archive.sh sd_files-v0.2.0.tar.gz
```

### Version Tagging

The updater uses semver comparison (`vX.Y.Z`). Tags must follow this format:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The release workflow then stages a draft release with the assets; publish it from the Releases page.

## Troubleshooting

**"Cannot load /lua/shell/update_config.lua"** -- The file has a syntax error or does not return a table. Fix it, or delete it to fall back to the built-in defaults.

**"Wi-Fi not connected"** -- Run `wifi on` first to connect.

**"HTTP 404"** -- Check that the release exists on the forge and the asset filenames match the config. Verify `download_base` is correct (GitHub uses `github.com`, not `api.github.com` for downloads).

**"Could not parse tags response"** -- The forge may require authentication, or the repo may have no tags. Verify the repo is public and has at least one tag.

**"Already up to date"** -- The version in `/version.txt` and the running firmware both match or are newer than the latest tag. To force a re-install of the SD card files, edit `/version.txt` to an older version or delete it.

**"Firmware update available!" after installing it** -- The updater reads the version of the firmware that is running. Check the `Firmware:` line it prints; if that still shows the old version, the new `.uf2` was downloaded but not selected in the uf2-loader.

**Backup fails** -- Check that there is enough free space on the SD card. The backup archives the entire `lua/` directory which can be several hundred KB.

**"memory is low or fragmented"** -- The session has used too much of the heap for the update to be safe, usually after running other programs. Answer `n`, reboot and run `update` first thing.

**"SD card files were not fully updated"** -- The extraction stopped, most often with `not enough memory`, and the card may hold a mix of old and new files. Reboot and run `update` again; it starts over and replaces every file.

**Extraction issues** -- If the update archive has an unexpected directory structure, files may extract to the wrong location. The archive should contain paths relative to the SD card root (e.g. `shell.lua`, `lua/modules/http.lua`, not `/sd_files/shell.lua`).

## Memory Considerations

The update process is designed for the PicoCalc's constrained memory (~200KB total, less with Wi-Fi active):

- The version check downloads < 1KB of JSON
- Downloads stream directly to disk in 4KB chunks, not buffered in RAM
- The HTTP and JSON modules are unloaded after each use
- Garbage collection runs aggressively between operations
- The tar backup and extract stream in 1KB blocks and collect garbage after each, so the buffers fit a fragmented heap
- On firmware up to v0.6.7, unpacking the `.tar.gz` needs one unbroken 32KB block for the gzip window, which is what a long-running session most often lacks: running programs leaves the free memory in ever smaller pieces, though there is as much of it. The updater tests for a 48KB block before it starts, and `tar` says to restart when the block cannot be had
- Later firmware takes the window as eight 4KB blocks (`gzip.blockSize`), so the updater only tests that 64KB is free in all

## Restoring from Backup

If an update goes wrong, restore from the backup:

```
tar x /backup/backup-v0.1.0.tar /
reload
```

This extracts the backed-up files over the current installation. Type `a` at the overwrite prompt to accept all.

For firmware, the previous `.uf2` file should still be in the uf2-loader directory. Enter uf2-loader (hold Up Arrow on boot) and select the older firmware.
