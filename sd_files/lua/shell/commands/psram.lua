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

]]

-- ANSI color codes
local c = require("lua/modules/simple-colors")

return {
  name = "psram",
  aliases = {"pr",},
  help = c.cyan.."psram"..c.yellow.." list|stats|alloc|free|freeall" .. c.white,
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
      for i, j in ipairs(allocs) do
        term.write(i .. ". ")
        local x, y = term.getCursorPos()
        term.write(c.cyan .. "addr: " .. c.yellow .. j.addr)
        term.setCursorPos(18, y+1)
        term.write(c.cyan .. "size: " .. c.yellow .. j.size)
        term.setCursorPos(33, y+1)
        local name = j.name or "(none)"
        term.write(c.white .. "'" .. c.green .. name .. c.white .. "'")
        term.write("\n")
      end
    
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
    
    -- free all allocated buffers
    elseif cmd == "freeall" then
      if psram.freeAll() ~= nil then
        sh:success("All PSRAM allocations freed.")
      else
        sh:error("PSRAM free all allocations failed.")
      end

    -- free buffer at specified address
    elseif cmd == "free" then
      if not args[2] then
        return sh:error("Usage: psram free <addr>")
      end
      local addr = args[2]
      if psram.free(addr) ~= nil then
        sh:success("PSRAM allocation at " .. addr .. " has been freed.")
      else
        sh:error("PSRAM free allocation at " .. addr .. " failed.")
      end
    else
      sh:error("unknown sub-command")
    end  
  end
}
