--[[
  tail.lua - display the last few lines of a file
]]

return {
  name = "tail",
  category = "util",
  usage = "<file> [n]",
  desc = "print last n lines [default 10]",
  args = "file number?",
  run = function(args)
    local num_lines = args.v[2] or 10
    local f <close> = fs.open(args.v[1], "r")

    -- assumes lines average under 80 bytes; longer lines yield fewer than n
    f:seek("end", -80 * num_lines)
    local lines = {}
    while true do
      local line = f:readLine()
      if not line then
        break
      end
      table.insert(lines, line)
    end

    for i = math.max(1, #lines - num_lines + 1), #lines do
      print(lines[i])
    end
  end
}
