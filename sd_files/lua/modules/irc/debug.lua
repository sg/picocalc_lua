--[[

  irc/debug.lua - Minimal Debug Logger for IRC Client

  Writes memory usage and IRC traffic directly to disk with immediate
  flush to capture state before OOM crashes.

  Uses the PicoCalc 'fs' module instead of standard 'io'.

  Usage:
    local Debug = require("lua/modules/irc/debug")
    Debug.init("irc_debug.log")
    Debug.mem("label")
    Debug.irc_in(line)
    Debug.irc_out(line)
    Debug.close()

]]

local Debug = {}
local log_file = nil
local enabled = false
local start_time = nil

function Debug.init(filename)
  -- Use fs module (PicoCalc's file system API)
  local ok, err = pcall(function()
    log_file = fs.open(filename, "w")
  end)

  if ok and log_file then
    enabled = true
    start_time = os.clock()
    log_file:write("=== IRC Debug Log Started ===\n")
    log_file:write("Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    local mem = collectgarbage("count")
    log_file:write(string.format("Initial memory: %.2f KB\n", mem))
    log_file:write("---\n")
    log_file:flush()
  else
    enabled = false
  end
  return enabled
end

function Debug.close()
  if log_file then
    local mem = collectgarbage("count")
    log_file:write("---\n")
    log_file:write(string.format("Final memory: %.2f KB\n", mem))
    log_file:write("=== IRC Debug Log Ended ===\n")
    log_file:flush()
    log_file:close()
    log_file = nil
    enabled = false
  end
end

-- Get elapsed time since init
local function elapsed()
  if start_time then
    return string.format("%.3f", os.clock() - start_time)
  end
  return "0.000"
end

-- Log memory usage with a label
function Debug.mem(label)
  if not enabled then return end
  local mem = collectgarbage("count")
  log_file:write(string.format("[%s] MEM %s: %.2f KB\n", elapsed(), label, mem))
  log_file:flush()
end

-- Log a general message
function Debug.log(category, message)
  if not enabled then return end
  log_file:write(string.format("[%s] %s: %s\n", elapsed(), category, message))
  log_file:flush()
end

-- Log incoming IRC data
function Debug.irc_in(line)
  if not enabled then return end
  -- Truncate very long lines to save disk space
  if #line > 200 then
    line = line:sub(1, 200) .. "..."
  end
  log_file:write(string.format("[%s] << %s\n", elapsed(), line))
  log_file:flush()
end

-- Log outgoing IRC data
function Debug.irc_out(line)
  if not enabled then return end
  -- Remove trailing CRLF for cleaner output
  line = line:gsub("\r\n$", "")
  log_file:write(string.format("[%s] >> %s\n", elapsed(), line))
  log_file:flush()
end

-- Log table creation/modification
function Debug.table_op(operation, name, size)
  if not enabled then return end
  local mem = collectgarbage("count")
  log_file:write(string.format("[%s] TABLE %s %s (size=%d) mem=%.2f KB\n",
    elapsed(), operation, name, size or 0, mem))
  log_file:flush()
end

-- Check if debug is enabled
function Debug.is_enabled()
  return enabled
end

return Debug
