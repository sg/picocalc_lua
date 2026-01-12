--[[

  page.lua - view file page by page, similar to
             'more' / 'less'

]]

-- ANSI color codes
local c = require("lua/shell/modules/simple-colors")


return {
  name = "page",
  aliases = {"less", "more"},
  help = c.cyan.."page"..c.yellow.." <file>"..c.white.." - print top n lines of a file",
  run = function(args, sh)
    if not args[1] then
      return sh:error("Usage: page <file>")
    end

    local path = sh:resolve_path(args[1])
    local fspath = sh:fs_path(path)

    if not fs.exists(fspath) then
      return sh:error("'" .. args[1] .. "' not found")
    end

    if fs.isDir(fspath) then
      return sh:error("'" .. args[1] .. "' is a directory")
    end

    local f = fs.open(fspath, "r")
    if not f then
      return sh:error("Cannot open '" .. args[1] .. "'")
    end

    term.clear()
    local lines_per_page = 39
    local line_count = 0
    local page_lines = 0
    local current_page_lines = {}
    local saved_line = nil
    local reading = true
    --for i,line in ipairs(content) do
    while reading do
      
      local line = f:readLine()
      if not line then
        reading = false
        break
      end

      if saved_line then
        -- starting a new page of lines, starting
        -- with an overflow line that wouldn't fit
        -- and was saved from the previous page
        table.insert(current_page_lines, saved_line)
        page_lines = #saved_line // 52 + 1
        line_count = line_count + page_lines
        saved_line = nil
      else
        
        page_lines = page_lines + (#line // 52 + 1)
        
        -- if the line just read takes up more than
        -- one console line and would surpass the
        -- available screen lines, save it for the
        -- next page and print what we have   
        if page_lines > lines_per_page then
          saved_line = line
          for c, pline in ipairs(current_page_lines) do
            print(pline)
          end
          term.write(c.yellow .. line_count .. c.green .. ": Type 'Q' to Quit -- Any other to Continue --" .. c.white)
          local i, j, k = keys.wait() 
          if k:lower() == 'q' then
            print("")
            break
          end
          term.clear()
          page_lines = 0
          current_page_lines = {}
        
        -- otherwise, add the line to the current page 
        else
          line_count = line_count + (#line // 52 + 1)
          table.insert(current_page_lines, line)
          
          -- check to see if we're at our line count
          -- and if so, print them and pause for input
          if page_lines == lines_per_page then
            for c, pline in ipairs(current_page_lines) do
              print(pline)
            end
            term.write(c.yellow .. line_count .. c.green .. ": Type 'Q' to Quit -- Any other to Continue --" .. c.white)
            local i, j, k = keys.wait() 
            if k:lower() == 'q' then
              print("")
              break
            end
            term.clear()          
            page_lines = 0
            current_page_lines = {}
          end
        end
        -- continue to next line
      end 
    end
    f:close()
    -- got all the lines, print remainder still in
    -- the page table
    for c, pline in ipairs(current_page_lines) do
      print(pline)
    end
    print(c.green.. "Total lines paged: " .. line_count .. c.white)
  end
}
