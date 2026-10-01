# PicoCalc Lua Update System

The `update` shell command checks a remote git forge for new releases and can download and install both SD card file updates and firmware `.uf2` files. Before making changes it creates a tar backup of the current installation.

## Quick Start

```
update config          -- show config template
edit /lua/shell/update_config.lua   -- create config
update check           -- check if an update is available
update                 -- download and install
```

## Requirements

- Wi-Fi connection (`wifi on`)
- A config file at `/lua/shell/update_config.lua`
- A `/version.txt` file on the SD card (created automatically after first update)
- Releases published on the configured git forge with tagged versions

## Configuration

Copy the example config and edit it:

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
  sd_asset = "sd_files.tar.gz",
  uf2_asset = "picolua-{board}.uf2",
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
| `sd_asset` | Filename of the SD card files archive in the release |
| `uf2_asset` | Filename pattern for firmware. `{board}` is replaced with `sys.board` at runtime (e.g. `pico2_w`, `pico_w`, `pimoroni_pico_plus2_w_rp2350`) |

## Commands

### `update`

Runs the full update flow:

1. Reads the current version from `/version.txt`
2. Queries the forge for the latest tagged release
3. Compares versions (semver: `vX.Y.Z`)
4. If an update is available, asks what to install
5. Creates a backup archive
6. Downloads and extracts SD card files
7. Downloads firmware to the uf2-loader directory
8. Updates `/version.txt`

### `update check`

Same as `update` but stops after comparing versions. Does not download or install anything. Useful for a quick "is there something new?" check.

### `update config`

Displays the current configuration. If no config file exists, prints a template showing the expected format.

## How It Works

### Version Check

The updater fetches the latest tag from the forge's API:

- **GitHub:** `GET https://api.github.com/repos/{owner}/{repo}/tags?per_page=1`
- **Forgejo/Gitea:** `GET https://{host}/api/v1/repos/{owner}/{repo}/tags?limit=1`

The response is a small JSON array (under 1KB). Only the first tag's `name` field is used. This is compared against the version string in `/version.txt` using semver comparison (`vX.Y.Z` format).

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

If the backup fails, the updater warns and asks whether to continue without a backup.

### SD Card File Update

The SD card files archive (e.g. `sd_files.tar.gz`) is downloaded to a temporary file at the root of the SD card, then extracted in place. The tar extractor prompts before overwriting existing files -- type `a` at the first prompt to accept all overwrites.

After extraction the temp file is deleted and `/version.txt` is updated to the new version.

### Firmware Update

Firmware `.uf2` files are downloaded to the uf2-loader application directory:

| Board Type | Directory |
|---|---|
| `pico`, `pico_w` (RP2040) | `/pico1-apps/` |
| `pico2`, `pico2_w`, `pimoroni_pico_plus2_w_rp2350` (RP2350) | `/pico2-apps/` |

The board type is detected automatically from `sys.board`. The `{board}` placeholder in the `uf2_asset` config field is replaced with the actual board name to download the correct firmware variant.

To install the firmware after downloading:

1. Power off or reboot the PicoCalc
2. Hold the **Up Arrow** key while powering on to enter uf2-loader
3. Select the new firmware file from the list

## Example Session

```
[/:> update
Checking https://api.github.com/repos/seclorum/picocalc_lua/tags?per_page=1
Current version: v0.1.0
 Latest version: v0.2.0

Update available!

Available:
  1. SD card files (sd_files.tar.gz)
  2. Firmware for pico2_w (picolua-pico2_w.uf2)

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

Downloading sd_files.tar.gz...
Downloaded 48.2k

Extracting update...
Tip: type 'a' at the overwrite prompt to accept all

  Overwrite shell.lua? [y/n/All]: a
  shell.lua
  main.lua
  lua/modules/http.lua
  ...
Extracted 35 entries

Downloading picolua-pico2_w.uf2...
Firmware saved to /pico2-apps/picolua-pico2_w.uf2 (512.0k)

Update complete!
SD files updated to v0.2.0
Run reload to reload shell commands.

To install firmware:
  1. Reboot while holding Up Arrow to enter uf2-loader
  2. Select picolua-pico2_w.uf2 from /pico2-apps/
```

## Publishing Releases

To make updates available to users, publish a release on your git forge with:

1. A semver git tag (e.g. `v0.2.0`)
2. An `sd_files.tar.gz` archive containing the SD card file tree
3. Board-specific `.uf2` firmware files named `picolua-{board}.uf2`

### Creating the SD Files Archive

From the project root:

```bash
cd sd_files
tar czf ../sd_files.tar.gz .
```

Or if your release only includes changed files, create a tar.gz of just those files, preserving the directory structure relative to the SD card root.

### Naming Firmware Files

Each board variant gets its own `.uf2` file. The naming convention must match the `uf2_asset` pattern in the config. With the default pattern `picolua-{board}.uf2`, the assets would be:

| Board | Filename |
|---|---|
| `pico_w` | `picolua-pico_w.uf2` |
| `pico2_w` | `picolua-pico2_w.uf2` |
| `pimoroni_pico_plus2_w_rp2350` | `picolua-pimoroni_pico_plus2_w_rp2350.uf2` |

### Version Tagging

The updater uses semver comparison (`vX.Y.Z`). Tags must follow this format:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Then create a release on the forge attached to that tag and upload the assets.

## Troubleshooting

**"No update config found"** -- Create `/lua/shell/update_config.lua`. Run `update config` to see the template.

**"Wi-Fi not connected"** -- Run `wifi on` first to connect.

**"HTTP 404"** -- Check that the release exists on the forge and the asset filenames match the config. Verify `download_base` is correct (GitHub uses `github.com`, not `api.github.com` for downloads).

**"Could not parse tags response"** -- The forge may require authentication, or the repo may have no tags. Verify the repo is public and has at least one tag.

**"Already up to date"** -- The version in `/version.txt` matches or is newer than the latest tag. To force a re-install, edit `/version.txt` to an older version or delete it.

**Backup fails** -- Check that there is enough free space on the SD card. The backup archives the entire `lua/` directory which can be several hundred KB.

**Extraction issues** -- If the update archive has an unexpected directory structure, files may extract to the wrong location. The archive should contain paths relative to the SD card root (e.g. `shell.lua`, `lua/modules/http.lua`, not `/sd_files/shell.lua`).

## Memory Considerations

The update process is designed for the PicoCalc's constrained memory (~200KB total, less with Wi-Fi active):

- The version check downloads < 1KB of JSON
- Downloads stream directly to disk in 4KB chunks, not buffered in RAM
- The HTTP and JSON modules are unloaded after each use
- Garbage collection runs aggressively between operations
- The tar backup and extract stream in 4KB blocks

## Restoring from Backup

If an update goes wrong, restore from the backup:

```
tar x /backup/backup-v0.1.0.tar /
reload
```

This extracts the backed-up files over the current installation. Type `a` at the overwrite prompt to accept all.

For firmware, the previous `.uf2` file should still be in the uf2-loader directory. Enter uf2-loader (hold Up Arrow on boot) and select the older firmware.
