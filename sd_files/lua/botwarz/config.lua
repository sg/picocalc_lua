-- BotWarz Configuration
-- All constants, colors, and polygon definitions

local M = {}

-- =============================================================================
-- SCREEN AND ARENA
-- =============================================================================

M.SCREEN_WIDTH = 320
M.SCREEN_HEIGHT = 320

-- Arena bounds (with margins for status bars)
M.ARENA_MARGIN_TOP = 20
M.ARENA_MARGIN_BOTTOM = 20
M.ARENA_MARGIN_SIDE = 20
M.ARENA_X = M.ARENA_MARGIN_SIDE
M.ARENA_Y = M.ARENA_MARGIN_TOP
M.ARENA_WIDTH = M.SCREEN_WIDTH - (M.ARENA_MARGIN_SIDE * 2)
M.ARENA_HEIGHT = M.SCREEN_HEIGHT - M.ARENA_MARGIN_TOP - M.ARENA_MARGIN_BOTTOM

-- =============================================================================
-- COLORS
-- =============================================================================

M.COLOR_BG = colors.black
M.COLOR_ARENA_BG = colors.fromRGB(0, 0, 32)  -- Dark blue
M.COLOR_ARENA_BORDER = colors.fromRGB(64, 64, 64)  -- Gray
M.COLOR_TEXT = colors.white
M.COLOR_DIM_TEXT = colors.fromRGB(128, 128, 128)  -- Lighter gray
M.COLOR_BOT1 = colors.fromRGB(0, 255, 0)    -- Green
M.COLOR_BOT2 = colors.fromRGB(255, 64, 64)  -- Red

-- =============================================================================
-- ROBOT CONSTANTS
-- =============================================================================

M.BOT_RADIUS = 12
M.BOT_MAX_SPEED = 5
M.BOT_TURN_RATE = 10  -- degrees per tick
M.BOT_WALL_TURN_PENALTY = 0.5  -- turn rate multiplier when hitting wall
M.BOT_MAX_ENERGY = 100
M.BOT_ENERGY_REGEN = 2  -- per tick
M.BOT_SCAN_RANGE = 150
M.BOT_SCAN_COST = 1  -- energy per scan

-- Bot script limits
M.BOT_INSTRUCTION_LIMIT = 500  -- max instructions per tick

-- =============================================================================
-- PROJECTILE CONSTANTS
-- =============================================================================

M.PROJ_TYPE_CANNON = 1
M.PROJ_TYPE_MISSILE = 2

M.CANNON_DAMAGE = 10
M.CANNON_SPEED = 8
M.CANNON_COOLDOWN = 10  -- ticks between shots
M.CANNON_ENERGY = 5

M.MISSILE_DAMAGE = 25
M.MISSILE_SPEED = 4
M.MISSILE_COOLDOWN = 30
M.MISSILE_ENERGY = 15
M.MISSILE_SPLASH_RADIUS = 20
M.MISSILE_SPLASH_DAMAGE = 5

M.MAX_PROJECTILES = 16

-- =============================================================================
-- GAME TIMING
-- =============================================================================

M.TICK_INTERVAL = 0.05  -- 20 ticks per second (50ms)

-- =============================================================================
-- PATHS
-- =============================================================================

M.BOTS_DIR = "lua/botwarz/bots/"
M.LOG_FILE = "lua/botwarz/debug.log"

-- =============================================================================
-- POLYGON DEFINITIONS
-- =============================================================================

-- Robot body (pointing up at angle 0)
M.POLY_BODY = {
    {0, -8},     -- nose
    {6, 6},      -- right rear
    {0, 3},      -- rear center notch
    {-6, 6},     -- left rear
    {0, -8}      -- back to nose (close)
}

-- Turret/cannon barrel (line from nose outward)
M.POLY_TURRET = {
    {0, -8},     -- base at nose
    {0, -14}     -- barrel tip
}

return M
