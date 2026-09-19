-- Modern Kanto encounter overlay: lib/dex_expansion.lua (the dex gate) and
-- lib/gen9_encounters.lua (the overlay, data version 2 = variable-length bucket ladders),
-- plus the Gen 1 adapter seam.
-- Run: lua tests/gen9_encounters_unit_test.lua
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

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = deepCopy(v) end
  return o
end
local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- ---------------------------------------------------------------- fixtures
local savedOpts = {}
local liveBucket = {}
local game
local mod = {
  id = "wilds_of_kanto_gen3", path = ".",
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k) return savedOpts[k] end },
}

local modules = {}
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

-- ladder({ {threshold, species, level}, ... }) -> { buckets = {...}, slots = {...} }
local function ladder(rows)
  local b, s = {}, {}
  for i, r in ipairs(rows) do
    b[i] = r[1]
    s[i] = { level = r[3], species = r[2], dex = 400 }
  end
  return { buckets = b, slots = s }
end

-- A 12-slot overlay (longer than the engine's default 10) where some slots name a species that is
-- never registered (MISSING_MON), so per-slot fallback is exercised at several probability positions.
local R1_GRASS = ladder({
  { 40, "FIXA", 30 },  { 80, "FIXB", 31 },  { 120, "MISSING_MON", 32 }, { 150, "FIXA", 33 },
  { 180, "MISSING_MON", 34 }, { 200, "FIXB", 35 }, { 215, "FIXA", 36 }, { 228, "MISSING_MON", 37 },
  { 240, "FIXB", 38 }, { 248, "FIXA", 39 }, { 253, "MISSING_MON", 40 }, { 256, "FIXB", 41 },
})
local DATA = {
  version = 2,
  maps = {
    ROUTE_1 = {
      grass = R1_GRASS,
      superRod = { { level = 20, species = "FIXA", dex = 400 }, { level = 20, species = "MISSING_MON", dex = 999 },
                   { level = 21, species = "FIXB", dex = 401 }, { level = 21, species = "FIXB", dex = 401 } },
    },
    ROUTE_2 = {
      grass = ladder({ { 100, "FIXA", 40 }, { 180, "FIXA", 41 }, { 256, "FIXA", 42 } }),
      water = ladder({ { 200, "FIXB", 41 }, { 256, "FIXB", 42 } }),
    },
    -- vanilla here has its own 2-slot ladder; the overlay's MISSING slot sits at position ~200
    ROUTE_3 = { grass = ladder({ { 100, "FIXA", 50 }, { 256, "MISSING_MON", 51 }, }) },
    -- malformed ladders must fail closed to vanilla
    ROUTE_4 = { grass = { buckets = { 100, 255 }, slots = { { level = 5, species = "FIXA" }, { level = 5, species = "FIXB" } } } },
    ROUTE_6 = { grass = { buckets = { 100, 256 }, slots = { { level = 5, species = "FIXA" } } } },
    ROUTE_7 = { grass = { buckets = { 200, 100, 256 }, slots = { { level = 5, species = "FIXA" }, { level = 5, species = "FIXA" }, { level = 5, species = "FIXA" } } } },
  },
}
modules.gen9_encounters_data = DATA

local function vanillaSlots(a, b)
  local out = {}
  for i = 1, 10 do out[i] = { level = 3, species = (i % 2 == 1) and a or b } end
  return out
end
local DEFAULT_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

local function newGame(withModern)
  local g = { data = {
    pokemon = { PIDGEY = { dex = 16 }, RATTATA = { dex = 19 }, MEOWTH_ALOLA = { dex = 30107 } },
    encounters = {
      ROUTE_1 = { grass = { rate = 25, slots = vanillaSlots("PIDGEY", "RATTATA"), buckets = deepCopy(DEFAULT_BUCKETS) } },
      ROUTE_2 = { grass = { rate = 25, slots = vanillaSlots("PIDGEY", "RATTATA") }, water = { rate = 5, slots = vanillaSlots("PIDGEY", "RATTATA") } },
      ROUTE_3 = { grass = { rate = 20, buckets = { 128, 256 }, slots = { { level = 7, species = "PIDGEY" }, { level = 8, species = "RATTATA" } } } },
      ROUTE_4 = { grass = { rate = 20, slots = vanillaSlots("PIDGEY", "RATTATA") } },
      ROUTE_5 = { grass = { rate = 15, slots = vanillaSlots("PIDGEY", "RATTATA") } },
      ROUTE_6 = { grass = { rate = 20, slots = vanillaSlots("PIDGEY", "RATTATA") } },
      ROUTE_7 = { grass = { rate = 20, slots = vanillaSlots("PIDGEY", "RATTATA") } },
    },
  } }
  if withModern then
    g.data.pokemon.FIXA = { dex = 400 }
    g.data.pokemon.FIXB = { dex = 401 }
  end
  return g
end

mod.world = nil
local function setGame(g)
  game = g
  mod.world = { game = g }
  -- Mirrors what Config.setOption/writeOptionBucket write and peekSavedOption reads.
  g.save = { options = { modOptions = { [mod.id] = liveBucket } } }
end

local Config = V.require("config")
local DexExpansion = V.require("dex_expansion")
local Gen9 = V.require("gen9_encounters")

-- ---------------------------------------------------------------- dex gate
setGame(newGame(false))
DexExpansion.invalidate()
check(DexExpansion.hasModernSpecies(mod, game) == false, "gate: Gen 1-2 species plus a 30000+ form record is NOT an expanded dex")

game.data.pokemon.KANTOREF = { dex = 386 }
DexExpansion.invalidate()
check(DexExpansion.hasModernSpecies(mod, game) == false, "gate: a Gen 3 dex (#386, Kanto Reforged) is not enough")

game.data.pokemon.FIXA = { dex = 400 }
DexExpansion.invalidate()
check(DexExpansion.hasModernSpecies(mod, game) == true, "gate: a species at #400 activates it")

game.data.pokemon.FIXA = nil
check(DexExpansion.hasModernSpecies(mod, game) == true, "gate: result is cached within an epoch (stale until invalidated)")
DexExpansion.invalidate()
check(DexExpansion.hasModernSpecies(mod, game) == false, "gate: invalidate() re-evaluates")

check(DexExpansion.speciesRegistered(mod, game, "PIDGEY") == true, "speciesRegistered: present key")
check(DexExpansion.speciesRegistered(mod, game, "NOPE") == false, "speciesRegistered: absent key")
check(DexExpansion.speciesRegistered(mod, game, nil) == false, "speciesRegistered: nil key")

-- ---------------------------------------------------------------- toggle read (live bucket)
setGame(newGame(true))
DexExpansion.invalidate()
Gen9.invalidate()
check(Config.modernSpawnsEnabled(mod) == true, "toggle defaults on")
liveBucket.modern_spawns = false
check(Config.modernSpawnsEnabled(mod) == false, "toggle reads the live save bucket the in-game menu writes to")
liveBucket.modern_spawns = nil
savedOpts.modern_spawns = false
check(Config.modernSpawnsEnabled(mod) == false, "toggle falls back to mod.options")
savedOpts = {}

-- ---------------------------------------------------------------- overlay
local function fresh(withModern)
  liveBucket.modern_spawns = nil
  savedOpts = {}
  setGame(newGame(withModern))
  DexExpansion.invalidate()
  Gen9.invalidate()
end

fresh(false)
local vanilla1 = game.data.encounters.ROUTE_1
check(Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1) == vanilla1, "inactive (no modern species): same vanilla object")

fresh(true)
vanilla1 = game.data.encounters.ROUTE_1
local snapshot = deepCopy(game.data.encounters)
local o1 = Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1)
check(o1 ~= vanilla1, "active: returns a copy, not the engine's table")
eq(o1.grass.rate, 25, "active: engine rate preserved")
eq(#o1.grass.slots, 12, "active: variable-length table (12 slots, longer than the default 10)")
eq(#o1.grass.buckets, 12, "active: overlay ladder carried with the slots (one threshold per slot)")
eq(o1.grass.buckets[12], 256, "active: ladder ends at 256")
check(o1.grass.buckets ~= R1_GRASS.buckets, "active: ladder is a copy of the data, not the data table")
check(deepEq(o1.grass.buckets, R1_GRASS.buckets), "active: ladder values match the data")
eq(o1.grass.slots[1].species, "FIXA", "slot 1: registered species used")
eq(o1.grass.slots[1].level, 30, "slot 1: overlay level used")
eq(o1.grass.slots[2].level, 31, "slot 2: each slot keeps its own level (per-level diversity)")
eq(o1.grass.slots[12].species, "FIXB", "slot 12 (beyond the default 10): registered species used")
check(o1.water == nil, "active: no water bucket is created where vanilla has none")
check(deepEq(game.data.encounters, snapshot), "engine's live encounter table is never mutated")
check(Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1) == o1, "active: overlay copy is cached")

-- Per-slot fallback by PROBABILITY POSITION on the vanilla default ladder
-- (51,102,141,166,191,216,229,242,253,256 -> odd vanilla slots PIDGEY, even RATTATA).
eq(o1.grass.slots[3].species, "RATTATA", "fallback: slot 3 (odds 80-120, mid 100) -> vanilla slot 2 (RATTATA)")
eq(o1.grass.slots[3].level, 3, "fallback: takes the vanilla slot's level")
eq(o1.grass.slots[5].species, "RATTATA", "fallback: slot 5 (150-180, mid 165) -> vanilla slot 4 (RATTATA)")
eq(o1.grass.slots[8].species, "PIDGEY", "fallback: slot 8 (215-228, mid 221.5) -> vanilla slot 7 (PIDGEY)")
eq(o1.grass.slots[11].species, "PIDGEY",
  "fallback: slot 11 (past the vanilla slot count) still resolves by position -> vanilla slot 9 (PIDGEY)")

local vanilla2 = game.data.encounters.ROUTE_2
local o2 = Gen9.overlayFor(mod, game, "ROUTE_2", vanilla2)
eq(#o2.grass.slots, 3, "second map: 3-slot grass ladder")
eq(#o2.water.slots, 2, "second map: water ladder replaced independently")
eq(o2.water.rate, 5, "second map: water rate preserved")
eq(o2.water.buckets[1], 200, "second map: water carries its own ladder")

local vanilla3 = game.data.encounters.ROUTE_3
local o3 = Gen9.overlayFor(mod, game, "ROUTE_3", vanilla3)
eq(o3.grass.slots[1].species, "FIXA", "custom vanilla ladder: registered slot overlaid")
eq(o3.grass.slots[2].species, "RATTATA",
  "custom vanilla ladder: MISSING slot at position 178 -> vanilla's 2nd slot (RATTATA, thresholds 128/256)")
eq(o3.grass.slots[2].level, 8, "custom vanilla ladder: fallback level from the vanilla slot")

for _, id in ipairs({ "ROUTE_4", "ROUTE_6", "ROUTE_7" }) do
  local v = game.data.encounters[id]
  check(Gen9.overlayFor(mod, game, id, v) == v, id .. ": malformed overlay ladder fails closed to the vanilla object")
end

local vanilla5 = game.data.encounters.ROUTE_5
check(Gen9.overlayFor(mod, game, "ROUTE_5", vanilla5) == vanilla5, "unmapped map: same vanilla object")
check(Gen9.overlayFor(mod, game, "ROUTE_1", nil) == nil, "nil vanilla table passes through")

Gen9.invalidate()
local o1b = Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1)
check(o1b ~= o1 and deepEq(o1b, o1), "invalidate() rebuilds an equal overlay")

liveBucket.modern_spawns = false
check(Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1) == vanilla1, "toggle off (live bucket): vanilla object returned")
liveBucket.modern_spawns = nil

game.data.pokemon.FIXA, game.data.pokemon.FIXB = nil, nil
DexExpansion.invalidate(); Gen9.invalidate()
check(Gen9.overlayFor(mod, game, "ROUTE_1", vanilla1) == vanilla1, "species disappear + invalidate: back to vanilla")

fresh(true)
game.data.pokemon.FIXB = nil
DexExpansion.invalidate(); Gen9.invalidate()
local o1c = Gen9.overlayFor(mod, game, "ROUTE_1", game.data.encounters.ROUTE_1)
eq(o1c.grass.slots[1].species, "FIXA", "partial registration: FIXA still overlaid")
eq(o1c.grass.slots[2].species, "RATTATA", "partial registration: FIXB slot (mid 60) falls back to vanilla slot 2 (RATTATA)")
eq(#o1c.grass.slots, 12, "partial registration: ladder length unchanged (probability mass preserved)")

check(Gen9.overlayFor(nil, game, "ROUTE_1", vanilla1) == vanilla1, "no mod: fails closed to vanilla")

-- Data written for another schema version is ignored (fails closed to vanilla).
do
  local savedData, savedMod = modules.gen9_encounters_data, modules.gen9_encounters
  modules.gen9_encounters_data = { version = 1, maps = DATA.maps }
  modules.gen9_encounters = nil
  local OldGen9 = V.require("gen9_encounters")
  fresh(true)
  DexExpansion.invalidate()
  local v = game.data.encounters.ROUTE_1
  check(OldGen9.overlayFor(mod, game, "ROUTE_1", v) == v, "data version 1 (old 10-slot schema) is ignored")
  modules.gen9_encounters_data, modules.gen9_encounters = savedData, savedMod
end

-- ---------------------------------------------------------------- classic encounter.roll hook
-- The engine hands encounter.roll the map's own table for grass/indoor rolls but a SYNTHETIC
-- { grass = map.water } for water rolls, and Encounter.roll only reads `.grass`.
fresh(true)
local real2 = game.data.encounters.ROUTE_2
local rolled = Gen9.rollDef(mod, game, "ROUTE_2", "grass", real2)
eq(rolled.grass.slots[1].species, "FIXA", "rollDef grass: overlay grass slots substituted")
eq(#rolled.grass.buckets, 3, "rollDef grass: the ladder travels with the substituted table")
check(rolled ~= real2, "rollDef grass: not the engine's table")
local rolledCave = Gen9.rollDef(mod, game, "ROUTE_2", "indoor", real2)
eq(rolledCave.grass.slots[1].species, "FIXA", "rollDef indoor (cave): grass bucket substituted")
local synthetic = { grass = real2.water }
local rolledWater = Gen9.rollDef(mod, game, "ROUTE_2", "water", synthetic)
eq(rolledWater.grass.slots[1].species, "FIXB", "rollDef water: the WATER overlay lands in .grass (not land species)")
eq(rolledWater.grass.rate, 5, "rollDef water: vanilla water rate preserved")
eq(#rolledWater.grass.buckets, 2, "rollDef water: the water ladder travels with it")
check(Gen9.rollDef(mod, game, "ROUTE_2", "water", real2) == real2,
  "rollDef water: an encDef that is not the synthetic water wrapper is left alone")
local foreign = { grass = { rate = 9, slots = vanillaSlots("PIDGEY", "RATTATA") } }
check(Gen9.rollDef(mod, game, "ROUTE_2", "grass", foreign) == foreign,
  "rollDef grass: a table another mod already replaced is not clobbered")
check(Gen9.rollDef(mod, game, "ROUTE_5", "grass", game.data.encounters.ROUTE_5) == game.data.encounters.ROUTE_5,
  "rollDef: unmapped map unchanged")
check(Gen9.rollDef(mod, game, "ROUTE_2", "grass", nil) == nil, "rollDef: nil passes through")
liveBucket.modern_spawns = false
check(Gen9.rollDef(mod, game, "ROUTE_2", "grass", real2) == real2, "rollDef: toggle off leaves the table alone")
liveBucket.modern_spawns = nil

-- ---------------------------------------------------------------- the picker reads the ladder
-- EncounterPick must honor the copied per-bucket ladder (end to end, deterministic rng draws).
do
  fresh(true)
  local EncounterPick = V.require("encounter_pick")
  local enc = Gen9.overlayFor(mod, game, "ROUTE_2", game.data.encounters.ROUTE_2)
  -- Slot widths 100/80/76 out of 256 -> draws 0, 99 | 100, 179 | 180, 255.
  local levels = {}
  for _, draw in ipairs({ 0, 99, 100, 179, 180, 255 }) do
    local picked = EncounterPick.pick(enc, function() return draw end, "grass")
    levels[#levels + 1] = picked and picked.level or "nil"
  end
  eq(table.concat(levels, ","), "40,40,41,41,42,42",
    "EncounterPick.pick honors the overlay ladder: draws map to the right per-level slots")
  local w = EncounterPick.slotWeights(enc, "grass")
  eq(#w, 3, "slotWeights: one weight per overlay slot")
  eq(w[1].weight + w[2].weight + w[3].weight, 256, "slotWeights: widths sum to 256")
  eq(w[2].weight, 80, "slotWeights: width comes from the copied ladder")
end

-- ---------------------------------------------------------------- fishing
fresh(true)
local vanillaRod = { { level = 5, species = "PIDGEY" }, { level = 5, species = "RATTATA" },
                     { level = 6, species = "PIDGEY" }, { level = 6, species = "RATTATA" } }
local pool = Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vanillaRod)
check(pool ~= vanillaRod, "fishing: overlay pool is a new list")
eq(#pool, 4, "fishing: <= 4 entries")
eq(pool[1].species, "FIXA", "fishing: registered entry used")
eq(pool[2].species, "RATTATA", "fishing: unregistered entry falls back to the vanilla entry at that index")
eq(pool[3].species, "FIXB", "fishing: third entry overlaid")
check(Gen9.fishingPool(mod, game, "ROUTE_1", "OLD_ROD", vanillaRod) == vanillaRod, "fishing: only the Super Rod is overlaid")
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", nil) == nil, "fishing: no vanilla group ('nothing here') stays that way")
local emptyRod = {}
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", emptyRod) == emptyRod, "fishing: empty vanilla group passes through")
check(Gen9.fishingPool(mod, game, "ROUTE_5", "SUPER_ROD", vanillaRod) == vanillaRod, "fishing: unmapped map keeps vanilla pool")
game.data.pokemon.FIXA, game.data.pokemon.FIXB = nil, nil
DexExpansion.invalidate(); Gen9.invalidate()
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vanillaRod) == vanillaRod, "fishing: inactive gate keeps vanilla pool")

-- ---------------------------------------------------------------- Gen 1 adapter seam
fresh(true)
local Gen1 = V.require("game_compat/gen1")
local viaSeam = Gen1.encountersForMap(game, "ROUTE_1")
eq(viaSeam.grass.slots[1].species, "FIXA", "Gen1.encountersForMap returns the overlay when active")
eq(#viaSeam.grass.buckets, 12, "Gen1.encountersForMap: the overlay's ladder comes through")
check(Gen1.encountersForMap(game, "ROUTE_5") == game.data.encounters.ROUTE_5, "Gen1.encountersForMap: unmapped map is the engine's own object")
check(Gen1.encountersForMap(game, "NO_SUCH_MAP") == nil, "Gen1.encountersForMap: unknown map is nil")
fresh(false)
check(Gen1.encountersForMap(game, "ROUTE_1") == game.data.encounters.ROUTE_1, "Gen1.encountersForMap: identity when the dex is not expanded")

-- ---------------------------------------------------------------- MODERN SPAWNS modes + Random
-- Config: the option is now table | random | off; pre-choice saves stored a boolean.
fresh(true)
liveBucket.legendary_spawns = nil
eq(Config.modernSpawnsMode(mod), "table", "mode: defaults to table")
liveBucket.modern_spawns = true
eq(Config.modernSpawnsMode(mod), "table", "mode: legacy boolean true migrates to table")
liveBucket.modern_spawns = false
eq(Config.modernSpawnsMode(mod), "off", "mode: legacy boolean false migrates to off")
eq(Config.modernSpawnsEnabled(mod), false, "mode: off reads as disabled")
liveBucket.modern_spawns = "random"
eq(Config.modernSpawnsMode(mod), "random", "mode: live bucket string random")
eq(Config.modernSpawnsEnabled(mod), true, "mode: random reads as enabled")
liveBucket.modern_spawns = "bogus"
eq(Config.modernSpawnsMode(mod), "table", "mode: unknown live value falls back to the default")
liveBucket.modern_spawns = nil
savedOpts.modern_spawns = "random"
eq(Config.modernSpawnsMode(mod), "random", "mode: falls back to mod.options")
liveBucket.modern_spawns = "off"
eq(Config.modernSpawnsMode(mod), "off", "mode: live bucket beats the schema value")
liveBucket.modern_spawns = nil
savedOpts = {}
eq(Config.legendarySpawnsEnabled(mod), false, "legendary toggle defaults off")
liveBucket.legendary_spawns = true
eq(Config.legendarySpawnsEnabled(mod), true, "legendary toggle reads the live bucket")
liveBucket.legendary_spawns = nil
savedOpts.legendary_spawns = true
eq(Config.legendarySpawnsEnabled(mod), true, "legendary toggle falls back to mod.options")
savedOpts = {}

-- Fixture: restricted species (Mewtwo 150, Mew 151, Nihilego 793, Koraidon 1007) beside ordinary ones.
local RESTRICTED_KEYS = { MEWTWO = 1, MEW = 1, NIHILEGO = 1, KORAIDON = 1 }
local function randomGame(withModern, legend, extra)
  fresh(withModern)
  local p = game.data.pokemon
  p.MEWTWO = { dex = 150 }; p.MEW = { dex = 151 }
  if withModern then -- dex >= 387 would itself count as an expanded dex
    p.NIHILEGO = { dex = 793 }; p.KORAIDON = { dex = 1007 }
  end
  for i = 1, extra or 0 do p["MON_" .. i] = { dex = 500 + i } end
  liveBucket.modern_spawns = "random"
  liveBucket.legendary_spawns = legend and true or nil
  DexExpansion.invalidate()
  Gen9.invalidate()
end
local function speciesSet(bucket)
  local set = {}
  for _, s in ipairs(bucket.slots) do set[s.species] = (set[s.species] or 0) + 1 end
  return set
end
local function levelCounts(bucket)
  local counts, prev = {}, 0
  local ladder = bucket.buckets or DEFAULT_BUCKETS
  for i, thr in ipairs(ladder) do
    local lv = bucket.slots[i].level
    counts[lv] = (counts[lv] or 0) + (thr - prev)
    prev = thr
  end
  return counts
end

-- off: vanilla identity even with a modern dex and legendaries registered
randomGame(true, false)
liveBucket.modern_spawns = "off"
Gen9.invalidate()
check(Gen9.overlayFor(mod, game, "ROUTE_1", game.data.encounters.ROUTE_1) == game.data.encounters.ROUTE_1, "off: vanilla object")
eq(Gen9.active(mod, game), false, "off: gate closed")
local vpool = { { level = 5, species = "PIDGEY" }, { level = 6, species = "RATTATA" } }
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vpool) == vpool, "off: fishing pool untouched")

-- random works with NO expanded dex, covers unmapped maps, keeps rate, never picks forms/restricted
randomGame(false, false)
eq(DexExpansion.hasModernSpecies(mod, game), false, "random/no-expansion: dex really is not expanded")
eq(Gen9.active(mod, game), true, "random: gate open without a dex expansion")
local snap = deepCopy(game.data.encounters)
local r5 = Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5)
check(r5 ~= game.data.encounters.ROUTE_5, "random: unmapped map is randomized too")
eq(#r5.grass.slots, 10, "random: the vanilla 10-slot layout")
eq(#r5.grass.buckets, 10, "random: one threshold per slot")
eq(r5.grass.buckets[1], 51, "random: first threshold is the vanilla default (51)")
eq(r5.grass.buckets[10], 256, "random: ladder ends at 256")
eq(r5.grass.rate, 15, "random: engine rate preserved")
check(r5.water == nil, "random: no water bucket created where vanilla has none")
check(deepEq(game.data.encounters, snap), "random: engine's live table never mutated")
local set5 = speciesSet(r5.grass)
check(set5.PIDGEY and set5.RATTATA, "random: ordinary species drawn")
check(not set5.MEOWTH_ALOLA, "random: alternate forms (dex 30000+) never drawn")
check(not (set5.MEWTWO or set5.MEW), "random: legendary/mythical/Ultra Beast/Paradox excluded by default")
eq(levelCounts(r5.grass)[3], 256, "random: levels come from the area (vanilla ROUTE_5 is all level 3)")
check(Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5) == r5, "random: roster cached within a visit")

-- level spread follows the area's ladder (ROUTE_3: 128 units at L7, 128 at L8)
local r3 = Gen9.overlayFor(mod, game, "ROUTE_3", game.data.encounters.ROUTE_3)
local lc3 = levelCounts(r3.grass)
eq(lc3[7], 128, "random: half the units keep the area's level 7")
eq(lc3[8], 128, "random: half the units keep the area's level 8")

-- water is randomized where vanilla has water, and the synthetic water table is substituted
local r2 = Gen9.overlayFor(mod, game, "ROUTE_2", game.data.encounters.ROUTE_2)
eq(#r2.water.slots, 10, "random: water bucket randomized on the vanilla ladder")
eq(r2.water.rate, 5, "random: water rate preserved")
local realR2 = game.data.encounters.ROUTE_2
local wd = Gen9.rollDef(mod, game, "ROUTE_2", "water", { grass = realR2.water })
check(wd.grass == r2.water, "random rollDef: water roll gets the random water ladder")
check(Gen9.rollDef(mod, game, "ROUTE_2", "grass", realR2) == r2, "random rollDef: grass roll gets the random table")
local foreign = { grass = { slots = {} } }
check(Gen9.rollDef(mod, game, "ROUTE_2", "grass", foreign) == foreign, "random rollDef: another mod's table is left alone")

-- EncounterPick sees a valid ladder: every slot is one 256th
local EncounterPick = V.require("encounter_pick")
local weights = EncounterPick.slotWeights({ grass = r5.grass }, "grass")
eq(#weights, 10, "random: EncounterPick sees the 10 vanilla slots")
eq(weights[1].weight, 51, "random: slot 1 keeps the vanilla 51/256 odds")
eq(weights[10].weight, 3, "random: slot 10 keeps the vanilla 3/256 odds")

-- Gen 1 adapter seam
local Gen1 = V.require("game_compat/gen1")
check(Gen1.encountersForMap(game, "ROUTE_5") == r5, "random: Gen1.encountersForMap returns the random table")

-- restricted species toggle
randomGame(true, true)
local r5L = Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5)
local setL = speciesSet(r5L.grass)
check(setL.MEWTWO and setL.MEW and setL.NIHILEGO and setL.KORAIDON, "random + legendary toggle: restricted species can appear")
check(not setL.MEOWTH_ALOLA, "random + legendary toggle: forms are still never drawn")
-- flipping the toggle live (no invalidate) must not serve the stale roster
liveBucket.legendary_spawns = nil
local r5N = Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5)
check(r5N ~= r5L, "random: toggling the legendary flag rebuilds the roster")
check(not speciesSet(r5N.grass).MEWTWO, "random: ...and the restricted species are gone again")

-- mode switch mid-visit rebuilds too
liveBucket.modern_spawns = "off"
check(Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5) == game.data.encounters.ROUTE_5,
  "switching to off returns the vanilla object without an invalidate")

-- large pool: the roster stays at 10 species, and a new map entry redraws
randomGame(false, false, 300)
local big = Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5)
local distinct = 0
for _ in pairs(speciesSet(big.grass)) do distinct = distinct + 1 end
eq(distinct, 10, "random: even a 300+ species pool gives an area only 10 distinct species")
local firstOrder = {}
for i, s in ipairs(big.grass.slots) do firstOrder[i] = s.species end
Gen9.invalidate() -- what map.entered does
local big2 = Gen9.overlayFor(mod, game, "ROUTE_5", game.data.encounters.ROUTE_5)
check(big2 ~= big, "random: a new map entry draws a fresh table")
local same = true
for i, s in ipairs(big2.grass.slots) do if s.species ~= firstOrder[i] then same = false break end end
check(not same, "random: the redrawn roster differs from the previous visit")

-- Random keeps the Spawn Table's level spread where one applies (mapped map + expanded dex)
randomGame(true, false)
liveBucket.modern_spawns = "table"
Gen9.invalidate()
local tableR1 = Gen9.overlayFor(mod, game, "ROUTE_1", game.data.encounters.ROUTE_1)
liveBucket.modern_spawns = "random"
Gen9.invalidate()
local randR1 = Gen9.overlayFor(mod, game, "ROUTE_1", game.data.encounters.ROUTE_1)
local tableLevels, allInside = levelCounts(tableR1.grass), true
for lv in pairs(levelCounts(randR1.grass)) do if not tableLevels[lv] then allInside = false end end
check(allInside, "random: every level comes from the Spawn Table overlay where the map is mapped")
eq(#randR1.grass.slots, 10, "random (mapped map): still the vanilla ladder, not the 12-slot overlay ladder")
check(not (speciesSet(randR1.grass).MEWTWO), "random (mapped map): restricted species stay out")

-- Super Rod: vanilla-shaped group, levels from the Spawn Table group where mapped, stable per visit
local vg = { { level = 10, species = "PIDGEY" }, { level = 10, species = "RATTATA" },
             { level = 11, species = "PIDGEY" }, { level = 11, species = "RATTATA" } }
local rod = Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vg)
eq(#rod, 4, "random fishing: 4 entries (engine limit)")
check(rod ~= vg, "random fishing: a new list, vanilla untouched")
eq(rod[1].level, 20, "random fishing: levels follow the Spawn Table group where mapped (entry 1)")
eq(rod[3].level, 21, "random fishing: levels follow the Spawn Table group where mapped (entry 3)")
for i, e in ipairs(rod) do
  check(game.data.pokemon[e.species] ~= nil and not RESTRICTED_KEYS[e.species],
    "random fishing: entry " .. i .. " is a registered, unrestricted species")
end
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vg) == rod, "random fishing: draw is stable for the visit")
check(Gen9.fishingPool(mod, game, "ROUTE_1", "OLD_ROD", vg) == vg, "random fishing: other rods stay vanilla")
local rodU = Gen9.fishingPool(mod, game, "ROUTE_5", "SUPER_ROD", vg)
eq(rodU[1].level, 10, "random fishing: unmapped map keeps the vanilla group's levels")
Gen9.invalidate()
check(Gen9.fishingPool(mod, game, "ROUTE_1", "SUPER_ROD", vg) ~= rod, "random fishing: redrawn on the next map entry")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nall passed")
