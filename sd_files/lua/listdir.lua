-- test listing directory contents

local dir = fs.list("/lua")
for _, v in pairs(dir) do
    if v.isDir then
        print("\27[93mD: "..v.name.."/\27[97m")
    else
        print("   "..v.name..", ("..v.size..")")
    end
end
