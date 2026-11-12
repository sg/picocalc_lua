# BotWarz - Programmable Robot Arena Battle

## Overview

BotWarz is a 2D overhead arena battle game where programmable robots fight to the death. Players write bot AI scripts in Lua using a provided `bot` API module, then watch their bots compete in an arena. A match is between 2 bots.

Run it with `run /lua/botwarz/main.lua`.

## Screen Layout

```
+----------------------------------+
|  BOT1 ████████ 100   BOT2 ███ 45 |  <- Status bar: name, health, ERR if the script failed
+----------------------------------+
|                                  |
|                                  |
|         ARENA (280x280)          |
|                                  |
|                                  |
+----------------------------------+
|  0:42  ESC:quit  S:scan pulse    |  <- Info bar: match time, keys, memory, script errors
+----------------------------------+
```

- **Screen**: 320x320 pixels
- **Arena**: 280x280 pixels (centered, 20px margins)
- **Status Bar**: Top 20px - names and health bars
- **Info Bar**: Bottom 20px - match time, keys, Lua memory in use; shows a script's error message in red for 5 seconds when one happens

### Keys during a match

| Key | Action |
|-----|--------|
| `S` | Step through the ways a scan is shown: pulse, sweep, wedge, off |
| `ESC` | Leave the match |

## Visual Style

Wireframe graphics:
- **Robots**: one of six outlines (below), with a gun barrel that pivots at the bot's centre
- **Cannon shells**: 2x2 pixel dots
- **Missiles**: 8 pixel lines along their direction of travel
- **Hits**: a burst of sparks at the point of impact, more of them and faster the more damage was done, and the bot's outline flashes white
- **Missile blast**: a ring growing to the splash radius
- **Destroyed bot**: its outline breaks into its edges, which drift apart as the ship's do in Asteroids, among a larger burst in the bot's color
- **Arena border**: Simple rectangle outline

### Avatars

A script picks its outline with `bot.shape`, by name or by number:

| # | Name | Looks like |
|---|------|-----------|
| 1 | `dart` | The narrow notched triangle borrowed from Asteroids (the default) |
| 2 | `tank` | A hull between two tracks, with a pointed bow |
| 3 | `saucer` | An octagon with a notch at the front |
| 4 | `crab` | A rounded body with two claws forward |
| 5 | `hammer` | A wide crossbar on a narrow body |
| 6 | `wing` | A wide swept-back chevron |

The outlines are in `config.lua` (`SHAPES`), as closed lists of x, y pairs pointing up. Each fits inside the bot's collision circle at any heading, so what is drawn is never larger than what can be hit. "How to Play" in the menu shows all six.

### The gun barrel

The barrel shows where the bot last aimed:
- after `bot.fire()` or `bot.missile()` it points straight ahead and turns with the bot;
- after `bot.fireAt(angle)` or `bot.missileAt(angle)` it points at that bearing and stays there while the bot turns under it, whether or not the shot was ready to fire.

Shots leave from the tip of the barrel. `bot.getAim()` returns its direction.

### Scan display

Each scan a bot makes can be seen, in a dim shade of the bot's color. `S` steps through the styles during a match, and `SCAN_DISPLAY` in `config.lua` sets the one a match starts with:

| Style | What is drawn |
|-------|---------------|
| `pulse` | An arc as wide as the scan, travelling outward from the bot to the scan range, like a sonar ping. One pulse at a time: a bot that scans every tick sends the next as the last dies out. |
| `sweep` | A line from the bot to the scan range, sweeping back and forth across the arc scanned. |
| `wedge` | The whole area scanned on that tick: both edges and the arc at full range. |
| `off` | Nothing. |

In every style but `off`, corner brackets appear around a bot on each tick that a scan finds it (`SCAN_LOCK` in `config.lua`).

When a bot scans more than once in a tick, one scan is shown: one that found something if any did, otherwise the last.

## Game Mechanics

### Robot Stats
- **Health**: 100 HP (destroyed at 0)
- **Energy**: 100 units, regenerates 2/tick; spent on scanning and firing
- **Ammo**: 50 cannon shells
- **Missiles**: 3
- **Speed**: -2 (reverse) to 5 units/tick
- **Turn Rate**: Max 10 degrees/tick (`BOT_TURN_RATE`)
- **Wall Turn Penalty**: 50% of the turn rate while pressing against a wall (`BOT_WALL_TURN_PENALTY`)
- **Size**: 12px radius (collision circle)

Bots start in opposite corners (`STARTS` in `config.lua`).

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
- **Special**: Splash damage (5 HP to every other bot whose centre is within 20px of the blast, the bot that fired it included)

At most 16 shots are in the air at once; a shot that would be the 17th is not fired and costs nothing.

### Scanning
- **Arc Width**: 1-90 degrees (clamped)
- **Range**: 150 pixels
- **Energy Cost**: 1 per scan, for `scan`, `scanAt` and `detectShot` alike
- **Finds**: the nearest enemy with any part of it inside the arc, which is what the scan drawn on screen shows
- **Returns**: distance and bearing to the enemy's centre, and the enemy's heading and speed; nil if nothing is found or there is no energy for it

A bot doing two scans every tick spends energy as fast as it comes back, and one that also fires will run short and find its scans returning nil.

### Turning and driving

What a script asks for with `drive`, `turn`, `turnTo` and `stop` is carried out once per tick, just after its `tick()` has run. Requests made in an event handler (`onHit`, `onWall`, ...) are held until then and count against the same allowance, so a bot never turns more than its turn rate in a tick however many handlers ran.

- `bot.turn(d)` adds `d` to the turn wanted this tick.
- `bot.turnTo(a)` replaces whatever turn was wanted with the shortest turn to face `a`.
- Only up to the turn rate is carried out; the rest is dropped, not saved for the next tick.
- A speed set with `bot.drive` is kept until changed, or until a wall or another bot stops the bot.

### Collisions
- **Wall**: The bot is held inside the arena and its speed set to 0. While it keeps pressing on the wall its turn rate is halved, so a bot that drives into a wall has to grind its way round. `onWall` fires on each tick that it presses.
- **Bot against bot**: Bots cannot overlap. Two that meet are pushed apart, both are stopped, and each gets `onCollision(direction)` with the bearing to the other, on every tick that they press together. A bot pushed against a wall stays put and the other gives way. There is no damage from ramming.
- **Shot against wall**: Cannon shells vanish; missiles explode with splash damage.
- **Shot against bot**: A shot is tested along the whole of its flight each tick against the bot's collision circle, so a shell cannot step over the edge of a bot, and a shot fired with the muzzle touching a bot hits it. Triggers `onHit(direction, damage)` on the victim and `onShotHit(name, damage)` on the bot that fired; if the victim is destroyed, `onKill(name)` as well. A bot cannot be hit directly by its own shot, but its own missile's blast can hurt it.

## Bot Scripting (Lua with `bot` Module)

Bots are written in Lua with a sandboxed environment. Only safe functions are available (math, string, table, etc.) plus the custom `bot` module. Scripts go in `lua/botwarz/bots/`.

### Bot Script Structure
```lua
-- Bot settings
bot.name = "MyBot"                       -- shown in the status bar (first 7 characters)
bot.color = colors.fromRGB(255, 0, 0)    -- optional
bot.shape = "tank"                       -- optional, see Avatars

-- Called once when match starts
function bot.init()
end

-- Called every tick (required)
function bot.tick()
end

-- Event handlers (all optional)
function bot.onHit(direction, damage)
    -- Hit by a shot or a blast.
    -- direction: the bearing the shot came from, so bot.turnTo(direction) faces the attacker
end

function bot.onWall()
    -- Pressing against an arena wall
end

function bot.onCollision(direction)
    -- Pressing against another bot; direction is the bearing to it
end

function bot.onScanned(direction)
    -- An enemy's scan found this bot; direction is the bearing to the scanner
end

function bot.onShotHit(victim_name, damage)
    -- One of this bot's shots, or its missile's blast, hurt another bot
end

function bot.onKill(victim_name)
    -- This bot destroyed another bot
end
```

### Bot API Reference

Angles are in degrees: 0 is up, 90 right, 180 down, 270 left. Positions are in arena pixels with (0, 0) at the top left.

#### Movement
```lua
bot.drive(speed)           -- Set speed, -2 (reverse) to 5
bot.turn(degrees)          -- Turn relative; at most 10 a tick (5 while pressing on a wall)
bot.turnTo(angle)          -- Turn toward absolute angle, the short way round
bot.stop()                 -- Set speed to 0
```

#### Sensing
```lua
-- Scan for enemies in an arc centred on the heading
-- Returns: distance, angle, enemy heading, enemy speed (or nil if nothing found)
local dist, ang, heading, speed = bot.scan(arc_degrees)

-- Scan an arc centred on an absolute direction
local dist, ang, heading, speed = bot.scanAt(angle, arc_degrees)

-- Nearest enemy shot within scan range that is closing on this bot
-- Returns: distance, bearing to it, its direction of travel, "cannon" or "missile" (or nil)
local dist, ang, heading, kind = bot.detectShot()

-- Distance from the bot's centre to the wall along its heading, or along a given angle.
-- The bot itself stops bot.RADIUS short of the wall.
local d = bot.wallDistance()
local d = bot.wallDistance(angle)

-- Get bot state
local heading = bot.getHeading()       -- Current facing (0-359)
local x, y = bot.getPosition()         -- Current position
local health = bot.getHealth()         -- Current HP
local energy = bot.getEnergy()         -- Current energy
local ammo = bot.getAmmo()             -- Remaining cannon shells
local missiles = bot.getMissiles()     -- Remaining missiles
local speed = bot.getSpeed()           -- Current speed
local aim = bot.getAim()               -- Where the gun points
local cannon, missile = bot.getCooldown()  -- Ticks until each can fire again

-- Arena info
local width, height = bot.getArenaSize()
```

#### Combat
```lua
bot.fire()                 -- Fire cannon straight ahead
bot.fireAt(angle)          -- Fire cannon at absolute angle
bot.missile()              -- Fire missile straight ahead
bot.missileAt(angle)       -- Fire missile at absolute angle
-- each returns true if the shot was fired

local canFire = bot.canFire()          -- true if cannon ready
local canMissile = bot.canMissile()    -- true if missile ready
```

#### Utility
```lua
local angle = bot.angleTo(x, y)        -- Bearing from the bot to a point
local dist = bot.distanceTo(x, y)      -- Distance from the bot to a point
local d = bot.angleDiff(from, to)      -- Shortest turn from one angle to another, -180 to 180
local tick = bot.getTick()             -- Current game tick
```

#### Constants
```lua
bot.MAX_SPEED       -- 5
bot.MAX_REVERSE     -- 2
bot.TURN_RATE       -- 10
bot.RADIUS          -- 12
bot.SCAN_RANGE      -- 150
bot.CANNON_SPEED    -- 8
bot.MISSILE_SPEED   -- 4
```

Numbers that are not finite (nan, inf) and values of the wrong type are ignored by every function.

### Sandboxed Environment

Bots run in a restricted Lua environment with only these globals:
- `bot` - The bot API module
- `math` - Full math library
- `string` - Full string library
- `table` - Full table library
- `pairs`, `ipairs`, `next` - Iteration
- `type`, `tostring`, `tonumber` - Type functions
- `print` - Writes to the debug log when `DEBUG_LOG` is on, and nowhere otherwise
- `colors` - Color creation (for bot.color)

**Not available** (sandboxed out):
- `os`, `io`, `fs` - No system/file access
- `require`, `dofile`, `loadfile` - No loading external code
- `rawget`, `rawset`, `setmetatable` - No metatable manipulation
- `debug` - No debug library access (except internally for instruction limits)

### Instruction Limiting

Each call into a script - `tick()` or an event handler - may run **5000 Lua VM instructions** (`BOT_INSTRUCTION_LIMIT`), counting those the API functions themselves use. A call that goes over is stopped where it is, with whatever it had already asked for still standing. The stock bots use 250 to 1000 a tick.

### Script errors

A script that fails, or goes over the instruction limit, does not stop the match. `ERR` appears beside the bot's health, the message is shown in the info bar for 5 seconds, and it is written to `lua/botwarz/debug.log`. A script that fails to load is reported before the match starts, which then runs with that bot standing still.

Set `DEBUG_LOG = true` in `config.lua` to have every scan that finds something, every shot and every hit written to the log as well. It is off by default because writing to the card during a match slows it down.

### Example Bot: "Spinner"
```lua
-- Spinner - Rotates and fires at anything detected
bot.name = "Spinner"
bot.color = colors.fromRGB(0, 255, 0)
bot.shape = "saucer"

local spin_dir = 1

function bot.tick()
    bot.turn(10 * spin_dir)

    local dist, ang = bot.scan(30)
    if dist and bot.canFire() then
        bot.fireAt(ang)
    end
end

function bot.onWall()
    spin_dir = spin_dir * -1
    bot.drive(3)
end
```

### Stock bots

| File | Avatar | Strategy |
|------|--------|----------|
| `spinner.lua` | saucer | Spins on the spot and fires at anything it sees |
| `hunter.lua` | dart | Sweeps for an enemy, then chases it |
| `camper.lua` | tank | Drives to a corner and defends it |
| `random.lua` | crab | Wanders at random and fires when something is ahead |
| `ace.lua` | wing | Circles its target, leads its shots from the target's heading and speed, turns before reaching a wall, sidesteps incoming fire, and looks toward whoever scans it |
| `wally.lua` | dart | Work in progress |

`ace.lua` is the one to read for the newer parts of the API.

## File Structure

```
sd_files/lua/
├── botwarz.md           # This document
├── botwarz/
│   ├── main.lua         # Game state, the match simulation and the main loop
│   ├── bot.lua          # Sandbox, bot API, loading and running scripts
│   ├── render.lua       # Geometry helpers, display list, bars, effects
│   ├── screens.lua      # Menu, bot selection and help screens
│   ├── config.lua       # Constants, colors, avatar outlines
│   ├── debug.log        # Written during a match (not in the repository)
│   └── bots/            # Bot scripts
```

## Implementation Status

- ✅ Core framework: game loop, arena, robots
- ✅ Bot loading: sandbox, instruction limit, selection menu
- ✅ Bot API: movement, sensing, events
- ✅ Combat: shell and missile pool, damage, cooldowns, energy, last bot standing
- ✅ Bot against bot collisions and `onCollision`
- ✅ Explosions, break-up of a destroyed bot, end of match shown on the arena
- ✅ Avatars, scan display, gun barrel that follows the aim
- ⬜ Round system (best of N)
- ⬜ Match time limit (highest HP wins when time expires)
- ⬜ Final stats on the results (damage dealt, shots fired, accuracy)

## Sound Design

Using the `sound` module's drum presets:

- **Cannon fire**: tom
- **Missile launch**: low kick
- **Hit taken**: snare
- **Missile blast**: kick
- **Bot destroyed**: deep kick

## Technical Details

### Rendering

Everything in the arena is drawn through a display list that `render.lua` fills each frame.

- With a framebuffer (QSPI PSRAM, or RAM when over 256KB is free) the arena is cleared and the list drawn off screen, then shown whole, so nothing flickers. Sending the frame to the LCD takes about 44ms, which is most of a tick.
- Without one, the last frame's list is drawn again in the background color to erase it and the new one drawn in its place.
- `USE_FRAMEBUFFER = false` in `config.lua` chooses the second way everywhere.
- Lines are clipped to the arena, so scans, wreckage and gun barrels never mark the border or the bars.
- The status and info bars are redrawn only when what they show changes.

### Memory

On a Pimoroni Pico Plus 2 W the game takes about 85KB of Lua memory on top of the shell with a match in progress, most of it the game's own code. Shots, sparks, wreckage and the display list are allocated once and reused, so a match makes almost no garbage.

`main.lua` loads the other modules without their debug information, which saves about 10KB. An error inside the game itself then has no line number; type `eval BOTWARZ_DEBUG=true` in the shell before starting the game to get them back. Bot scripts always keep theirs.

### Key Constants (in config.lua)
```lua
BOT_RADIUS = 12              -- Collision radius in pixels
BOT_MAX_SPEED = 5            -- Maximum speed units per tick
BOT_MAX_REVERSE = 2          -- Maximum speed in reverse
BOT_TURN_RATE = 10           -- Maximum degrees per tick
BOT_WALL_TURN_PENALTY = 0.5  -- Turn rate multiplier while pressing on a wall
BOT_MAX_ENERGY = 100
BOT_ENERGY_REGEN = 2         -- Energy regenerated per tick
BOT_SCAN_RANGE = 150         -- Maximum scan distance in pixels
BOT_SCAN_COST = 1            -- Energy cost per scan
BOT_START_AMMO = 50
BOT_START_MISSILES = 3
BARREL_LENGTH = 12           -- Shots leave from here

CANNON_DAMAGE = 10
CANNON_SPEED = 8             -- Pixels per tick
CANNON_COOLDOWN = 10         -- Ticks between shots
CANNON_ENERGY = 5

MISSILE_DAMAGE = 25
MISSILE_SPEED = 4
MISSILE_COOLDOWN = 30
MISSILE_ENERGY = 15
MISSILE_SPLASH_RADIUS = 20
MISSILE_SPLASH_DAMAGE = 5

MAX_PROJECTILES = 16
BOT_INSTRUCTION_LIMIT = 5000 -- VM instructions per call into a script
TICK_INTERVAL = 0.05         -- 20 ticks per second

SCAN_DISPLAY = "pulse"       -- pulse, sweep, wedge or off
SCAN_LOCK = true             -- Brackets around a bot a scan has found
USE_FRAMEBUFFER = true
DEBUG_LOG = false
```

### Tick System
- Game runs at **20 ticks per second** (50ms per tick). If drawing falls behind, the ticks owed are run before the next frame is drawn, so the match keeps its pace at a lower frame rate.
- Each tick:
  1. Regenerate energy, count down cooldowns
  2. Run each bot's `tick()`, then carry out the turn and speed it has asked for
  3. Deliver `onScanned` to bots that were found by a scan
  4. Move the bots; resolve wall and bot collisions; deliver `onWall` and `onCollision`
  5. Move the shots, testing each along its path; apply damage and deliver `onHit`, `onShotHit`, `onKill`
  6. Advance the effects
  7. Check whether one bot or none is left

Both bots take their tick before either moves, so each sees the other where it was at the end of the last tick, whichever is bot 1.

### Coordinate System
- Origin (0, 0) at top-left of arena
- Angles: 0° = up, 90° = right, 180° = down, 270° = left
- Positive turn = clockwise

## Menu Flow

```
BOTWARZ
├── START MATCH
│   ├── Select Bot 1 (from bots/ directory)
│   ├── Select Bot 2
│   └── ENTER begins
├── HOW TO PLAY
│   └── keys, the bot API, the avatars
└── QUIT
```

## Victory Conditions

- The last bot standing wins. When a bot is destroyed the match stops where it is: the wreckage drifts, shots still in the air fly on harmlessly, and the winner's name is shown over the arena, followed by "Press any key to continue".
- If both are destroyed on the same tick it is a draw.
- There is no time limit yet, and some pairs of bots never find each other (two Campers, for one); `ESC` ends such a match.

## Ideas Not Yet Built

- **Match clock**: end a match after a set time, highest HP winning, so that every match has a result
- **Rounds**: best of N, with the bots swapping corners
- **Energy that matters more**: driving could cost energy, or a shield could, so that a bot has to budget
- **A gun that takes time to turn**: the gun now swings to any bearing at once; a turn rate of its own would make aiming a skill and `bot.aim()` worth having
- **Ramming damage**
- **Obstacles** in the arena, which scans and shots would stop at
- **3rd bot** (the simulation already treats the bots as a list; the status bar and start positions assume two)
