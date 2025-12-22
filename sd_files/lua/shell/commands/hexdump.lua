--[[
    hexdump.lua - Display file in hexadecimal
    External command for shell.lua
]]

return {
    name = "hexdump",
    aliases = {"xxd", "hd"},
    help = "'hexdump <file> [bytes]' - display file in hex (default 256 bytes)",
    run = function(args, sh)
        if not args[1] then
            return sh:error("Usage: hexdump <file> [max_bytes]")
        end

        local path = sh:resolve_path(args[1])
        local fspath = sh:fs_path(path)
        local max_bytes = tonumber(args[2]) or 256

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

        if not content then
            print("(empty file)")
            return
        end

        local len = math.min(#content, max_bytes)
        local offset = 0

        while offset < len do
            -- Address
            local line = string.format("%08x  ", offset)

            -- Hex bytes
            local hex_part = ""
            local ascii_part = ""

            for i = 0, 15 do
                local pos = offset + i + 1
                if pos <= len then
                    local byte = string.byte(content, pos)
                    hex_part = hex_part .. string.format("%02x ", byte)

                    -- ASCII representation
                    if byte >= 32 and byte < 127 then
                        ascii_part = ascii_part .. string.char(byte)
                    else
                        ascii_part = ascii_part .. "."
                    end
                else
                    hex_part = hex_part .. "   "
                    ascii_part = ascii_part .. " "
                end

                -- Add extra space in middle
                if i == 7 then
                    hex_part = hex_part .. " "
                end
            end

            print(line .. hex_part .. " |" .. ascii_part .. "|")
            offset = offset + 16
        end

        if #content > max_bytes then
            print(string.format("... (%d more bytes)", #content - max_bytes))
        end

        print(string.format("\nTotal: %d bytes", #content))
    end
}
