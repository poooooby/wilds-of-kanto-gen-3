-- Regression: cave reachability BFS must respect Gen1's directional
-- elevation/ledge tile-pair collisions, not just per-cell isWalkableCell.
-- Reported live: MT_MOON_1F spawned wild mons in a pocket only reachable
-- by crossing a ledge the real player can never climb back through
-- (real tile pair: CAVERN tileset a=32 b=5), making the pocket look
-- connected to a BFS that only checks single-cell walkability.
-- Run: lua tests/cave_ledge_tile_pair_unit_test.lua
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

local V = { path = ".", mod = {}, require = function() error("no nested require") end }
local CaveReachability = assert(loadfile("lib/cave_reachability.lua"))(V)

-- 1x5 corridor: (0,0)-(4,0), all floor, no warps. A ledge sits between
-- (1,0) [tile 32] and (2,0) [tile 5], mirroring the real CAVERN pair.
local tiles = { [0] = 1, [1] = 32, [2] = 5, [3] = 1, [4] = 1 }
local corridor = {
  widthCells = 5,
  heightCells = 1,
  def = { tileset = "CAVERN" },
  inBounds = function(_, x, y) return x >= 0 and x < 5 and y == 0 end,
  isWalkableCell = function(_, x, y) return x >= 0 and x < 5 and y == 0 end,
  isWaterCell = function() return false end,
  warpAtCell = function() return nil end,
  cellTile = function(_, x, y) return tiles[x] end,
}
local player = { cellX = 0, cellY = 0 }
local tilePairs = { { tileset = "CAVERN", a = 32, b = 5 } }

print("== without tilePairs: BFS has no ledge awareness ==")
local noPairs = CaveReachability.build(corridor, player)
check(CaveReachability.isReachable(noPairs, 4, 0),
  "reaches (4,0) across the ledge when no tile-pair data is supplied")

print("== with tilePairs: the ledge blocks BFS from crossing it ==")
local withPairs = CaveReachability.build(corridor, player, { tilePairs = tilePairs })
check(CaveReachability.isReachable(withPairs, 1, 0), "still reaches (1,0), before the ledge")
check(not CaveReachability.isReachable(withPairs, 2, 0), "cannot cross onto (2,0), past the ledge")
check(not CaveReachability.isReachable(withPairs, 4, 0), "far side (4,0) is unreachable")

print("== the pair check is direction-agnostic (matches a<->b either order) ==")
local player2 = { cellX = 4, cellY = 0 }
local fromFarSide = CaveReachability.build(corridor, player2, { tilePairs = tilePairs })
check(CaveReachability.isReachable(fromFarSide, 2, 0), "still reaches (2,0) from the far side")
check(not CaveReachability.isReachable(fromFarSide, 1, 0),
  "cannot cross back onto (1,0) from the far side either")
check(not CaveReachability.isReachable(fromFarSide, 0, 0), "near side (0,0) is unreachable from here")

print("== a tileset mismatch never blocks (pair is per-tileset) ==")
local otherTileset = {
  widthCells = 5,
  heightCells = 1,
  def = { tileset = "ROCK_TUNNEL" },
  inBounds = function(_, x, y) return x >= 0 and x < 5 and y == 0 end,
  isWalkableCell = function(_, x, y) return x >= 0 and x < 5 and y == 0 end,
  isWaterCell = function() return false end,
  warpAtCell = function() return nil end,
  cellTile = function(_, x, y) return tiles[x] end,
}
local diffTileset = CaveReachability.build(otherTileset, player, { tilePairs = tilePairs })
check(CaveReachability.isReachable(diffTileset, 4, 0),
  "same tile ids on a different tileset are unaffected by a CAVERN-only pair")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("cave_ledge_tile_pair_unit_test: all passed")
