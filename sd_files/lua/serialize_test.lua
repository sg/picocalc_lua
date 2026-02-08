local serialize = require("lua/modules/serialize")

local t = {
           ["a"] = "foo",
           ["b"] = 2,
           ["new york"] = {lat = "30.25", lon = "-97.75",},
           ["los angeles"] = {lat = "50.55", lon = "-90.75",},
          }
local s = serialize.toString(t)
print(s)
