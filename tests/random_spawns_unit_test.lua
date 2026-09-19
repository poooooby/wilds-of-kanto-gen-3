-- lib/random_spawns.lua: species pool, restricted set, and the random bucket / Super Rod builders.
-- (The mode/option wiring is covered in tests/gen9_encounters_unit_test.lua.)
-- Run: lua tests/random_spawns_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { mod = {}, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local RandomSpawns = V.require("random_spawns")

-- ---------------------------------------------------------------- rng
local a, b = RandomSpawns.newRng(42), RandomSpawns.newRng(42)
local sameSeq, inRange = true, true
for _ = 1, 200 do
  local x, y = a(1, 6), b(1, 6)
  if x ~= y then sameSeq = false end
  if x < 1 or x > 6 then inRange = false end
end
check(sameSeq, "rng: same seed gives the same sequence")
check(inRange, "rng: stays inside [lo, hi]")
local c = RandomSpawns.newRng(43)
local diff = false
for _ = 1, 50 do if RandomSpawns.newRng(42)(1, 1000) ~= c(1, 1000) then diff = true break end end
check(diff, "rng: different seeds diverge")
local zero = RandomSpawns.newRng(0)
check(zero(1, 10) >= 1, "rng: seed 0 is usable")

-- ---------------------------------------------------------------- restricted kinds
eq(RandomSpawns.restrictedKind(150), "legendary", "restrictedKind: Mewtwo")
eq(RandomSpawns.restrictedKind(151), "mythical", "restrictedKind: Mew")
eq(RandomSpawns.restrictedKind(793), "ultra_beast", "restrictedKind: Nihilego")
eq(RandomSpawns.restrictedKind(984), "paradox", "restrictedKind: Great Tusk")
eq(RandomSpawns.restrictedKind(25), nil, "restrictedKind: Pikachu is ordinary")

-- ---------------------------------------------------------------- pool
local game = { data = { pokemon = {
  PIKACHU = { dex = 25 }, EEVEE = { dex = 133 }, PICHU = { dex = 172 },
  MEWTWO = { dex = 150 }, MEW = { dex = 151 }, NIHILEGO = { dex = 793 }, GREAT_TUSK = { dex = 984 },
  ROGGENROLA = { dex = 524 }, MEOWTH_ALOLA = { dex = 30107 }, BROKEN = {}, WORDY = { dex = "x" },
} } }
local mod = {}

local pool = RandomSpawns.pool(mod, game, false, 1)
local set = {}
for _, k in ipairs(pool) do set[k] = true end
check(set.PIKACHU and set.EEVEE and set.PICHU and set.ROGGENROLA, "pool: ordinary species (babies included) are in")
check(not (set.MEWTWO or set.MEW or set.NIHILEGO or set.GREAT_TUSK), "pool: legendary/mythical/UB/Paradox out by default")
check(not set.MEOWTH_ALOLA, "pool: 30000+ alternate forms are out")
check(not (set.BROKEN or set.WORDY), "pool: records without a numeric dex are out")
eq(#pool, 4, "pool: exactly the four ordinary species")
eq(pool[1], "PIKACHU", "pool: sorted by dex (25 first)")
eq(pool[4], "ROGGENROLA", "pool: sorted by dex (524 last)")
check(RandomSpawns.pool(mod, game, false, 1) == pool, "pool: cached within an epoch")

local withAll = RandomSpawns.pool(mod, game, true, 1)
eq(#withAll, 8, "pool: including restricted adds the four restricted species")
local setAll = {}
for _, k in ipairs(withAll) do setAll[k] = true end
check(setAll.MEWTWO and setAll.MEW and setAll.NIHILEGO and setAll.GREAT_TUSK, "pool: restricted species present when included")
check(not setAll.MEOWTH_ALOLA, "pool: forms still excluded when restricted are included")
check(RandomSpawns.pool(mod, game, false, 1) == pool, "pool: the two variants are cached independently")

game.data.pokemon.NEWMON = { dex = 700 }
eq(#RandomSpawns.pool(mod, game, false, 1), 4, "pool: stale within the same epoch")
eq(#RandomSpawns.pool(mod, game, false, 2), 5, "pool: rebuilt when the epoch changes")

-- content registry species are picked up too, without duplicating game.data ones
local content = { pokemon = { each = function()
  local list = { { "CONTENTMON", { dex = 850 } }, { "PIKACHU", { dex = 25 } } }
  local i = 0
  return function() i = i + 1; if list[i] then return list[i][1], list[i][2] end end
end } }
local p3 = RandomSpawns.pool({ content = content }, game, false, 3)
local n3 = {}
for _, k in ipairs(p3) do n3[k] = (n3[k] or 0) + 1 end
check(n3.CONTENTMON == 1, "pool: content-registered species included")
eq(n3.PIKACHU, 1, "pool: no duplicate when in both registries")
eq(#RandomSpawns.pool(mod, nil, false, 1), 0, "pool: no game -> empty")

-- generation cap (maxDex): species above that national dex are dropped, cached per cap
local capGame = { data = { pokemon = {
  PIKACHU = { dex = 25 }, MEWTWO = { dex = 150 }, PICHU = { dex = 172 }, TORCHIC = { dex = 255 },
  TURTWIG = { dex = 387 }, ROGGENROLA = { dex = 524 }, NIHILEGO = { dex = 793 },
} } }
local function keys(list) return table.concat(list, ",") end
eq(keys(RandomSpawns.pool(mod, capGame, false, 1, 151)), "PIKACHU", "pool cap Gen 1: only #151 and below (restricted Mewtwo out)")
eq(keys(RandomSpawns.pool(mod, capGame, false, 1, 251)), "PIKACHU,PICHU", "pool cap Gen 1-2")
eq(keys(RandomSpawns.pool(mod, capGame, false, 1, 386)), "PIKACHU,PICHU,TORCHIC", "pool cap Gen 1-3")
eq(keys(RandomSpawns.pool(mod, capGame, false, 1, nil)), "PIKACHU,PICHU,TORCHIC,TURTWIG,ROGGENROLA", "pool no cap: everything unrestricted")
eq(keys(RandomSpawns.pool(mod, capGame, true, 1, 251)), "PIKACHU,MEWTWO,PICHU", "pool cap Gen 1-2 + restricted allowed: Mewtwo in, Nihilego (#793) still capped out")
eq(keys(RandomSpawns.pool(mod, capGame, true, 1, nil)), "PIKACHU,MEWTWO,PICHU,TORCHIC,TURTWIG,ROGGENROLA,NIHILEGO", "pool no cap + restricted allowed: all")
check(RandomSpawns.pool(mod, capGame, false, 1, 151) == RandomSpawns.pool(mod, capGame, false, 1, 151), "pool cap: cached per cap")
check(RandomSpawns.pool(mod, capGame, false, 1, 151) ~= RandomSpawns.pool(mod, capGame, false, 1, 251), "pool cap: different caps are different cache entries")
eq(#RandomSpawns.pool(mod, capGame, false, 1, "251"), 2, "pool cap: a numeric string cap works")

-- ---------------------------------------------------------------- bucket
-- base ladder {128,192,256}: units 0-127 are L10, 128-191 are L12, 192-255 are L14.
local base = { rate = 20, buckets = { 128, 192, 256 }, slots = {
  { level = 10, species = "A" }, { level = 12, species = "B" }, { level = 14, species = "C" } } }
local big = {}
for i = 1, 300 do big[i] = "MON_" .. i end
local DEFAULT = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

local bk = RandomSpawns.bucket(base, big, RandomSpawns.newRng(7))
eq(#bk.slots, 10, "bucket: default is the engine's 10 slots")
eq(#bk.buckets, 10, "bucket: 10 thresholds")
local ladderOk = true
for i, thr in ipairs(bk.buckets) do if thr ~= DEFAULT[i] then ladderOk = false end end
check(ladderOk, "bucket: thresholds are the engine's default ladder")
check(bk.buckets ~= DEFAULT, "bucket: the ladder is a copy")

local seen, dupes = {}, 0
for i, s in ipairs(bk.slots) do
  if seen[s.species] then dupes = dupes + 1 end
  seen[s.species] = true
  check(type(s.species) == "string" and type(s.level) == "number", "bucket: slot shape")
  check(s.level == 10 or s.level == 12 or s.level == 14, "bucket: slot " .. i .. " level comes from the base table")
end
eq(dupes, 0, "bucket: species are distinct")
-- slots whose whole odds interval sits inside one base level are exact
eq(bk.slots[1].level, 10, "bucket: slot 1 interval 0-50 is all base L10")
eq(bk.slots[2].level, 10, "bucket: slot 2 interval 51-101 is all base L10")
eq(bk.slots[4].level, 12, "bucket: slot 4 interval 141-165 is all base L12")
eq(bk.slots[5].level, 12, "bucket: slot 5 interval 166-190 is all base L12")
for i = 7, 10 do eq(bk.slots[i].level, 14, "bucket: slot " .. i .. " interval is all base L14") end

-- a custom vanilla ladder keeps its shape and per-interval levels
local cb = RandomSpawns.bucket(base, big, RandomSpawns.newRng(7), { 128, 192, 256 })
eq(#cb.slots, 3, "bucket: custom ladder gives one slot per threshold")
eq(cb.buckets[3], 256, "bucket: custom ladder ends at 256")
eq(cb.slots[1].level, 10, "bucket: custom slot 1 level")
eq(cb.slots[2].level, 12, "bucket: custom slot 2 level")
eq(cb.slots[3].level, 14, "bucket: custom slot 3 level")
local two = RandomSpawns.bucket(base, big, RandomSpawns.newRng(7), { 128, 256 })
eq(#two.slots, 2, "bucket: a 2-slot ladder gives 2 slots")
eq(two.slots[1].level, 10, "bucket: 2-slot ladder, first interval is all L10")
check(two.slots[2].level == 12 or two.slots[2].level == 14, "bucket: 2-slot ladder, second interval spans L12/L14")

-- the roster stays small no matter how big the pool is
local distinctAcrossDraws = 0
for seed = 1, 20 do
  local b = RandomSpawns.bucket(base, big, RandomSpawns.newRng(seed))
  local set, n = {}, 0
  for _, s in ipairs(b.slots) do if not set[s.species] then set[s.species] = true; n = n + 1 end end
  if n > 10 then distinctAcrossDraws = n end
end
eq(distinctAcrossDraws, 0, "bucket: never more than 10 distinct species from a 300-species pool")

local small = { "X", "Y", "Z" }
local sb = RandomSpawns.bucket(base, small, RandomSpawns.newRng(7))
local counts = {}
for _, s in ipairs(sb.slots) do counts[s.species] = (counts[s.species] or 0) + 1 end
check(math.abs(counts.X - counts.Y) <= 1 and math.abs(counts.Y - counts.Z) <= 1, "bucket: a tiny pool cycles evenly (reshuffled each pass)")

local r1 = RandomSpawns.bucket(base, big, RandomSpawns.newRng(99))
local r2 = RandomSpawns.bucket(base, big, RandomSpawns.newRng(99))
local identical = true
for i = 1, 10 do
  if r1.slots[i].species ~= r2.slots[i].species or r1.slots[i].level ~= r2.slots[i].level then identical = false end
end
check(identical, "bucket: same seed -> same table")
local r3 = RandomSpawns.bucket(base, big, RandomSpawns.newRng(100))
local differs = false
for i = 1, 10 do if r1.slots[i].species ~= r3.slots[i].species then differs = true break end end
check(differs, "bucket: different seed -> different roster")

-- default ladder (base without `buckets`) reads the engine's 10-slot default: slot i keeps level i
local dflt = { slots = {} }
for i = 1, 10 do dflt.slots[i] = { level = i, species = "S" .. i } end
local db = RandomSpawns.bucket(dflt, big, RandomSpawns.newRng(1))
for i = 1, 10 do eq(db.slots[i].level, i, "bucket: default-ladder base, slot " .. i .. " keeps its level") end

check(RandomSpawns.bucket(nil, big) == nil, "bucket: nil base -> nil")
check(RandomSpawns.bucket({ slots = {} }, big) == nil, "bucket: empty base -> nil")
check(RandomSpawns.bucket(base, {}) == nil, "bucket: empty pool -> nil")
check(RandomSpawns.bucket(base, nil) == nil, "bucket: nil pool -> nil")
local input = { "A", "B", "C" }
RandomSpawns.bucket(base, input, RandomSpawns.newRng(3))
eq(table.concat(input, ","), "A,B,C", "bucket: the caller's pool is not reordered")

-- ---------------------------------------------------------------- super rod
local group = { { level = 15, species = "GOLDEEN" }, { level = 15, species = "MAGIKARP" },
                { level = 20, species = "POLIWAG" }, { level = 20, species = "TENTACOOL" } }
local rod = RandomSpawns.superRod(group, big, RandomSpawns.newRng(5))
eq(#rod, 4, "superRod: same length as the base group")
eq(rod[1].level, 15, "superRod: levels kept in order (1)")
eq(rod[4].level, 20, "superRod: levels kept in order (4)")
local rs = {}
for _, e in ipairs(rod) do rs[e.species] = true end
local rn = 0
for _ in pairs(rs) do rn = rn + 1 end
eq(rn, 4, "superRod: no repeats while the pool allows")
eq(#RandomSpawns.superRod({ { level = 5, species = "X" } }, big), 1, "superRod: a 1-entry group stays 1 entry")
local five = { group[1], group[2], group[3], group[4], { level = 30, species = "EXTRA" } }
eq(#RandomSpawns.superRod(five, big), 4, "superRod: never more than 4 (engine 2-bit roll)")
check(RandomSpawns.superRod({}, big) == nil, "superRod: empty group -> nil")
check(RandomSpawns.superRod(group, {}) == nil, "superRod: empty pool -> nil")
eq(#RandomSpawns.superRod(group, { "ONLY" }, RandomSpawns.newRng(1)), 4, "superRod: a one-species pool still fills the group")

-- default (unseeded) rng path runs
local anon = RandomSpawns.bucket(base, big)
eq(#anon.slots, 10, "bucket: works with the default rng")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
