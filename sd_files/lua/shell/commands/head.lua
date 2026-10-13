--[[

  head.lua - display first few lines of a file

]]

return {
  name = "head",
  category = "util",
  usage = "<file> [n]",
  desc = "print top n lines of a file",
  args = "file number?",
  pager = true,
  run = function(args)
    local f <close> = fs.open(args.v[1], "r")

    for _ = 1, args.v[2] or 10 do
      local line = f:readLine()
      if not line then
        break
      end
      print(line)
    end
  end
}
