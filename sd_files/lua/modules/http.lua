--[[

  HTTP/S client library for picocalc_lua

  It doesnt require a valid cert for https
  urls, but at least the connection won't be
  in the clear ;)

  Supports chunked transfer-encoding and
  optimizes memory usage devices.
  Max buffered response size is 32KB, but larger
  responses can be streamed to file or console.

  Debug options:
    http.DEBUG = true 
    (print debug to console)
    http.DEBUG_FILE = "out.txt" 
    (write debug to file)

  Streaming options (in options table):
    output_file = "out.txt"  -- stream body to file
    stream_to_console = true -- stream body to console

  When streaming, response.body is nil and
  response.streamed is true.

]]

local http = {}

http._VERSION = "1.1"
http.DEBUG = false      
http.DEBUG_FILE = nil  
   
-- default settings
http.TIMEOUT = 30 -- seconds
http.MAX_REDIRECTS = 5
-- setting the user agent to a common tool can help with
-- some website not rejecting the connection.
http.USER_AGENT = "curl/8.14.1" 

-- track size of data rec'd during requests
local total_size = 0

-- debug file handle (opened lazily)
local debug_file = nil

-- store parsed info when streaming (since we can't return full response)
local streamed_info = nil

-- debug output
local function dbg(msg)
  local line = "http: " .. msg
  if http.DEBUG then
    print(line)
  end
  if http.DEBUG_FILE then
    if not debug_file then
      debug_file = fs.open(http.DEBUG_FILE, "w")
    end
    if debug_file then
      debug_file:write(line .. "\n")
      debug_file:flush()
    end
  end
end

-- close debug file if open (call when done with requests)
local function close_debug_file()
  if debug_file then
    debug_file:close()
    debug_file = nil
  end
end

-- write raw headers to debug file
local function dbg_headers(raw_headers, redirect_num)
  if not http.DEBUG_FILE then return end
  -- ensure file is open
  if not debug_file then
    debug_file = fs.open(http.DEBUG_FILE, "w")
  end
  if debug_file then
    local label = "Raw HTTP Headers"
    if redirect_num and redirect_num > 0 then
      label = string.format("Raw HTTP Headers (redirect %d)", redirect_num)
    end
    debug_file:write("\n========== " .. label .. " ==========\n")
    debug_file:write(raw_headers)
    if not raw_headers:match("\n$") then
      debug_file:write("\n")
    end
    debug_file:write(string.rep("=", 22 + #label) .. "\n\n")
    -- flush to disk immediately so we don't lose log data on
    -- on an OOM panic
    debug_file:flush()
  end
end


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

-- decode chunked transfer-encoding body
-- returns decoded body string, or nil and error message
local function dechunk_body(data)
  local result = {}
  local pos = 1
  local data_len = #data

  while pos <= data_len do
    -- find end of chunk size line
    local line_end = data:find("\r\n", pos)
    if not line_end then
      break
    end

    -- parse chunk size (hex)
    local size_str = data:sub(pos, line_end - 1)
    -- chunk size may have extensions after semicolon, ignore them
    size_str = size_str:match("^([%x]+)")
    if not size_str then
      return nil, "invalid chunk size"
    end

    local chunk_size = tonumber(size_str, 16)
    if not chunk_size then
      return nil, "invalid chunk size hex"
    end

    pos = line_end + 2  -- skip past \r\n

    if chunk_size == 0 then
      -- final chunk, done
      break
    end

    -- extract chunk data
    if pos + chunk_size - 1 > data_len then
      -- incomplete chunk
      return nil, "incomplete chunk data"
    end

    table.insert(result, data:sub(pos, pos + chunk_size - 1))
    pos = pos + chunk_size

    -- skip trailing \r\n after chunk data
    if data:sub(pos, pos + 1) == "\r\n" then
      pos = pos + 2
    end
  end

  return table.concat(result)
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
-- stream_opts: { output_file = "path", stream_to_console = bool }
local function read_response(sock, timeout, redirect_count, stream_opts)
  local chunks = {}
  total_size = 0
  local max_size = 32 * 1024  -- 32KB max response buffered into memory
  local chunked_max_size = 128 * 1024  -- 128KB limit for chunked responses
  local retry_count = 0
  local max_retries = 3  -- retries on timeout when expecting more data
  stream_opts = stream_opts or {}

  sock:settimeout(timeout)
  dbg("read_response starting, timeout=" .. timeout)

  -- tracking for header parsing (only done once)
  local headers_parsed = false
  local header_byte_count = 0  -- bytes before body starts
  local content_length = nil
  local is_chunked = false
  local early_complete_data = nil  -- reuse concat'd data if response complete at header parse

  while total_size < max_size or (is_chunked and total_size < chunked_max_size) do
    dbg(string.format("receive loop: total=%d, chunks=%d, memfree=%d",
        total_size, #chunks, sys.freeMemory()))

    local chunk, err = sock:receive(1024)  -- small buffer to reduce memory pressure esp if heap is super fragmented
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

      -- for chunked responses past normal limit, run periodic GC and check for terminator
      if is_chunked and total_size >= max_size then
        -- futzed around with how often, and seems less likely to OOM panic if the #chunks % X value is set on the low side. Ymmv...
        if #chunks % 2 == 0 then
          collectgarbage("collect")
          dbg(string.format("GC during chunked: total=%d, memfree=%d", total_size, sys.freeMemory()))
        end

        -- check for terminator in last few chunks to break early
        local search_data
        if #chunks <= 3 then
          search_data = table.concat(chunks)
        else
          search_data = chunks[#chunks-2] .. chunks[#chunks-1] .. chunks[#chunks]
        end
        if search_data:find("0\r\n\r\n") then
          dbg("found chunked terminator (extended read)")
          break
        end
      end

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
          -- found header end marker - do one concat to parse headers
          local data = table.concat(chunks)
          local headers, body_start = parse_headers(data, 1)
          headers_parsed = true
          header_byte_count = body_start - 1  -- bytes consumed by headers
          dbg(string.format("headers parsed, header_bytes=%d", header_byte_count))

          -- write raw headers to debug file immediately (before content-length check)
          local raw_header_end = data:find("\r\n\r\n")
          if raw_header_end then
            dbg_headers(data:sub(1, raw_header_end + 3), redirect_count or 0)
          end

          if headers["content-length"] then
            content_length = tonumber(headers["content-length"])
            dbg(string.format("Content-Length: %d", content_length))
            -- check if response is too large to buffer
            if content_length > max_size then
              -- can we stream it?
              if stream_opts.output_file or stream_opts.stream_to_console then
                dbg(string.format("Content-Length %d exceeds max_size %d to buffer in RAM, streaming...", content_length, max_size))
                -- parse status line before we free the data
                local first_line_end = data:find("\r\n")
                local status_line = data:sub(1, first_line_end - 1)
                local status_code, status_reason = parse_status_line(status_line)
                -- save parsed info for later
                streamed_info = {
                  status = status_code or 200,
                  reason = status_reason or "OK",
                  headers = headers
                }
                -- open output file if specified
                local out_file = nil
                if stream_opts.output_file then
                  out_file = fs.open(stream_opts.output_file, "w")
                  if not out_file then
                    for i = 1, #chunks do chunks[i] = nil end
                    streamed_info = nil
                    return nil, "cannot open output file: " .. stream_opts.output_file
                  end
                end
                -- write any body data we already have
                local body_so_far = data:sub(body_start)
                local bytes_written = #body_so_far
                if out_file then
                  out_file:write(body_so_far)
                end
                if stream_opts.stream_to_console then
                  term.write(body_so_far)
                end
                -- free the chunks we've accumulated
                for i = 1, #chunks do chunks[i] = nil end
                chunks = nil
                data = nil
                collectgarbage()
                dbg(string.format("streamed initial %d bytes, memfree=%d", bytes_written, sys.freeMemory()))
                -- continue reading and streaming
                while bytes_written < content_length do
                  local chunk, err = sock:receive(1024)
                  if not chunk then
                    if err == "timeout" and retry_count < max_retries then
                      retry_count = retry_count + 1
                      dbg(string.format("stream retry %d/%d", retry_count, max_retries))
                    else
                      dbg("stream ended: " .. (err or "unknown"))
                      break
                    end
                  else
                    retry_count = 0
                    bytes_written = bytes_written + #chunk
                    if out_file then
                      out_file:write(chunk)
                    end
                    if stream_opts.stream_to_console then
                      term.write(chunk)
                    end
                    -- free chunk immediately
                    chunk = nil
                    if bytes_written % 8192 == 0 then  -- GC
                      collectgarbage()
                      dbg(string.format("streaming: %d/%d bytes, memfree=%d", bytes_written, content_length, sys.freeMemory()))
                    end
                  end
                end
                if out_file then
                  out_file:close()
                end
                if stream_opts.stream_to_console then
                  term.write("\n")
                end
                dbg(string.format("stream complete: %d bytes", bytes_written))
                -- return marker for streamed body
                return string.format("__STREAMED__:%d", bytes_written)
              else
                dbg(string.format("Content-Length %d exceeds max_size %d, aborting", content_length, max_size))
                -- clear chunks to free memory before returning error
                for i = 1, #chunks do chunks[i] = nil end
                return nil, string.format("response too large: %d bytes (max %d)", content_length, max_size)
              end
            end
            local body_received = total_size - header_byte_count
            if body_received >= content_length then
              dbg("got full response (at header parse)")
              early_complete_data = data  -- reuse this, skip final concat
              break  -- got full response
            end
          elseif headers["transfer-encoding"] and headers["transfer-encoding"]:lower():find("chunked") then
            is_chunked = true
            dbg("Transfer-Encoding: chunked detected")
            -- check if we already have the final chunk terminator
            local body_data = data:sub(body_start)
            if body_data:find("0\r\n\r\n") or body_data:find("0\r\n%s*\r\n") then
              dbg("got complete chunked response (at header parse)")
              early_complete_data = data  -- reuse this, skip final concat
              break
            end
          else
            dbg("no Content-Length header, not chunked")
          end
          -- allow data to be garbage collected if we're continuing
          data = nil
          collectgarbage()
        end
      else
        -- headers already parsed, just track body size
        if content_length then
          local body_received = total_size - header_byte_count
          if body_received >= content_length then
            dbg("got full response")
            break  -- got full response
          end
        elseif is_chunked then
          -- for chunked, check last chunks for final terminator
          local search_data
          if #chunks <= 2 then
            search_data = table.concat(chunks)
          else
            -- only search last 2 chunks to find terminator
            search_data = chunks[#chunks - 1] .. chunks[#chunks]
          end
          if search_data:find("0\r\n\r\n") or search_data:find("0\r\n%s*\r\n") then
            dbg("got complete chunked response")
            break
          end
        end
        -- no content-length and not chunked means read
        -- until close or max_size
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
      dbg(string.format("Warning: incomplete body, got %d of %d bytes", body_received, content_length))
    end
  end

  -- use early concat result if available, otherwise concat now
  local result
  if early_complete_data then
    dbg(string.format("reusing early concat data, memfree=%d", sys.freeMemory()))
    result = early_complete_data
    early_complete_data = nil
  else
    dbg(string.format("concatenating %d chunks, memfree=%d", #chunks, sys.freeMemory()))
    result = table.concat(chunks)
  end
  -- clear chunks table to free memory before returning
  for i = 1, #chunks do chunks[i] = nil end
  chunks = nil
  collectgarbage()
  dbg(string.format("result ready, %d bytes, memfree=%d", #result, sys.freeMemory()))
  return result
end

-- perform HTTP request
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
    close_debug_file()
    return nil, host  -- 'host' var contains error message
  end
  dbg(string.format("parsed: scheme=%s host=%s port=%d path=%s", scheme, host, port, path))

  -- create socket type based on scheme
  local sock, err
  -- force garbage collection before creating socket
  -- (TLS sockets use 16kb)
  collectgarbage()
  dbg(string.format("memfree after GC: %d", sys.freeMemory()))
  dbg("creating socket...")
  if scheme == "https" then
    sock, err = socket.tls()
  else
    sock, err = socket.tcp()
  end

  if not sock then
    close_debug_file()
    return nil, "failed to create socket: " .. (err or "unknown error")
  end
  dbg(string.format("socket created, memfree: %d", sys.freeMemory()))

  -- connect
  dbg(string.format("connecting to %s:%d...", host, port))
  local ok, conn_err = sock:connect(host, port, timeout * 1000)
  if not ok then
    sock:close()
    close_debug_file()
    return nil, "connection failed: " .. (conn_err or "unknown error")
  end
  dbg(string.format("connected, memfree: %d", sys.freeMemory()))

  -- build and send request
  local request = build_request(method, host, port, path, headers, body)
  dbg(string.format("sending request (%d bytes)...", #request))
  local sent, send_err = sock:send(request)
  if not sent or sent < #request then
    sock:close()
    close_debug_file()
    return nil, "send failed: " .. (send_err or "incomplete")
  end
  dbg(string.format("sent %d bytes, memfree: %d", sent, sys.freeMemory()))

  -- read response
  dbg("reading response...")
  local stream_opts = {
    output_file = options.output_file,
    stream_to_console = options.stream_to_console
  }
  local response_data, read_err = read_response(sock, timeout, options._redirect_count or 0, stream_opts)
  sock:close()

  if not response_data then
    close_debug_file()
    return nil, "read failed: " .. (read_err or "unknown error")
  end

  -- check if body was streamed
  local streamed_bytes = response_data:match("^__STREAMED__:(%d+)$")
  if streamed_bytes then
    dbg(string.format("body was streamed: %d bytes", tonumber(streamed_bytes)))
    -- close debug file if this is top-level request
    if not options._redirect_count or options._redirect_count == 0 then
      close_debug_file()
    end
    -- use saved info from streaming
    local info = streamed_info or {}
    streamed_info = nil  -- clear for next request
    return {
      status = info.status or 200,
      reason = info.reason or "OK",
      headers = info.headers or {},
      body = nil,
      streamed = true,
      streamed_bytes = tonumber(streamed_bytes),
      output_file = options.output_file
    }
  end

  dbg(string.format("got %d bytes, memfree: %d", #response_data, sys.freeMemory()))

  -- parse response
  local first_line_end = response_data:find("\r\n")
  if not first_line_end then
    close_debug_file()
    return nil, "invalid response: no status line"
  end

  local status_line = response_data:sub(1, first_line_end - 1)
  local status_code, status_reason = parse_status_line(status_line)
  if not status_code then
    close_debug_file()
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
    collectgarbage()
    dbg(string.format("body extracted, %d bytes, memfree: %d", #response_body, sys.freeMemory()))

    -- handle chunked transfer-encoding
    if response_headers["transfer-encoding"] and
       response_headers["transfer-encoding"]:lower():find("chunked") then
      dbg("decoding chunked body...")
      local decoded, decode_err = dechunk_body(response_body)
      if decoded then
        response_body = decoded
        collectgarbage()
        dbg(string.format("dechunked to %d bytes, memfree: %d", #response_body, sys.freeMemory()))
      else
        dbg("dechunk failed: " .. (decode_err or "unknown"))
        -- keep original chunked body if decode fails
      end
    end
  end

  -- handle redirects
  if follow_redirects and (status_code == 301 or status_code == 302 or status_code == 303 or status_code == 307 or status_code == 308) then
    local location = response_headers["location"]
    if location then
      local redirect_count = options._redirect_count or 0
      if redirect_count >= http.MAX_REDIRECTS then
        close_debug_file()
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
      dbg(string.format("redirect %d: %d -> %s", redirect_count + 1, status_code, location))
      --for 303, set method to GET
      if status_code == 303 then
        options.method = "GET"
        options.body = nil
      end
      return http.request(location, options)
    end
  end

  -- close debug file if this is the top-level request (not a redirect)
  if not options._redirect_count or options._redirect_count == 0 then
    close_debug_file()
  end

  --return response table
  return {
    status = status_code,
    reason = status_reason,
    headers = response_headers,
    body = response_body
  }
end

-- GET requests
function http.get(url, options)
  options = options or {}
  options.method = "GET"
  return http.request(url, options)
end

-- POST requests
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
