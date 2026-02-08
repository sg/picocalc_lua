# BotWarz - Programmable Robot Arena Battle

## Overview

BotWarz is a 2D overhead arena battle game where programmable robots fight to the death. Players write bot AI scripts in Lua using a provided `bot` API module, then watch their bots compete in an arena. The game supports 2 bots per match (with optional 3rd bot if memory permits).

## Screen Layout

```
+----------------------------------+
|  BOT1: ████████ 100  A:8  M:1    |  <- Status bar (10px per bot)
|  BOT2: ██████   75   A:6  M:0    |
+----------------------------------+
|                                  |
|                                  |
|         ARENA (280x280)          |
|                                  |
|                                  |
+----------------------------------+
|  TIME: 120  |  ROUND: 1/3        |  <- Info bar (20px)
+----------------------------------+
```

- **Screen**: 320x320 pixels
- **Arena**: 280x280 pixels (centered, 20px margins)
- **Status Bar**: Top 20px - health bars, ammo counts
- **Info Bar**: Bottom 20px - match timer, round info

## Visual Style

Wireframe polygon graphics (similar to asteroids-new.lua):
- **Robots**: Triangular body with turret line indicating aim direction
- **Cannon projectiles**: 2x2 pixel dots
- **Missiles**: 2x8 pixel lines (oriented to travel direction)
- **Explosions**: Expanding circle outlines
- **Arena border**: Simple rectangle outline

### Robot Polygon Definition
```lua
-- Robot body (pointing up at angle 0)
local poly_body = {
    {0, -8},    -- nose
    {6, 6},     -- right rear
    {0, 3},     -- rear center notch
    {-6, 6},    -- left rear
    {0, -8}     -- back to nose
}

-- Turret/cannon barrel
local poly_turret = {
    {0, -8},    -- base (at nose)
    {0, -14}    -- barrel tip
}
```

## Game Mechanics

### Robot Stats
- **Health**: 100 HP (destroyed at 0)
- **Energy**: 100 units (regenerates 2/tick, used for movement and scanning)
- **Ammo**: 8 cannon shells (finite per round)
- **Missiles**: 1 missile (finite per round)
- **Speed**: 0-5 units/tick
- **Turn Rate**: Max 10 degrees/tick (configurable via `BOT_TURN_RATE`)
- **Wall Turn Penalty**: 50% of normal turn rate when hitting walls (configurable via `BOT_WALL_TURN_PENALTY`)
- **Size**: 12px radius (collision circle)

### Weapons

#### Cannon
- **Damage**: 10 HP
- **Speed**: 8 units/tick
- **Range**: Unlimited (until wall hit)
- **Cooldown**: 10 ticks
- **Energy Cost**: 5

#### Missile
- **Damage**: 25 HP
- **Speed**: 4 units/tick
- **Range**: Unlimited
- **Cooldown**: 30 ticks
- **Energy Cost**: 15
- **Special**: Splash damage (5 HP within 20px radius)

### Scanning
- **Arc Width**: Configurable (1-90 degrees)
- **Range**: 150 pixels max
- **Energy Cost**: 1 per scan
- **Returns**: Distance and angle to nearest enemy in arc, or nil if none

### Collisions
- **Wall Collision**: Velocity zeroed, turn rate reduced to 50% (configurable via `BOT_WALL_TURN_PENALTY`). Bots must "grind" along the wall to escape, creating a penalty for poor navigation. The `onWall` event fires each time the bot collides.
- **Bot Collision**: Not yet implemented (bots pass through each other)
- **Projectile-Wall**: Cannon shots deactivate; missiles explode with splash damage
- **Projectile-Bot**: Point-in-circle collision (BOT_RADIUS = 12). Triggers `onHit(direction, damage)` event. If bot dies, triggers `onKill(victim_name)` on the shooter.

## Bot Scripting (Lua with `bot` Module)

Bots are written in Lua with a sandboxed environment. Only safe functions are available (math, string, table, etc.) plus the custom `bot` module.

### Bot Script Structure
```lua
-- Bot metadata (required)
bot.name = "MyBot"
bot.color = colors.fromRGB(255, 0, 0)  -- optional, default: random

-- Called once when match starts
function bot.init()
    -- Initialize any state variables
end

-- Called every tick (required)
function bot.tick()
    -- Main bot logic here
end

-- Event handlers (optional)
function bot.onHit(direction, damage)
    -- Called when hit by projectile
    -- direction: angle the shot came from
    -- damage: amount of damage taken
end

function bot.onWall()
    -- Called when colliding with arena wall
end

function bot.onCollision()
    -- Called when colliding with another bot
end

function bot.onKill(victim_name)
    -- Called when this bot destroys another bot
end
```

### Bot API Reference

#### Movement
```lua
bot.drive(speed)           -- Set forward speed (0-5)
bot.turn(degrees)          -- Turn relative (clamped to ±10/tick, or ±5/tick during wall collision)
bot.turnTo(angle)          -- Turn toward absolute angle (0-359)
bot.stop()                 -- Set speed to 0
```

#### Sensing
```lua
-- Scan for enemies in arc ahead
-- Returns: distance, angle (or nil, nil if nothing found)
local dist, ang = bot.scan(arc_degrees)

-- Scan specific absolute direction
local dist, ang = bot.scanAt(angle, arc_degrees)

-- Get bot state
local heading = bot.getHeading()       -- Current facing (0-359)
local x, y = bot.getPosition()         -- Current position
local health = bot.getHealth()         -- Current HP
local energy = bot.getEnergy()         -- Current energy
local ammo = bot.getAmmo()             -- Remaining cannon shells
local missiles = bot.getMissiles()     -- Remaining missiles
local speed = bot.getSpeed()           -- Current speed

-- Arena info
local width, height = bot.getArenaSize()
```

#### Combat
```lua
bot.fire()                 -- Fire cannon in current heading
bot.fireAt(angle)          -- Fire cannon at absolute angle
bot.missile()              -- Fire missile in current heading
bot.missileAt(angle)       -- Fire missile at absolute angle

-- Check cooldowns
local canFire = bot.canFire()          -- true if cannon ready
local canMissile = bot.canMissile()    -- true if missile ready
```

#### Utility
```lua
-- Calculate angle from current position to a point
local angle = bot.angleTo(x, y)

-- Calculate distance to a point
local dist = bot.distanceTo(x, y)

-- Get current game tick
local tick = bot.getTick()
```

### Sandboxed Environment

Bots run in a restricted Lua environment with only these globals:
- `bot` - The bot API module
- `math` - Full math library
- `string` - Full string library
- `table` - Full table library
- `pairs`, `ipairs`, `next` - Iteration
- `type`, `tostring`, `tonumber` - Type functions
- `print` - For debugging (output shown in debug mode)
- `colors` - Color creation (for bot.color)

**Not available** (sandboxed out):
- `os`, `io`, `fs` - No system/file access
- `require`, `dofile`, `loadfile` - No loading external code
- `rawget`, `rawset`, `setmetatable` - No metatable manipulation
- `debug` - No debug library access (except internally for instruction limits)

### Instruction Limiting

Each bot's `tick()` function is limited to **500 Lua instructions** per tick. If exceeded, the bot's tick is terminated early (bot continues with whatever state it reached). This prevents infinite loops from freezing the game and keeps execution time bounded.

### Example Bot: "Spinner"
```lua
-- Spinner - Rotates and fires at anything detected
bot.name = "Spinner"
bot.color = colors.fromRGB(0, 255, 0)

local spin_dir = 1

function bot.init()
    -- Nothing special needed
end

function bot.tick()
    -- Rotate continuously
    bot.turn(10 * spin_dir)

    -- Scan forward
    local dist, ang = bot.scan(30)

    -- Fire if enemy detected and cannon ready
    if dist and bot.canFire() then
        bot.fire()
    end
end

function bot.onWall()
    -- Reverse spin direction on wall hit
    spin_dir = spin_dir * -1
    bot.drive(3)
end
```

### Example Bot: "Hunter"
```lua
-- Hunter - Actively seeks and destroys enemies
bot.name = "Hunter"
bot.color = colors.fromRGB(255, 0, 0)

local target_dist = nil
local target_ang = nil
local scan_offset = 0
local hunting = false
local evade_timer = 0

function bot.init()
    bot.drive(2)  -- Start moving
end

function bot.tick()
    -- Handle evasion cooldown
    if evade_timer > 0 then
        evade_timer = evade_timer - 1
        return
    end

    if not hunting then
        -- Search mode: sweep scan
        scan_offset = scan_offset + 45
        if scan_offset > 180 then
            scan_offset = -180
        end

        local dist, ang = bot.scanAt(bot.getHeading() + scan_offset, 45)
        if dist then
            target_dist = dist
            target_ang = ang
            hunting = true
        end

        -- Wander slowly
        bot.drive(2)
        bot.turn(3)
    else
        -- Chase mode: pursue target
        bot.turnTo(target_ang)

        if target_dist > 50 then
            bot.drive(4)
        else
            bot.drive(2)
        end

        -- Update target position
        local dist, ang = bot.scan(20)
        if dist then
            target_dist = dist
            target_ang = ang

            -- Fire when in range and aimed
            if dist < 100 and bot.canFire() then
                bot.fire()
            end
        else
            hunting = false
        end
    end
end

function bot.onHit(direction, damage)
    -- Turn toward attacker and return fire
    bot.turnTo(direction)
    if bot.canFire() then
        bot.fire()
    end
    -- Evasive maneuver
    bot.drive(5)
    evade_timer = 15
end

function bot.onWall()
    bot.turn(90)
    bot.drive(3)
end
```

### Example Bot: "Camper"
```lua
-- Camper - Finds a corner and defends it
bot.name = "Camper"
bot.color = colors.fromRGB(128, 128, 255)

local settled = false
local scan_angle = 0

function bot.init()
    -- Head toward a corner
    bot.turnTo(45)  -- Toward top-right
    bot.drive(4)
end

function bot.tick()
    if not settled then
        -- Keep moving until we hit a wall twice
        local x, y = bot.getPosition()
        local w, h = bot.getArenaSize()

        -- Check if in a corner region
        local in_corner = (x < 40 or x > w - 40) and (y < 40 or y > h - 40)
        if in_corner then
            settled = true
            bot.stop()
        end
    else
        -- Settled: sweep scan and shoot
        scan_angle = scan_angle + 5
        if scan_angle > 360 then
            scan_angle = 0
        end

        local dist, ang = bot.scanAt(scan_angle, 30)
        if dist and bot.canFire() then
            bot.fireAt(ang)
        end
    end
end

function bot.onWall()
    if not settled then
        -- Turn and keep going to find corner
        bot.turn(45)
    end
end

function bot.onHit(direction, damage)
    -- Return fire at attacker
    if bot.canFire() then
        bot.fireAt(direction)
    end
    -- Launch missile if we have one
    if bot.canMissile() then
        bot.missileAt(direction)
    end
end
```

## File Structure

```
sd_files/lua/
├── botwarz.md           # This design document
├── botwarz/
│   ├── main.lua         # All game code in single file (~1365 lines)
│   └── bots/            # Bot scripts directory (all created)
│       ├── spinner.lua  # Spins in place, fires at anything detected
│       ├── hunter.lua   # Actively seeks and pursues enemies
│       ├── camper.lua   # Finds a corner and defends it
│       └── random.lua   # Random movement, opportunistic firing
```

**Design Decision**: Single main.lua file instead of multiple modules.
- Avoids multiple `require()` / `dofile()` calls
- Reduces memory fragmentation
- Easier to track total code size
- Current: main.lua ~1365 lines (with full combat system)

## Implementation Phases

### Phase 1: Core Framework + Memory Baseline ✅ COMPLETE
1. ✅ Main game loop and state machine (menu, playing, results)
2. ✅ Arena rendering (border via draw.rect)
3. ✅ Robot rendering (wireframe polygons with erase/redraw)
4. ✅ **Memory checkpoint**: Baseline verified
5. ✅ Basic robot movement (keyboard test mode - later replaced by bot control)

**Bugs fixed during Phase 1:**
- Cursor blinking in top-left: Added `term.setCursorBlink(false)` at startup and match init
- `show_help` nil error: Moved function definition before first call
- Memory indicator too dim: Created `COLOR_DIM_TEXT = colors.fromRGB(128, 128, 128)`
- Rotation too fast / leaving trails: Moved held-key processing into `update_playing()` so it only runs once per tick

### Phase 2: Bot Loading (Memory Critical) ✅ COMPLETE
1. ✅ Shared restricted environment setup
2. ✅ Bot script loading with `loadfile(path, "t", sandbox)` (Lua 5.2+ style - setfenv removed in 5.2+)
3. ✅ Instruction limiting with `debug.sethook()`
4. ✅ **Memory checkpoint**: 2 bots loaded successfully
5. ✅ Basic `bot.tick()` execution
6. ✅ Bot selection menu with file scanning

**Bugs fixed during Phase 2:**
- `fs.list()` returns tables with `.name` and `.isDir` properties, not strings
- `setfenv` doesn't exist in Lua 5.2+: Changed to `loadfile(filepath, "t", sandbox)`

### Phase 3: Bot API - Movement & Sensing ✅ COMPLETE
1. ✅ Movement commands (drive, turn, turnTo, stop)
2. ✅ State queries (getPosition, getHeading, getHealth, getEnergy, getAmmo, getMissiles, getSpeed, getArenaSize, getTick)
3. ✅ Scanning system (scan, scanAt with distance/angle calculation)
4. ✅ Both bots running simultaneously
5. ✅ Event handlers (onWall, onHit, onCollision) with pending action application
6. ✅ Wall collision turn penalty system

**Bugs fixed during Phase 3:**
- Bots stuck at walls: `execute_bot_event()` now resets and applies pending actions (turn/speed) after event handlers run
- Wall turn too fast: Added `BOT_WALL_TURN_PENALTY` (0.5) - bots turn at 50% rate when hitting walls as a navigation penalty

### Phase 4: Combat System ✅ COMPLETE
1. ✅ Pre-allocated projectile pool (16 slots)
2. ✅ Cannon projectiles (spawn from pool, update, render as 2x2 dots)
3. ✅ Collision detection (point-in-circle for bots, bounds check for walls)
4. ✅ Damage application with health tracking
5. ✅ Event callbacks (onHit, onWall, onKill)
6. ✅ Missiles with splash damage (25 direct + 5 splash within 20px radius)
7. ✅ Cooldown system (cannon: 10 ticks, missile: 30 ticks)
8. ✅ Energy cost (cannon: 5, missile: 15)
9. ✅ Win condition (last bot standing)
10. ⬜ **Memory checkpoint**: Need to verify < 120KB

**Projectile constants:**
- Cannon: 10 damage, speed 8, cooldown 10 ticks, energy 5
- Missile: 25 damage + 5 splash, speed 4, cooldown 30 ticks, energy 15, splash radius 20px

### Phase 5: Game Flow 🔄 PARTIAL
1. ✅ Bot selection menu (list files in bots/)
2. ⬜ Round system (best of N)
3. ✅ Win/lose conditions (last bot standing)
4. ✅ Results screen (shows winner name)

### Phase 6: Polish (Memory Permitting) ⬜ NOT STARTED
1. ⬜ Sound effects (minimal - fire, hit, explode) - placeholder sounds exist
2. ⬜ Simple explosions (expanding circles, 3 frames)
3. ✅ Default bots (4 strategies: spinner, hunter, camper, random)
4. ⬜ **Final memory verification**: < 150KB typical

## Sound Design

Using `sound` module with drum presets and custom instruments:
```lua
local sounds = {
    cannon = sound.instrument(sound.drums.tom),
    missile = sound.instrument(sound.presets.warp),
    hit = sound.instrument(sound.drums.snare2),
    explode = sound.instrument(sound.drums.kick1),
    wall = sound.instrument(sound.drums.hihat),
}
sounds.cannon.decay = 100
sounds.missile.decay = 200
sounds.missile.attack = 50
```

- **Cannon fire**: Short tom hit
- **Missile launch**: Warp/whoosh sound
- **Hit taken**: Snare
- **Explosion (bot destroyed)**: Kick drum
- **Wall collision**: Hi-hat

## Technical Details

### Memory Budget (~150-200KB target)

The PicoCalc has limited RAM. Target memory budget breakdown:

| Component | Estimated Size | Notes |
|-----------|---------------|-------|
| Game code (main.lua, etc.) | ~15-20KB | Lua bytecode for game logic |
| Bot scripts (2 bots) | ~8-12KB | ~4-6KB per bot compiled |
| Bot runtime state | ~2KB | Fixed arrays, not tables |
| Projectile pool | ~1KB | Pre-allocated, 16 max |
| Rendering (no buffer) | ~0KB | Direct drawing, no framebuffer |
| Lua VM overhead | ~50-80KB | Baseline interpreter state |
| **Total estimate** | **~80-120KB** | Leaves headroom for GC |

### Memory-Saving Strategies

#### 1. No Double Buffering
Use direct drawing like asteroids-new.lua instead of `draw.enableBuffer()`:
- Erase objects at old positions
- Update positions
- Draw objects at new positions
- This avoids 200KB framebuffer allocation

#### 2. Single Shared Environment (Not Per-Bot Sandboxes)
Instead of creating separate sandboxed environments per bot (expensive), use a **single shared environment** with bot isolation via closures:

```lua
-- Load bot into shared environment, returns bot interface
function loadBot(filename, bot_id)
    -- Create bot's private state table
    local state = {
        id = bot_id,
        x = 0, y = 0, heading = 0, health = 100,
        -- ... other fixed fields
    }

    -- Create bot's API that references this state
    local bot = createBotAPI(state)

    -- Load and run bot script with sandbox as environment
    -- Uses Lua 5.2+ style: loadfile(path, mode, env)
    local chunk = loadfile(filename, "t", createRestrictedEnv(bot))
    chunk()

    return {
        state = state,
        tick = bot.tick,
        onHit = bot.onHit,
        -- ... other callbacks
    }
end
```

**Note**: The PicoCalc uses Lua 5.4, which removed `setfenv`. Instead, use `loadfile(path, "t", sandbox)` where the third parameter is the environment table.

#### 3. Pre-allocated Projectile Pool
Instead of creating/destroying tables for projectiles:

```lua
-- Fixed-size projectile pool (no allocation during gameplay)
local MAX_PROJECTILES = 16
local projectiles = {}
for i = 1, MAX_PROJECTILES do
    projectiles[i] = {
        active = false,
        x = 0, y = 0, vx = 0, vy = 0,
        type = 0, owner = 0
    }
end

function spawnProjectile(x, y, vx, vy, ptype, owner)
    for i = 1, MAX_PROJECTILES do
        if not projectiles[i].active then
            local p = projectiles[i]
            p.active = true
            p.x, p.y = x, y
            p.vx, p.vy = vx, vy
            p.type, p.owner = ptype, owner
            return true
        end
    end
    return false  -- Pool exhausted
end
```

#### 4. Fixed Robot State Arrays
Use simple numbered arrays instead of named tables where possible:

```lua
-- Bot state as compact arrays (indices are constants)
local BOT_X, BOT_Y, BOT_HEADING, BOT_SPEED = 1, 2, 3, 4
local BOT_HEALTH, BOT_ENERGY, BOT_AMMO, BOT_MISSILES = 5, 6, 7, 8
local BOT_COOLDOWN_CANNON, BOT_COOLDOWN_MISSILE = 9, 10

local bots = {
    {0, 0, 0, 0, 100, 100, 10, 2, 0, 0},  -- Bot 1
    {0, 0, 0, 0, 100, 100, 10, 2, 0, 0},  -- Bot 2
}
```

#### 5. Bot Script Size Limits
- Maximum bot script file size: **4KB** (source code)
- Maximum bot local variables: Soft limit via code review
- Encourage simple, focused bot logic

#### 6. Aggressive Garbage Collection
```lua
-- Call after each round, during menus
collectgarbage("collect")

-- Optional: call periodically during match if needed
if tick % 100 == 0 then
    collectgarbage("step", 10)
end
```

#### 7. Reuse Polygon Arrays
```lua
-- Single scratch array for transformed polygons
local scratch_poly = {0,0, 0,0, 0,0, 0,0, 0,0}  -- 5 points max

function draw_rotated(shape, x, y, ang, scale, color)
    local sin = math.sin(ang) * scale
    local cos = math.cos(ang) * scale
    local idx = 1
    for i = 1, #shape do
        local px = x + shape[i][1] * cos - shape[i][2] * sin
        local py = y + shape[i][1] * sin + shape[i][2] * cos
        scratch_poly[idx] = math.floor(px + 0.5)
        scratch_poly[idx + 1] = math.floor(py + 0.5)
        idx = idx + 2
    end
    draw.polygon(scratch_poly, color)
end
```

### Reduced Scope for Memory

| Original | Memory-Conscious |
|----------|-----------------|
| 2-4 bots | 2 bots (3 optional) |
| 10 cannon + 2 missiles | 8 cannon + 1 missile |
| Unlimited projectiles | Max 16 active |
| Splash damage calc | Simple radius check |
| Per-bot sandboxes | Shared environment |
| Double buffering | Direct draw (erase/redraw) |

### Key Constants (in main.lua)
```lua
-- Robot behavior
BOT_RADIUS = 12              -- Collision radius in pixels
BOT_MAX_SPEED = 5            -- Maximum speed units per tick
BOT_TURN_RATE = 10           -- Maximum degrees per tick (normal)
BOT_WALL_TURN_PENALTY = 0.5  -- Turn rate multiplier when hitting wall (0.5 = 50%)
BOT_MAX_ENERGY = 100         -- Maximum energy
BOT_ENERGY_REGEN = 2         -- Energy regenerated per tick
BOT_SCAN_RANGE = 150         -- Maximum scan distance in pixels
BOT_SCAN_COST = 1            -- Energy cost per scan

-- Cannon projectile
CANNON_DAMAGE = 10           -- Direct hit damage
CANNON_SPEED = 8             -- Pixels per tick
CANNON_COOLDOWN = 10         -- Ticks between shots
CANNON_ENERGY = 5            -- Energy cost per shot

-- Missile projectile
MISSILE_DAMAGE = 25          -- Direct hit damage
MISSILE_SPEED = 4            -- Pixels per tick
MISSILE_COOLDOWN = 30        -- Ticks between shots
MISSILE_ENERGY = 15          -- Energy cost per shot
MISSILE_SPLASH_RADIUS = 20   -- Splash damage radius in pixels
MISSILE_SPLASH_DAMAGE = 5    -- Damage within splash radius

-- Projectile pool
MAX_PROJECTILES = 16         -- Pre-allocated pool size

-- Script limits
BOT_INSTRUCTION_LIMIT = 500  -- Max Lua instructions per tick() call

-- Timing
TICK_INTERVAL = 0.05         -- 20 ticks per second (50ms)
```

### Tick System
- Game runs at **20 ticks per second** (50ms per frame)
- Each tick:
  1. Execute all bot `tick()` functions (with instruction limits)
  2. Apply movement (update positions based on speed/heading)
  3. Update projectiles
  4. Check collisions (walls, bots, projectiles)
  5. Apply damage and trigger events
  6. Check win conditions
  7. Render frame (erase old, draw new)

### Coordinate System
- Origin (0, 0) at top-left of arena
- Angles: 0° = up, 90° = right, 180° = down, 270° = left
- Positive turn = clockwise

### Collision Detection
- Bots: Circle collision (12px radius)
- Projectiles: Point collision against bot circles
- Walls: Simple bounds checking

### Performance Considerations
- **No framebuffer** - direct drawing with erase/redraw pattern
- Clear only changed areas (object old positions)
- Limit to 2-3 bots maximum
- Instruction limit (500 per tick) prevents runaway bot code
- Pre-allocated object pools avoid runtime allocation
- Periodic garbage collection during low-activity moments

## Menu Flow

```
BOTWARZ
├── START MATCH
│   ├── Select Bot 1 (from bots/ directory)
│   ├── Select Bot 2
│   ├── Rounds: 1 / 3 / 5
│   └── BEGIN
├── EDIT BOT
│   └── (launches text editor with selected .lua file)
├── HOW TO PLAY
│   └── (shows bot API reference)
└── QUIT
```

Note: 3-bot matches may be added later if memory permits after testing.

## Victory Conditions

**Round win:**
- Last bot standing (all others at 0 HP)
- If time expires: highest HP wins
- If tied HP at time expiry: draw (no points)

**Match win:**
- First to win majority of rounds (e.g., 2/3 or 3/5)
- Displayed with final stats (damage dealt, shots fired, accuracy)

## Future Enhancements (Post-MVP, Memory Permitting)

- 3rd bot support (if memory allows after testing)
- Simple obstacles (1-2 static rectangles in arena)
- Bot debugging mode (pause, show scan arcs - useful for development)
- More default bot strategies

**Unlikely due to memory constraints:**
- 4 bots (would require ~40KB additional)
- Power-ups (additional object tracking)
- Replay recording (would need significant storage)
- Complex weapon types (mines, shields)
