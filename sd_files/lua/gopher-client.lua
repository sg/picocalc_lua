--[[
    gopher-client.lua - Gopher Protocol Client for PicoCalc

    A reusable Gopher protocol implementation.

    Usage:
        local gopher = require("gopher-client")

        -- Parse a gopher URL
        local host, port, gtype, selector = gopher.parse_url("gopher://example.com/1/")

        -- Fetch a resource
        local response, err = gopher.fetch(host, port, selector, timeout)

        -- Parse menu response
        local items = gopher.parse_menu(response)
]]

local gopher = {}
gopher._VERSION = "1.0"

-- Default settings
gopher.DEFAULT_PORT = 70
gopher.DEFAULT_TIMEOUT = 30000  -- ms
gopher.MAX_RESPONSE = 64 * 1024  -- 64KB max response

-- Gopher item types
gopher.types = {
    TEXT      = "0",  -- Text file
    MENU      = "1",  -- Directory/menu
    CSO       = "2",  -- CSO phone book
    ERROR     = "3",  -- Error
    BINHEX    = "4",  -- BinHex encoded
    DOS       = "5",  -- DOS binary
    UUENCODE  = "6",  -- UUencoded
    SEARCH    = "7",  -- Search query
    TELNET    = "8",  -- Telnet session
    BINARY    = "9",  -- Binary file
    MIRROR    = "+",  -- Redundant server
    GIF       = "g",  -- GIF image
    IMAGE     = "I",  -- Image (other)
    INFO      = "i",  -- Informational text
    HTML      = "h",  -- HTML link
    SOUND     = "s",  -- Sound file
    DOC       = "d",  -- Document
    PNG       = "p",  -- PNG image
}

-- Human-readable type names
gopher.type_names = {
    ["0"] = "TXT",
    ["1"] = "DIR",
    ["2"] = "CSO",
    ["3"] = "ERR",
    ["7"] = "???",
    ["9"] = "BIN",
    ["g"] = "GIF",
    ["I"] = "IMG",
    ["i"] = "   ",
    ["h"] = "HTM",
    ["s"] = "SND",
    ["p"] = "PNG",
}

-- Check if an item type is navigable (can be selected/opened)
function gopher.is_navigable(item_type)
    return item_type == gopher.types.TEXT
        or item_type == gopher.types.MENU
        or item_type == gopher.types.SEARCH
        or item_type == gopher.types.HTML
end

-- Check if an item type is a directory/menu
function gopher.is_menu(item_type)
    return item_type == gopher.types.MENU
end

-- Check if an item type is downloadable
function gopher.is_downloadable(item_type)
    return item_type == gopher.types.BINARY
        or item_type == gopher.types.GIF
        or item_type == gopher.types.IMAGE
        or item_type == gopher.types.SOUND
        or item_type == gopher.types.DOS
        or item_type == gopher.types.PNG
end

-- Parse a Gopher URL
-- Format: gopher://host[:port][/type[selector]]
-- Returns: host, port, type, selector (or nil, error)
function gopher.parse_url(url)
    if not url then
        return nil, "no URL provided"
    end

    -- Remove gopher:// prefix
    local rest = url:match("^gopher://(.+)$")
    if not rest then
        -- Try without scheme
        if url:match("^[%w%-%.]+") then
            rest = url
        else
            return nil, "invalid gopher URL"
        end
    end

    -- Split host:port from path
    local host_port, path = rest:match("^([^/]+)(.*)$")
    if not host_port then
        host_port = rest
        path = ""
    end

    -- Extract port
    local host, port = host_port:match("^(.+):(%d+)$")
    if not host then
        host = host_port
        port = gopher.DEFAULT_PORT
    else
        port = tonumber(port)
    end

    -- Parse path: /type/selector or /typeselector
    local gtype = gopher.types.MENU  -- Default to menu
    local selector = ""

    if path and path ~= "" and path ~= "/" then
        -- Remove leading slash
        path = path:sub(2)

        -- First character is type, rest is selector
        if #path >= 1 then
            gtype = path:sub(1, 1)
            selector = path:sub(2)
            -- Remove leading slash from selector if present
            if selector:sub(1, 1) == "/" then
                selector = selector:sub(2)
            end
        end
    end

    return host, port, gtype, selector
end

-- Build a Gopher URL from components
function gopher.build_url(host, port, gtype, selector)
    local url = "gopher://" .. host
    if port and port ~= gopher.DEFAULT_PORT then
        url = url .. ":" .. port
    end
    url = url .. "/" .. (gtype or "1")
    if selector and selector ~= "" then
        url = url .. "/" .. selector
    end
    return url
end

-- Fetch a Gopher resource
-- Returns: response_data, error
function gopher.fetch(host, port, selector, timeout)
    port = port or gopher.DEFAULT_PORT
    selector = selector or ""
    timeout = timeout or gopher.DEFAULT_TIMEOUT

    -- Check Wi-Fi
    if not wifi.isConnected() then
        return nil, "Wi-Fi not connected"
    end

    -- Create socket
    local sock, err = socket.tcp()
    if not sock then
        return nil, "socket error: " .. (err or "unknown")
    end

    -- Connect
    local ok, conn_err = sock:connect(host, port, timeout)
    if not ok then
        sock:close()
        return nil, "connect error: " .. (conn_err or "timeout")
    end

    -- Send request (selector + CRLF)
    local sent, send_err = sock:send(selector .. "\r\n")
    if not sent then
        sock:close()
        return nil, "send error: " .. (send_err or "unknown")
    end

    -- Receive response
    local chunks = {}
    local total = 0

    sock:settimeout(timeout / 1000)

    while total < gopher.MAX_RESPONSE do
        local chunk, recv_err = sock:receive(4096)
        if not chunk then
            if recv_err == "timeout" and total > 0 then
                break
            elseif recv_err == "closed" or recv_err == "connection closed" then
                break
            elseif total > 0 then
                break
            else
                sock:close()
                return nil, "receive error: " .. (recv_err or "unknown")
            end
        end

        if #chunk == 0 then
            break
        end

        table.insert(chunks, chunk)
        total = total + #chunk

        -- Check for end marker (lone period on a line)
        if chunk:match("\r\n%.\r\n$") or chunk:match("\n%.\n$") or chunk == ".\r\n" then
            break
        end
    end

    sock:close()

    if #chunks == 0 then
        return nil, "empty response"
    end

    return table.concat(chunks)
end

-- Parse a menu response into items
-- Each item: {type, display, selector, host, port, raw}
function gopher.parse_menu(response)
    if not response then
        return {}
    end

    local items = {}

    for line in response:gmatch("[^\r\n]+") do
        -- Skip end marker
        if line == "." then
            break
        end

        -- Parse line: TypeDisplayText\tSelector\tHost\tPort
        local item_type = line:sub(1, 1)
        local rest = line:sub(2)

        -- Split by tabs
        local parts = {}
        for part in rest:gmatch("[^\t]+") do
            table.insert(parts, part)
        end

        -- Handle lines with missing tabs (common for info lines)
        local display = parts[1] or ""
        local selector = parts[2] or ""
        local item_host = parts[3] or ""
        local item_port = tonumber(parts[4]) or gopher.DEFAULT_PORT

        -- Clean up display text
        display = display:gsub("[\r\n]", "")

        table.insert(items, {
            type = item_type,
            display = display,
            selector = selector,
            host = item_host,
            port = item_port,
            raw = line,
        })
    end

    return items
end

-- Perform a search query (type 7)
-- Returns: response_data, error
function gopher.search(host, port, selector, query, timeout)
    -- Search selector format: selector\tquery
    local search_selector = selector .. "\t" .. query
    return gopher.fetch(host, port, search_selector, timeout)
end

-- Get type name for display
function gopher.get_type_name(item_type)
    return gopher.type_names[item_type] or "???"
end

return gopher
