--[[
  PSRAM Buffer Module Example

  Demonstrates all features of the psram module:
  - Allocation and freeing (with optional names)
  - Named buffer lookup and management
  - Writing and reading data
  - Fill and copy operations
  - Stats and listing allocations
  - Downloading web content to PSRAM and writing to file
]]

-- Helper function to format bytes
local function formatBytes(bytes)
  if bytes >= 1024 * 1024 then
    return string.format("%.2f MB", bytes / (1024 * 1024))
  elseif bytes >= 1024 then
    return string.format("%.2f KB", bytes / 1024)
  else
    return string.format("%d bytes", bytes)
  end
end

-- Print a separator
local function separator(title)
  print("\n" .. string.rep("=", 40))
  print(title)
  print(string.rep("=", 40))
end

-- ============================================================================
-- Test 1: Basic Stats
-- ============================================================================
separator("1. PSRAM Statistics")

local stats = psram.stats()
print("Total PSRAM:      " .. formatBytes(stats.total))
print("Reserved (LCD):   " .. formatBytes(stats.reserved))
print("Available:        " .. formatBytes(stats.available))
print("Currently used:   " .. formatBytes(stats.used))
print("Currently free:   " .. formatBytes(stats.free))
print("Max allocations:  " .. stats.maxAllocations)

-- ============================================================================
-- Test 2: Basic Allocation
-- ============================================================================
separator("2. Basic Allocation")

-- Allocate a 1KB buffer
local buf1 = psram.alloc(1024)
if buf1 then
  print("Allocated 1KB buffer at address: " .. buf1)
else
  print("ERROR: Failed to allocate 1KB buffer")
  return
end

-- Allocate a larger 64KB buffer
local buf2 = psram.alloc(64 * 1024)
if buf2 then
  print("Allocated 64KB buffer at address: " .. buf2)
else
  print("ERROR: Failed to allocate 64KB buffer")
  psram.free(buf1)
  return
end

-- Check sizes
print("Buffer 1 size: " .. psram.size(buf1) .. " bytes")
print("Buffer 2 size: " .. psram.size(buf2) .. " bytes")

-- ============================================================================
-- Test 3: Write and Read
-- ============================================================================
separator("3. Write and Read")

-- Write test data to buffer 1
local testData = "Hello, PSRAM! This is a test message stored in external memory."
local written = psram.write(buf1, 0, testData)
print("Wrote " .. written .. " bytes to buffer 1")

-- Read it back
local readBack = psram.read(buf1, 0, #testData)
print("Read back: " .. readBack)

-- Verify
if readBack == testData then
  print("SUCCESS: Data verified correctly!")
else
  print("ERROR: Data mismatch!")
end

-- ============================================================================
-- Test 4: Fill Operation
-- ============================================================================
separator("4. Fill Operation")

-- Fill buffer 2 with a pattern (0xAA)
local filled = psram.fill(buf2, 0, 256, 0xAA)
print("Filled " .. filled .. " bytes with 0xAA")

-- Read back and check first few bytes
local fillCheck = psram.read(buf2, 0, 8)
local correct = true
for i = 1, #fillCheck do
  if fillCheck:byte(i) ~= 0xAA then
    correct = false
    break
  end
end
print("Fill verification: " .. (correct and "SUCCESS" or "FAILED"))

-- ============================================================================
-- Test 5: Copy Operation
-- ============================================================================
separator("5. Copy Operation")

-- Write something to buffer 1 at offset 100
psram.write(buf1, 100, "COPY_TEST_DATA")

-- Copy from buffer 1 to buffer 2
local copied = psram.copy(buf2, 500, buf1, 100, 14)
print("Copied " .. copied .. " bytes from buf1 to buf2")

-- Read back from destination
local copyResult = psram.read(buf2, 500, 14)
print("Copy result: " .. copyResult)
print("Copy verification: " .. (copyResult == "COPY_TEST_DATA" and "SUCCESS" or "FAILED"))

-- ============================================================================
-- Test 6: List Allocations
-- ============================================================================
separator("6. List Allocations")

local allocs = psram.list()
print("Current allocations: " .. #allocs)
for i, alloc in ipairs(allocs) do
  local nameStr = alloc.name and string.format(" name='%s'", alloc.name) or ""
  print(string.format("  [%d] addr=0x%06X size=%s%s", i, alloc.addr, formatBytes(alloc.size), nameStr))
end

-- ============================================================================
-- Test 7: Free and Reallocate
-- ============================================================================
separator("7. Free and Reallocate")

-- Free buffer 1
psram.free(buf1)
print("Freed buffer 1")

-- Check stats
stats = psram.stats()
print("Allocations after free: " .. stats.allocations)

-- Allocate again - should reuse the space
local buf3 = psram.alloc(512)
print("Allocated new 512-byte buffer at: " .. buf3)

-- ============================================================================
-- Test 8: Web Download to PSRAM (if wifi available)
-- ============================================================================
separator("8. Web Download to PSRAM")

-- Check if wifi module is available and connected
local wifiOk = false
if wifi and wifi.status then
  local status = wifi.status()
  wifiOk = (status == wifi.CONNECTED)
end

if not wifiOk then
  print("WiFi not connected - skipping web download test")
  print("To test: connect to WiFi first, then run this script")
else
  print("WiFi connected - attempting download...")

  -- Allocate a buffer for download (100KB)
  local downloadBuf = psram.alloc(100 * 1024)
  if not downloadBuf then
    print("ERROR: Could not allocate download buffer")
  else
    print("Allocated 100KB download buffer at: " .. downloadBuf)

    -- Use the http module to download
    local http = require("modules/http")
    http.DEBUG = false  -- Set to true for verbose output

    -- Download a small test file
    local testUrl = "http://httpbin.org/robots.txt"
    print("Downloading: " .. testUrl)

    local resp, err = http.get(testUrl)
    if not resp then
      print("Download failed: " .. (err or "unknown error"))
    else
      print("HTTP Status: " .. resp.status)
      print("Body length: " .. #resp.body .. " bytes")

      -- Write the body to PSRAM
      local written = psram.write(downloadBuf, 0, resp.body)
      print("Wrote " .. written .. " bytes to PSRAM")

      -- Write length marker at the end (as 4-byte little-endian)
      local lenBytes = string.char(
        written % 256,
        math.floor(written / 256) % 256,
        math.floor(written / 65536) % 256,
        math.floor(written / 16777216) % 256
      )
      psram.write(downloadBuf, 99996, lenBytes)

      -- Now read it back and write to file
      print("\nWriting PSRAM content to file...")

      local outFile = io.open("psram_download.txt", "w")
      if outFile then
        -- Read in chunks and write to file
        local chunkSize = 1024
        local offset = 0
        local totalWritten = 0

        while offset < written do
          local toRead = math.min(chunkSize, written - offset)
          local chunk = psram.read(downloadBuf, offset, toRead)
          if chunk then
            outFile:write(chunk)
            totalWritten = totalWritten + #chunk
          end
          offset = offset + toRead
        end

        outFile:close()
        print("Wrote " .. totalWritten .. " bytes to psram_download.txt")

        -- Verify by reading file back
        local verifyFile = io.open("psram_download.txt", "r")
        if verifyFile then
          local content = verifyFile:read("*a")
          verifyFile:close()
          if content == resp.body then
            print("File verification: SUCCESS")
          else
            print("File verification: MISMATCH (got " .. #content .. " bytes)")
          end
        end
      else
        print("ERROR: Could not open output file")
      end
    end

    -- Free the download buffer
    psram.free(downloadBuf)
    print("Freed download buffer")
  end
end

-- ============================================================================
-- Test 9: Named Buffers
-- ============================================================================
separator("9. Named Buffers")

-- Allocate a named buffer
local namedBuf, err = psram.alloc(2048, "myBuffer")
if namedBuf then
  print("Allocated named buffer 'myBuffer' at: " .. namedBuf)
else
  print("ERROR: " .. (err or "unknown"))
end

-- Try to allocate with the same name (should fail)
local dupBuf, dupErr = psram.alloc(1024, "myBuffer")
if dupBuf then
  print("ERROR: Duplicate name should have failed!")
  psram.free(dupBuf)
else
  print("Name collision detected: " .. dupErr)
end

-- Find buffer by name
local foundAddr, findErr = psram.find("myBuffer")
if foundAddr then
  print("Found 'myBuffer' at address: " .. foundAddr)
  print("Addresses match: " .. (foundAddr == namedBuf and "YES" or "NO"))
else
  print("Find failed: " .. findErr)
end

-- Get name from address
local bufName = psram.getName(namedBuf)
print("getName() returned: " .. (bufName or "nil"))

-- Create unnamed buffer and set name later
local unnamedBuf = psram.alloc(512)
print("\nAllocated unnamed buffer at: " .. unnamedBuf)
print("Name before setName: " .. (psram.getName(unnamedBuf) or "nil"))

local ok, setErr = psram.setName(unnamedBuf, "laterNamed")
if ok then
  print("setName() succeeded")
  print("Name after setName: " .. (psram.getName(unnamedBuf) or "nil"))
else
  print("setName() failed: " .. setErr)
end

-- Free by name
print("\nFreeing 'myBuffer' by name...")
local freed, freeErr = psram.free("myBuffer")
if freed then
  print("Successfully freed by name")
else
  print("Free by name failed: " .. freeErr)
end

-- Verify it's gone
local goneBuf, goneErr = psram.find("myBuffer")
if not goneBuf then
  print("Confirmed 'myBuffer' no longer exists")
end

-- Free the other named buffer by name
psram.free("laterNamed")
print("Freed 'laterNamed' buffer")

-- List remaining allocations to show named buffer management
print("\nCurrent allocations after named buffer tests:")
allocs = psram.list()
for i, alloc in ipairs(allocs) do
  local nameStr = alloc.name and string.format(" name='%s'", alloc.name) or ""
  print(string.format("  [%d] addr=0x%06X size=%s%s", i, alloc.addr, formatBytes(alloc.size), nameStr))
end

-- ============================================================================
-- Cleanup
-- ============================================================================
separator("10. Cleanup")

-- Free all remaining buffers
psram.free(buf2)
psram.free(buf3)
print("Freed all test buffers")

-- Or use freeAll to free everything at once:
-- psram.freeAll()

-- Final stats
stats = psram.stats()
print("\nFinal PSRAM state:")
print("  Used: " .. formatBytes(stats.used))
print("  Free: " .. formatBytes(stats.free))
print("  Allocations: " .. stats.allocations)

separator("Tests Complete!")
