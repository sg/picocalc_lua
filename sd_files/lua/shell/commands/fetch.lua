--[[

  fetch.lua - simple HTTP/S fetch command for downloading
              a page/file from a given URL

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "fetch",
  aliases = {"wget"},
  help = c.cyan.."fetch"..c.yellow.." [-d] <url> [file]"..c.white.." - download URL [to file]",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: fetch [-d] <url> [output_file]")
    end

    if not wifi.isConnected() then
      return sh:error("Wi-Fi not connected")
    end

    -- load http module
    local http = require("lua/modules/http")

    local url = args[1]
    local output_file = args[2]
    local debug_mode = false

    if url == "-d" then
      debug_mode = true
      http.DEBUG = true
      http.DEBUG_FILE = "lua/http.dbg.txt"
      url = args[2]
      output_file = args[3]
    end

    print("Fetching " .. url .. "...")

    -- build request options with streaming support
    local options = {}
    if output_file then
      -- stream directly to output file (handles large responses)
      local path = sh:resolve_path(output_file)
      local fspath = sh:fs_path(path)
      options.output_file = fspath
    else
      -- stream to console for large responses
      options.stream_to_console = true
    end

    local response, err = http.get(url, options)

    if not response then
      return sh:error(err or "request failed")
    end

    print(string.format("Status: %d %s", response.status, response.reason or ""))

    if response.status >= 400 then
      return sh:error("Request failed with status " .. response.status)
    end

    -- check if response was streamed
    if response.streamed then
      if output_file then
        sh:success(string.format("Streamed %d bytes to %s", response.streamed_bytes, output_file))
      else
        -- body was already printed to console during streaming
        print(string.format("\n[Streamed %d bytes]", response.streamed_bytes))
      end
    else
      -- normal (buffered) response
      local body = response.body or ""
      if output_file then
        -- save buffered body to file
        local path = sh:resolve_path(output_file)
        local fspath = sh:fs_path(path)
        local f = fs.open(fspath, "w")
        if not f then
          return sh:error("Cannot write to " .. output_file)
        end
        f:write(body)
        f:close()
        sh:success(string.format("Saved %d bytes to %s", #body, output_file))
      else
        -- print buffered body to console
        print("")
        print(body)
      end
    end

    -- unload http module to free up memory
    package.loaded["lua/modules/http"] = nil
    collectgarbage()
  end
}
