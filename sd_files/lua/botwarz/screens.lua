-- BotWarz Screens Module
-- Menu, selection, help, and results screens

local M = {}

-- Module-local references (set via init)
local config = nil
local render = nil
local state = nil  -- shared game state

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function M.init(cfg, rnd, game_state)
    config = cfg
    render = rnd
    state = game_state
end

-- =============================================================================
-- HELP SCREEN
-- =============================================================================

function M.show_help()
    term.clear()
    draw.text(config.SCREEN_WIDTH / 2, 20, "HOW TO PLAY", colors.cyan, config.COLOR_BG, draw.align_center)

    local help_text = {
        "BotWarz is a battle game where",
        "Lua-scripted bots fight each other.",
        "",
        "Bot scripts go in: botwarz/bots/",
        "",
        "Bot API functions:",
        "  bot.drive(speed)  - Set speed 0-5",
        "  bot.turn(deg)     - Turn relative",
        "  bot.turnTo(ang)   - Turn to angle",
        "  bot.scan(arc)     - Scan for enemies",
        "  bot.fire()        - Fire cannon",
        "  bot.getPosition() - Get x, y",
        "  bot.getHeading()  - Get angle",
        "",
        "Press any key to return..."
    }

    for i, line in ipairs(help_text) do
        draw.text(10, 35 + i * 12, line, config.COLOR_TEXT, config.COLOR_BG)
    end

    keys.wait()
end

-- =============================================================================
-- MENU SCREEN
-- =============================================================================

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
                -- Go to bot selection
                state.available_bots = state.scan_bot_files()
                if #state.available_bots < 2 then
                    term.clear()
                    draw.text(config.SCREEN_WIDTH/2, 100, "Need at least 2 bot files", colors.red, config.COLOR_BG, draw.align_center)
                    draw.text(config.SCREEN_WIDTH/2, 130, "in botwarz/bots/", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)
                    draw.text(config.SCREEN_WIDTH/2, 180, "Press any key...", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
                    keys.wait()
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

-- =============================================================================
-- BOT SELECTION SCREEN
-- =============================================================================

function M.draw_select_screen()
    term.clear()

    draw.text(config.SCREEN_WIDTH / 2, 20, "SELECT BOTS", colors.cyan, config.COLOR_BG, draw.align_center)

    -- Slot 1
    local color1 = (state.select_slot == 1) and colors.yellow or config.COLOR_TEXT
    draw.text(20, 50, "Bot 1:", color1, config.COLOR_BG)
    local bot1_name = state.available_bots[state.selected_bots[1]] or "???"
    draw.text(80, 50, "< " .. bot1_name .. " >", config.COLOR_BOT1, config.COLOR_BG)

    -- Slot 2
    local color2 = (state.select_slot == 2) and colors.yellow or config.COLOR_TEXT
    draw.text(20, 80, "Bot 2:", color2, config.COLOR_BG)
    local bot2_name = state.available_bots[state.selected_bots[2]] or "???"
    draw.text(80, 80, "< " .. bot2_name .. " >", config.COLOR_BOT2, config.COLOR_BG)

    -- Instructions
    draw.text(config.SCREEN_WIDTH / 2, 130, "UP/DOWN: Select slot", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 150, "LEFT/RIGHT: Change bot", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 170, "ENTER: Start match", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 190, "ESC: Back to menu", config.COLOR_DIM_TEXT, config.COLOR_BG, draw.align_center)

    -- Show available bots list
    draw.text(20, 220, "Available bots:", config.COLOR_TEXT, config.COLOR_BG)
    local y = 240
    for i, name in ipairs(state.available_bots) do
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
            -- Start match with selected bots
            state.game_state = "playing"
            state.init_match()
        elseif code == keys.esc then
            state.game_state = "menu"
            M.draw_menu()
        end
    end
end

-- =============================================================================
-- RESULTS SCREEN
-- =============================================================================

function M.draw_results()
    term.clear()
    draw.text(config.SCREEN_WIDTH / 2, 80, "MATCH OVER", colors.cyan, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 120, state.winner_name .. " WINS!", colors.yellow, config.COLOR_BG, draw.align_center)
    draw.text(config.SCREEN_WIDTH / 2, 200, "Press any key...", config.COLOR_TEXT, config.COLOR_BG, draw.align_center)
end

function M.results_input()
    local key_state = keys.poll()
    if key_state == keys.states.pressed then
        state.game_state = "menu"
        M.draw_menu()
    end
end

return M
