--[[

  A curl-like utility for making HTTP/HTTPS requests

  Usage:
    curl(url)                           -- Simple GET request
    curl(url, options)                  -- GET with options table
    curl("-X", "POST", "-d", data, url) -- Command-line style

  Options table:
    method      - HTTP method (GET, POST, PUT, DELETE, HEAD, PATCH)
    headers     - Table of headers {["Content-Type"] = "application/json"}
    data        - Request body data
    output      - File path to save response body
    timeout     - Request timeout in seconds
    follow      - Follow redirects (default: true)
    verbose     - Show detailed request/response info
    head_only   - Only show response headers (HEAD request)
    include     - Include response headers in output
    silent      - Suppress progress/status messages
    user        - Basic auth "username:password"

  Examples:
    curl("https://example.com")
    curl("-i", "https://httpbin.org/get")
    curl("-X", "POST", "-H", "Content-Type: application/json",
         "-d", '{"key":"value"}', url)

]]

-- load the http module
local http = require("lua/shell/modules/http")
local curl = {}

-- configuration
curl.DEFAULT_TIMEOUT = 30
curl.VERSION = "0.666"

-- show help
local function show_help()
  print("curl.lua - HTTP client for picocalc_lua")
  print("")
  print("usage:")
  print("  curl(url)               - simple GET request")
  print("  curl(url, {options})    - request with options table")
  print("  curl('-X', 'POST', ...) - command-line style")
  print("")
  print("command-line options:")
  print(" -X METHOD  HTTP method (GET, POST, PUT, DELETE, HEAD, PATCH)")
  print(" -H header  Add header (e.g., 'Content-Type: application/json')")
  print(" -d data    Request body data")
  print(" -o file    Write output to file")
  print(" -i         Include response headers in output")
  print(" -I         Show only response headers (HEAD request)")
  print(" -L         Follow redirects (default: on)")
  print(" -v         Verbose mode")
  print(" -s         Silent mode (no progress)")
  print(" -u user:pass HTTP basic authentication")
  print(" -m seconds Timeout in seconds")
  print(" -h         Show this help")
  print("")
  print("options table keys:")
  print(" method, headers, data, output, timeout,")
  print(" follow, verbose, head_only, include, silent, user")
  print("")
  print("examples:")
  print(" curl('https://example.com')")
  print(" curl('-i', 'https://httpbin.org/get')")
  print(" curl('-X', 'POST', '-d', 'name=test', 'https://httpbin.org/post')")
  print(" curl('https://api.example.com', {")
  print("   method = 'POST',")
  print("   headers = {['Content-Type'] = 'application/json'},")
  print("   data = '{\"key\": \"value\"}'")
  print(" })")
end

-- base64 encode for basic auth
local function base64_encode(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, byte = '', x:byte()
    for i = 8, 1, -1 do
      r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and '1' or '0')
    end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
      local c = 0
      for i = 1, 6 do
        c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
      end
      return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- parse command-line style arguments
local function parse_args(args)
  local options = {
    method = "GET",
    headers = {},
    data = nil,
    output = nil,
    timeout = curl.DEFAULT_TIMEOUT,
    follow = true,
    verbose = false,
    head_only = false,
    include = false,
    silent = false,
    user = nil,
  }
  local url = nil

  local i = 1
  while i <= #args do
    local arg = args[i]

    if arg == "-X" or arg == "--request" then
      i = i + 1
      options.method = args[i] and args[i]:upper() or "GET"

    elseif arg == "-H" or arg == "--header" then
      i = i + 1
      if args[i] then
        local name, value = args[i]:match("^([^:]+):%s*(.*)$")
        if name then
          options.headers[name] = value
        end
      end

    elseif arg == "-d" or arg == "--data" then
      i = i + 1
      options.data = args[i]
      -- default to POST if method not explicitly set
      if options.method == "GET" then
        options.method = "POST"
      end

    elseif arg == "--data-raw" then
      i = i + 1
      options.data = args[i]
      if options.method == "GET" then
        options.method = "POST"
      end

    elseif arg == "-o" or arg == "--output" then
      i = i + 1
      options.output = args[i]

    elseif arg == "-i" or arg == "--include" then
      options.include = true

    elseif arg == "-I" or arg == "--head" then
      options.head_only = true
      options.method = "HEAD"

    elseif arg == "-L" or arg == "--location" then
      options.follow = true

    elseif arg == "-v" or arg == "--verbose" then
      options.verbose = true

    elseif arg == "-s" or arg == "--silent" then
      options.silent = true

    elseif arg == "-u" or arg == "--user" then
      i = i + 1
      options.user = args[i]

    elseif arg == "-m" or arg == "--max-time" then
      i = i + 1
      options.timeout = tonumber(args[i]) or curl.DEFAULT_TIMEOUT

    elseif arg == "-h" or arg == "--help" then
      options.help = true

    elseif not arg:match("^%-") then
      -- not an option, must be URL
      url = arg
    end

    i = i + 1
  end

  return url, options
end

-- format headers for display
local function format_headers(headers, prefix)
  prefix = prefix or ""
  local lines = {}
  for name, value in pairs(headers) do
    table.insert(lines, prefix .. name .. ": " .. value)
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

-- perform the HTTP request
local function do_request(url, options)
  -- build http.request options
  local http_opts = {
    method = options.method,
    headers = options.headers or {},
    body = options.data,
    timeout = options.timeout,
    follow_redirects = options.follow,
  }

  -- add basic auth header
  if options.user then
    local encoded = base64_encode(options.user)
    http_opts.headers["Authorization"] = "Basic " .. encoded
  end

  -- add Content-Type for POST if not set and we have data
  if options.data and not http_opts.headers["Content-Type"] then
    -- try to detect JSON
    if options.data:match("^%s*[{%[]") then
      http_opts.headers["Content-Type"] = "application/json"
    else
      http_opts.headers["Content-Type"] = "application/x-www-form-urlencoded"
    end
  end

  -- verbose: show request details
  if options.verbose then
    print("> " .. options.method .. " " .. url)
    for name, value in pairs(http_opts.headers) do
      print("> " .. name .. ": " .. value)
    end
    if options.data then
      print(">")
      print("> " .. options.data)
    end
      print("")
  end

  -- progress message
  if not options.silent then
    term.write("Requesting " .. url .. "...")
  end

  -- make the request
  local response, err = http.request(url, http_opts)

  if not response then
    if not options.silent then
      print("FAILED")
    end
    return nil, err
  end

  if not options.silent then
    print(response.status .. " " .. (response.reason or ""))
  end

  return response
end

-- output the response
local function output_response(response, options)
  local output_text = ""

  -- verbose: show response details
  if options.verbose then
    print("")
    print("< HTTP " .. response.status .. " " .. (response.reason or ""))
    for name, value in pairs(response.headers or {}) do
      print("< " .. name .. ": " .. value)
    end
    print("")
  end

  -- include headers in output
  if options.include and not options.verbose then
    print("HTTP " .. response.status .. " " .. (response.reason or ""))
    for name, value in pairs(response.headers or {}) do
      print(name .. ": " .. value)
    end
    print("")
  end

  -- just show headers?
  if options.head_only then
    if not options.include and not options.verbose then
      print("HTTP " .. response.status .. " " .. (response.reason or ""))
      for name, value in pairs(response.headers or {}) do
        print(name .. ": " .. value)
      end
    end
    return true
  end

  -- output body
  local body = response.body or ""

  if options.output then
    -- write to file
    local file, ferr = io.open(options.output, "wb")
    if not file then
      print("Error: Cannot write to " .. options.output .. ": " .. (ferr or "unknown"))
      return false
    end
    file:write(body)
    file:close()
    if not options.silent then
      print("Saved " .. #body .. " bytes to " .. options.output)
    end
  else
    -- print to console
    print(body)
  end

  return true
end

-- main curl function
function curl.request(url, options)
  options = options or {}
  -- set defaults
  options.method = options.method or "GET"
  options.headers = options.headers or {}
  options.timeout = options.timeout or curl.DEFAULT_TIMEOUT
  if options.follow == nil then options.follow = true end

  -- check wifi
  if not wifi.isConnected() then
    return nil, "Wi-Fi not connected"
  end

  -- make request
  local response, err = do_request(url, options)
  if not response then
    return nil, err
  end

  -- output response
  output_response(response, options)

  return response
end

-- main entry point (supports both table and command-line style)
local function main(...)
  local args = {...}

  if #args == 0 then
    show_help()
    return nil
  end

  -- check if first arg is help
  if args[1] == "-h" or args[1] == "--help" or args[1] == "help" then
    show_help()
    return nil
  end

  -- wifi check
  if not wifi.isConnected() then
    print("Error: Wi-Fi not connected")
    print("Run: dofile('lua/wifi-start.lua')")
    return nil
  end

  local url, options

  -- check if second arg is a table (options style)
  if #args == 2 and type(args[2]) == "table" then
    url = args[1]
    options = args[2]
    -- set defaults for table style
    options.method = options.method or "GET"
    options.headers = options.headers or {}
    options.timeout = options.timeout or curl.DEFAULT_TIMEOUT
    if options.follow == nil then options.follow = true end
  elseif #args == 1 and not args[1]:match("^%-") then
    -- simple URL only
    url = args[1]
    options = {
      method = "GET",
      headers = {},
      timeout = curl.DEFAULT_TIMEOUT,
      follow = true,
    }
  else
    -- command-line style
    url, options = parse_args(args)
  end

  if options.help then
    show_help()
    return nil
  end

  if not url then
    print("Error: URL required")
    show_help()
    return nil
  end

  -- make request
  local response, err = do_request(url, options)
  if not response then
    print("Error: " .. (err or "request failed"))
    return nil
  end

  -- output response
  output_response(response, options)
  return response
end

-- allow calling as function
setmetatable(curl, {
  __call = function(_, ...)
    return main(...)
  end
})

return curl
