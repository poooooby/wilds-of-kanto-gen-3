-- Gold Unown spawns: the letter is drawn at spawn (respecting the wall-puzzle unlocks), the battle mon gets the same DVs,
-- and Ruins of Alph style dungeon maps (environment CAVE / DUNGEON, no "CAVE" in the id) count as spawnable cave floor.
-- Engine modules are faked with the same formulas as src/core/gen2/Unown.lua (letter = middle two bits of each DV).
-- Run: lua tests/gen2_unown_unit_test.lua
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

-- ------------------------------------------------------------------ fake Gold engine modules
package.loaded["src.core.GameVersion"] = {
  get = function() return "gold" end,
  isYellow = function() return false end,
  isGold = function() return true end,
  generation = function() return 2 end,
}

local function middleBits(dv) return math.floor((dv or 0) / 2) % 4 end
local Unown = {}
Unown.UNLOCK_SETS = {
  { flag = 42, first = 1, last = 11 }, { flag = 43, first = 12, last = 18 },
  { flag = 44, first = 19, last = 23 }, { flag = 45, first = 24, last = 26 },
}
function Unown.letterFromDVs(dvs)
  if not dvs then return nil end
  local packed = middleBits(dvs.attack) * 64 + middleBits(dvs.defense) * 16 + middleBits(dvs.speed) * 4 + middleBits(dvs.special)
  return math.floor(packed / 10) + 1
end
function Unown.anyUnlocked(flags)
  for _, set in ipairs(Unown.UNLOCK_SETS) do if flags and flags[set.flag] then return true end end
  return false
end
function Unown.letterUnlocked(letter, flags)
  for _, set in ipairs(Unown.UNLOCK_SETS) do
    if flags and flags[set.flag] and letter >= set.first and letter <= set.last then return true end
  end
  return false
end
function Unown.wildDVs(flags, randomDVs)
  local dvs = randomDVs()
  for _ = 1, 4096 do
    if Unown.letterUnlocked(Unown.letterFromDVs(dvs), flags) then return dvs end
    dvs = randomDVs()
  end
  error("no unlocked letter found")
end
package.loaded["src.core.gen2.Unown"] = Unown

local originalRandomDVs = function()
  return { attack = math.random(0, 15), defense = math.random(0, 15), speed = math.random(0, 15), special = math.random(0, 15) }
end
local Mon = { randomDVs = originalRandomDVs }
package.loaded["src.battle.gen2.Mon"] = Mon

local modules = {}
local V = {
  mod = { path = ".", id = "wilds_of_kanto_gen3", log = { info = function() end, warn = function() end },
    content = { pokemon = { get = function() return nil end } } },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local GameCompat = V.require("game_compat")
math.randomseed(7)

-- ------------------------------------------------------------------ wildVariant
local unlockedFlags = {}
local world = { map = { id = "RUINS_OF_ALPH_KABUTO_CHAMBER" }, unownUnlockFlags = function() return unlockedFlags end }
local game = { world = world, data = { pokemon = { UNOWN = { dex = 201 } } } }

eq(GameCompat.wildVariant(game, "PIKACHU", { ow = world }), nil, "a species with no variation answers nil")

unlockedFlags = {}
local v, why = GameCompat.wildVariant(game, "UNOWN", { ow = world })
eq(v, false, "no puzzle solved: the Unown slot is no encounter")
check(type(why) == "string" and why ~= "", "the refusal carries a reason")

unlockedFlags = { [42] = true } -- A..K
local counts, formOk, dvsOk = {}, true, true
for _ = 1, 400 do
  local var = GameCompat.wildVariant(game, "UNOWN", { ow = world })
  counts[var.unownLetter] = (counts[var.unownLetter] or 0) + 1
  local wantForm = var.unownLetter >= 2 and var.unownLetter - 1 or nil
  if var.unownForm ~= wantForm then formOk = false end
  if Unown.letterFromDVs(var.dvs) ~= var.unownLetter then dvsOk = false end
end
local distinct, outOfSet = 0, false
for letter in pairs(counts) do
  distinct = distinct + 1
  if letter < 1 or letter > 11 then outOfSet = true end
end
check(not outOfSet, "only letters from a solved puzzle's set appear (A-K)")
check(distinct >= 8, "the letters vary across spawns (" .. distinct .. " distinct of 11)")
check(formOk, "unownForm is the sprite-file suffix: A = nil, B..Z = 1..25")
check(dvsOk, "the DVs handed back spell the same letter")

unlockedFlags = { [42] = true, [45] = true } -- A-K and X-Z
local sawXtoZ = false
for _ = 1, 400 do
  local var = GameCompat.wildVariant(game, "UNOWN", { ow = world })
  if var.unownLetter >= 24 then sawXtoZ = true end
end
check(sawXtoZ, "a second solved puzzle adds its letters")

unlockedFlags = {}
local forced = GameCompat.wildVariant(game, "UNOWN", { ow = world, forced = true })
check(type(forced) == "table" and forced.unownLetter >= 1 and forced.unownLetter <= 26,
  "a forced / test spawn ignores the unlock rule and takes any letter")

local blind = GameCompat.wildVariant({ data = game.data }, "UNOWN", { ow = {} })
eq(blind, nil, "without a world that can report the unlocks, the engine default is left alone")

-- ------------------------------------------------------------------ battle DVs
local captured
local wildWorld = {
  queueScript = function(_, rows)
    captured = { rows = rows, dvs = Mon.randomDVs() }
    return true
  end,
}
local want = { attack = 6, defense = 4, speed = 2, special = 0 }
local ok = GameCompat.startWildBattle(wildWorld, "UNOWN", 5, game, { dvs = want })
eq(ok, true, "startWildBattle still reports success")
eq(captured.rows[1][2], "wild", "the wild battle row is queued unchanged")
eq(captured.dvs.attack, 6, "the queued Mon is built from the spawn's DVs (attack)")
eq(captured.dvs.special, 0, "the queued Mon is built from the spawn's DVs (special)")
eq(Mon.randomDVs, originalRandomDVs, "Mon.randomDVs is put back after the queue ran")

captured = nil
GameCompat.startWildBattle(wildWorld, "PIDGEY", 3, game)
check(captured and captured.dvs.attack ~= nil, "without DVs the engine's own random DVs are used")
eq(Mon.randomDVs, originalRandomDVs, "and Mon.randomDVs is untouched")

local boom = { queueScript = function() error("queue exploded") end }
local okBoom, errBoom = GameCompat.startWildBattle(boom, "UNOWN", 5, game, { dvs = want })
eq(okBoom, nil, "a failing queue reports failure")
check(tostring(errBoom):find("queue exploded", 1, true) ~= nil, "with the underlying error")
eq(Mon.randomDVs, originalRandomDVs, "Mon.randomDVs is restored even when the queue throws")

-- ------------------------------------------------------------------ dungeon maps spawn (Ruins of Alph & co.)
modules.encounter_pick = { kindTable = function(encDef, kind) return encDef and encDef[kind] end,
  hasGrassTable = function(encDef) return encDef and encDef.grass ~= nil end }
local Surface = V.require("surface")
local encDef = { grass = { rate = 10, slots = { { species = "UNOWN", level = 5 } }, buckets = { 256 } } }
local function goldMap(id, tileset, environment)
  return { id = id, def = { tileset = tileset, environment = environment, index = 100 }, widthCells = 4, heightCells = 4,
    isGrassCell = function() return false end }
end
local goldGame = { data = { field = {} } } -- no Gen 1 indoorEncounters table in Gold data
for _, id in ipairs({ "RUINS_OF_ALPH_KABUTO_CHAMBER", "RUINS_OF_ALPH_INNER_CHAMBER", "SLOWPOKE_WELL_B1F", "ICE_PATH_1F",
    "MOUNT_MORTAR_1F_INSIDE", "WHIRL_ISLAND_NW" }) do
  local r = Surface.resolve(goldGame, goldMap(id, "DUNGEON_TILESET", "DUNGEON"), encDef)
  check(r.supported == true and r.surface == Surface.CAVE, id .. ": a DUNGEON map spawns on its walkable floor")
end
local cave = Surface.resolve(goldGame, goldMap("UNION_CAVE_1F", "CAVE", "CAVE"), encDef)
check(cave.supported == true and cave.surface == Surface.CAVE, "a CAVE-environment map spawns on its walkable floor")
local town = Surface.resolve(goldGame, goldMap("VIOLET_CITY", "JOHTO", "TOWN"), encDef)
check(town.supported == false, "a town with a table but no grass, cave or water is still unsupported")
local route = Surface.resolve(goldGame, goldMap("ROUTE_29", "JOHTO", "ROUTE"), encDef)
check(route.supported == false, "an outdoor route without grass tiles is still unsupported")

-- Gen 1 keeps its own rule (field.indoorEncounters), whatever a stray `environment` says.
local gen1Game = { data = { field = { indoorEncounters = { firstIndoorMap = 37, excludedTileset = "FOREST" } } } }
local gen1Outdoor = { id = "ROUTE_1", def = { tileset = "OVERWORLD", environment = "DUNGEON", index = 12 }, widthCells = 2, heightCells = 2,
  isGrassCell = function() return false end }
check(Surface.resolve(gen1Game, gen1Outdoor, encDef).supported == false, "Gen 1 still decides indoor-ness by its map index table")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("gen2_unown_unit_test: all passed")
