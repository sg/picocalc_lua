--[[

  A simple CLI shell for picocalc_lua

  Built-in commands are defined in the 'commands' 
  table. External commands can be added by placing
  .lua files in /lua/shell/commands/

  Each command module should return a table with:
    name     - command name (string)
    aliases  - optional aliases (table of strings)
    help     - help text (string)
    run      - handler function(args, shell)

]]

term.setCursorBlink(true)

-- load readline module for history support
local readline = require("lua/shell/modules/readline")

-- shell state and configuration

local shell = {
  cwd = "/",
  prev_cwd = "/",
  running = true,
  -- registered commands
  commands = {},
  -- ANSI color codes
  colors = {
    black   = "\27[90m",
    red     = "\27[91m",
    green   = "\27[92m",
    yellow  = "\27[93m",
    blue    = "\27[94m",
    magenta = "\27[95m",
    cyan    = "\27[96m",
    white   = "\27[97m",
    reset   = "\27[0m",
  },
  -- configuration
  config = {
    external_cmd_path = "/lua/shell/commands",
    prompt_format = "> ",
    load_external = true,
    history_file = "/lua/shell/.shell_history",
    max_history = 100,
  },
}
-- shorthand color references
local c = shell.colors


-- utility functions

-- print colored text
function shell:color(color_name, text)
  local color = c[color_name] or ""
  return color .. text .. c.white
end

-- print error message
function shell:error(msg)
  term.write(c.red .. "Error: " .. c.white .. msg .. "\n")
  return false
end

-- print warning message
function shell:warn(msg)
  term.write(c.yellow .. "Warning: " .. c.white .. msg .. "\n")
end

-- print success message
function shell:success(msg)
  term.write(c.green .. msg .. c.white .. "\n")
end

-- resolve a path relative to cwd
function shell:resolve_path(path)
  if not path or path == "" then
    return self.cwd
  end

  -- cd to previous directory
  if path == "-" then
    return self.prev_cwd
  end

  -- absolute path
  if path:sub(1, 1) == "/" then
    return self:normalize_path(path)
  end

  -- relative path
  local base = self.cwd
  if not base:match("/$") then
    base = base .. "/"
  end

  return self:normalize_path(base .. path)
end

-- normalize path (handle . and ..)
function shell:normalize_path(path)
  -- ensure leading slash
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end

  -- split into components
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      -- go to parent dir
      if #parts > 0 then
        table.remove(parts)
      end
    elseif part ~= "." and part ~= "" then
      table.insert(parts, part)
    end
  end

  local result = "/" .. table.concat(parts, "/")
  return result
end

-- convert shell path to fs API path
-- FatFS expects "" for root directory with f_opendir
function shell:fs_path(path)
  -- handle root directory
  if path == "/" or path == "" then
    return ""
  end
  -- remove trailing slash if present (but not for root)
  path = path:gsub("/$", "")
  if path == "" then
    return ""
  end
  -- remove leading slash for fs API
  if path:sub(1, 1) == "/" then
    return path:sub(2)
  end
  return path
end

-- check if path is the root directory
function shell:is_root(path)
  return path == "/" or path == ""
end

-- parse input into command and arguments
function shell:parse_input(input)
  if not input or input == "" then
    return nil, {}
  end

  local parts = {}
  local in_quote = false
  local quote_char = nil
  local current = ""

  for i = 1, #input do
    local char = input:sub(i, i)

    if not in_quote and (char == '"' or char == "'") then
      in_quote = true
      quote_char = char
    elseif in_quote and char == quote_char then
      in_quote = false
      quote_char = nil
    elseif not in_quote and char == " " then
      if current ~= "" then
        table.insert(parts, current)
        current = ""
      end
    else
      current = current .. char
    end
  end

  if current ~= "" then
    table.insert(parts, current)
  end

  local cmd = parts[1]
  local args = {}
  for i = 2, #parts do
    table.insert(args, parts[i])
  end

  return cmd, args
end

-- print directory listing
function shell:print_dir(entries)
  if not entries or #entries == 0 then
    term.write("  (empty)\n")
    return
  end

  -- sort: directories first, then alphabetically
  table.sort(entries, function(a, b)
    if a.isDir ~= b.isDir then
      return a.isDir
    end
    return a.name:lower() < b.name:lower()
  end)

  for _, entry in ipairs(entries) do
    if entry.isDir then
      term.write(" d. " .. c.cyan .. entry.name .. "/".. c.white .. "\n")
    else
      local size_str = self:format_size(entry.size)
      local cx, cy = term.getCursorPos()
      cy = cy + 1
      term.write(" f. " .. entry.size)
      term.setCursorPos((cx + 14), cy)
      term.write(" ".. c.green .. size_str .. c.white)
      term.setCursorPos(cx + 22, cy)
      term.setCursorBlink(false)
      term.write(entry.name .. "\n")
      term.setCursorBlink(true)
    end
  end
end

-- format file size
function shell:format_size(size)
  if size < 1024 then
    return size .. "b"
  elseif size < 1024 * 1024 then
    return string.format("%.1fk", size / 1024)
  else
    return string.format("%.1fm", size / (1024 * 1024))
  end
end

-- display the prompt and read input
function shell:prompt()
  local cwd_display = c.green .. "[" .. c.white .. self.cwd .. c.green .. ":" .. c.white
  --term.write(cwd_display .. "\n")
  local prompt_str = cwd_display .. c.green .. self.config.prompt_format .. c.white
  return readline.read(prompt_str)
end

-- change directory with history tracking
function shell:change_dir(path)
  local new_path = self:resolve_path(path)

  -- check if directory exists (skip for root - f_stat can't stat root)
  if not self:is_root(new_path) then
    local fs_check = self:fs_path(new_path)
    if not fs.isDir(fs_check) then
      return self:error("'" .. path .. "' is not a directory")
    end
  end

  -- ensure trailing slash for directories (except root)
  if new_path ~= "/" and not new_path:match("/$") then
    new_path = new_path .. "/"
  end

  -- root is a special case
  if new_path == "//" then
    new_path = "/"
  end

  self.prev_cwd = self.cwd
  self.cwd = new_path
  return true
end

-- command registration

-- register a command
function shell:register(cmd_def)
  if type(cmd_def) ~= "table" then
    return self:error("Invalid command definition")
  end

  local name = cmd_def.name
  if not name then
    return self:error("Command must have a name")
  end

  self.commands[name] = {
    help = cmd_def.help or "No help available",
    run = cmd_def.run or function() end,
  }

  -- register aliases
  if cmd_def.aliases then
    for _, alias in ipairs(cmd_def.aliases) do
      self.commands[alias] = self.commands[name]
    end
  end

  return true
end

-- load external commands from directory
function shell:load_external_commands()
  local cmd_path = self.config.external_cmd_path
  local fs_cmd_path = self:fs_path(cmd_path)

  if not fs.isDir(fs_cmd_path) then
    return  -- no external commands directory, that's fine
  end

  local entries = fs.list(fs_cmd_path)
  if not entries then return end

  for _, entry in ipairs(entries) do
    if not entry.isDir and entry.name:match("%.lua$") then
      local full_path = fs_cmd_path .. "/" .. entry.name
      local ok, result = pcall(dofile, full_path)

      if ok and type(result) == "table" and result.name then
        self:register(result)
      elseif not ok then
        self:warn("Failed to load command: " .. entry.name)
      end
    end
  end
end

-- execute a command
function shell:execute(cmd, args)
  if not cmd then return end

  local command = self.commands[cmd]
  if command then
    local ok, err = pcall(command.run, args, self)
    if not ok then
      self:error("Command failed: " .. tostring(err))
    end
  else
    self:error("Unknown command: " .. cmd)
    term.write("Type 'help' for available commands\n")
  end
end

-- built-in Commands

local builtin_commands = {
  -- help: show available commands
  {
    name = "help",
    aliases = {"?"},
    help = c.cyan.."help"..c.yellow.." [cmd]"..c.white.."- show help for commands",
    run = function(args, sh)
      if args[1] then
        -- help for specific command
        local cmd = sh.commands[args[1]]
        if cmd then
          term.write(cmd.help .. "\n")
        else
          sh:error("Unknown command: " .. args[1])
        end
      else
        -- list all commands
        term.write(c.green .. "Available commands:" .. c.white .. "\n")

        -- collect unique commands (skip aliases)
        local seen = {}
        local cmds = {}
        for name, def in pairs(sh.commands) do
          if not seen[def] then
            seen[def] = true
            table.insert(cmds, {name = name, help = def.help})
          end
        end

        -- sort alphabetically
        table.sort(cmds, function(a, b) return a.name < b.name end)

        for _, cmd in ipairs(cmds) do
          term.write(" " .. cmd.help .. "\n")
        end
      end
    end
  },

  -- exit: exit the shell
  {
    name = "exit",
    aliases = {"quit", "q"},
    help = c.cyan.."exit"..c.white.." - exit the shell",
    run = function(args, sh)
      term.write("Exiting shell...\n")
      sh.running = false
    end
  },

  -- ls: List directory contents
  {
    name = "ls",
    aliases = {"dir", "list"},
    help = c.cyan.."ls"..c.yellow.." [dir]"..c.white.." - list directory contents",
    run = function(args, sh)
      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      -- skip isDir check for root (f_stat can't stat root)
      if not sh:is_root(path) then
        if not fs.isDir(fspath) then
          return sh:error("'" .. (args[1] or path) .. "' is not a directory")
        end
      end

      term.write(c.green.."Contents of '"..path.."':"..c.white.."\n")
      local entries = fs.list(fspath)
      sh:print_dir(entries)
    end
  },

  -- cd: change directory
  {
    name = "cd",
    help = c.cyan.."cd"..c.yellow.." [dir|..|-]"..c.white.." - change directory",
    run = function(args, sh)
      local path = args[1] or "/"
      sh:change_dir(path)
    end
  },

  -- pwd: print working directory
  {
    name = "pwd",
    aliases = {"cwd"},
    help = c.cyan.."pwd"..c.white.." - print current directory",
    run = function(args, sh)
      term.write(sh.cwd .. "\n")
    end
  },

  -- cat: display file contents
  {
    name = "cat",
    aliases = {"type"},
    help = c.cyan.."cat"..c.yellow.." <file>"..c.white.." - display file contents",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: cat <file>")
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

      local content = f:readAll()
      f:close()

      if content then
        term.write(content .. "\n")
      end
    end
  },

  -- edit: open file in editor
  {
    name = "edit",
    aliases = {"vi", "nano"},
    help = c.cyan.."edit"..c.yellow.." <file>"..c.white.." - open file in editor",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: edit <file>")
      end

      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      if fs.exists(fspath) then
        if fs.isDir(fspath) then
          return sh:error("'" .. args[1] .. "' is a directory")
        end
        edit(fspath)
      else
        -- create new file
        local f = fs.open(fspath, "w+")
        if f then
          f:close()
          edit(fspath)
        else
          return sh:error("Cannot create '" .. args[1] .. "'")
        end
      end
    end
  },

  -- rm: delete file
  {
    name = "rm",
    aliases = {"del", "delete"},
    help = c.cyan.."rm"..c.yellow.." <file>"..c.white.." - delete file",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: rm <file>")
      end

      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      if not fs.exists(fspath) then
        return sh:error("'" .. args[1] .. "' not found")
      end

      if fs.isDir(fspath) then
        return sh:error("'" .. args[1] .. "' is a directory (use rmdir)")
      end

      fs.delete(fspath)
      sh:success("Deleted '" .. args[1] .. "'")
    end
  },

  -- mkdir: create directory
  {
    name = "mkdir",
    help = c.cyan.."mkdir"..c.yellow.." <dir>"..c.white.." - create directory",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: mkdir <dir>")
      end

      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      if fs.exists(fspath) then
        return sh:error("'" .. args[1] .. "' already exists")
      end

      if fs.makeDir(fspath) then
        sh:success("Created '" .. args[1] .. "'")
      else
        return sh:error("Failed to create '" .. args[1] .. "'")
      end
    end
  },

  -- rmdir: delete directory (if empty)
  {
    name = "rmdir",
    help = c.cyan.."rmdir"..c.yellow.." <dir>"..c.white.." - remove empty directory",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: rmdir <dir>")
      end

      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      if not fs.exists(fspath) then
        return sh:error("'" .. args[1] .. "' not found")
      end

      if not fs.isDir(fspath) then
        return sh:error("'" .. args[1] .. "' is not a directory")
      end

      -- check if empty
      local entries = fs.list(fspath)
      if entries and #entries > 0 then
        return sh:error("Directory not empty")
      end

      fs.delete(fspath)
      sh:success("Removed '" .. args[1] .. "'")
    end
  },

  -- mv: move/rename file
  {
    name = "mv",
    aliases = {"rename", "ren"},
    help = c.cyan.."mv"..c.yellow.." <src> <dst>"..c.white.." - move or rename file",
    run = function(args, sh)
      if not args[1] or not args[2] then
        return sh:error("Usage: mv <source> <destination>")
      end

      local src = sh:resolve_path(args[1])
      local dst = sh:resolve_path(args[2])
      local src_fs = sh:fs_path(src)
      local dst_fs = sh:fs_path(dst)

      if not fs.exists(src_fs) then
        return sh:error("'" .. args[1] .. "' not found")
      end

      if fs.exists(dst_fs) then
        return sh:error("'" .. args[2] .. "' already exists")
      end

      local ok, err = pcall(fs.move, src_fs, dst_fs)
      if ok then
        sh:success("Moved/renamed '" .. args[1] .. "' to '" .. args[2] .. "'")
      else
        return sh:error("Failed to move/rename: " .. (err or "unknown"))
      end
    end
  },

  -- cp: copy file
  {
    name = "cp",
    aliases = {"copy"},
    help = c.cyan.."cp"..c.yellow.." <source> <dest>"..c.white.." - copy file",
    run = function(args, sh)
      if not args[1] or not args[2] then
        return sh:error("Usage: cp <source> <destination>")
      end

      local src = sh:resolve_path(args[1])
      local dst = sh:resolve_path(args[2])
      local src_fs = sh:fs_path(src)
      local dst_fs = sh:fs_path(dst)

      if not fs.exists(src_fs) then
        return sh:error("'" .. args[1] .. "' not found")
      end

      if fs.isDir(src_fs) then
        return sh:error("Cannot copy directories")
      end

      if fs.exists(dst_fs) then
        return sh:error("'" .. args[2] .. "' already exists")
      end

      -- read source file
      local sf = fs.open(src_fs, "r")
      if not sf then
        return sh:error("Cannot read '" .. args[1] .. "'")
      end
      local content = sf:readAll()
      sf:close()

      -- write destination file
      local df = fs.open(dst_fs, "w")
      if not df then
        return sh:error("Cannot write '" .. args[2] .. "'")
      end
      df:write(content or "")
      df:close()

      sh:success("Copied '" .. args[1] .. "' to '" .. args[2] .. "'")
    end
  },

  -- eval: execute Lua code
  {
    name = "eval",
    aliases = {"exec", "lua"},
    help = c.cyan.."eval"..c.yellow.." <lua code>"..c.white.." - execute Lua code",
    run = function(args, sh)
      if #args == 0 then
        return sh:error("Usage: eval <lua code>")
      end

      local code = table.concat(args, " ")

      local chunk, load_err = load(code)
      if not chunk then
        return sh:error("Syntax error: " .. tostring(load_err))
      end

      local ok, result = pcall(chunk)
      if not ok then
        return sh:error("Runtime error: " .. tostring(result))
      end

      if result ~= nil then
        term.write(tostring(result) .. "\n")
      end
    end
  },

  -- run: execute Lua file (dofile)
  {
    name = "run",
    aliases = {"dofile"},
    help = c.cyan.."run"..c.yellow.." <file.lua>"..c.white.." - execute Lua script",
    run = function(args, sh)
      if not args[1] then
        return sh:error("Usage: run <file.lua>")
      end

      local path = sh:resolve_path(args[1])
      local fspath = sh:fs_path(path)

      if not fs.exists(fspath) then
        return sh:error("'" .. args[1] .. "' not found")
      end

      local ok, err = pcall(dofile, fspath)
      if not ok then
        return sh:error(tostring(err))
      end
    end
  },

  -- clear: clear screen
  {
    name = "clear",
    aliases = {"cls"},
    help = c.cyan.."clear"..c.white.." - clear the screen",
    run = function(args, sh)
      term.clear()
    end
  },

  -- history: show command history
  {
    name = "history",
    aliases = {"hist"},
    help = c.cyan.."history"..c.yellow.." [n]"..c.white.." - show command history (last n entries)",
    run = function(args, sh)
      local count = tonumber(args[1]) or #readline.history
      local start = math.max(1, #readline.history - count + 1)

      if #readline.history == 0 then
        term.write("No commands in history\n")
        return
      end

      for i = start, #readline.history do
        term.write(string.format("%4d  %s", i, readline.history[i]) .. "\n")
      end
    end
  },

  -- info: system info
  {
    name = "info",
    aliases = {"sysinfo"},
    help = c.cyan.."info"..c.white.." - show system information",
    run = function(args, sh)
      term.write(c.green .. "PicoCalc System Info:" .. c.white .. "\n")
      term.write(c.cyan .. "    CPU Mhz:  " .. c.white .. sys.getClock() .. "\n")
      local totalMem = sys.totalMemory()
      local freeMem = sys.freeMemory()
      local usedMem = totalMem - freeMem
      term.write(c.cyan .. "Tot. Memory:  " .. c.white .. sh:format_size(totalMem) .. "\n")
      term.write(c.cyan .. "Used Memory:  " .. c.white .. sh:format_size(usedMem) .. "\n")
      term.write(c.cyan .. "Free Memory:  " .. c.white .. sh:format_size(freeMem) .. "\n")
      term.write(c.cyan .. "    Battery:  " .. c.white .. sys.battery() .. " %\n")

      if wifi and wifi.isInitialized and wifi.isInitialized() then
        local status = wifi.isConnected() and "connected" or "disconnected"
        term.write(c.cyan .. "      Wi-Fi:  " .. c.white .. status .. "\n")
        if wifi.isConnected() and wifi.getInfo then
          local info = wifi.getInfo()
          if info and info.ip then
            term.write(c.cyan .. " IP Address:  " .. c.white .. info.ip .. "\n")
          end
        end
      end
    end
  },

  -- batt: print battery info
  {
    name = "batt",
    aliases = {"battery"},
    help = c.cyan.."batt"..c.white.." - show battery info",
    run = function(args, sh)
      local batt = sys.battery()
      term.write(c.cyan .. "Battery: " .. c.white .. batt .. " %\n")
    end
  },

  -- reload: reload external comands to update changes
  {
    name = "reload",
    aliases = {},
    help = c.cyan.."reload"..c.white.." - reload external commands",
    run = function(args, sh)
      sh:load_external_commands()
      term.write("External commands reloaded.\n")
    end
  },
}

-- main: setup and loop

local function main()
  -- register built-in commands
  for _, cmd in ipairs(builtin_commands) do
    shell:register(cmd)
  end

  -- load external commands
  if shell.config.load_external then
    shell:load_external_commands()
  end

  -- load command history
  readline.max_history = shell.config.max_history
  readline.load_history(shell.config.history_file)

  -- welcome message
  term.write("\n")
  term.write(c.green .. "PicoCalc Lua Shell" .. c.white .. " - Type '" .. c.cyan .. "help" .. c.white .. "' for commands\n")

  -- loop until 'exit' sets shell.running to false 
  while shell.running do
    local input = shell:prompt()

    if input and input ~= "" then
      -- add to history
      readline.add_history(input)

      local cmd, args = shell:parse_input(input)
      shell:execute(cmd, args)
    end
  end

  -- save command history on exit
  readline.save_history(shell.config.history_file)
end

-- send it!
main()
