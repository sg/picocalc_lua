--[[

  A simple command-line interface (shell) for
  picocalc_lua.

  Built-in commands are defined in the 'commands'
  table. External commands can be added by placing
  .lua files in /lua/shell/commands/

  Each command module returns a table with:
    name      - command name (string)
    aliases   - optional aliases (table of strings)
    category  - help category: core, util, net, games
    usage     - argument summary, e.g. "<file> [n]"
    desc      - one-line description for help
    long      - optional extra help text (string)
    args      - optional spec of positional arguments,
                checked before run is called (see below)
    flags     - optional string of accepted flag letters,
                e.g. "fv"; words like "-f" are removed
                from args and recorded in args.flags
    needs     - optional requirements, e.g. {"wifi"}
    complete  - optional: "path" to complete every
                argument as a path, or a function
                (sh, word, index, prior_args) returning
                a list of completions
    keep_modules - true keeps modules required by the
                command loaded after it returns
    resident  - true keeps the command body in memory
                after its first use (see below)
    pager     - true adds a -p flag that pages the
                command's output (see modules/pager.lua)
    help      - optional preformatted help line; built
                from name, usage and desc when absent
    run       - handler function(args, sh, raw_input)

  The args spec is a space-separated list of types:
    file     existing file; args.v[i] is the fs path
    dir      existing directory; args.v[i] is the fs path
    entry    existing file or directory; fs path
    path     any path; args.v[i] is the fs path
    newpath  path that must not exist; fs path
    number   numeric; args.v[i] is the number
    string   anything; args.v[i] is the word
  A type may be followed by "?" (optional), "?=default"
  (optional with a default) or "..." (one or more;
  "?..." for zero or more). Path types also set
  args.abs[i] to the absolute shell path.

  Before run is called the shell parses flags, checks
  requirements and validates the arguments, printing
  the usage line and skipping run on any problem. It
  also fills in args.sh and args.raw, reports errors
  with a traceback, and unloads any modules the command
  loaded unless keep_modules is set.

  External command files are run once at startup to
  collect the fields above; the run function itself is
  then discarded and the file is loaded again each time
  the command executes, so idle commands cost no heap.
  Set resident = true on a command, or
  config.lazy_commands = false for all of them, to keep
  bodies loaded instead.

]]

term.setCursorBlink(true)

-- load readline module for history support
local readline = require("lua/shell/modules/readline")

-- ANSI escape codes
local ESC = "\27["
local RESET = ESC .. "0m"
local DIM = ESC .. "2m"
local CLEAR_LINE = ESC .. "K"

-- shell state and configuration
local shell = {
  cwd = "/",
  prev_cwd = "/",
  running = true,
  -- registered commands
  commands = {},
  -- ANSI color codes
  colors = {
    black   = ESC .. "90m",
    red     = ESC .. "91m",
    green   = ESC .. "92m",
    yellow  = ESC .. "93m",
    blue    = ESC .. "94m",
    magenta = ESC .. "95m",
    cyan    = ESC .. "96m",
    white   = ESC .. "97m",
    reset   = RESET,
  },
  -- configuration
  config = {
    external_cmd_path = "/lua/shell/commands",
    prompt_format = "> ",
    load_external = true,
    history_file = "/lua/shell/.shell_history",
    max_history = 100,
    traceback = true,
    lazy_commands = true,
    -- collector settings applied at startup; see shell:apply_gc
    gc = {
      mode = "incremental",
      pause = 120,
      stepmul = 600,
    },
  },
  -- last command's exit status: false when it failed or returned false
  last_status = true,
}
-- shorthand color references
local c = shell.colors

-- requirement checks named by a command's 'needs' list
shell.requirements = {
  wifi = function()
    if wifi and wifi.isConnected and wifi.isConnected() then
      return true
    end
    return false, "Wi-Fi not connected"
  end,
}

-- argument spec parsing

local path_types = { file = true, dir = true, entry = true, path = true, newpath = true }
local arg_types = { number = true, string = true }
for t in pairs(path_types) do arg_types[t] = true end

-- parse an args spec string into a list of {type, optional, default, rest}
local function parse_spec(spec)
  if spec == nil then
    return nil
  end

  local list = {}
  for word in spec:gmatch("%S+") do
    local entry = {}
    local t, rest = word:match("^(%a+)(.*)$")
    rest = rest or word

    if rest:sub(-3) == "..." then
      entry.rest = true
      rest = rest:sub(1, -4)
    end

    if rest:sub(1, 1) == "?" then
      entry.optional = true
      rest = rest:sub(2)
      if rest:sub(1, 1) == "=" then
        entry.default = rest:sub(2)
        rest = ""
      end
    end

    if not arg_types[t] or rest ~= "" then
      return nil, "bad argument spec '" .. word .. "'"
    end

    entry.type = t
    table.insert(list, entry)
  end

  return list
end

-- spec entry covering positional argument i, or nil if there is none
local function spec_entry(spec, i)
  if not spec or #spec == 0 then
    return nil
  end
  if i > #spec then
    local last = spec[#spec]
    return last.rest and last or nil
  end
  return spec[i]
end


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

-- apply config.gc: mode is "incremental" or "generational", the other
-- keys are collectgarbage("param") names (pause, stepmul, stepsize,
-- minormul, minormajor, majorminor) given in percent
function shell:apply_gc()
  local gc = self.config.gc
  if not gc then
    return
  end

  local ok, err = pcall(function()
    if gc.mode then
      collectgarbage(gc.mode)
    end
    for name, value in pairs(gc) do
      if name ~= "mode" then
        collectgarbage("param", name, value)
      end
    end
  end)
  if not ok then
    self:warn("GC settings not applied: " .. tostring(err))
  end
end

-- print the usage line for a command (by name or definition)
function shell:usage(cmd, why)
  local def = type(cmd) == "table" and cmd or self.commands[cmd]

  if why then
    term.write(c.red .. "Error: " .. c.white .. why .. "\n")
  end

  if def then
    local line = c.cyan .. def.name
    if def.usage then
      line = line .. c.yellow .. " " .. def.usage
    end
    term.write("Usage: " .. line .. c.white .. "\n")
  end

  return false
end

-- build the one-line help entry for a command definition
function shell:format_help(def)
  local line = c.cyan .. def.name
  if def.pager then
    line = line .. c.yellow .. " [-p]"
  end
  if def.usage then
    line = line .. c.yellow .. " " .. def.usage
  end
  return line .. c.white .. " - " .. (def.desc or "no description")
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
  -- remove trailing slash if present
  path = path:gsub("/$", "")
  if path == "" then
    return ""
  end
  -- remove leading slash for 'fs' API
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

-- file size in at most six characters: bytes, then decimal M or G
function shell:short_size(size)
  if size < 1000000 then
    return tostring(size)
  end
  local value, unit = size / 1e6, "M"
  if size >= 1e9 then
    value, unit = size / 1e9, "G"
  end
  local s = string.format("%.2f%s", value, unit)
  if #s > 6 then s = string.format("%.1f%s", value, unit) end
  if #s > 6 then s = string.format("%.0f%s", value, unit) end
  return s
end

-- print directory listing: one entry per line with byte sizes when long
-- is set, otherwise compact sizes and two columns once the listing
-- would not fit the screen
function shell:print_dir(entries, long)
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
  
  if long then
    for _, entry in ipairs(entries) do
      if entry.isDir then
        term.write("  --Dir--  " .. c.yellow .. entry.name .. "/" .. c.white .. "\n")
      else
        term.write(string.format("%9d  %s\n", entry.size, entry.name))
      end
    end
    term.write("\n")
    return
  end

  -- a cell per entry: six-character size, a space, the name; width is
  -- the visible length since directory names carry colour codes
  local cells = {}
  for i, entry in ipairs(entries) do
    local text, shown
    if entry.isDir then
      shown = entry.name .. "/"
      text = string.format("%6s ", "<dir>") .. c.yellow .. shown .. c.white
    else
      shown = entry.name
      text = string.format("%6s %s", self:short_size(entry.size), shown)
    end
    cells[i] = { text = text, width = 7 + #shown }
  end

  local width, height = term.getSize()
  -- header, listing and the trailing blank line against the rows
  -- the pager can show
  local two_columns = #cells + 4 > height - 1
  -- the pager indents by one column, so the grid is one narrower
  local cell_width = (width - 1) // 2

  -- entries are paired left to right; one too wide for a cell takes a
  -- row of its own and the pairing resumes after it
  local i = 1
  while i <= #cells do
    local a, b = cells[i], cells[i + 1]
    if two_columns and a.width < cell_width and b and b.width < cell_width then
      term.write(a.text .. string.rep(" ", cell_width - a.width) .. b.text .. "\n")
      i = i + 2
    else
      term.write(a.text .. "\n")
      i = i + 1
    end
  end
  term.write("\n")
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

-- complete command names
function shell:complete_command(prefix)
  local matches = {}
  local seen = {}

  for name, _ in pairs(self.commands) do
    if not seen[name] and name:sub(1, #prefix) == prefix then
      table.insert(matches, name)
      seen[name] = true
    end
  end

  table.sort(matches)
  return matches
end

-- complete file/directory paths
function shell:complete_path(partial)
  -- handle empty partial
  if not partial or partial == "" then
    partial = "./"
  end

  -- determine directory to list and prefix to match
  local dir_part, name_part

  -- check for trailing slash (list directory contents)
  if partial:match("/$") then
    dir_part = partial:gsub("/+$", "")
    name_part = ""
  else
    -- split into directory and filename parts
    local last_slash = partial:match(".*/()")
    if last_slash then
      dir_part = partial:sub(1, last_slash - 2)
      name_part = partial:sub(last_slash)
    else
      dir_part = ""
      name_part = partial
    end
  end

  -- resolve the directory path
  local resolved_dir
  if dir_part == "" then
    resolved_dir = self.cwd
  else
    resolved_dir = self:resolve_path(dir_part)
  end

  local fs_dir = self:fs_path(resolved_dir)

  -- check directory exists
  if not self:is_root(resolved_dir) and not fs.isDir(fs_dir) then
    return {}
  end

  -- list directory entries
  local entries = fs.list(fs_dir)
  if not entries then
    return {}
  end

  local matches = {}
  local prefix_lower = name_part:lower()

  for _, entry in ipairs(entries) do
    local name = entry.name
    if name:lower():sub(1, #prefix_lower) == prefix_lower then
      -- build the completion string
      local completion
      if dir_part == "" and partial:sub(1, 1) == "/" then
        -- root directory
        completion = "/" .. name
      elseif dir_part == "" then
        completion = name
      else
        completion = dir_part .. "/" .. name
      end

      -- add trailing slash for directories
      if entry.isDir then
        completion = completion .. "/"
      end

      table.insert(matches, completion)
    end
  end

  table.sort(matches)
  return matches
end

-- main completion function called by readline
function shell:complete(buffer, cursor_x)
  -- extract word boundaries
  local before_cursor = buffer:sub(1, cursor_x - 1)

  -- find the start of the current word (handle quotes)
  local word_start = 1
  local in_quote = false
  local quote_char = nil

  for i = 1, #before_cursor do
    local char = before_cursor:sub(i, i)
    if not in_quote and (char == '"' or char == "'") then
      in_quote = true
      quote_char = char
      word_start = i + 1
    elseif in_quote and char == quote_char then
      in_quote = false
      quote_char = nil
    elseif not in_quote and char == " " then
      word_start = i + 1
    end
  end

  local current_word = before_cursor:sub(word_start)

  -- determine if completing command or argument
  local first_space = buffer:find(" ")
  local is_command = not first_space or cursor_x <= first_space

  if is_command then
    return self:complete_command(current_word), word_start, cursor_x - 1
  end

  local cmd = buffer:match("^(%S+)")
  local def = self.commands[cmd]
  if not def then
    return nil, word_start, cursor_x - 1
  end

  -- position of the current word among the positional arguments
  local _, prior = self:parse_input(before_cursor:sub(1, word_start - 1))
  local index = #prior + 1
  if def.flags then
    index = 1
    for _, word in ipairs(prior) do
      if not word:match("^%-%a+$") then
        index = index + 1
      end
    end
  end

  local completions
  local mode = def.complete
  if type(mode) == "function" then
    completions = mode(self, current_word, index, prior)
  else
    local entry = spec_entry(def.spec, index)
    if mode == "path" or (entry and path_types[entry.type]) then
      completions = self:complete_path(current_word)
    end
  end

  return completions, word_start, cursor_x - 1
end

-- display the prompt and read input
function shell:prompt()
  local cwd_display = c.green .. "[" .. c.white .. self.cwd .. c.green .. ":" .. c.white
  --term.write(cwd_display .. "\n")
  local prompt_str = cwd_display .. c.green .. self.config.prompt_format .. c.white

  -- create completion callback
  local complete_fn = function(buffer, cursor_x)
    return self:complete(buffer, cursor_x)
  end

  return readline.read(prompt_str, complete_fn)
end

-- change directory 
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
  if new_path == "//" then
    new_path = "/"
  end

  self.prev_cwd = self.cwd
  self.cwd = new_path
  return true
end

-- command registration

-- register a command; file is set for commands indexed from disk
function shell:register(cmd_def, file)
  if type(cmd_def) ~= "table" then
    return self:error("Invalid command definition")
  end

  if not cmd_def.name then
    return self:error("Command must have a name")
  end

  if not cmd_def.run then
    return self:error("Command '" .. cmd_def.name .. "' must have a 'run' function")
  end

  local spec, spec_err = parse_spec(cmd_def.args)
  if spec_err then
    return self:error("Command '" .. cmd_def.name .. "': " .. spec_err)
  end

  local def = {
    name = cmd_def.name,
    aliases = {},
    category = cmd_def.category or "util",
    usage = cmd_def.usage,
    desc = cmd_def.desc,
    long = cmd_def.long,
    spec = spec,
    flags = cmd_def.flags,
    pager = cmd_def.pager,
    needs = cmd_def.needs,
    complete = cmd_def.complete,
    keep_modules = cmd_def.keep_modules,
    resident = cmd_def.resident,
    file = file,
    run = cmd_def.run,
  }
  def.help = cmd_def.help or self:format_help(def)

  if def.pager and not (def.flags and def.flags:find("p", 1, true)) then
    def.flags = (def.flags or "") .. "p"
  end

  -- drop the body so the chunk can be collected; execute reloads it from file
  if file and self.config.lazy_commands and not def.resident then
    def.run = nil
  end

  self.commands[def.name] = def

  -- register aliases
  for _, alias in ipairs(cmd_def.aliases or {}) do
    if alias ~= "" then
      self.commands[alias] = def
      table.insert(def.aliases, alias)
    end
  end

  return true
end

-- load external commands from directory
function shell:load_external_commands()
  local cmd_path = self.config.external_cmd_path
  local fs_cmd_path = self:fs_path(cmd_path)

  if not fs.isDir(fs_cmd_path) then
    print("External cmd directory: '" .. fs_cmd_path .. "' not found. Using built-in commands only.")
    return  -- no external commands directory, that's fine
  end

  local entries = fs.list(fs_cmd_path)
  if not entries then return end

  for _, entry in ipairs(entries) do
    if not entry.isDir and entry.name:match("%.lua$") then
      local full_path = fs_cmd_path .. "/" .. entry.name
      local ok, result = pcall(dofile, full_path)

      if ok and type(result) == "table" and result.name then
        self:register(result, full_path)
      elseif not ok then
        self:warn("Failed to load command: " .. entry.name)
        print(tostring(result))
      end
    end
  end
end

-- validate one word against a spec entry; returns value, absolute path
function shell:check_arg(entry, word)
  local t = entry.type

  if t == "number" then
    local n = tonumber(word)
    if not n then
      return nil, nil, "'" .. word .. "' is not a number"
    end
    return n
  end

  if not path_types[t] then
    return word
  end

  local abs = self:resolve_path(word)
  local fspath = self:fs_path(abs)
  -- f_stat cannot stat the root and isDir raises on missing paths
  local root = self:is_root(abs)
  local exists = root or fs.exists(fspath)

  if t == "newpath" then
    if exists then
      return nil, nil, "'" .. word .. "' already exists"
    end
  elseif t ~= "path" then
    if not exists then
      return nil, nil, "'" .. word .. "' not found"
    end
    if t ~= "entry" then
      local is_dir = root or fs.isDir(fspath)
      if t == "file" and is_dir then
        return nil, nil, "'" .. word .. "' is a directory"
      end
      if t == "dir" and not is_dir then
        return nil, nil, "'" .. word .. "' is not a directory"
      end
    end
  end

  return fspath, abs
end

-- parse flags, check requirements and validate positional
-- arguments; returns false after reporting the first problem
function shell:prepare_args(def, args, raw_input)
  args.sh = self
  args.raw = raw_input
  args.flags = {}
  args.v = {}
  args.abs = {}

  if def.flags then
    local i = 1
    while i <= #args do
      local word = args[i]
      if word == "--" then
        table.remove(args, i)
        break
      elseif word:match("^%-%a+$") then
        for letter in word:gmatch("%a") do
          if not def.flags:find(letter, 1, true) then
            return self:usage(def, "unknown flag -" .. letter)
          end
          args.flags[letter] = true
        end
        table.remove(args, i)
      else
        i = i + 1
      end
    end
  end

  if def.needs then
    for _, need in ipairs(def.needs) do
      local check = self.requirements[need]
      local ok, msg = false, "unknown requirement '" .. need .. "'"
      if check then
        ok, msg = check()
      end
      if not ok then
        return self:error(msg or (need .. " not available"))
      end
    end
  end

  local spec = def.spec
  if not spec then
    return true
  end

  for i = 1, math.max(#spec, #args) do
    local entry = spec_entry(spec, i)
    if not entry then
      return self:usage(def, "too many arguments")
    end

    local word = args[i]
    if word == nil and i <= #spec then
      if entry.default then
        word = entry.default
        args[i] = word
      elseif not entry.optional then
        return self:usage(def)
      end
    end

    if word ~= nil then
      local v, abs, err = self:check_arg(entry, word)
      if err then
        return self:error(err)
      end
      args.v[i] = v
      args.abs[i] = abs
    end
  end

  return true
end

-- keep the frames inside the command; the shell's own frames below xpcall add nothing
local function trace_handler(err)
  local msg = debug.traceback(tostring(err), 2)
  return (msg:gsub("\n%s*%[C%]: in %a+ 'xpcall'.*$", ""))
end

-- report a failed command, shortening keyboard interrupts
function shell:report_failure(msg)
  msg = tostring(msg)
  local first = msg:match("^[^\n]*")

  if first:match("interrupted$") then
    term.write(c.yellow .. "Interrupted" .. c.white .. "\n")
    return
  end

  if not self.config.traceback then
    msg = first
  end
  self:error("Command failed: " .. msg)
end

-- load the run function of an indexed command from its file
function shell:load_body(def)
  local mod = dofile(def.file)
  if type(mod) ~= "table" or type(mod.run) ~= "function" then
    error("'" .. def.file .. "' did not return a command table")
  end
  if def.resident then
    def.run = mod.run
  end
  return mod.run
end

-- execute a command
function shell:execute(cmd, args, raw_input)
  if not cmd then return end
  args = args or {}

  local def = self.commands[cmd]
  if not def then
    self:error("Unknown command: " .. cmd)
    term.write("Type 'help' for available commands\n")
    self.last_status = false
    return false
  end

  local status = false
  if self:prepare_args(def, args, raw_input) then
    local pager, failed
    if def.pager and args.flags.p then
      -- required before the snapshot below so it stays resident once used
      local ok, result = pcall(require, "lua/shell/modules/pager")
      if ok then
        pager = result
      else
        failed = true
        self:report_failure(result)
      end
    end

    local loaded_before = {}
    if not def.keep_modules then
      for name in pairs(package.loaded) do
        loaded_before[name] = true
      end
    end

    -- the body is loaded after the snapshot so modules it requires are unloaded too
    local run = def.run
    if not run and not failed then
      local ok, result = xpcall(self.load_body, trace_handler, self, def)
      if ok then
        run = result
      else
        self:report_failure(result)
      end
    end

    if run and not failed then
      local ok, result
      if pager then
        ok, result = pager.run(run, args, self, raw_input)
      else
        ok, result = xpcall(run, trace_handler, args, self, raw_input)
      end
      if ok then
        status = result ~= false
      else
        self:report_failure(result)
      end
    end

    if not def.keep_modules then
      for name in pairs(package.loaded) do
        if not loaded_before[name] then
          package.loaded[name] = nil
        end
      end
    end
  end
  self.last_status = status

  -- blit buffer if in buffer mode (for screenshot support)
  if _G._buffer_mode_blit then
    draw.blitBuffer()
  end
  collectgarbage()

  return status
end

-- help category definitions
local help_categories = {
  {id = "core",  label = "Core Functionality"},
  {id = "util",  label = "Utilities"},
  {id = "net",   label = "Network"},
  {id = "games", label = "Games"},
}

-- built-in Commands

local builtin_commands = {
  -- help: show available commands
  {
    name = "help",
    aliases = {"?"},
    category = "core",
    usage = "[category|cmd]",
    desc = "show help for categories or commands",
    args = "string?",
    pager = true,
    complete = function(sh, word, index)
      if index ~= 1 then
        return nil
      end
      local matches = sh:complete_command(word)
      for _, cat in ipairs(help_categories) do
        if cat.id:sub(1, #word) == word then
          table.insert(matches, cat.id)
        end
      end
      table.sort(matches)
      return matches
    end,
    run = function(args, sh)
      if not args[1] then
        -- no args: show category list
        term.write(c.green .. "Help categories:" .. c.white .. "\n\n")
        for _, cat in ipairs(help_categories) do
          term.write("  " .. c.cyan .. cat.id .. c.white .. " - " .. cat.label .. "\n")
        end
        term.write("\nUsage: " .. c.cyan .. "help " .. c.yellow .. "<category>" .. c.white .. " to list commands\n")
        term.write("       " .. c.cyan .. "help " .. c.yellow .. "<command>" .. c.white .. "  for command help\n")
        return
      end

      local query = args[1]

      -- check if query matches a category
      for _, cat in ipairs(help_categories) do
        if cat.id == query then
          term.write(c.green .. cat.label .. ":" .. c.white .. "\n")
          -- collect unique commands in this category
          local seen = {}
          local cmds = {}
          for _, def in pairs(sh.commands) do
            if not seen[def] and def.category == cat.id then
              seen[def] = true
              table.insert(cmds, def)
            end
          end
          table.sort(cmds, function(a, b) return a.name < b.name end)
          for _, def in ipairs(cmds) do
            term.write(" " .. def.help .. "\n")
          end
          return
        end
      end

      -- check if query matches a command
      local def = sh.commands[query]
      if not def then
        return sh:error("Unknown command or category: " .. query)
      end

      term.write(def.help .. "\n")
      if #def.aliases > 0 then
        term.write("  aliases: " .. table.concat(def.aliases, ", ") .. "\n")
      end
      if def.long then
        term.write(def.long .. "\n")
      end
    end
  },

  -- exit: exit the shell
  {
    name = "exit",
    aliases = {"quit", "q"},
    category = "core",
    desc = "exit the shell",
    run = function(args, sh)
      term.write("Exiting shell...\n")
      sh.running = false
    end
  },

  -- ls: List directory contents
  {
    name = "ls",
    aliases = {"dir", "list"},
    category = "core",
    usage = "[-l] [dir]",
    desc = "list directory contents",
    long = "Two columns when the listing would not fit the screen; -l lists one entry per line with sizes in bytes",
    flags = "l",
    args = "dir?=.",
    pager = true,
    run = function(args, sh)
      term.write(c.green.."-----------------------------------"..c.white.."\n")
      term.write(c.green.." " .. args.abs[1] ..c.white..":\n")
      term.write("\n")
      sh:print_dir(fs.list(args.v[1]), args.flags.l)
    end
  },

  -- cd: change directory
  {
    name = "cd",
    category = "core",
    usage = "[dir|..|-]",
    desc = "change directory",
    args = "dir?=/",
    run = function(args, sh)
      sh:change_dir(args[1])
    end
  },

  -- pwd: print working directory
  {
    name = "pwd",
    aliases = {"cwd"},
    category = "core",
    desc = "print current directory",
    run = function(args, sh)
      term.write(sh.cwd .. "\n")
    end
  },

  -- cat: display file contents
  {
    name = "cat",
    aliases = {"type"},
    category = "core",
    usage = "<file>",
    desc = "display file contents",
    args = "file",
    pager = true,
    run = function(args)
      local f <close> = fs.open(args.v[1], "r")

      -- smaller reads leave room for the Wi-Fi stack's buffers
      local block_size = wifi.isConnected() and 4096 or 16384
      local block = f:read(block_size)
      while block ~= nil do
        term.write(block)
        block = f:read(block_size)
      end
      term.write("\n")
    end
  },

  -- edit: open file in editor
  {
    name = "edit",
    aliases = {"vi", "nano"},
    category = "core",
    usage = "<file>",
    desc = "open file in editor",
    args = "path",
    run = function(args, sh)
      local fspath = args.v[1]

      if fs.exists(fspath) then
        if fs.isDir(fspath) then
          return sh:error("'" .. args[1] .. "' is a directory")
        end
        edit(fspath)
        return
      end

      -- create new file?
      local ans = term.read("Create new file ".. c.green .. fspath .. c.white .. " ? y/[N]: ")
      if ans ~= "y" then
        term.write("Ok, not created.\n")
        return
      end

      local f = fs.open(fspath, "w+")
      f:close()
      edit(fspath)
    end
  },

  -- rm: delete file
  {
    name = "rm",
    aliases = {"del", "delete"},
    category = "core",
    usage = "<file>",
    desc = "delete file",
    args = "file",
    run = function(args, sh)
      fs.delete(args.v[1])
      sh:success("Deleted '" .. args[1] .. "'")
    end
  },

  -- mkdir: create directory
  {
    name = "mkdir",
    category = "core",
    usage = "<dir>",
    desc = "create directory",
    args = "newpath",
    run = function(args, sh)
      local fspath, path = args.v[1], args.abs[1]

      fs.makeDir(fspath)
      if fs.exists(fspath) then
        sh:success("Created '" .. path .. "'")
      else
        return sh:error("Failed to create '" .. path .. "'")
      end
    end
  },

  -- rmdir: delete directory (if empty), or recursively with -f
  {
    name = "rmdir",
    category = "core",
    usage = "[-f] <dir>",
    desc = "remove directory (-f = force recursive)",
    flags = "f",
    args = "dir",
    run = function(args, sh)
      local fspath, path = args.v[1], args.abs[1]

      if sh:is_root(path) then
        return sh:error("Cannot remove the root directory")
      end

      if args.flags.f then
        local ans = term.read("Delete '" .. path .. "' and ALL contents? y/[N]: ")
        ans = ans and ans:lower() or ""
        if ans ~= "y" then
          return term.write("Cancelled.\n")
        end

        -- recursive delete: depth-first
        local function rm_recursive(p)
          local items = fs.list(p)
          if items then
            for _, item in ipairs(items) do
              local child = p .. "/" .. item.name
              if item.isDir then
                rm_recursive(child)
              else
                fs.delete(child)
              end
            end
          end
          fs.delete(p)
        end

        rm_recursive(fspath)
      else
        -- check if empty
        local entries = fs.list(fspath)
        if entries and #entries > 0 then
          return sh:error("Directory not empty (use -f to force)")
        end

        fs.delete(fspath)
      end

      if not fs.exists(fspath) then
        return sh:success("Removed '" .. path .. "'")
      else
        return sh:error("Failed. Directory '" .. path .. "' still exists.")
      end
    end
  },

  -- mv: move/rename file
  {
    name = "mv",
    aliases = {"rename", "ren"},
    category = "core",
    usage = "<src> <dst>",
    desc = "move or rename file",
    args = "entry newpath",
    run = function(args, sh)
      local ok, err = pcall(fs.move, args.v[1], args.v[2])
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
    category = "core",
    usage = "<source> <dest>",
    desc = "copy file",
    args = "file newpath",
    run = function(args, sh)
      local sf <close> = fs.open(args.v[1], "r")
      local df <close> = fs.open(args.v[2], "w")

      -- smaller reads leave room for the Wi-Fi stack's buffers
      local block_size = wifi.isConnected() and 4096 or 16384
      local block = sf:read(block_size)
      local bytes_copied = 0
      local blocks_copied = 0
      while block ~= nil do
        df:write(block)
        df:flush()
        bytes_copied = bytes_copied + #block
        blocks_copied = blocks_copied + 1
        local x, y = term.getCursorPos()
        term.setCursorPos(1, y+1)
        term.write("Bytes copied: " .. bytes_copied)
        if blocks_copied % 100 == 0 then
          term.write(" (freeMemory: " .. sys.freeMemory() .. ")")
        end
        block = sf:read(block_size)
      end

      sh:success("\nCopied '" .. args[1] .. "' to '" .. args[2] .. "'")
    end
  },

  -- eval: execute Lua code
  {
    name = "eval",
    aliases = {"lua"},
    category = "core",
    usage = "<lua code>",
    desc = "execute Lua code",
    run = function(args, sh, raw_input)
      -- Extract raw code after command name to preserve quotes
      local code = raw_input and raw_input:match("^%s*%S+%s+(.+)$")
      if not code or code == "" then
        return sh:usage("eval")
      end

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
    aliases = {"dofile", "exec"},
    category = "core",
    usage = "<file.lua>",
    desc = "execute Lua script",
    args = "file",
    run = function(args)
      dofile(args.v[1])
    end
  },

  -- clear: clear screen
  {
    name = "clear",
    aliases = {"cls"},
    category = "core",
    desc = "clear the screen",
    run = function(args, sh)
      term.clear()
    end
  },

  -- history: show command history
  {
    name = "history",
    aliases = {"hist"},
    category = "core",
    usage = "[n]",
    desc = "show command history [last n entries]",
    args = "number?",
    pager = true,
    run = function(args, sh)
      local count = args.v[1] or #readline.history
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
    category = "util",
    desc = "show system information",
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
          if info then
            term.write(c.cyan .. "       SSID:  " .. c.white .. info.ssid .. "\n")
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
    category = "util",
    desc = "show battery info",
    run = function(args, sh)
      local batt = sys.battery()
      term.write(c.cyan .. "Battery: " .. c.white .. batt .. " %\n")
    end
  },

  -- reload: reload external comands to update changes
  {
    name = "reload",
    category = "core",
    desc = "reload external commands",
    run = function(args, sh)
      sh:load_external_commands()
      term.write("External commands reloaded.\n")
    end
  },
}

-- main: setup and loop

local function main()
  shell:apply_gc()

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
  term.write(c.green .. "PicoCalc Lua Shell" .. c.white .. " -- " .. c.blue .. _VERSION .. c.white .. "\n")
  term.write("Type '" .. c.cyan .. "help" .. c.white .. "' for commands\n")
  collectgarbage()

  -- loop until 'exit' sets shell.running to false 
  while shell.running do
    local input = shell:prompt()

    if input and input ~= "" then
      -- add to history
      readline.add_history(input)

      local cmd, args = shell:parse_input(input)
      shell:execute(cmd, args, input)
    end
  end

  -- save command history on exit
  readline.save_history(shell.config.history_file)
end

-- send it!
main()
