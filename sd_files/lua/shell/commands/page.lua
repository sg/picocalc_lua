--[[

  page.lua - view a file with scrolling, like less

  The viewer itself lives in lua/shell/modules/pager.lua,
  which also documents the keys.

]]

return {
  name = "page",
  category = "util",
  aliases = {"less", "more"},
  usage = "<file>",
  desc = "view file with scrolling",
  long = "Keys: Down/Enter line, Space/PageDown page, Up and b/PageUp back, Home, End, q quit",
  args = "file",
  run = function(args)
    local pager = require("lua/shell/modules/pager")

    -- indexing reads the whole file once, which takes a moment for big ones
    print("Indexing file...")
    local store = pager.file_store(args.v[1])
    if store:total() == 0 then
      print("(empty file)")
      return
    end
    pager.view(store)
  end
}
