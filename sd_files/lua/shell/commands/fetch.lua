--[[

  fetch.lua - simple HTTP/S fetch command for downloading
              a page/file from a given URL

]]

return {
  name = "fetch",
  category = "net",
  aliases = {"wget"},
  usage = "[-d] <url> [file]",
  desc = "download URL [to file]",
  flags = "d",
  args = "string path?",
  needs = {"wifi"},
  run = function(args, sh)
    local http = require("lua/modules/http")

    local url = args[1]
    local output_file = args[2]

    if args.flags.d then
      http.DEBUG = true
      http.DEBUG_FILE = "lua/http.dbg.txt"
    end

    print("Fetching " .. url .. "...")

    -- build request options with streaming support
    local options = {}
    if output_file then
      -- stream directly to output file (handles large responses)
      options.output_file = args.v[2]
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
        local f <close> = fs.open(args.v[2], "w")
        f:write(body)
        sh:success(string.format("Saved %d bytes to %s", #body, output_file))
      else
        print("")
        print(body)
      end
    end
  end
}
