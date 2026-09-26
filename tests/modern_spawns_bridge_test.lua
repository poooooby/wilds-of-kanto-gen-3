-- Standalone, from a gen1recomp root that has this mod, modern_spawns and
-- Red + Gold imported:
--   luajit mods/overworld_wild_spawns/tests/modern_spawns_bridge_test.lua
-- Skips (exit 0) when mods/modern_spawns is not installed next to this mod.
--
-- Visible spawns pick from Modern Spawns' generated tables when that mod is
-- active (lib/modern_spawns_bridge.lua), and from the game's own tables when
-- it is absent or OFF. The game's tables are never modified.
package.path = "./?.lua;./?/init.lua;" .. package.path

local SELF = ((arg and arg[0]) or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$")
  or "mods/overworld_wild_spawns"
local MS = "mods/modern_spawns"
local probe = io.open(MS .. "/manifest.json")
if not probe then
  print("SKIP: " .. MS .. " is not installed")
  os.exit(0)
end
probe:close()

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")

local function serialize(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function speciesSet(slots)
  local set = {}
  for _, s in ipairs(slots or {}) do set[s.species] = true end
  return set
end

local function setOption(loader, key, value)
  loader.modOptions.modern_spawns[key] = value
  loader.events:emit("mod.options_changed", { mod = "modern_spawns", key = key, value = value })
end

-- ------------------------------------------------------------------ Red

GameVersion.set("red")
local Data = require("src.core.Data")
Data:load()
local before = serialize(Data.encounters)

local run = T.sdk.loadMods({ MS .. "/tests/fixtures/modern/national_dex", MS, SELF },
                           { data = Data })
T.eq(#run.errors, 0, "Red: loads clean with Modern Spawns (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "PALLET" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local ms = loader.exports.modern_spawns
local wilds = loader.exports.wilds_of_kanto_gen3
T.check(ms.isActive(), "Modern Spawns is active")
local lib = wilds.lib
local GameCompat = lib.require("game_compat")
local EncounterPick = lib.require("encounter_pick")
local AmbientPokemon = lib.require("ambient_pokemon")
local WaterSpawn = lib.require("water_spawn")
local EncounterIndex = lib.require("encounter_index")
local Bridge = lib.require("modern_spawns_bridge")
local game = { data = Data }

local generated = ms.tableFor("ROUTE_1", "grass")
local def = GameCompat.encountersForMap(game, "ROUTE_1")
T.eq(serialize(def.grass.slots), serialize(generated.slots),
     "Route 1 grass is Modern Spawns' table")
local genSet = speciesSet(generated.slots)
local allGenerated = true
for _ = 1, 100 do
  local pick = EncounterPick.pick(def, nil, "grass")
  if not (pick and genSet[pick.species]) then allGenerated = false end
end
T.check(allGenerated, "every visible grass pick is a generated species")
local changed = false
for sp in pairs(genSet) do
  if not speciesSet(Data.encounters.ROUTE_1.grass.slots)[sp] then changed = true end
end
T.check(changed, "and they differ from the cart's Route 1")

local waterMap
for mapId, enc in pairs(Data.encounters) do
  if enc.water and ms.tableFor(mapId, "water") then waterMap = mapId break end
end
T.check(waterMap ~= nil, "a map with a generated surf table exists")
T.eq(serialize(GameCompat.encountersForMap(game, waterMap).water.slots),
     serialize(ms.tableFor(waterMap, "water").slots), waterMap .. " surf is generated too")

local pool = AmbientPokemon.speciesPool(game, "ROUTE_1", nil)
local poolOk = #pool > 0
for _, sp in ipairs(pool) do if not genSet[sp] then poolOk = false end end
T.check(poolOk, "ambient Pokemon draw from the generated table")

local rodMap
for mapId in pairs(Data.field.superRod) do
  if ms.superRodFor(mapId) then rodMap = mapId break end
end
if rodMap then
  local rods = WaterSpawn.rodSlotsForMap(game, rodMap)
  local want = speciesSet(ms.superRodFor(rodMap))
  local rodOk = #rods.super > 0
  for _, s in ipairs(rods.super) do if not want[s.species] then rodOk = false end end
  T.check(rodOk, rodMap .. " Super Rod water mons are Modern Spawns' catches")
end

local index = EncounterIndex.build(game)
local newInIndex = false
for sp in pairs(genSet) do
  if not speciesSet(Data.encounters.ROUTE_1.grass.slots)[sp] and index[sp] then newInIndex = true end
end
T.check(newInIndex, "the encounter index lists generated species")

-- LEGENDARIES
setOption(loader, "legendaries", "on")
local homes = ms.legendaryHomes()
local home, hosts
for mapId, byKind in pairs(homes or {}) do
  if byKind.grass and Data.encounters[mapId] then home, hosts = mapId, byKind.grass break end
end
if home then
  local hostSet = {}
  for _, h in ipairs(hosts) do hostSet[h.id] = true end
  local hits, onlyHosts = 0, true
  for _ = 1, 20000 do
    local id = Bridge.legendary(home, "grass")
    if id then hits = hits + 1 if not hostSet[id] then onlyHosts = false end end
  end
  T.check(hits > 0, "visible spawns get the rare legendary roll on " .. home .. " (" .. hits .. "/20000)")
  T.check(onlyHosts, "only with that map's hosts")
end
setOption(loader, "legendaries", "off")
T.eq(Bridge.legendary(home or "ROUTE_1", "grass"), nil, "no legendary with LEGENDARIES OFF")

-- RANDOM: a fresh table per pick
setOption(loader, "spawn_mode", "random")
local seen = {}
for _ = 1, 8 do seen[serialize(GameCompat.encountersForMap(game, "ROUTE_1").grass.slots)] = true end
local draws = 0
for _ in pairs(seen) do draws = draws + 1 end
T.check(draws > 1, "RANDOM: visible spawns draw afresh (" .. draws .. " tables)")
setOption(loader, "spawn_mode", "seeded")

-- OFF: the game's own table, the same object
setOption(loader, "enabled", "off")
T.check(GameCompat.encountersForMap(game, "ROUTE_1") == Data.encounters.ROUTE_1,
        "MODERN SPAWNS OFF: the cart's own table")
T.eq(serialize(Data.encounters), before, "the cart's tables were never modified")

-- Modern Spawns not installed: mod:find answers nil (one boot per process,
-- so this stands in for loading Wilds on its own)
setOption(loader, "enabled", "on")
local find = lib.mod.find
lib.mod.find = function() return nil end
T.check(GameCompat.encountersForMap(game, "ROUTE_1") == Data.encounters.ROUTE_1,
        "without Modern Spawns: the cart's own table")
lib.mod.find = find
run.release()

T.finish("wilds modern_spawns bridge")
