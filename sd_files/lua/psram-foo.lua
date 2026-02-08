--[[


]]

local function formatBytes(bytes)
  if bytes >= 1024 * 1024 then
    return string.format("%.2f MB", bytes / (1024 * 1024))
  elseif bytes >= 1024 then
    return string.format("%.2f KB", bytes / 1024)
  else
    return string.format("%d bytes", bytes)
  end
end


--local stats = psram.stats()
--print("Total PSRAM:      " .. formatBytes(stats.total))
--print("Reserved (LCD):   " .. formatBytes(stats.reserved))
--print("Available:        " .. formatBytes(stats.available))
--print("Currently used:   " .. formatBytes(stats.used))
--print("Currently free:   " .. formatBytes(stats.free))
--print("Max allocations:  " .. stats.maxAllocations)


-- allocate a 4MB buffer
local buf1 = psram.alloc(4194304)
if buf1 then
  print("Allocated 4MB buffer at address: " .. buf1)
else
  print("ERROR: Failed to allocate 4MB buffer")
  return
end

-- check size
print("Buffer 1 size: " .. psram.size(buf1) .. " bytes")

-- write test data to buffer 1
local testData = 
local written = psram.write(buf1, 0, testData)
print("Wrote " .. written .. " bytes to buffer 1")

-- read it back
local readBack = psram.read(buf1, 0, #testData)
print("Read back: " .. readBack)

-- verify
if readBack == testData then
  print("SUCCESS: Data verified correctly!")
else
  print("ERROR: Data mismatch!")
end

-- fill buffer 1 with a pattern (0xAA)
local filled = psram.fill(buf1, 0, 4194304, 0xAA)
print("Filled " .. filled .. " bytes with 0xAA")

-- Read back and check first few bytes
local fillCheck = psram.read(buf1, 0, 8)
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
  print(string.format("  [%d] addr=0x%06X size=%s", i, alloc.addr, formatBytes(alloc.size)))
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

if not wifi.isConnected() then
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
    local http = require("lua/modules/http")
    http.DEBUG = true  -- Set to true for verbose output

    -- Download a small test file
    --local testUrl = "http://httpbin.org/robots.txt"
    local testUrl = "https://github.com"
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

      local outFile = fs.open("psram_download.txt", "w")
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
        local verifyFile = fs.open("psram_download.txt", "r")
        if verifyFile then
          local content = verifyFile:readAll()
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
-- Cleanup
-- ============================================================================
separator("9. Cleanup")

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
