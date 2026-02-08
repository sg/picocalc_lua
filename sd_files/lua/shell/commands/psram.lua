--[[

  psram.lua - PSRAM allocations management command.
    - list: list all allocations by offset and size.
    - stats: return table with keys: total, available,
             used, free, allocations, maxAllocations. 
    - alloc size,name: allocate a new buffer of size
             bytes. Returns addr of buffer.
    - free name|addr: free/release buffer at addr
             offset. 
    - freeall: free all allocations.
    - write <file> <buff_name>:  write file to buffer 
    - read <buff_name> <file>:  read buffer and write to file

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "psram",
  aliases = {"psr",},
  help = c.cyan.."psram"..c.yellow.." list|stats|alloc|write|read|free|freeall" .. c.white,
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: psram list|stats|alloc|free <buffer_name> [size]")
    end

    local cmd = args[1]
    
    -- list allocated buffers
    if cmd == "list" then
      local allocs = psram.list()
      table.sort(allocs, function(a, b)
        return a.addr < b.addr
      end)
      term.setCursorBlink(false)
      for i, j in ipairs(allocs) do
        term.write(i .. ". ")
        local x, y = term.getCursorPos()
        term.write(c.cyan .. "Addr: " .. c.yellow .. j.addr)
        term.setCursorPos(18, y+1)
        -- subtract 2-byte name pointer from size
        term.write(c.cyan .. " Len: " .. c.yellow .. j.size - 2)
        term.setCursorPos(33, y+1)
        local name = j.name or " (none)"
        term.write(c.cyan .. " Name:" .. "'" .. c.green .. name .. c.white .. "'")
        term.write(c.white .. "\n")
        term.setCursorBlink(true)
      end

    -- list status
    elseif cmd == "stats" then
      local stats = psram.stats()
      term.setCursorBlink(false)
      local x, y = term.getCursorPos()
      term.write(c.cyan .. "PSRAM Total:")
      term.setCursorPos(18, y+1)
      term.write(c.yellow .. stats.total .. "\n")
      term.write(c.cyan .. "Reserved (LCD):")
      term.setCursorPos(18, y+2)
      term.write(c.yellow .. stats.reserved .. "\n")
      term.write(c.cyan .. "Available:")
      term.setCursorPos(18, y+3)
      term.write(c.yellow .. stats.available .. "\n")
      term.write(c.cyan .. "Allocated:")
      term.setCursorPos(18, y+4)
      term.write(c.yellow .. stats.used .. "\n")
      term.write(c.cyan .. "Free:")
      term.setCursorPos(18, y+5)
      term.write(c.yellow .. stats.free .. "\n")
      
      term.write(c.white .. "\n")
      term.setCursorBlink(true)
        


    
    -- allocate a new buffer
    elseif cmd == "alloc" then
      
      if not args[2] then
        return sh:error("Usage: psram alloc <size> [name]")
      end
      
      local bname
      if args[3] then bname = args[3] end
      local size = args[2]
      local addr = 0
      
      if bname then
        print("creating buffer named '" .. bname .. "', " ..size .. " bytes...")
        addr, err = psram.alloc(size, bname)
      else
        addr, err = psram.alloc(size)
      end
      
      if addr ~= nil then
        sh:success("allocated " ..size.. " bytes at addr: " ..addr)
      else
        sh:error(err)
      end
    
    -- alloc buffer and write file to it
    elseif cmd == "write" then
      
      if not args[2] and not args[3] then
        return sh:error("Usage: psram write <file> <buffer_name>")
      end
      
      local path = sh:resolve_path(args[2])      
      local fpath = sh:fs_path(path)
      local buffname = args[3]

      if not fs.exists(fpath) then
        return sh:error("File doesn't exist: '" .. fpath .. "'")
      end
      
      local fsize = fs.getSize(fpath)
      local stats = psram.stats()
      if fsize >= stats.free then
        return sh:error("File size (" .. fsize ..") too large. Only " .. stats.free .. " bytes available in psram.")
      end

      print("creating buffer named '" .. buffname .. "', " ..fsize .. " bytes...")
      local addr, err = psram.alloc(fsize, buffname)
      if addr ~= nil then
        sh:success("Buffer '" .. buffname .. "', allocated " ..fsize.. " bytes at addr: " ..addr)
      else
        sh:error(err)
      end
      
      local f = fs.open(fpath, "r")
      local offset = 0
      local bytes = 0
      local total_bytes = 0
      local x, y = term.getCursorPos()
      y = y + 1
      bytes = f:read(1024)
      while bytes do
        psram.write(addr, offset, bytes)
        offset = offset + #bytes 
        total_bytes = total_bytes + #bytes
        if total_bytes % 4096 == 0 then
          term.setCursorPos(1, y)
          term.write("Bytes copied: " .. total_bytes)
          collectgarbage("collect")
        end
        bytes = f:read(1024)
      end
      term.setCursorPos(1, y)
      term.write("Bytes copied: " .. total_bytes .. "\n")
      f:close() 

      
    -- read from buffer allocation and write to file
    elseif cmd == "read" then
      
      if not args[2] and not args[3] then
        return sh:error("Usage: psram read <buffer_name> <file>")
      end
      
      local buffname = args[2]

      local path = sh:resolve_path(args[3])      
      local fpath = sh:fs_path(path)

      if fs.exists(fpath) then
        local ans = term.read("Overwrite file '" .. fpath .. "'? [N/y] ")
        if string.lower(ans) ~= "y" then
          return
        end
      end

      local addr = psram.find(buffname)
      if not addr then
        return sh:error("Can't find buffer name: '" .. buffname .. "'")
      end
      
      local buffsize = psram.size(addr)
      local err
      local f = fs.open(fpath, "w")
      local offset = 0
      local bytes = 0
      local total_bytes = 0
      local bytes_remaining = buffsize - 2 -- subtract 2 byte name pointer
      local x, y = term.getCursorPos()
      y = y + 1
      local bytes_to_read = 1024
      if bytes_remaining < bytes_to_read then bytes_to_read = bytes_remaining end
      bytes, err = psram.read(addr, offset, bytes_to_read)
      if not bytes then 
        print("psram read err: " .. err)
      end

      while bytes do
        f:write(bytes)
        offset = offset + #bytes
        bytes_remaining = bytes_remaining - #bytes
        total_bytes = total_bytes + #bytes
        if total_bytes % 4096 == 0 then
          term.setCursorPos(1, y)
          term.write("Bytes copied: " .. total_bytes)
          collectgarbage("collect")
        end
        if bytes_remaining <= bytes_to_read then 
          bytes_to_read = bytes_remaining
          total_bytes = total_bytes + bytes_to_read
          bytes, err = psram.read(addr, offset, bytes_to_read)
          if not bytes then 
            print("psram read err: " .. err)
            break
          else 
            f:write(bytes)
          end
          break
        else
          bytes, err = psram.read(addr, offset, bytes_to_read)
          if not bytes then 
            print("psram read err: " .. err)
            break
          end
        end
      end

      term.setCursorPos(1, y)
      term.write("Bytes copied: " .. total_bytes .. "\n")
      f:close() 

    -- free all allocated buffers
    elseif cmd == "freeall" then
      if psram.freeAll() ~= nil then
        sh:success("All PSRAM allocations freed.")
      else
        sh:error("PSRAM free all allocations failed.")
      end

    -- free buffer with specified name/address
    elseif cmd == "free" then
      if not args[2] then
        return sh:error("Usage: psram free <name|addr>")
      end
      local name = args[2]
      local addr = psram.find(name)
      if addr then
        if psram.free(addr) ~= nil then
          sh:success("PSRAM allocation '" .. name .. "' has been freed.")
        
        else
          sh:error("PSRAM free allocation '" .. name .. "' at " .. addr .. " failed.")
        end
      else
        addr = args[2]
        if psram.free(addr) ~= nil then
          sh:success("PSRAM allocation at " .. addr .. " has been freed.")
        
        else
          sh:error("PSRAM free allocation at " .. addr .. " failed.")
        end
      end
    else
      sh:error("unknown sub-command")
    end  
  end
}
