-- BotWarz menu, bot selection and help screens

local M = {}

local config = nil
local render = nil
local state = nil

function M.init(cfg, rnd, game_state)
    config = cfg
    render = rnd
    state = game_state
end

local function draw_avatars()
    local pts = {}
    for i, name in ipairs(config.SHAPE_NAMES) do
        local shape = config.SHAPES[name]
        local cx = 60 + ((i - 1) % 3) * 100
        local cy = 150 + ((i - 1) // 3) * 90
        local color = (i % 2 == 1) and config.COLOR_BOT1 or config.COLOR_BOT2
        for k = 1, #shape, 2 do
            pts[k], pts[k + 1] = cx + shape[k] * 2, cy + shape[k + 1] * 2
        end
        -- draw.polygon goes by the table's length, and the outlines differ in theirs
        for k = #pts, #shape + 1, -1 do pts[k] = nil end
        draw.polygon(pts, color)
        draw.line(cx, cy - 6, cx, cy - config.BARREL_LENGTH * 2, color)
        draw.text(cx, cy + 30, name, config.COLOR_TEXT, config.COLOR_BG, draw.align_center)
    end
end

local function help_pages()
    return {
        {
            title = "HOW TO PLAY",
            "BotWarz is a battle game where",
            "Lua-scripted bots fight each other.",
            "",
            "A bot is a script in lua/botwarz/bots/",
            "that sets bot.name and defines bot.tick(),",
            "which is run 20 times a second.",
            "",
            "During a match:",
            "  S    change how scans are shown",
            "  ESC  leave the match",
            "",
            "The bars at the top show each bot's health.",
            "ERR marks a bot whose script has failed;",
            "lua/botwarz/debug.log says how.",
            "",
            "The whole API is described in lua/botwarz.md",
        },
        {
            title = "BOT API",
            "bot.drive(speed)        -2 to 5",
            "bot.turn(degrees)       10 a tick at most",
            "bot.turnTo(angle)       0 is up, clockwise",
            "bot.stop()",
            "bot.scan(arc)           ahead; gives distance,",
            "bot.scanAt(angle, arc)    angle, heading, speed",
            "bot.detectShot()        nearest incoming shot",
            "bot.wallDistance(angle)",
            "bot.fire()     bot.fireAt(angle)",
            "bot.missile()  bot.missileAt(angle)",
            "bot.canFire()  bot.canMissile()",
            "bot.getPosition()  bot.getHeading()",
            "bot.getHealth()    bot.getEnergy()",
            "",
            "Handlers a bot may define:",
            "bot.init()  bot.onWall()",
            "bot.onHit(direction, damage)",
            "bot.onCollision(direction)",
            "bot.onScanned(direction)",
            "bot.onShotHit(name, damage)  bot.onKill(name)",
        },
        {
            title = "AVATARS",
            avatars = true,
            "A bot picks its outline by name:",
            "",
            "    bot.shape = \"tank\"",
        },
    }
end

function M.show_help()
    local pages = help_pages()
    for n, page in ipairs(pages) do
        term.clear()
        draw.text(config.SCREEN_WIDTH / 2, 20, page.title, colors.cyan, config.COLOR_BG, draw.align_center)
        for i, line in ipairs(page) do
            draw.text(10, 35 + i * 12, line, config.COLOR_TEXT, config.COLOR_BG)
        end
        if page.avatars then draw_avatars() end
        local prompt = n < #pages and "Any key: next page   ESC: menu" or "Press any key to return..."
        draw.text(config.SCREEN_WIDTH / 2, config.SCREEN_HEIGHT - 14, prompt, config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)

        local _, _, code = keys.wait(true)
        if code == keys.esc then return end
    end
end

function M.draw_menu()
    term.clear()

    draw.text(config.SCREEN_WIDTH / 2, 40, "BOTWARZ", colors.cyan, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 60, "Robot Arena Battle", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)

    local start_y = 120
    for i, item in ipairs(state.menu_items) do
        local color = (i == state.menu_selection) and colors.yellow or config.COLOR_TEXT
        local prefix = (i == state.menu_selection) and "> " or "  "
        draw.text(config.SCREEN_WIDTH / 2, start_y + (i - 1) * 25, prefix .. item, color, config.COLOR_BG, draw.align_center)
    end

    draw.text(5, config.SCREEN_HEIGHT - 20, "Mem: " .. render.get_memory_kb() .. "KB", config.COLOR_DIM_TEXT, config.COLOR_BG)
end

function M.menu_input()
    local key_state, _, code = keys.poll()

    if key_state == keys.states.pressed then
        if code == keys.up then
            state.menu_selection = state.menu_selection - 1
            if state.menu_selection < 1 then state.menu_selection = #state.menu_items end
            M.draw_menu()
        elseif code == keys.down then
            state.menu_selection = state.menu_selection + 1
            if state.menu_selection > #state.menu_items then state.menu_selection = 1 end
            M.draw_menu()
        elseif code == keys.enter then
            if state.menu_selection == 1 then
                state.available_bots = state.scan_bot_files()
                if #state.available_bots < 2 then
                    term.clear()
                    draw.text(config.SCREEN_WIDTH/2, 100, "Need at least 2 bot files", colors.red, config.COLOR_BG, draw.align_center)
                    draw.text(config.SCREEN_WIDTH/2, 130, "in botwarz/bots/", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)
                    draw.text(config.SCREEN_WIDTH/2, 180, "Press any key...", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
                    keys.wait(true)
                    M.draw_menu()
                else
                    state.game_state = "select"
                    state.select_slot = 1
                    state.selected_bots = {1, 2}
                    M.draw_select_screen()
                end
            elseif state.menu_selection == 2 then
                M.show_help()
                M.draw_menu()
            elseif state.menu_selection == 3 then
                state.quit_game = true
            end
        elseif code == keys.esc then
            state.quit_game = true
        end
    end
end

function M.draw_select_screen()
    term.clear()

    draw.text(config.SCREEN_WIDTH / 2, 20, "SELECT BOTS", colors.cyan, config.COLOR_BG, draw.align_center)

    local color1 = (state.select_slot == 1) and colors.yellow or config.COLOR_TEXT
    draw.text(20, 50, "Bot 1:", color1, config.COLOR_BG)
    local bot1_name = state.available_bots[state.selected_bots[1]] or "???"
    draw.text(80, 50, "< " .. bot1_name .. " >", config.COLOR_BOT1, config.COLOR_BG)

    local color2 = (state.select_slot == 2) and colors.yellow or config.COLOR_TEXT
    draw.text(20, 80, "Bot 2:", color2, config.COLOR_BG)
    local bot2_name = state.available_bots[state.selected_bots[2]] or "???"
    draw.text(80, 80, "< " .. bot2_name .. " >", config.COLOR_BOT2, config.COLOR_BG)

    draw.text(config.SCREEN_WIDTH / 2, 130, "UP/DOWN: Select slot", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 150, "LEFT/RIGHT: Change bot", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 170, "ENTER: Start match", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 190, "ESC: Back to menu", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)

    draw.text(20, 220, "Available bots:", config.COLOR_TEXT, config.COLOR_BG)
    local y = 240
    for _, name in ipairs(state.available_bots) do
        if y < config.SCREEN_HEIGHT - 30 then
            draw.text(30, y, name, config.COLOR_DIM_TEXT, config.COLOR_BG)
            y = y + 15
        end
    end

    draw.text(5, config.SCREEN_HEIGHT - 15, "Mem: " .. render.get_memory_kb() .. "KB", config.COLOR_DIM_TEXT, config.COLOR_BG)
end

function M.select_input()
    local key_state, _, code = keys.poll()

    if key_state == keys.states.pressed then
        if code == keys.up then
            state.select_slot = 1
            M.draw_select_screen()
        elseif code == keys.down then
            state.select_slot = 2
            M.draw_select_screen()
        elseif code == keys.left then
            state.selected_bots[state.select_slot] = state.selected_bots[state.select_slot] - 1
            if state.selected_bots[state.select_slot] < 1 then
                state.selected_bots[state.select_slot] = #state.available_bots
            end
            M.draw_select_screen()
        elseif code == keys.right then
            state.selected_bots[state.select_slot] = state.selected_bots[state.select_slot] + 1
            if state.selected_bots[state.select_slot] > #state.available_bots then
                state.selected_bots[state.select_slot] = 1
            end
            M.draw_select_screen()
        elseif code == keys.enter then
            state.init_match()
        elseif code == keys.esc then
            state.game_state = "menu"
            M.draw_menu()
        end
    end
end

return M
