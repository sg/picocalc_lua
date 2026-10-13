--[[

  tar.lua - Create, extract, and list tar archives

  Supports UStar format. Streams data in small blocks
  to minimize memory usage on embedded systems.

  Usage:
    tar c <archive> <file1> [file2] ...  - create archive
    tar x <archive> [dir]                - extract archive
    tar t <archive>                      - list contents

]]

local c = require("lua/modules/simple-colors")
local gzip = _G.gzip  -- nil if firmware doesn't include gzip module

local BLOCK = 512
local ZERO_BLOCK = string.rep("\0", BLOCK)
local READ_SIZE = 4096

-- UStar header layout shared by the writer and the reader:
-- name mode uid gid size mtime chksum type linkname magic
-- version uname gname devmajor devminor prefix pad
local HEADER_FMT = "c100 c8 c8 c8 c12 c12 c8 c1 c100 c6 c2 c32 c32 c8 c8 c155 c12"
assert(string.packsize(HEADER_FMT) == BLOCK)

-- text before the first NUL of a fixed-width field
local function cstring(s)
  return (s:match("^[^\0]*"))
end

-- decode octal field to number
local function from_octal(s)
  s = cstring(s):gsub("[%s]+$", "")
  if s == "" then return 0 end
  return tonumber(s, 8) or 0
end

-- compute tar header checksum
-- all 512 bytes are summed as unsigned values, with the
-- 8-byte checksum field (offset 148-155) treated as spaces
local function calc_checksum(hdr)
  local sum = 0
  for i = 1, BLOCK do
    if i >= 149 and i <= 156 then
      sum = sum + 32
    else
      sum = sum + string.byte(hdr, i)
    end
  end
  return sum
end

-- build a 512-byte UStar header block; nil, err if the name cannot fit
local function make_header(name, size, is_dir)
  if is_dir and name:sub(-1) ~= "/" then
    name = name .. "/"
  end

  -- split long names using prefix field (155) + name (100)
  local prefix = ""
  if #name > 100 then
    local split
    for i = math.max(1, #name - 99), math.min(#name, 155) do
      if name:sub(i, i) == "/" then split = i end
    end
    if not split then
      return nil, "Name too long for tar: " .. name
    end
    prefix = name:sub(1, split - 1)
    name = name:sub(split + 1)
  end

  -- pack zero-fills every field; octal fields leave room for their NUL
  local function build(checksum)
    return HEADER_FMT:pack(
      name,
      is_dir and "0000755" or "0000644",
      "0000000", "0000000",
      string.format("%011o", is_dir and 0 or size),
      "00000000000",
      checksum,
      is_dir and "5" or "0",
      "",
      "ustar", "00",
      "", "",
      "0000000", "0000000",
      prefix,
      "")
  end

  -- the checksum is computed over the header with its own field blank
  local hdr = build("        ")
  return build(string.format("%06o\0 ", calc_checksum(hdr)))
end

-- parse a 512-byte header block
-- returns table with name, size, is_dir, valid; or nil at end-of-archive
local function parse_header(block)
  if block == ZERO_BLOCK then return nil end

  local name, _, _, _, size, _, checksum, typeflag, _, _, _, _, _, _, _, prefix
    = HEADER_FMT:unpack(block)

  name = cstring(name)
  if name == "" then return nil end

  prefix = cstring(prefix)
  if prefix ~= "" then
    name = prefix .. "/" .. name
  end

  return {
    name = name,
    size = from_octal(size),
    is_dir = typeflag == "5" or name:sub(-1) == "/",
    valid = from_octal(checksum) == calc_checksum(block),
  }
end

-- create all directories along a path
local function mkdirs(path)
  path = path:gsub("/+$", "")
  if path == "" then return end
  local accum = ""
  for part in path:gmatch("[^/]+") do
    accum = accum == "" and part or (accum .. "/" .. part)
    if not fs.exists(accum) then
      fs.makeDir(accum)
    end
  end
end

-- get parent directory of a file path
local function parent_of(path)
  return path:match("^(.+)/[^/]+$")
end

-- write a single file's data to the archive in streaming chunks
-- runs GC every 16KB to prevent dead string accumulation
-- (aggressive due to heap fragmentation when WiFi is active)
local function write_file_data(out, fspath, size)
  local f = fs.open(fspath, "r")
  if not f then return false, "Cannot read: " .. fspath end

  local rem = size
  while rem > 0 do
    local data = f:read(math.min(READ_SIZE, rem))
    if not data then break end
    out:write(data)
    rem = rem - #data
  end
  f:close()

  -- null-pad to block boundary
  local tail = size % BLOCK
  if tail > 0 then
    out:write(string.rep("\0", BLOCK - tail))
  end

  return true
end

-- recursively walk directory tree and write entries directly to archive
-- streams one entry at a time instead of collecting the full tree first
local function walk_and_write(out, fspath, arcname, sh)
  local count = 0

  if fs.isDir(fspath) then
    -- write directory header
    local hdr, err = make_header(arcname .. "/", 0, true)
    if not hdr then return nil, err end
    out:write(hdr)
    term.write("  " .. c.yellow .. arcname .. "/" .. c.white .. "\n")
    count = 1

    -- list and recurse into children
    local items = fs.list(fspath)
    if items then
      table.sort(items, function(a, b) return a.name < b.name end)
      for _, item in ipairs(items) do
        local child_fs = fspath == "" and item.name
          or (fspath .. "/" .. item.name)
        local n, err = walk_and_write(out, child_fs,
          arcname .. "/" .. item.name, sh)
        if not n then return nil, err end
        count = count + n
      end
    end
  else
    -- write file header + data
    local size = fs.getSize(fspath) or 0
    local hdr, err = make_header(arcname, size, false)
    if not hdr then return nil, err end
    out:write(hdr)

    if size > 0 then
      local ok, err = write_file_data(out, fspath, size)
      if not ok then return nil, err end
    end

    term.write("  " .. arcname .. "\n")
    count = 1
  end

  return count
end

------------------------------------------------------------
-- TAR CREATE
------------------------------------------------------------
local function tar_create(archive_fs, sources, sh)
  local out = fs.open(archive_fs, "w")
  if not out then return sh:error("Cannot create: " .. archive_fs) end

  local total = 0

  for _, src in ipairs(sources) do
    local count, err = walk_and_write(out, src.fspath, src.name, sh)
    if not count then
      out:close()
      return sh:error(err)
    end
    total = total + count
  end

  -- end-of-archive marker: two zero blocks
  out:write(ZERO_BLOCK)
  out:write(ZERO_BLOCK)
  out:flush()
  out:close()

  sh:success(string.format("Created archive: %d entries", total))
end

------------------------------------------------------------
-- TAR EXTRACT
------------------------------------------------------------
-- skip past a file entry's data blocks in the archive
local function skip_data(f, size)
  if size > 0 then
    local blocks = math.ceil(size / BLOCK)
    f:seek("cur", blocks * BLOCK)
  end
end

local function tar_extract(archive_fs, dest, sh)
  local is_gz = archive_fs:match("%.tar%.gz$") or archive_fs:match("%.tgz$")
  local f
  if is_gz then
    if not gzip then
      return sh:error("gzip module not available (firmware update required)")
    end
    f = gzip.open(archive_fs)
  else
    f = fs.open(archive_fs, "r")
  end
  if not f then return sh:error("Cannot open: " .. archive_fs) end

  local count = 0
  local skipped = 0
  local overwrite_all = false

  while true do
    local block = f:read(BLOCK)
    if not block or #block < BLOCK then break end

    local h = parse_header(block)
    if not h then break end
    if not h.valid then
      f:close()
      return sh:error("Bad checksum: " .. h.name)
    end

    -- build output path relative to dest
    local out_path = dest == "" and h.name or (dest .. "/" .. h.name)
    local clean = out_path:gsub("/+$", "")

    if h.is_dir then
      mkdirs(clean)
      term.write("  " .. c.yellow .. h.name .. c.white .. "\n")
    else
      -- check if file already exists
      if not overwrite_all and fs.exists(clean) then
        local ans = term.read("  " .. c.red .. "Overwrite " .. c.white
          .. h.name .. "? [y/n/All]: ")
        ans = ans and ans:lower() or "n"
        if ans == "a" or ans == "all" then
          overwrite_all = true
        elseif ans ~= "y" then
          skip_data(f, h.size)
          term.write("  " .. c.dim .. h.name .. " (skipped)" .. c.reset .. "\n")
          skipped = skipped + 1
          goto continue
        end
      end

      -- ensure parent directories exist
      local par = parent_of(clean)
      if par then mkdirs(par) end

      local out = fs.open(clean, "w")
      if not out then
        f:close()
        return sh:error("Cannot create: " .. clean)
      end

      local rem = h.size
      while rem > 0 do
        local data = f:read(math.min(READ_SIZE, rem))
        if not data then break end
        out:write(data)
        rem = rem - #data
      end
      out:flush()
      out:close()

      -- skip past block padding
      local tail = h.size % BLOCK
      if tail > 0 then
        f:seek("cur", BLOCK - tail)
      end

      term.write("  " .. h.name .. "\n")
    end

    count = count + 1
    ::continue::
  end

  f:close()
  local msg = string.format("Extracted %d entries", count)
  if skipped > 0 then
    msg = msg .. string.format(", %d skipped", skipped)
  end
  sh:success(msg)
end

------------------------------------------------------------
-- TAR LIST
------------------------------------------------------------
local function tar_list(archive_fs, sh)
  local is_gz = archive_fs:match("%.tar%.gz$") or archive_fs:match("%.tgz$")
  local f
  if is_gz then
    if not gzip then
      return sh:error("gzip module not available (firmware update required)")
    end
    f = gzip.open(archive_fs)
  else
    f = fs.open(archive_fs, "r")
  end
  if not f then return sh:error("Cannot open: " .. archive_fs) end

  local count = 0
  local total = 0

  while true do
    local block = f:read(BLOCK)
    if not block or #block < BLOCK then break end

    local h = parse_header(block)
    if not h then break end

    if h.is_dir then
      term.write("   <DIR>  " .. h.name .. "\n")
    else
      term.write(string.format("%8d  %s\n", h.size, h.name))
    end

    -- skip data blocks
    if h.size > 0 then
      local blocks = math.ceil(h.size / BLOCK)
      f:seek("cur", blocks * BLOCK)
    end

    count = count + 1
    total = total + h.size
  end

  f:close()
  term.write(string.format("\n%d entries, %d bytes total\n", count, total))
end

------------------------------------------------------------
-- COMMAND ENTRY POINT
------------------------------------------------------------
return {
  name = "tar",
  category = "util",
  usage = "<c|x|t> <archive> [files...]",
  desc = "tar archive tool",
  long = "  tar c <archive> <file1> [file2] ...  create\n"
    .. "  tar x <archive> [dir]                extract\n"
    .. "  tar t <archive>                      list",
  complete = "path",
  run = function(args, sh)
    if #args < 2 then
      term.write("Usage:\n")
      term.write("  " .. c.cyan .. "tar c" .. c.yellow
        .. " <archive> <file1> [file2] ..." .. c.white .. " - create\n")
      term.write("  " .. c.cyan .. "tar x" .. c.yellow
        .. " <archive> [dir]" .. c.white .. "              - extract\n")
      term.write("  " .. c.cyan .. "tar t" .. c.yellow
        .. " <archive>" .. c.white .. "                    - list\n")
      return
    end

    local op = args[1]
    local archive_fs = sh:fs_path(sh:resolve_path(args[2]))

    if op == "c" or op == "create" then
      -- need at least one source file/dir
      if #args < 3 then
        return sh:error("Usage: tar c <archive> <file1> [file2] ...")
      end

      -- resolve each source: fspath for I/O, name for archive entry
      local sources = {}
      for i = 3, #args do
        local fspath = sh:fs_path(sh:resolve_path(args[i]))
        if not fs.exists(fspath) then
          return sh:error("Not found: " .. args[i])
        end
        -- use the resolved fs path as the archive name (relative to root)
        -- strip trailing slashes for a clean base name
        local name = fspath:gsub("/+$", "")
        table.insert(sources, { fspath = fspath, name = name })
      end

      tar_create(archive_fs, sources, sh)

    elseif op == "x" or op == "extract" then
      if not fs.exists(archive_fs) then
        return sh:error("Not found: " .. args[2])
      end

      -- destination directory: explicit arg or cwd
      local dest
      if args[3] then
        local abs = sh:resolve_path(args[3])
        dest = sh:fs_path(abs)
        -- the root cannot be stat'ed or created, only used
        if not sh:is_root(abs) and not fs.exists(dest) then
          fs.makeDir(dest)
        end
      else
        dest = sh:fs_path(sh.cwd)
      end

      tar_extract(archive_fs, dest, sh)

    elseif op == "t" or op == "list" then
      if not fs.exists(archive_fs) then
        return sh:error("Not found: " .. args[2])
      end

      tar_list(archive_fs, sh)

    else
      return sh:error("Unknown operation: " .. op .. " (use c, x, or t)")
    end
  end
}
