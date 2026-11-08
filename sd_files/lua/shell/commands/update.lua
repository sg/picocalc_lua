--[[

  update.lua - Check for and install PicoCalc Lua updates

  Checks a remote git forge (GitHub, Forgejo, Gitea) for
  new releases. Downloads SD card file updates and/or
  firmware .uf2 files.

  Before updating, backs up current installation to a
  tar archive in /backup/.

  Usage:
    update              - check and install updates
    update check        - check only, don't install
    update config       - show current update config

  Configuration is read from /lua/shell/update_config.lua when
  it exists; any key it leaves out, or the whole file, falls
  back to DEFAULT_CONFIG below.

]]

local c = require("lua/modules/simple-colors")

------------------------------------------------------------
-- DEFAULT CONFIG
------------------------------------------------------------
local DEFAULT_CONFIG = {
  -- "github", "forgejo", or "gitea"
  platform = "github",
  -- API host (include https://)
  host = "https://api.github.com",
  -- repository owner and name
  owner = "sg",
  repo = "picocalc_lua",
  -- download base URL for release assets
  -- (may differ from API host, e.g. github.com vs api.github.com)
  download_base = "https://github.com/sg/picocalc_lua/releases/download",
  -- release asset patterns: {tag} is the release tag and {board}
  -- the short board name build.sh uses, derived from sys.board
  sd_asset = "sd_files-{tag}.tar.gz",
  uf2_asset = "picolua-{board}-{tag}.uf2",
}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

-- returns the config and where it came from, or nil and an error;
-- a file that exists but will not load is reported rather than
-- silently replaced by the defaults
local function load_config()
  local path = "lua/shell/update_config.lua"
  local cfg, source = {}, "built-in defaults"
  if fs.exists(path) then
    local ok, result = pcall(dofile, path)
    if not ok then
      return nil, "Cannot load /" .. path .. ": " .. tostring(result)
    end
    if type(result) ~= "table" then
      return nil, "/" .. path .. " must return a table"
    end
    cfg, source = result, "/" .. path
  end
  for k, v in pairs(DEFAULT_CONFIG) do
    if cfg[k] == nil then cfg[k] = v end
  end
  return cfg, source
end

-- read current version from /version.txt
local function read_version()
  if not fs.exists("version.txt") then return nil end
  local f = fs.open("version.txt", "r")
  if not f then return nil end
  local v = f:read(64)
  f:close()
  if v then v = v:match("^%s*(.-)%s*$") end
  return v
end

-- write version to /version.txt
local function write_version(ver)
  local f = fs.open("version.txt", "w")
  if not f then return false end
  f:write(ver .. "\n")
  f:flush()
  f:close()
  return true
end

-- build the API URL for fetching latest tag
local function tags_url(cfg)
  local prefix = ""
  if cfg.platform == "forgejo" or cfg.platform == "gitea" then
    prefix = "/api/v1"
  end
  local limit_param = cfg.platform == "github"
    and "?per_page=1" or "?limit=1"
  return cfg.host .. prefix .. "/repos/"
    .. cfg.owner .. "/" .. cfg.repo .. "/tags" .. limit_param
end

-- build download URL for a release asset
local function asset_url(cfg, tag, filename)
  return cfg.download_base .. "/" .. tag .. "/" .. filename
end

-- determine uf2 directory based on board name
local function uf2_dir()
  local board = sys.board or ""
  -- pico2, pico2_w, and pimoroni boards are RP2350-based
  if board:match("pico2") or board:match("rp2350")
    or board:match("pimoroni") then
    return "pico2-apps"
  end
  return "pico1-apps"
end

-- build.sh names firmware by these short names, not the SDK board names
local BOARD_NAMES = {
  pico = "pico",
  pico_w = "picow",
  pico2 = "pico2",
  pico2_w = "pico2w",
  pimoroni_pico_plus2_w_rp2350 = "pim2w",
}

local function asset_name(pattern, tag)
  local board = sys.board or "unknown"
  board = BOARD_NAMES[board] or board
  return (pattern:gsub("{board}", board):gsub("{tag}", tag))
end

-- true if release a is newer than b; a version without an X.Y.Z
-- number, which is what an archive built from an untagged commit
-- carries, counts as older than any release
local function version_newer(a, b)
  if not a or not b then return a ~= nil end
  local a1, a2, a3 = a:match("^v?(%d+)%.(%d+)%.(%d+)")
  local b1, b2, b3 = b:match("^v?(%d+)%.(%d+)%.(%d+)")
  if not a1 then return a > b end
  if not b1 then return true end
  a1, a2, a3 = tonumber(a1), tonumber(a2), tonumber(a3)
  b1, b2, b3 = tonumber(b1), tonumber(b2), tonumber(b3)
  if a1 ~= b1 then return a1 > b1 end
  if a2 ~= b2 then return a2 > b2 end
  return a3 > b3
end

-- ensure a directory exists, creating parents as needed
local function ensure_dir(path)
  if path == "" then return true end
  if fs.exists(path) then return true end
  -- try to create parent first
  local parent = path:match("^(.+)/[^/]+$")
  if parent then ensure_dir(parent) end
  fs.makeDir(path)
  return fs.exists(path)
end

-- stream-download a file, return bytes written or nil + error
local function download_file(url, dest_path, sh)
  local http = require("lua/modules/http")
  collectgarbage("collect")

  local resp = http.get(url, { output_file = dest_path })

  -- free http module
  package.loaded["lua/modules/http"] = nil
  collectgarbage("collect")

  if not resp then
    return nil, "No response from server"
  end
  if resp.status ~= 200 then
    -- clean up partial download
    if fs.exists(dest_path) then fs.delete(dest_path) end
    return nil, "HTTP " .. tostring(resp.status)
  end

  local bytes = resp.streamed_bytes or (resp.body and #resp.body) or 0
  -- if response was buffered (small file), write it out
  if resp.body and not resp.streamed then
    local f = fs.open(dest_path, "w")
    if not f then return nil, "Cannot write " .. dest_path end
    f:write(resp.body)
    f:flush()
    f:close()
  end

  return bytes
end

-- fetch latest tag from the forge
local function fetch_latest_tag(cfg, sh)
  local http = require("lua/modules/http")
  local json = require("lua/modules/json")
  collectgarbage("collect")

  local url = tags_url(cfg)
  term.write(c.cyan .. "Checking " .. c.white .. url .. "\n")

  local resp = http.get(url)

  -- free modules
  package.loaded["lua/modules/http"] = nil
  collectgarbage("collect")

  if not resp then
    package.loaded["lua/modules/json"] = nil
    collectgarbage("collect")
    return nil, "No response from server"
  end
  if resp.status ~= 200 then
    package.loaded["lua/modules/json"] = nil
    collectgarbage("collect")
    return nil, "HTTP " .. tostring(resp.status)
  end

  local ok, tags = pcall(json.decode, resp.body)
  resp = nil
  package.loaded["lua/modules/json"] = nil
  collectgarbage("collect")

  if not ok or type(tags) ~= "table" or #tags == 0 then
    return nil, "Could not parse tags response"
  end

  return tags[1].name
end

------------------------------------------------------------
-- BACKUP
------------------------------------------------------------
local function create_backup(current_version, sh)
  local backup_dir = "backup"
  ensure_dir(backup_dir)

  local ver_str = current_version or "unknown"
  ver_str = ver_str:gsub("[^%w%.%-]", "_")
  local archive = backup_dir .. "/backup-" .. ver_str .. ".tar"

  term.write("Backing up to /" .. archive .. "...\n")

  -- collect files/dirs to back up
  local sources = {}
  local to_backup = {
    "shell.lua", "main.lua", "lua/", "version.txt",
  }
  for _, name in ipairs(to_backup) do
    if fs.exists(name) then
      table.insert(sources, name)
    end
  end

  if #sources == 0 then
    sh:warn("Nothing to back up")
    return true
  end

  -- drive the tar command through the shell
  local tar_args = {"c", "/" .. archive}
  for _, s in ipairs(sources) do
    table.insert(tar_args, "/" .. s)
  end
  sh:execute("tar", tar_args)

  if fs.exists(archive) then
    sh:success("Backup created: /" .. archive)
    return true
  else
    return false, "Backup failed"
  end
end

------------------------------------------------------------
-- EXTRACT UPDATE (tar.gz with auto-overwrite)
------------------------------------------------------------
local function extract_update(archive_path, dest, sh)
  -- use tar extract via shell command
  -- the tar extract prompts for overwrites, so we use
  -- a simple approach: extract to a temp dir first isn't
  -- practical on limited storage. Instead, invoke tar x
  -- and the user can answer "All" to overwrite.
  term.write("Extracting update...\n")
  term.write(c.yellow .. "Tip: " .. c.white
    .. "type 'a' at the overwrite prompt to accept all\n\n")
  local tar_args = {"x", archive_path}
  if dest and dest ~= "" then
    table.insert(tar_args, dest)
  end
  sh:execute("tar", tar_args)
  return true
end

------------------------------------------------------------
-- MAIN UPDATE LOGIC
------------------------------------------------------------
local function do_update(args, sh)
  -- check wifi
  if not wifi.isConnected() then
    return sh:error("Wi-Fi not connected. Connect with: wifi on")
  end

  local cfg, source = load_config()
  if not cfg then return sh:error(source) end

  -- read current version
  local current = read_version()
  local current_display = current or "(none)"
  term.write(c.cyan .. "Current version: " .. c.white
    .. current_display .. "\n")
  term.write(c.cyan .. "       Firmware: " .. c.white
    .. (sys.version or "unknown") .. "\n")

  -- fetch latest tag
  local latest, err = fetch_latest_tag(cfg, sh)
  if not latest then
    return sh:error("Failed to check for updates: " .. (err or "unknown"))
  end

  term.write(c.cyan .. " Latest version: " .. c.white
    .. latest .. "\n\n")

  -- compare
  if current and not version_newer(latest, current) then
    sh:success("Already up to date!")
    return
  end

  -- check-only mode
  if args[1] == "check" then
    term.write(c.green .. "Update available: " .. c.white
      .. latest .. "\n")
    term.write("Run 'update' to install.\n")
    return
  end

  -- confirm with user
  term.write(c.green .. "Update available!" .. c.white .. "\n\n")

  -- determine what's available
  local sd_name = asset_name(cfg.sd_asset, latest)
  local sd_url = asset_url(cfg, latest, sd_name)
  local fw_name = asset_name(cfg.uf2_asset, latest)
  local fw_url = asset_url(cfg, latest, fw_name)
  local fw_dir = uf2_dir()

  term.write("Available:\n")
  term.write("  1. SD card files (" .. sd_name .. ")\n")
  if sys.board then
    term.write("  2. Firmware for " .. sys.board
      .. " (" .. fw_name .. ")\n")
  end
  term.write("\n")

  -- ask what to update
  local do_sd = false
  local do_fw = false

  local ans = term.read("Update SD card files? [Y/n]: ")
  ans = ans and ans:lower() or "y"
  if ans == "" or ans == "y" then do_sd = true end

  if sys.board then
    ans = term.read("Download firmware update? [y/N]: ")
    ans = ans and ans:lower() or "n"
    if ans == "y" then do_fw = true end
  end

  if not do_sd and not do_fw then
    term.write("Nothing to do.\n")
    return
  end

  -- backup current installation
  term.write("\n")
  local ok, backup_err = create_backup(current, sh)
  if not ok then
    sh:warn("Backup failed: " .. (backup_err or "unknown"))
    ans = term.read("Continue without backup? [y/N]: ")
    ans = ans and ans:lower() or "n"
    if ans ~= "y" then
      term.write("Cancelled.\n")
      return
    end
  end
  term.write("\n")

  -- download and install SD files
  if do_sd then
    local tmp_archive = "tmp_update.tar.gz"  -- fs path (no leading /)
    term.write("Downloading " .. sd_name .. "...\n")

    local bytes, dl_err = download_file(sd_url, tmp_archive, sh)
    if not bytes then
      -- clean up
      if fs.exists(tmp_archive) then fs.delete(tmp_archive) end
      return sh:error("Download failed: " .. (dl_err or "unknown"))
    end
    sh:success("Downloaded " .. sh:format_size(bytes))
    term.write("\n")

    -- extract to root of SD card
    -- pass absolute paths so tar resolves them correctly
    extract_update("/" .. tmp_archive, "/", sh)

    -- clean up temp file
    if fs.exists(tmp_archive) then fs.delete(tmp_archive) end
    term.write("\n")
  end

  -- download firmware
  if do_fw then
    ensure_dir(fw_dir)
    local fw_dest = fw_dir .. "/" .. fw_name
    term.write("Downloading " .. fw_name .. "...\n")

    local bytes, dl_err = download_file(fw_url, fw_dest, sh)
    if not bytes then
      if fs.exists(fw_dest) then fs.delete(fw_dest) end
      sh:error("Firmware download failed: " .. (dl_err or "unknown"))
    else
      sh:success("Firmware saved to /" .. fw_dest
        .. " (" .. sh:format_size(bytes) .. ")")
    end
    term.write("\n")
  end

  -- update version file
  if do_sd then
    write_version(latest)
  end

  -- summary
  term.write(c.green .. "Update complete!" .. c.white .. "\n")
  if do_sd then
    term.write("SD files updated to " .. latest .. "\n")
    term.write("Run " .. c.cyan .. "reload" .. c.white
      .. " to reload shell commands.\n")
  end
  if do_fw then
    term.write("\nTo install firmware:\n")
    term.write("  1. Reboot while holding " .. c.yellow
      .. "Up Arrow" .. c.white .. " to enter uf2-loader\n")
    term.write("  2. Select " .. c.cyan .. fw_name
      .. c.white .. " from /" .. fw_dir .. "/\n")
  end
end

------------------------------------------------------------
-- SHOW CONFIG
------------------------------------------------------------
local function show_config(sh)
  local cfg, source = load_config()
  if not cfg then return sh:error(source) end
  term.write(c.green .. "Update config" .. c.white .. " from " .. source .. ":\n")
  term.write("  Platform: " .. cfg.platform .. "\n")
  term.write("      Host: " .. cfg.host .. "\n")
  term.write("     Owner: " .. cfg.owner .. "\n")
  term.write("      Repo: " .. cfg.repo .. "\n")
  term.write("  Download: " .. cfg.download_base .. "\n")
  term.write("  SD asset: " .. cfg.sd_asset .. "\n")
  term.write(" UF2 asset: " .. cfg.uf2_asset .. "\n")
  if source == "built-in defaults" then
    term.write("\nCreate /lua/shell/update_config.lua to override any of these;\n"
      .. "see update_config.lua.example in the same directory.\n")
  end
end

------------------------------------------------------------
-- COMMAND ENTRY POINT
------------------------------------------------------------
return {
  name = "update",
  category = "core",
  help = c.cyan .. "update" .. c.yellow .. " [check|config]"
    .. c.white .. " - check for and install updates",
  run = function(args, sh)
    if args[1] == "config" then
      show_config(sh)
    elseif args[1] == "check" then
      do_update(args, sh)
    else
      do_update(args, sh)
    end
  end,
}
