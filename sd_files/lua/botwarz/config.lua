-- BotWarz constants, colors and avatar outlines

local M = {}

M.SCREEN_WIDTH = 320
M.SCREEN_HEIGHT = 320

M.ARENA_MARGIN_TOP = 20
M.ARENA_MARGIN_BOTTOM = 20
M.ARENA_MARGIN_SIDE = 20
M.ARENA_X = M.ARENA_MARGIN_SIDE
M.ARENA_Y = M.ARENA_MARGIN_TOP
M.ARENA_WIDTH = M.SCREEN_WIDTH - (M.ARENA_MARGIN_SIDE * 2)
M.ARENA_HEIGHT = M.SCREEN_HEIGHT - M.ARENA_MARGIN_TOP - M.ARENA_MARGIN_BOTTOM

-- colors.black is a dark grey, which shows as a box behind every character on a cleared screen
M.COLOR_BG = colors.fromRGB(0, 0, 0)
M.COLOR_ARENA_BG = colors.fromRGB(0, 0, 32)
M.COLOR_ARENA_BORDER = colors.fromRGB(64, 64, 64)
M.COLOR_TEXT = colors.white
M.COLOR_DIM_TEXT = colors.fromRGB(128, 128, 128)
M.COLOR_BOT1 = colors.fromRGB(0, 255, 0)
M.COLOR_BOT2 = colors.fromRGB(255, 64, 64)
M.COLOR_SPARK = colors.fromRGB(255, 220, 64)

-- opposite corners, each bot side-on to the other
M.STARTS = {
    {x = 50, y = M.ARENA_HEIGHT - 50, heading = 315, color = M.COLOR_BOT1},
    {x = M.ARENA_WIDTH - 50, y = 50, heading = 135, color = M.COLOR_BOT2},
}

M.BOT_RADIUS = 12
M.BOT_MAX_SPEED = 5
M.BOT_MAX_REVERSE = 2
M.BOT_TURN_RATE = 10
M.BOT_WALL_TURN_PENALTY = 0.5
M.BOT_MAX_HEALTH = 100
M.BOT_MAX_ENERGY = 100
M.BOT_ENERGY_REGEN = 2
M.BOT_SCAN_RANGE = 150
M.BOT_SCAN_COST = 1
M.BOT_START_AMMO = 50
M.BOT_START_MISSILES = 3

-- the gun reaches exactly to the collision circle, so neither its tip nor a shot leaving it is ever outside the arena
M.BARREL_LENGTH = M.BOT_RADIUS

-- VM instructions one call into a bot script may run, the API's own included
M.BOT_INSTRUCTION_LIMIT = 5000
M.BOT_LOAD_INSTRUCTION_LIMIT = 20000

M.PROJ_TYPE_CANNON = 1
M.PROJ_TYPE_MISSILE = 2

M.CANNON_DAMAGE = 10
M.CANNON_SPEED = 8
M.CANNON_COOLDOWN = 10
M.CANNON_ENERGY = 5

M.MISSILE_DAMAGE = 25
M.MISSILE_SPEED = 4
M.MISSILE_COOLDOWN = 30
M.MISSILE_ENERGY = 15
M.MISSILE_SPLASH_RADIUS = 20
M.MISSILE_SPLASH_DAMAGE = 5

M.MAX_PROJECTILES = 16

M.TICK_INTERVAL = 0.05

-- draw each frame off screen and show it whole, where there is memory for that; without it shapes are erased and redrawn in place
M.USE_FRAMEBUFFER = true

-- how a scan is shown; S steps through these during a match
M.SCAN_MODES = {"pulse", "sweep", "wedge", "off"}
M.SCAN_DISPLAY = "pulse"
-- brackets around a bot on each tick a scan finds it
M.SCAN_LOCK = true
M.SCAN_PULSE_SPEED = 25

M.MAX_DOTS = 48
M.MAX_WRECKAGE = 32
M.MAX_RINGS = 4
-- ticks the wreckage drifts before the match asks for a key
M.FINALE_TICKS = 50
M.ERROR_SHOW_TICKS = 100

M.BOTS_DIR = "lua/botwarz/bots/"
M.LOG_FILE = "lua/botwarz/debug.log"
-- every scan and shot written to LOG_FILE; script errors are written there either way
M.DEBUG_LOG = false

-- Avatars are closed outlines as x, y pairs, pointing up, and fit inside BOT_RADIUS at any heading.
M.SHAPES = {
    dart   = {0,-8, 6,6, 0,3, -6,6, 0,-8},
    tank   = {-7,-8, -4,-8, -4,-5, 0,-10, 4,-5, 4,-8, 7,-8, 7,8, 4,8, 4,5, -4,5, -4,8, -7,8, -7,-8},
    saucer = {-4,-10, 0,-6, 4,-10, 10,-4, 10,4, 4,10, -4,10, -10,4, -10,-4, -4,-10},
    crab   = {-8,-6, -5,-9, -3,-3, 3,-3, 5,-9, 8,-6, 9,3, 5,8, -5,8, -9,3, -8,-6},
    hammer = {-9,-6, 9,-6, 9,-2, 3,-2, 3,10, -3,10, -3,-2, -9,-2, -9,-6},
    wing   = {0,-10, 9,5, 6,8, 0,-1, -6,8, -9,5, 0,-10},
}
M.SHAPE_NAMES = {"dart", "tank", "saucer", "crab", "hammer", "wing"}
M.DEFAULT_SHAPE = "dart"

return M
