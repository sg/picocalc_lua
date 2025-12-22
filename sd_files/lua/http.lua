--[[
    HTTP Client Library for PicoCalc
    A pure Lua HTTP/1.1 client built on top of the socket module.
    Supports both HTTP and HTTPS (via TLS sockets).
]]

local http = {}
http._VERSION = "1.0"

-- Default settings
http.TIMEOUT = 30       -- seconds
http.MAX_REDIRECTS = 5
http.USER_AGENT = "PicoCalc-HTTP/1.0"

-- Parse a URL into components
-- Returns: scheme, host, port, path
local function parse_url(url)
    local scheme, rest = url:match("^(%a+)://(.+)$")
    if not scheme then
        return nil, "invalid URL: missing scheme"
    end

    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then
        return nil, "unsupported scheme: " .. scheme
    end

    -- Extract host and path
    local host_port, path = rest:match("^([^/]+)(.*)$")
    if not host_port then
        host_port = rest
        path = "/"
    end
    if path == "" then
        path = "/"
    end

    -- Extract port from host
    local host, port = host_port:match("^(.+):(%d+)$")
    if not host then
        host = host_port
        port = (scheme == "https") and 443 or 80
    else
        port = tonumber(port)
    end

    return scheme, host, port, path
end

-- Build HTTP request headers
local function build_request(method, host, port, path, headers, body)
    local lines = {}

    -- Request line
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

    -- End of headers
    table.insert(lines, "")
    table.insert(lines, "")

    local request = table.concat(lines, "\r\n")

    -- Append body if present
    if body then
        request = request .. body
    end

    return request
end

-- Parse HTTP response status line
local function parse_status_line(line)
    local version, code, reason = line:match("^HTTP/(%d%.%d)%s+(%d+)%s*(.*)")
    if not version then
        return nil, "invalid status line"
    end
    return tonumber(code), reason, version
end

-- Parse HTTP headers from response
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
            -- Normalize header name to lowercase
            name = name:lower()
            headers[name] = value
        end
    end

    return headers, body_start
end

-- Read HTTP response
local function read_response(sock, timeout)
    local chunks = {}
    local total_size = 0
    local max_size = 64 * 1024  -- 64KB max response

    sock:settimeout(timeout)

    -- Read data in chunks
    while total_size < max_size do
        local chunk, err = sock:receive(4096)
        if not chunk then
            if err == "timeout" and total_size > 0 then
                break  -- Got some data, timeout is okay
            elseif err == "connection closed" and total_size > 0 then
                break  -- Connection closed after receiving data
            elseif total_size > 0 then
                break  -- Have data, any error ends read
            else
                return nil, err or "receive failed"
            end
        end
        table.insert(chunks, chunk)
        total_size = total_size + #chunk

        -- Check if we have a complete response
        if #chunks > 0 then
            local data = table.concat(chunks)
            -- Look for end of headers
            local header_end = data:find("\r\n\r\n")
            if header_end then
                local headers, body_start = parse_headers(data, 1)

                -- Check Content-Length
                local content_length = headers["content-length"]
                if content_length then
                    content_length = tonumber(content_length)
                    local body_received = #data - body_start + 1
                    if body_received >= content_length then
                        break  -- Got full response
                    end
                end

                -- Check for chunked encoding or connection close
                local transfer_encoding = headers["transfer-encoding"]
                if not transfer_encoding and not content_length then
                    -- No length specified, read until connection closes
                    -- Continue reading
                end
            end
        end
    end

    if #chunks == 0 then
        return nil, "no response received"
    end

    return table.concat(chunks)
end

-- Perform an HTTP request
function http.request(url, options)
    options = options or {}
    local method = options.method or "GET"
    local headers = options.headers
    local body = options.body
    local timeout = options.timeout or http.TIMEOUT
    local follow_redirects = options.follow_redirects
    if follow_redirects == nil then follow_redirects = true end

    -- Parse URL
    local scheme, host, port, path = parse_url(url)
    if not scheme then
        return nil, host  -- host contains error message
    end

    -- Create appropriate socket
    local sock, err
    if scheme == "https" then
        sock, err = socket.tls()
    else
        sock, err = socket.tcp()
    end

    if not sock then
        return nil, "failed to create socket: " .. (err or "unknown error")
    end

    -- Connect
    local ok, conn_err = sock:connect(host, port, timeout * 1000)
    if not ok then
        sock:close()
        return nil, "connection failed: " .. (conn_err or "unknown error")
    end

    -- Build and send request
    local request = build_request(method, host, port, path, headers, body)
    local sent, send_err = sock:send(request)
    if not sent or sent < #request then
        sock:close()
        return nil, "send failed: " .. (send_err or "incomplete")
    end

    -- Read response
    local response_data, read_err = read_response(sock, timeout)
    sock:close()

    if not response_data then
        return nil, "read failed: " .. (read_err or "unknown error")
    end

    -- Parse response
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
    local response_body = ""
    if body_start and body_start <= #response_data then
        response_body = response_data:sub(body_start)
    end

    -- Handle redirects
    if follow_redirects and (status_code == 301 or status_code == 302 or status_code == 303 or status_code == 307 or status_code == 308) then
        local location = response_headers["location"]
        if location then
            local redirect_count = options._redirect_count or 0
            if redirect_count >= http.MAX_REDIRECTS then
                return nil, "too many redirects"
            end

            -- Handle relative URLs
            if not location:match("^%a+://") then
                if location:sub(1, 1) == "/" then
                    location = scheme .. "://" .. host .. ":" .. port .. location
                else
                    local base_path = path:match("^(.*/)")  or "/"
                    location = scheme .. "://" .. host .. ":" .. port .. base_path .. location
                end
            end

            options._redirect_count = redirect_count + 1
            -- For 303, change method to GET
            if status_code == 303 then
                options.method = "GET"
                options.body = nil
            end
            return http.request(location, options)
        end
    end

    -- Return response table
    return {
        status = status_code,
        reason = status_reason,
        headers = response_headers,
        body = response_body
    }
end

-- Convenience function for GET requests
function http.get(url, options)
    options = options or {}
    options.method = "GET"
    return http.request(url, options)
end

-- Convenience function for POST requests
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
