-- Z-Machine Game Player Shell Command
-- Run interactive fiction games (.z3, .z4, .z5, .z8 files)


return {
    name = "zplay",
    category = "games",
    aliases = {"zork", "zmachine"},
    usage = "<story_file>",
    desc = "run z-machine for <story_file>",
    long = "Supported formats: .z1 through .z8\nExample: zplay zork1.z3",
    args = "path",

    run = function(args, sh)
        local fs_path = args.v[1]

        -- Check file exists
        if not fs.exists(fs_path) then
            -- Try adding common extensions
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

        -- Check extension
        local ext = fs_path:match("%.z(%d)$")
        if not ext then
            return sh:error("Not a Z-machine file (expected .z1 through .z8): " .. args[1])
        end

        -- Show file info first
        local zmachine = require("lua/zmachine/init")
        local info, err = zmachine.info(fs_path)

        if not info then
            return sh:error("Cannot read story file: " .. (err or "unknown error"))
        end

        print(string.format("Story: Release %d / Serial %s", info.release, info.serial))
        print(string.format("Z-machine version %d, %d KB story file", info.version, math.floor(info.story_size / 1024)))
        print("")

        -- Run the game
        local ok, run_err = zmachine.run(fs_path)

        if not ok then
            return sh:error("Game error: " .. (run_err or "unknown"))
        end

        print("\nGame ended.")
    end
}
