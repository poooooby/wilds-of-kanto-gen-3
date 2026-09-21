-- Gold cave reachability: a directed flood fill over the engine's own movement rules (one-way UP_WALL edges, ledge hops,
-- warp HOLES decided by collision, not by warp_event coordinates). The engine's Permissions module is stubbed with the same
-- rules for the handful of collision bytes used here, so the test needs no engine checkout.
-- Run: lua tests/cave_reachability_gold_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

-- ------------------------------------------------------------------ stubbed engine rules (src/world/gen2/Permissions.lua)
local WALL, UP_WALL, HOP_DOWN, HOP_RIGHT, WARP = 0x07, 0xb2, 0xa3, 0xa0, 0x72
local P = {}
function P.isWalkable(c) return c ~= nil and c ~= WALL and c ~= 0xff end
function P.isWarpCollision(c) return c ~= nil and math.floor(c / 16) == 7 end
function P.carpetDirection() return nil end
local LEDGE = { [0x3] = { down = true }, [0x0] = { right = true } }
function P.ledgeFacings(c) if c and math.floor(c / 16) == 0xa then return LEDGE[c % 8] end end
package.loaded["src.world.gen2.Permissions"] = P

local V = { mod = {}, path = "." }
local cache = {}
function V.require(name)
  if not cache[name] then cache[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return cache[name]
end
local CR = V.require("cave_reachability")

-- F floor, # wall, U up-wall, L hop-down ledge, R hop-right ledge, W real warp tile (collision + event),
-- E warp_event on plain floor, V warp-collision tile with NO warp event
local CH = { F = 0x00, ["#"] = WALL, U = UP_WALL, L = HOP_DOWN, R = HOP_RIGHT, W = WARP, E = 0x00, V = WARP }
local function goldMap(rows)
  local m = { id = "GOLD_DEMO", widthCells = #rows[1], heightCells = #rows }
  local function coll(x, y)
    local r = rows[y + 1]
    if not r or x < 0 or x >= #r then return 0xff end
    return CH[r:sub(x + 1, x + 1)]
  end
  local function event(x, y)
    local r = rows[y + 1]
    local ch = r and r:sub(x + 1, x + 1)
    return ch == "W" or ch == "E"
  end
  m.cellCollision = function(_, x, y) return coll(x, y) end
  m.inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < m.widthCells and y < m.heightCells end
  m.isWalkableCell = function(_, x, y) return m:inBounds(x, y) and P.isWalkable(coll(x, y)) end
  m.isWaterCell = function() return false end
  m.warpAtCell = function(_, x, y) if event(x, y) then return {} end end
  -- Gold's side-wall rules (bug-compatible arms): standing on an UP_WALL you cannot move up; nobody steps DOWN onto one.
  m.stepPermitted = function(_, x, y, dir)
    if coll(x, y) == UP_WALL and dir == "up" then return false end
    if dir == "down" and coll(x, y + 1) == UP_WALL then return false end
    return true
  end
  return m
end
local function reach(rows, px, py, opts)
  local map = goldMap(rows)
  local data = CR.build(map, { cellX = px, cellY = py }, opts or {})
  return data, map
end
local function has(data, x, y) return CR.isReachable(data, x, y) end

-- ------------------------------------------------------------------ the fill picks the Gold model
local data = reach({ "FF", "FF" }, 0, 0)
eq(data.model, "gold", "a map that exposes stepPermitted / cellCollision uses the directed Gold fill")
eq(reach({ "FF", "FF" }, 0, 0, { directed = false }).model, "grid", "directed = false keeps the plain grid fill")
local plain = { widthCells = 2, heightCells = 2, isWalkableCell = function() return true end }
eq(CR.build(plain, { cellX = 0, cellY = 0 }, {}).model, "grid", "a Gen 1 style map (no stepPermitted) keeps the grid fill")

-- ------------------------------------------------------------------ one-way UP_WALL edge below a ledge room
-- The player is BELOW: they may step up onto the UP_WALL cell but never past it, so the room above is not theirs.
local cliff = { "#F#", "#F#", "#L#", "#U#", "#F#", "#F#" }
data = reach(cliff, 1, 5)
check(has(data, 1, 4) and has(data, 1, 3), "from below: the floor and the UP_WALL cell itself are reachable")
check(not has(data, 1, 2) and not has(data, 1, 1) and not has(data, 1, 0),
  "from below: the ledge cell and the room above the one-way edge are NOT reachable")
data = reach(cliff, 1, 5, { directed = false })
check(has(data, 1, 0), "the plain grid fill would have fabricated the room above (the bug this fixes)")

-- From ABOVE the player cannot step down onto the UP_WALL cell (nobody may), so the lower area is not theirs either.
data = reach({ "#F#", "#F#", "#U#", "#F#", "#F#" }, 1, 0)
check(has(data, 1, 1) and not has(data, 1, 2) and not has(data, 1, 3), "from above: the edge cell and everything past it are unreachable")

-- ------------------------------------------------------------------ ledge hops
-- Standing on a hop-down ledge whose next cell is a wall, the refused step hops two cells and lands past the wall.
local hop = { "#F#", "#L#", "###", "#F#", "#F#" }
data = reach(hop, 1, 0)
check(has(data, 1, 1), "the ledge cell is reachable by walking")
check(has(data, 1, 3) and has(data, 1, 4), "a hop-down ledge lands the player two cells on: the pocket below IS reachable")
data = reach(hop, 1, 4)
check(has(data, 1, 3), "sanity: the lower pocket is reachable from inside it")
check(not has(data, 1, 1) and not has(data, 1, 0), "and there is no way back up: a hop never comes back")
data = reach({ "FRF#F", "#####" }, 0, 0)
check(has(data, 1, 0) and has(data, 2, 0), "a hop only fires when the plain step is refused (here the step is open)")
data = reach({ "FR#F", "####" }, 0, 0)
check(has(data, 3, 0), "a hop-right ledge hops right over the wall")
data = reach({ "F#F" }, 0, 0)
check(not has(data, 2, 0), "a plain wall with no ledge is never hopped")

-- ------------------------------------------------------------------ warp holes are decided by collision
-- A warp_event on plain floor (a ladder landing spot) never fires, so it must not cut a one-wide corridor.
data = reach({ "FEF" }, 0, 0)
check(has(data, 2, 0), "a warp_event on plain floor does not block the corridor")
data = reach({ "FEF" }, 0, 0, { directed = false })
check(not has(data, 2, 0), "the grid fill treated it as a hole (the second bug this fixes)")
-- A real warp tile is a hole.
data = reach({ "FWF" }, 0, 0)
check(not has(data, 1, 0) and not has(data, 2, 0), "a real warp tile is a hole in the floor")
-- A warp-collision tile with no warp event does nothing in the game (CheckWarpTile finds no warp), so it is floor.
data = reach({ "FVF" }, 0, 0)
check(has(data, 1, 0) and has(data, 2, 0), "a warp-collision tile with no warp event is plain floor, not a hole")
-- Arriving ON a real warp tile: only the steps the player may take seed the fill.
data = reach({ "#F#", "#F#", "#W#", "#U#", "#F#" }, 1, 2)
check(has(data, 1, 1) and has(data, 1, 0), "arriving on a warp hole: the open side is reachable")
check(not has(data, 1, 3), "arriving on a warp hole: a step it may not take (down onto an UP_WALL) seeds nothing")
eq(data.status, "FALLBACK", "seeding from a hole's neighbours reports FALLBACK like the grid fill")
data = reach({ "FEF" }, 1, 0)
check(has(data, 0, 0) and has(data, 2, 0) and has(data, 1, 0), "arriving on a plain-floor landing spot seeds that cell itself")
eq(data.status, "READY", "and that is a normal READY fill")

-- ------------------------------------------------------------------ classification still keeps spawns off warp-event cells
local rows = { "FEF" }
local map = goldMap(rows)
data = CR.build(map, { cellX = 0, cellY = 0 }, {})
eq(CR.classifyCell(map, data, 1, 0), CR.CLASS.INVALID, "a warp-event cell is never a spawn candidate")
eq(CR.classifyCell(map, data, 2, 0), CR.CLASS.REACHABLE, "but the cell beyond it is reachable and spawnable")

-- ------------------------------------------------------------------ entry seeds and rebuild still work
local twoRooms = { "FF#FF" }
data = reach(twoRooms, 0, 0, { entrySeeds = { { x = 4, y = 0 } } })
check(has(data, 3, 0) and has(data, 4, 0) and has(data, 1, 0), "explicit entry seeds join the fill")
data = reach(twoRooms, 0, 0)
check(CR.needsRebuild(data, goldMap(twoRooms), { cellX = 4, cellY = 0 }) == true,
  "a player standing outside the mask (another room) triggers a rebuild")

-- ------------------------------------------------------------------ no Permissions module: quietly stays on the grid fill
package.loaded["src.world.gen2.Permissions"] = nil
local realRequire = require
_G.require = function(name)
  if name == "src.world.gen2.Permissions" then error("module not found") end
  return realRequire(name)
end
eq(reach({ "FF" }, 0, 0).model, "grid", "without the engine's Permissions module the fill falls back to the grid model")
_G.require = realRequire

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("cave_reachability_gold_unit_test: all passed")
