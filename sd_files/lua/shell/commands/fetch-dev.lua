--[[

  fetch-dev.lua - pull a development build from the build
                  machine's web server

  Usage:
    fetch-dev <version> [base_url]

  Downloads picolua-<board>-<version>.uf2 into the uf2-loader
  directory and sd_files-<version>.tar.gz into the SD root,
  using the names build.sh and make-sd-archive.sh produce.

]]

local c = require("lua/modules/simple-colors")

local DEV_URL = "http://192.168.27.164:8080"

-- build.sh names firmware by these short names, not the SDK board names
local BOARD_NAMES = {
  pico = "pico",
  pico_w = "picow",
  pico2 = "pico2",
  pico2_w = "pico2w",
  pimoroni_pico_plus2_w_rp2350 = "pim2w",
}

-- the uf2-loader keeps RP2350 firmware apart from RP2040 firmware
local function uf2_dir()
  local board = sys.board or ""
  if board:match("pico2") or board:match("rp2350") or board:match("pimoroni") then
    return "pico2-apps"
  end
  return "pico1-apps"
end

-- git describe appends + to a dirty build, which a URL path cannot carry as is
local function url_for(base, name)
  return base .. "/" .. (name:gsub("%+", "%%2B"))
end

return {
  name = "fetch-dev",
  category = "net",
  aliases = {"fdev"},
  usage = "<version> [base_url]",
  desc = "download a dev firmware and SD archive by version",
  args = "string string?",
  needs = {"wifi"},
  run = function(args, sh)
    local version = args[1]
    local base = (args[2] or DEV_URL):gsub("/+$", "")
    local board = BOARD_NAMES[sys.board or ""] or sys.board or "unknown"

    local uf2 = ("picolua-%s-%s.uf2"):format(board, version)
    local archive = ("sd_files-%s.tar.gz"):format(version)
    local dir = uf2_dir()
    if not fs.exists(dir) then fs.makeDir(dir) end

    local jobs = {
      { url_for(base, uf2), "/" .. dir .. "/" .. uf2 },
      { url_for(base, archive), "/" .. archive },
    }
    for _, job in ipairs(jobs) do
      if not sh:execute("fetch", { job[1], job[2] }) then
        return sh:error("Stopped at " .. job[1])
      end
      term.write("\n")
    end

    term.write("To install:\n")
    term.write("  " .. c.cyan .. "tar x /" .. archive .. c.white
      .. "  (answer 'a' at the overwrite prompt)\n")
    term.write("  reboot holding " .. c.yellow .. "Up Arrow" .. c.white
      .. " and pick " .. c.cyan .. uf2 .. c.white .. " from /" .. dir .. "/\n")
  end
}
