-- Gold cave reachability on the REAL Gold maps: the directed fill must agree with the engine's own offline model
-- (tools/goldwalk/mapgraph.lua) on every cave / dungeon map from every warp arrival, and must beat the plain grid fill.
-- Needs a Gen1Recomp checkout that has the extracted Gold data (gold/data/generated) and src/; skips without one.
--   GEN1RECOMP_GOLD_ROOT=/path/to/gen1recomp lua tests/cave_reachability_gold_data_unit_test.lua
-- Default lookups: $GEN1RECOMP_GOLD_ROOT, ../gen1recomp
package.path = "./?.lua;./?/init.lua;" .. package.path

local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end
local root
local candidates = {}
local envRoot = os.getenv("GEN1RECOMP_GOLD_ROOT")
if type(envRoot) == "string" and envRoot ~= "" then candidates[#candidates + 1] = envRoot end
candidates[#candidates + 1] = "../gen1recomp"
for _, cand in ipairs(candidates) do
  if fileExists(cand .. "/gold/data/generated/maps.lua") and fileExists(cand .. "/src/world/gen2/Map.lua") then
    root = cand
    break
  end
end
if not root then
  print("skip: no Gen1Recomp checkout with extracted Gold data (set GEN1RECOMP_GOLD_ROOT)")
  os.exit(0)
end

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

package.path = root .. "/?.lua;" .. package.path
package.loaded["src.core.GameVersion"] = {
  fixes = function() return { sideWallArms = false } end, -- Gold (Crystal fixes it)
  get = function() return "gold" end, isYellow = function() return false end,
  isGold = function() return true end, generation = function() return 2 end,
}
package.loaded["src.core.Logger"] = { warn = function() end, info = function() end }
local Permissions = require("src.world.gen2.Permissions")
local Map = require("src.world.gen2.Map")

local V = { mod = {}, path = "." }
local cache = {}
function V.require(name)
  if not cache[name] then cache[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return cache[name]
end
local CR = V.require("cave_reachability")

local G = root .. "/gold/data/generated/"
local maps = dofile(G .. "maps.lua")
local tilesets = dofile(G .. "tilesets.lua")
local enc = dofile(G .. "encounters.lua")

local ORDER = { { 0, -1, "up" }, { 0, 1, "down" }, { -1, 0, "left" }, { 1, 0, "right" } }
local function key(x, y) return x .. ":" .. y end

-- Reference model: a line-for-line port of the engine tool's stepsFrom / region (tools/goldwalk/mapgraph.lua).
local function reference(map, def)
  local coll = function(x, y) return map:cellCollision(x, y) end
  local function hole(x, y)
    for _, w in ipairs(def.warps or {}) do
      if w.x == x and w.y == y then
        local c = coll(x, y)
        return Permissions.isWarpCollision(c) or Permissions.carpetDirection(c) ~= nil
      end
    end
    return false
  end
  local function passable(x, y)
    return map:inBounds(x, y) and Permissions.isWalkable(coll(x, y)) and not hole(x, y)
  end
  local function region(sx, sy)
    local seen = { [key(sx, sy)] = true }
    local queue, head = { { sx, sy } }, 1
    while head <= #queue do
      local c = queue[head]
      head = head + 1
      local hop = Permissions.ledgeFacings(coll(c[1], c[2]))
      for _, d in ipairs(ORDER) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local to
        if Permissions.stepPermitted(coll, c[1], c[2], d[3]) and passable(nx, ny) then
          to = { nx, ny }
        elseif hop and hop[d[3]] and passable(c[1] + d[1] * 2, c[2] + d[2] * 2) then
          to = { c[1] + d[1] * 2, c[2] + d[2] * 2 }
        end
        if to and not seen[key(to[1], to[2])] then
          seen[key(to[1], to[2])] = true
          queue[#queue + 1] = to
        end
      end
    end
    return seen, passable
  end
  return region
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local ids = {}
for id, def in pairs(maps) do
  if type(def) == "table" and (def.environment == "CAVE" or def.environment == "DUNGEON") and def.blocks and tilesets[def.tileset] then
    ids[#ids + 1] = id
  end
end
table.sort(ids)

local checked, wildMaps, improved, arrivals = 0, 0, 0, 0
local byId = {}
for _, id in ipairs(ids) do
  local def = maps[id]
  local map = Map.new(def, tilesets[def.tileset])
  local region = reference(map, def)
  local hasWild = (enc.grass and enc.grass[id] ~= nil) or (enc.water and enc.water[id] ~= nil)
  if hasWild then wildMaps = wildMaps + 1 end
  local mapImproved = false
  for i, w in ipairs(def.warps or {}) do
    arrivals = arrivals + 1
    local player = { cellX = w.x, cellY = w.y }
    local data = CR.build(map, player, {})
    check(data.model == "gold", id .. ": uses the directed Gold fill")
    local reg, standableAt = region(w.x, w.y)
    -- the mod's set is the engine's region minus holes, exactly: no fabricated cell, no missed one
    local extra, missed = 0, 0
    for k in pairs(data.reachable) do if not reg[k] then extra = extra + 1 end end
    for k in pairs(reg) do
      local x, y = k:match("(%d+):(%d+)")
      x, y = tonumber(x), tonumber(y)
      if standableAt(x, y) and not data.reachable[k] then missed = missed + 1 end
    end
    check(extra == 0, string.format("%s warp %d: %d cells reachable to the mod but not to the engine", id, i, extra))
    check(missed == 0, string.format("%s warp %d: %d cells reachable to the engine but missed by the mod", id, i, missed))
    checked = checked + 1
    local grid = CR.build(map, player, { directed = false })
    if grid.reachableCount > data.reachableCount then mapImproved = true end
    byId[id] = byId[id] or {}
    -- the engine tool counts the arrival cell itself; the mod's set has only standable cells
    byId[id][i] = { mod = data.reachableCount, engine = count(reg), grid = grid.reachableCount, hole = not standableAt(w.x, w.y) }
  end
  if mapImproved and hasWild then improved = improved + 1 end
end
check(#ids >= 60, "the Gold data has its cave / dungeon maps (" .. #ids .. ")")
check(arrivals >= 100, "many warp arrivals were checked (" .. arrivals .. ")")
check(improved >= 30, "the directed fill differs from the plain grid fill on most wild-table caves (" .. improved .. ")")

-- Pinned to the engine tool's own answers (`mapgraph.lua reach MAP X Y`, which counts the start cell).
local function pinned(id, warp, engineCount, note)
  local r = byId[id] and byId[id][warp]
  check(r ~= nil, id .. " warp " .. warp .. " exists")
  if r then
    check(r.engine == engineCount, string.format("%s: reference model gives %d cells, the engine tool says %d", id, r.engine, engineCount))
    check(r.mod + (r.hole and 1 or 0) == engineCount,
      string.format("%s warp %d: mod %d (+start hole) should equal the engine tool's %d (%s)", id, warp, r.mod, engineCount, note))
  end
end
pinned("UNION_CAVE_1F", 1, 180, "the grid fill said 438")
pinned("DARK_CAVE_BLACKTHORN_ENTRANCE", 1, 21, "the grid fill said 705")
pinned("RUINS_OF_ALPH_INNER_CHAMBER", 1, 334, "the grid fill missed 144 cells")
pinned("MOUNT_MORTAR_B1F", 1, 75, "the grid fill said 540")
check(byId.UNION_CAVE_1F and byId.UNION_CAVE_1F[1].grid == 438, "Union Cave 1F: the plain grid fill really did mark all 438 cells reachable")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print(string.format("cave_reachability_gold_data_unit_test: %d arrivals on %d Gold cave maps (%d with wild tables) match the engine model; all passed",
  checked, #ids, wildMaps))
