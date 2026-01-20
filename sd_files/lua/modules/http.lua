--[[

  HTTP/S client library for picocalc_lua
  
  It doesnt require a valid cert for https
  urls, but at least the connection won't be
  in the clear ;)
  
  Large page returns will cause an out of memory
  panic. Need to figure out a non-crash solution
  for that :(

]]

local http = {}

-- track size of data rec'd during requests
local total_size = 0

-- debug output (set http.DEBUG = true to enable)
local function dbg(msg)
  if http.DEBUG then
    print("http: " .. msg)
  end
end

http._VERSION = "1.1"
http.DEBUG = false  -- set to true to enable debug output
   
-- default settings
http.TIMEOUT = 30 -- seconds
http.MAX_REDIRECTS = 5
http.USER_AGENT = "picocalc_lua-http"

-- parse a URL into components
-- returns: scheme, host, port, path
local function parse_url(url)
  local scheme, rest = url:match("^(%a+)://(.+)$")
  if not scheme then
    return nil, "invalid URL: missing scheme"
  end

  scheme = scheme:lower()
  if scheme ~= "http" and scheme ~= "https" then
    return nil, "unsupported scheme: " .. scheme
  end

  -- extract host and path
  local host_port, path = rest:match("^([^/]+)(.*)$")
  if not host_port then
    host_port = rest
    path = "/"
  end
  if path == "" then
    path = "/"
  end

  -- extract port from host
  local host, port = host_port:match("^(.+):(%d+)$")
  if not host then
    host = host_port
    port = (scheme == "https") and 443 or 80
  else
    port = tonumber(port)
  end

  return scheme, host, port, path
end

-- build HTTP request headers
local function build_request(method, host, port, path, headers, body)
  local lines = {}
  
  -- request line
  table.insert(lines, string.format("%s %s HTTP/1.1", method, path))

  -- Host header (required for HTTP/1.1)
  local host_header = host
  if (port ~= 80 and port ~= 443) then
    host_header = host .. ":" .. port
  end
  table.insert(lines, "Host: " .. host_header)

  -- User-Agent
  if not headers or not headers["User-Agent"] then
    table.insert(lines, "User-Agent: " .. http.USER_AGENT)
  end

  -- Connection header
  if not headers or not headers["Connection"] then
    table.insert(lines, "Connection: close")
  end

  -- Content-Length for body
  if body and #body > 0 then
    table.insert(lines, "Content-Length: " .. #body)
  end

  -- Custom headers
  if headers then
    for name, value in pairs(headers) do
      table.insert(lines, name .. ": " .. value)
    end
  end

  -- end of headers
  table.insert(lines, "")
  table.insert(lines, "")

  local request = table.concat(lines, "\r\n")

  -- append body if present
  if body then
    request = request .. body
  end

  return request
end

-- parse HTTP response status line
local function parse_status_line(line)
  local version, code, reason = line:match("^HTTP/(%d%.%d)%s+(%d+)%s*(.*)")
  if not version then
    return nil, "invalid status line"
  end
  return tonumber(code), reason, version
end

-- parse HTTP headers from response
local function parse_headers(data, start_pos)
  local headers = {}
  local pos = start_pos or 1
  local body_start = nil

  while true do
    local line_end = data:find("\r\n", pos)
    if not line_end then
      break
    end

    local line = data:sub(pos, line_end - 1)
    pos = line_end + 2

    if line == "" then
      -- End of headers
      body_start = pos
      break
    end

    local name, value = line:match("^([^:]+):%s*(.*)$")
    if name then
      -- lcase the header name
      name = name:lower()
      --if not value then value = "no value passed" end
      --print(string.format("debug: got header: %s: %s", name, value))
      headers[name] = value
    end
  end

  return headers, body_start
end

-- read HTTP response
local function read_response(sock, timeout)
  local chunks = {}
  total_size = 0
  local max_size = 64 * 1024  -- 64KB max response
  local retry_count = 0
  local max_retries = 3  -- retries on timeout when expecting more data

  sock:settimeout(timeout)
  dbg("read_response starting, timeout=" .. timeout)

  -- tracking for header parsing (only done once)
  local headers_parsed = false
  local header_byte_count = 0  -- bytes before body starts
  local content_length = nil

  while total_size < max_size do
    dbg(string.format("receive loop: total=%d, chunks=%d, memfree=%d",
        total_size, #chunks, sys.freeMemory()))

    local chunk, err = sock:receive(4096)
    if not chunk then
      dbg("receive returned nil: " .. (err or "nil"))

      -- check if we have all expected data
      if content_length then
        local body_received = total_size - header_byte_count
        local body_remaining = content_length - body_received
        dbg(string.format("body status: received=%d, expected=%d, remaining=%d",
            body_received, content_length, body_remaining))

        if body_remaining <= 0 then
          dbg("have all expected data, done")
          break  -- got everything
        end

        -- still need more data - retry on timeout, give up on close
        if err == "timeout" and retry_count < max_retries then
          retry_count = retry_count + 1
          dbg(string.format("retry %d/%d: need %d more bytes", retry_count, max_retries, body_remaining))
          -- continue loop to try again
        elseif err == "connection closed" then
          dbg(string.format("connection closed early, missing %d bytes", body_remaining))
          break  -- server closed, can't retry
        else
          dbg(string.format("giving up after error '%s', missing %d bytes", err or "nil", body_remaining))
          break
        end
      elseif total_size > 0 then
        dbg("no content-length, have some data, stopping")
        break  -- no content-length, have some data, stop on error
      else
        return nil, err or "receive failed"
      end
    else
      retry_count = 0  -- reset retry count on successful receive
      total_size = total_size + #chunk
      dbg(string.format("got chunk: %d bytes, total now %d", #chunk, total_size))
      table.insert(chunks, chunk)

      if not headers_parsed then
        -- search for end of headers in last 2 chunks only (to catch boundary)
        local search_data
        if #chunks == 1 then
          search_data = chunks[1]
        else
          search_data = chunks[#chunks - 1] .. chunks[#chunks]
        end

        if search_data:find("\r\n\r\n") then
          dbg("found header end marker")
          -- found header end marker - do ONE concat to parse headers
          local data = table.concat(chunks)
          local headers, body_start = parse_headers(data, 1)
          headers_parsed = true
          header_byte_count = body_start - 1  -- bytes consumed by headers
          dbg(string.format("headers parsed, header_bytes=%d", header_byte_count))

          if headers["content-length"] then
            content_length = tonumber(headers["content-length"])
            dbg(string.format("Content-Length: %d", content_length))
            local body_received = total_size - header_byte_count
            if body_received >= content_length then
              dbg("got full response (at header parse)")
              break  -- got full response
            end
          else
            dbg("no Content-Length header")
          end
          -- allow data to be garbage collected
          data = nil
          collectgarbage("step")
        end
      else
        -- headers already parsed, just track body size
        if content_length then
          local body_received = total_size - header_byte_count
          if body_received >= content_length then
            dbg("got full response")
            break  -- got full response
          end
        end
        -- no content-length means read until close or max_size
      end
    end
  end

  dbg(string.format("read_response done: total=%d, chunks=%d", total_size, #chunks))

  if #chunks == 0 then
    return nil, "no response received"
  end

  -- warn if we didn't get expected content
  if content_length then
    local body_received = total_size - header_byte_count
    if body_received < content_length then
      dbg(string.format("WARNING: incomplete body, got %d of %d bytes", body_received, content_length))
    end
  end

  -- single final concatenation
  dbg(string.format("concatenating %d chunks, memfree=%d", #chunks, sys.freeMemory()))
  local result = table.concat(chunks)
  -- clear chunks table to free memory before returning
  for i = 1, #chunks do chunks[i] = nil end
  chunks = nil
  collectgarbage("collect")
  dbg(string.format("concat done, result=%d bytes, memfree=%d", #result, sys.freeMemory()))
  return result
end

-- perform an HTTP request
function http.request(url, options)
  options = options or {}
  local method = options.method or "GET"
  local headers = options.headers
  local body = options.body
  local timeout = options.timeout or http.TIMEOUT
  local follow_redirects = options.follow_redirects
  if follow_redirects == nil then follow_redirects = true end

  dbg(string.format("request: %s %s", method, url))
  dbg(string.format("memfree at start: %d", sys.freeMemory()))

  -- parse URL
  local scheme, host, port, path = parse_url(url)
  if not scheme then
    return nil, host  -- 'host' var contains error message
  end
  dbg(string.format("parsed: scheme=%s host=%s port=%d path=%s", scheme, host, port, path))

  -- create socket type based on scheme
  local sock, err
  dbg("creating socket...")
  if scheme == "https" then
    sock, err = socket.tls()
  else
    sock, err = socket.tcp()
  end

  if not sock then
    return nil, "failed to create socket: " .. (err or "unknown error")
  end
  dbg(string.format("socket created, memfree: %d", sys.freeMemory()))

  -- connect
  dbg(string.format("connecting to %s:%d...", host, port))
  local ok, conn_err = sock:connect(host, port, timeout * 1000)
  if not ok then
    sock:close()
    return nil, "connection failed: " .. (conn_err or "unknown error")
  end
  dbg(string.format("connected, memfree: %d", sys.freeMemory()))

  -- build and send request
  local request = build_request(method, host, port, path, headers, body)
  dbg(string.format("sending request (%d bytes)...", #request))
  local sent, send_err = sock:send(request)
  if not sent or sent < #request then
    sock:close()
    return nil, "send failed: " .. (send_err or "incomplete")
  end
  dbg(string.format("sent %d bytes, memfree: %d", sent, sys.freeMemory()))

  -- read response
  dbg("reading response...")
  local response_data, read_err = read_response(sock, timeout)
  sock:close()

  if not response_data then
    return nil, "read failed: " .. (read_err or "unknown error")
  end
  dbg(string.format("got %d bytes, memfree: %d", #response_data, sys.freeMemory()))

  -- parse response
  local first_line_end = response_data:find("\r\n")
  if not first_line_end then
    return nil, "invalid response: no status line"
  end

  local status_line = response_data:sub(1, first_line_end - 1)
  local status_code, status_reason = parse_status_line(status_line)
  if not status_code then
    return nil, "invalid response: " .. (status_reason or "bad status line")
  end

  local response_headers, body_start = parse_headers(response_data, first_line_end + 2)
  dbg(string.format("headers parsed, body_start=%d, memfree: %d", body_start or 0, sys.freeMemory()))

  -- extract body - this creates a new string, so GC the old one after
  local response_body = ""
  if body_start and body_start <= #response_data then
    response_body = response_data:sub(body_start)
    -- release original data now that we have the body
    response_data = nil
    collectgarbage("collect")
    dbg(string.format("body extracted, %d bytes, memfree: %d", #response_body, sys.freeMemory()))
  end

  -- handle redirects
  if follow_redirects and (status_code == 301 or status_code == 302 or status_code == 303 or status_code == 307 or status_code == 308) then
    local location = response_headers["location"]
    if location then
      local redirect_count = options._redirect_count or 0
      if redirect_count >= http.MAX_REDIRECTS then
        return nil, "too many redirects"
      end
      -- handle relative URLs
      if not location:match("^%a+://") then
        if location:sub(1, 1) == "/" then
          location = scheme .. "://" .. host .. ":" .. port .. location
        else
          local base_path = path:match("^(.*/)")  or "/"
          location = scheme .. "://" .. host .. ":" .. port .. base_path .. location
        end
      end

      options._redirect_count = redirect_count + 1
      --for 303, change method to GET
      if status_code == 303 then
        options.method = "GET"
        options.body = nil
      end
      return http.request(location, options)
    end
  end

  --return response table
  return {
    status = status_code,
    reason = status_reason,
    headers = response_headers,
    body = response_body
  }
end

-- convenience function for GET requests
function http.get(url, options)
  options = options or {}
  options.method = "GET"
  return http.request(url, options)
end

-- convenience function for POST requests
function http.post(url, body, content_type, options)
  options = options or {}
  options.method = "POST"
  options.body = body
  options.headers = options.headers or {}
  options.headers["Content-Type"] = content_type or "application/x-www-form-urlencoded"
  return http.request(url, options)
end

-- URL encode a string
function http.urlencode(str)
  str = str:gsub("\n", "\r\n")
  str = str:gsub("([^%w%-%.%_%~ ])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = str:gsub(" ", "+")
  return str
end

-- URL encode a table of parameters
function http.encode_params(params)
  local parts = {}
  for key, value in pairs(params) do
    table.insert(parts, http.urlencode(tostring(key)) .. "=" .. http.urlencode(tostring(value)))
  end
  return table.concat(parts, "&")
end

return http
