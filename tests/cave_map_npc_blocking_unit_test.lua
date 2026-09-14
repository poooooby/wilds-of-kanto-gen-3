-- Regression: wild Pokemon wander must treat native map NPCs (trainers,
-- signs, Strength boulders -- ow.npcs) as blocked cells, not just Wilds'
-- own ow.entities. Reported live: cave wild mons wandering onto a
-- boulder/trainer-occupied cell in MT_MOON_1F that looks like solid wall.
-- Run: lua tests/cave_map_npc_blocking_unit_test.lua
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

local modules = {}
local V = {
  mod = {
    path = ".",
    log = { info = function() end, warn = function() end, error = function() end },
    find = function() return nil end,
    options = { get = function() return nil end },
  },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local Behavior = V.require("behavior")
local Surface = V.require("surface")

-- Deterministic rng: shuffle is a no-op (rng(i) = i keeps dirs in their
-- original order: up, down, left, right) and the no-arg float call always
-- clears the 0.35 "face only, don't move" branch.
local function detRng(a, b)
  if b then return a end
  if a then return a end
  return 0.9
end

-- Open 5x5 room, every cell walkable, no real walls anywhere -- isolates
-- the map-NPC check from ordinary tile collision.
local openMap = {
  widthCells = 5,
  heightCells = 5,
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 5 and y < 5 end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  isGrassCell = function() return false end,
  warpAtCell = function() return nil end,
}

local function makeWanderEntity()
  local e = {
    id = "wild_1",
    species = "GEODUDE",
    cellX = 2, cellY = 2,
    surface = Surface.CAVE,
    overworldWildSpawn = true,
    passable = false,
  }
  Behavior.attach(e, Behavior.GRASS_WANDER, nil, detRng)
  e.behaviorState.nextActionAt = 0 -- bypass the initial idle-look cooldown
  return e
end

print("== baseline: without mapNpcs, up (2,1) is a free choice ==")
local baseline = makeWanderEntity()
Behavior.tick(baseline, {
  map = openMap,
  entities = { baseline },
  player = { cellX = 4, cellY = 4 },
  rng = detRng,
  dt = 0.016,
})
check(baseline.movement and baseline.movement.targetTileX == 2
  and baseline.movement.targetTileY == 1,
  "baseline steps up onto (2,1) when nothing blocks it (got "
    .. tostring(baseline.movement and baseline.movement.targetTileX) .. ","
    .. tostring(baseline.movement and baseline.movement.targetTileY) .. ")")

print("== fix: a stationary map NPC at (2,1) must be treated as blocked ==")
local guarded = makeWanderEntity()
Behavior.tick(guarded, {
  map = openMap,
  entities = { guarded },
  mapNpcs = { { cellX = 2, cellY = 1 } }, -- e.g. a Strength boulder / trainer
  player = { cellX = 4, cellY = 4 },
  rng = detRng,
  dt = 0.016,
})
check(not (guarded.movement and guarded.movement.targetTileX == 2
  and guarded.movement.targetTileY == 1),
  "never steps onto the map-NPC-occupied cell (2,1)")
check(guarded.movement and guarded.movement.targetTileX == 2
  and guarded.movement.targetTileY == 3,
  "falls through to the next direction (down, 2,3) instead (got "
    .. tostring(guarded.movement and guarded.movement.targetTileX) .. ","
    .. tostring(guarded.movement and guarded.movement.targetTileY) .. ")")

print("== a map NPC that has since moved off the cell no longer blocks it ==")
local vacated = makeWanderEntity()
Behavior.tick(vacated, {
  map = openMap,
  entities = { vacated },
  mapNpcs = { { cellX = 0, cellY = 0 } }, -- occupies an unrelated cell
  player = { cellX = 4, cellY = 4 },
  rng = detRng,
  dt = 0.016,
})
check(vacated.movement and vacated.movement.targetTileX == 2
  and vacated.movement.targetTileY == 1,
  "steps up onto (2,1) when the map NPC is elsewhere")

print("== initial spawn placement must also avoid map-NPC-occupied cells ==")
local Grass = V.require("grass")

local spawnMap = {
  widthCells = 5,
  heightCells = 5,
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 5 and y < 5 end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  isGrassCell = function() return false end,
  warpAtCell = function() return nil end,
}
local player = { cellX = 4, cellY = 4 }

local okNoNpc, reasonNoNpc = Grass.validateWalkableTile(
  spawnMap, {}, player, 2, 1, 0, nil, nil, nil)
check(okNoNpc == true, "cell (2,1) valid with no map NPCs (reason="
  .. tostring(reasonNoNpc) .. ")")

local okWithNpc, reasonWithNpc = Grass.validateWalkableTile(
  spawnMap, {}, player, 2, 1, 0, nil, nil, { { cellX = 2, cellY = 1 } })
check(okWithNpc == false, "cell (2,1) rejected once a map NPC (e.g. a boulder) occupies it")
check(reasonWithNpc == "rejected: occupied by NPC",
  "rejection reason names NPC occupancy (got " .. tostring(reasonWithNpc) .. ")")

-- Two-cell candidate pool, rng forced to "pick the first candidate" (index
-- 1): (2,1) is first in the list, so the baseline call must return it, and
-- the guarded call can only return it if the map NPC failed to exclude it
-- from the pool -- proving exclusion from the pool itself, not just that a
-- different index got hit.
local twoCells = { { x = 2, y = 1 }, { x = 0, y = 0 } }
local firstIndexRng = function() return 1 end

local pxBase, pyBase = Grass.pickFree(
  spawnMap, {}, player, 0, firstIndexRng, twoCells, 12, nil, { mode = "walkable" })
check(pxBase == 2 and pyBase == 1,
  "baseline: (2,1) is a normal candidate absent any map NPC (got "
    .. tostring(pxBase) .. "," .. tostring(pyBase) .. ")")

local pxGuarded, pyGuarded = Grass.pickFree(
  spawnMap, {}, player, 0, firstIndexRng, twoCells, 12, nil, {
    mode = "walkable",
    mapNpcs = { { cellX = 2, cellY = 1 } },
  })
check(pxGuarded == 0 and pyGuarded == 0,
  "guarded: (2,1) is dropped from the candidate pool, only (0,0) remains (got "
    .. tostring(pxGuarded) .. "," .. tostring(pyGuarded) .. ")")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("cave_map_npc_blocking_unit_test: all passed")
