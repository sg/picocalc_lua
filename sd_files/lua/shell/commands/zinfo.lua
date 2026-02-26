-- Z-Machine File Info Command
-- Display information about Z-machine story files

local c = require("lua/modules/simple-colors")

return {
    name = "zinfo",
    category = "games",
    aliases = {},
    help = c.cyan .. "zinfo" .. c.yellow .. " <story_file>" .. c.white .. " - show info for z-story_file",

    run = function(args, sh)
        if #args == 0 then
            return sh:error("Usage: zinfo <story-file>")
        end

        local filepath = sh:resolve_path(args[1])
        local fs_path = sh:fs_path(filepath)

        -- Check file exists
        if not fs.exists(fs_path) then
            local extensions = {".z3", ".z4", ".z5", ".z8", ".z1", ".z2", ".z6", ".z7"}
            local found = false
            for _, ext in ipairs(extensions) do
                if fs.exists(fs_path .. ext) then
                    fs_path = fs_path .. ext
                    found = true
                    break
                end
            end
            if not found then
                return sh:error("File not found: " .. args[1])
            end
        end

        local zmachine = require("lua/zmachine/init")
        local info, err = zmachine.info(fs_path)

        package.loaded["lua/zmachine/init"] = nil
        package.loaded["lua/zmachine/memory"] = nil
        collectgarbage("collect")

        if not info then
            return sh:error("Cannot read story: " .. (err or "unknown"))
        end

        print("Z-Machine Story File Information")
        print("=================================")
        print(string.format("File:          %s", fs_path))
        print(string.format("Version:       Z%d", info.version))
        print(string.format("Release:       %d", info.release))
        print(string.format("Serial:        %s", info.serial))
        print(string.format("Story size:    %d bytes (%.1f KB)", info.story_size, info.story_size / 1024))
        print(string.format("Dynamic mem:   %d bytes (%.1f KB)", info.dynamic_size, info.dynamic_size / 1024))
        print("")
        print("Memory Layout:")
        print(string.format("  Static base: 0x%04X", info.static_base))
        print(string.format("  High memory: 0x%04X", info.himem))
        print(string.format("  Initial PC:  0x%04X", info.initial_pc))
        print(string.format("  Dictionary:  0x%04X", info.dictionary))
        print(string.format("  Objects:     0x%04X", info.object_table))
        print(string.format("  Globals:     0x%04X", info.globals))

        -- Version-specific info
        if info.version <= 3 then
            print("")
            print("This is a classic V3 game (Zork-era).")
            print("Supports: Status line, basic I/O, save/restore")
        elseif info.version <= 5 then
            print("")
            print("This is an enhanced V" .. info.version .. " game.")
            print("Supports: Split windows, undo, timed input")
        end
    end
}
