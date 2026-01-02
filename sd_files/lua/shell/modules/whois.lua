--[[
  whois.lua - WHOIS client for picocalc_lua

  Usage:
    whois(query)         -- Auto-detect domain or IP
    whois(query, server) -- Use specific whois server
    whois("-h")          -- Show help

  Examples:
    whois("example.com")
    whois("208.67.222.222")
    whois("example.org", "whois.pir.org")
]]

local whois = {}

-- configuration
whois.TIMEOUT = 30       -- Connection timeout (seconds)
whois.PORT = 43          -- Standard whois port

-- default whois servers by TLD
whois.TLD_SERVERS = {
  ["com"] = "whois.verisign-grs.com",
  ["net"] = "whois.verisign-grs.com",
  ["org"] = "whois.pir.org",
  ["info"] = "whois.afilias.net",
  ["biz"] = "whois.biz",
  ["us"] = "whois.nic.us",
  ["uk"] = "whois.nic.uk",
  ["co.uk"] = "whois.nic.uk",
  ["io"] = "whois.nic.io",
  ["co"] = "whois.nic.co",
  ["me"] = "whois.nic.me",
  ["tv"] = "whois.nic.tv",
  ["cc"] = "whois.nic.cc",
  ["edu"] = "whois.educause.edu",
  ["gov"] = "whois.dotgov.gov",
  ["mil"] = "whois.nic.mil",
  ["de"] = "whois.denic.de",
  ["fr"] = "whois.nic.fr",
  ["nl"] = "whois.domain-registry.nl",
  ["eu"] = "whois.eu",
  ["au"] = "whois.auda.org.au",
  ["ca"] = "whois.cira.ca",
  ["jp"] = "whois.jprs.jp",
  ["cn"] = "whois.cnnic.cn",
  ["ru"] = "whois.tcinet.ru",
  ["br"] = "whois.registro.br",
}

-- IP address whois servers (Regional Internet Registries)
whois.IP_SERVERS = {
  default = "whois.arin.net",      -- ARIN (Americas) - good starting point
  arin = "whois.arin.net",         -- North America
  ripe = "whois.ripe.net",         -- Europe/Middle East
  apnic = "whois.apnic.net",       -- Asia Pacific
  lacnic = "whois.lacnic.net",     -- Latin America
  afrinic = "whois.afrinic.net",   -- Africa
}

-- show help
local function show_help()
  print("whois.lua - WHOIS client for picocalc_lua")
  print("")
  print("Usage:")
  print("  whois(query)         Query domain or IP address")
  print("  whois(query, server) Use specific whois server")
  print("  whois('-h')          Show this help")
  print("")
  print("Examples:")
  print("  whois('example.com')    -- Domain lookup")
  print("  whois('208.67.222.222') -- IP lookup")
  print("  whois('example.org', 'whois.pir.org') -- Custom server")
  print("")
  print("Common servers:")
  print("  whois.verisign-grs.com  - .com/.net domains")
  print("  whois.pir.org   - .org domains")
  print("  whois.arin.net  - IP addresses (Americas)")
  print("  whois.ripe.net  - IP addresses (Europe)")
  print("  whois.apnic.net - IP addresses (Asia/Pacific)")
end

-- check if string is an IP address
local function is_ip_address(str)
  local parts = {str:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
  if #parts == 4 then
    for _, part in ipairs(parts) do
      local num = tonumber(part)
      if not num or num < 0 or num > 255 then
        return false
      end
    end
    return true
  end
  return false
end

-- get TLD from domain name
local function get_tld(domain)
  -- Handle multi-part TLDs like co.uk
  local parts = {}
  for part in domain:gmatch("[^%.]+") do
    table.insert(parts, part)
  end

  if #parts >= 2 then
    -- check for two-part TLD (e.g., co.uk)
    local two_part = parts[#parts - 1] .. "." .. parts[#parts]
    if whois.TLD_SERVERS[two_part:lower()] then
      return two_part:lower()
    end
    -- Return single TLD
    return parts[#parts]:lower()
  end

  return nil
end

-- select appropriate whois server for query
local function select_server(query)
  if is_ip_address(query) then
    return whois.IP_SERVERS.default
  end

  -- domain name - find server by TLD
  local tld = get_tld(query)
  if tld and whois.TLD_SERVERS[tld] then
    return whois.TLD_SERVERS[tld]
  end

  -- default to IANA for unknown TLDs
  return "whois.iana.org"
end

-- format query for specific servers 
-- (some have special requirements)
local function format_query(query, server)
  -- ARIN needs special prefix for some queries
  if server == "whois.arin.net" and is_ip_address(query) then
    return "n " .. query  -- 'n' for network lookup
  end

  -- DENIC (German domains) needs special format
  if server == "whois.denic.de" then
    return "-T dn " .. query
  end

  -- most servers just want the raw query
  return query
end

-- perform whois query
local function do_query(query, server)
  -- create socket
  local sock, err = socket.tcp()
  if not sock then
    return nil, "Failed to create socket: " .. (err or "unknown")
  end

  -- connect to whois server
  local ok, conn_err = sock:connect(server, whois.PORT, whois.TIMEOUT * 1000)
  if not ok then
    sock:close()
    return nil, "Connection to " .. server .. " failed: " .. (conn_err or "unknown")
  end

  -- format and send query
  local formatted_query = format_query(query, server)
  local sent, send_err = sock:send(formatted_query .. "\r\n")
  if not sent then
    sock:close()
    return nil, "Send failed: " .. (send_err or "unknown")
  end

  -- read response
  local chunks = {}
  local total = 0
  local max_size = 32 * 1024  -- 32KB max response

  sock:settimeout(whois.TIMEOUT)

  while total < max_size do
    local chunk, recv_err = sock:receive(4096)
    if not chunk then
      if recv_err == "timeout" and total > 0 then
        break
      elseif recv_err == "connection closed" then
        break
      elseif total > 0 then
        break
      else
        sock:close()
        return nil, "Receive failed: " .. (recv_err or "unknown")
      end
    end
    table.insert(chunks, chunk)
    total = total + #chunk
  end

  sock:close()

  if #chunks == 0 then
    return nil, "No response received"
  end

  return table.concat(chunks)
end

-- parse referral from response (for following redirects)
local function find_referral(response)
  -- Common referral patterns
  local patterns = {
    "ReferralServer:%s*whois://([^%s:]+)",
    "Whois Server:%s*([^%s]+)",
    "whois:%s*([^%s]+)",
    "refer:%s*([^%s]+)",
  }

  for _, pattern in ipairs(patterns) do
    local server = response:match(pattern)
    if server then
      -- clean up server name
      server = server:gsub("^whois://", "")
      server = server:gsub(":43$", "")
      return server
    end
  end

  return nil
end

-- main whois function
function whois.query(query, server, follow_referrals)
  if not query or query == "" then
    return nil, "Query required"
  end

  -- default to following referrals
  if follow_referrals == nil then
    follow_referrals = true
  end

  -- clean up query
  query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")

  -- select server if not specified
  server = server or select_server(query)

  --perform query
  local response, err = do_query(query, server)
  if not response then
    return nil, err
  end

  -- check for referral
  if follow_referrals then
    local referral = find_referral(response)
    if referral and referral ~= server then
      --query the referred server
      local ref_response, ref_err = do_query(query, referral)
      if ref_response then
        -- combine responses or return referral response
        response = response .. "\n\n--- Referral to " .. referral .. " ---\n\n" .. ref_response
      end
    end
  end

  return response, server
end

-- print formatted whois results
function whois.print_result(response, server)
  print("--- WHOIS response from " .. server .. " ---")
  print("")
  print(response)
end

-- main entry point
local function main(query, server)
  if query == "-h" or query == "--help" or query == "help" then
    show_help()
    return nil
  end

  if not query then
    show_help()
    return nil
  end

  -- check Wi-Fi connection
  if not wifi.isConnected() then
    print("Error: Wi-Fi not connected")
    print("Run: dofile('lua/wifi-start.lua')")
    return nil
  end

  --determine server
  local use_server = server or select_server(query)
  print(string.format("Querying %s for '%s'...", use_server, query))

  --perform query
  local response, result_server = whois.query(query, server)
  if not response then
    print("Error: " .. (result_server or "query failed"))
    return nil
  end
  print("")
  whois.print_result(response, result_server or use_server)

  return response
end

-- allow calling as function
setmetatable(whois, {
  __call = function(_, query, server)
    return main(query, server)
  end
})

return whois
