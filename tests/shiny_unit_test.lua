-- lib/shiny.lua: SHINY RATE (roll, shiny DVs, pending hand-off, Pokemon.new / BattleState.newWild wrappers).
-- Run: lua tests/shiny_unit_test.lua
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

-- ---------------------------------------------------------------- fixtures
local savedOpts = {}
local mod = {
  id = "wilds_of_kanto_gen3", path = ".",
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k) return savedOpts[k] end },
}
local modules = {}
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Config = V.require("config")
local Shiny = V.require("shiny")

-- The engine's rule (src/pokemon/Stats.lua isShiny), copied so this test doesn't need the engine.
local ENGINE_SHINY_ATK = { [2] = true, [3] = true, [6] = true, [7] = true, [10] = true, [11] = true, [14] = true, [15] = true }
local function engineIsShiny(dvs)
  if type(dvs) ~= "table" then return false end
  return (dvs.defense or 0) == 10 and (dvs.speed or 0) == 10 and (dvs.special or 0) == 10
     and ENGINE_SHINY_ATK[dvs.attack or 0] == true
end

local DATA = { pokemon = { PIDGEY = { baseStats = { hp = 40, attack = 45, defense = 40, speed = 56, special = 35 } } } }

-- Fake engine modules. Stats.calc is a stand-in whose result depends on the DVs, so a recompute is visible.
local calcCalls = 0
local Stats = {
  isShiny = engineIsShiny,
  calc = function(def, level, dvs, statExp)
    calcCalls = calcCalls + 1
    return { hp = 100 + (dvs.hp or 0), attack = 10 + dvs.attack, defense = 10 + dvs.defense,
             speed = 10 + dvs.speed, special = 10 + dvs.special }
  end,
}

local naturalDVs -- what the fake Pokemon.new rolls; tests set it
local newCalls = 0
local function freshEngine()
  local Pokemon = {}
  function Pokemon.new(data, species, level, rng)
    newCalls = newCalls + 1
    local dvs = {}
    for k, v in pairs(naturalDVs or { attack = 5, defense = 5, speed = 5, special = 5, hp = 15 }) do dvs[k] = v end
    return { species = species, level = level, dvs = dvs, statExp = {}, stats = { hp = 50 }, hp = 50 }
  end
  local BattleState = {}
  function BattleState.newWild(game, species, level, opts)
    return { kind = "wild", enemy = { mon = Pokemon.new(game.data, species, level, game.rng) } }
  end
  return Pokemon, BattleState
end

local function install(gen2)
  local Pokemon, BattleState = freshEngine()
  local ok, why = Shiny.install(mod, {
    Pokemon = Pokemon, BattleState = BattleState, Stats = Stats,
    isGen2 = function() return gen2 == true end,
  })
  return Pokemon, BattleState, ok, why
end

local function setRate(key) savedOpts.shiny_rate = key end
local game = { data = DATA }

-- ---------------------------------------------------------------- config
savedOpts = {}
eq(Config.shinyRate(mod), "modern", "config: default rate is modern (1/4096)")
setRate("always")
eq(Config.shinyRate(mod), "always", "config: schema value")
setRate("OFF")
eq(Config.shinyRate(mod), "off", "config: case-insensitive")
setRate(true)
eq(Config.shinyRate(mod), "always", "config: legacy boolean true means always")
setRate("nonsense")
eq(Config.shinyRate(mod), "modern", "config: unknown value falls back to modern")
eq(Shiny.rateKey(mod), "modern", "rateKey: follows config")
local schema = assert(loadfile("options.lua"))()
local row
for _, r in ipairs(schema) do if r.key == "shiny_rate" then row = r end end
check(row ~= nil and row.type == "choice", "options: shiny_rate choice exists")
eq(row and row.default, "modern", "options: default is modern")
local values = {}
for _, c in ipairs(row and row.choices or {}) do values[#values + 1] = c[2]; check(#c[1] <= 14, "options: label fits (" .. c[1] .. ")") end
eq(table.concat(values, ","), "off,gen2,modern,common,frequent,often,high,always", "options: choice order")
for _, key in ipairs(values) do
  check(key == "off" or Shiny.RATE_DENOMINATOR[key] ~= nil, "every choice has a denominator: " .. key)
end
eq(Shiny.RATE_DENOMINATOR.gen2, 8192, "denominator gen2")
eq(Shiny.RATE_DENOMINATOR.modern, 4096, "denominator modern")
eq(Shiny.RATE_DENOMINATOR.common, 1024, "denominator common")
eq(Shiny.RATE_DENOMINATOR.frequent, 512, "denominator frequent")
eq(Shiny.RATE_DENOMINATOR.often, 100, "denominator often")
eq(Shiny.RATE_DENOMINATOR.high, 10, "denominator high")

-- ---------------------------------------------------------------- roll
savedOpts = {}
setRate("off")
check(Shiny.roll(mod, function() return 1 end) == false, "roll: off is never shiny")
setRate("always")
check(Shiny.roll(mod, function() return 2 end) == true, "roll: always is always shiny")
setRate("modern")
local seenLo, seenHi
check(Shiny.roll(mod, function(lo, hi) seenLo, seenHi = lo, hi; return 1 end) == true, "roll: modern hits on 1")
eq(seenLo, 1, "roll: rng lower bound")
eq(seenHi, 4096, "roll: modern draws from 1/4096")
check(Shiny.roll(mod, function() return 2 end) == false, "roll: modern misses on 2")
setRate("high")
eq(select(2, pcall(function() local h; Shiny.roll(mod, function(lo, hi) h = hi; return 2 end); return h end)), 10, "roll: high draws from 1/10")
setRate("gen2")
Shiny.roll(mod, function(lo, hi) seenHi = hi; return 2 end)
eq(seenHi, 8192, "roll: gen2 draws from 1/8192")
-- statistical sanity at 1/10 with a real RNG (seeded): well inside a wide band
setRate("high")
math.randomseed(1234)
local hits = 0
for _ = 1, 20000 do if Shiny.roll(mod, math.random) then hits = hits + 1 end end
check(hits > 1700 and hits < 2300, "roll: 1/10 gives ~10% (got " .. hits .. "/20000)")

-- ---------------------------------------------------------------- DVs
math.randomseed(99)
local allValid = true
local attacks = {}
for _ = 1, 400 do
  local dvs = Shiny.makeDVs(math.random)
  if not engineIsShiny(dvs) or not Shiny.dvsAreShiny(dvs) then allValid = false end
  local expectHp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + (dvs.special % 2)
  if dvs.hp ~= expectHp then allValid = false end
  attacks[dvs.attack] = true
end
check(allValid, "makeDVs: always satisfies the engine's shiny rule with a derived HP DV")
local nAtk = 0
for _ in pairs(attacks) do nAtk = nAtk + 1 end
eq(nAtk, 8, "makeDVs: all eight shiny Attack DVs occur")
check(Shiny.dvsAreShiny({ attack = 4, defense = 10, speed = 10, special = 10 }) == false, "dvsAreShiny: Attack 4 is not shiny")
check(Shiny.dvsAreShiny({ attack = 2, defense = 10, speed = 10, special = 9 }) == false, "dvsAreShiny: Special 9 is not shiny")
check(Shiny.dvsAreShiny(nil) == false, "dvsAreShiny: nil")
check(Shiny.isShiny({ shiny = true }) and Shiny.isShiny({ dvs = { attack = 15, defense = 10, speed = 10, special = 10 } })
  and not Shiny.isShiny({ dvs = { attack = 1, defense = 1, speed = 1, special = 1 } }), "isShiny: flag or DVs")

-- ---------------------------------------------------------------- applyToMon / clearShiny / finalize
calcCalls = 0
local mon = { species = "PIDGEY", level = 5, dvs = { attack = 1, defense = 2, speed = 3, special = 4, hp = 5 }, statExp = {}, stats = { hp = 1 }, hp = 1 }
local sdv = { attack = 7, defense = 10, speed = 10, special = 10, hp = 9 }
Shiny.applyToMon(DATA, mon, sdv, { Stats = Stats })
eq(mon.shiny, true, "applyToMon: flagged shiny")
eq(mon.dvs, sdv, "applyToMon: DVs replaced")
eq(mon.stats.attack, 17, "applyToMon: stats recomputed from the new DVs")
eq(mon.hp, mon.stats.hp, "applyToMon: HP refilled to the new max")
eq(calcCalls, 1, "applyToMon: one recompute")

local nat = { species = "PIDGEY", level = 5, dvs = { attack = 15, defense = 10, speed = 10, special = 10, hp = 15 }, statExp = {}, stats = { hp = 1 }, hp = 1 }
Shiny.clearShiny(DATA, nat, { Stats = Stats })
check(not engineIsShiny(nat.dvs), "clearShiny: a natural shiny spread is broken")
eq(nat.dvs.special, 9, "clearShiny: nudges Special to 9")
eq(nat.dvs.hp, (15 % 2) * 8 + 0 + 0 + 1, "clearShiny: HP DV recomputed")
eq(nat.shiny, false, "clearShiny: flag false")
local calcBefore = calcCalls
local plain = { species = "PIDGEY", level = 5, dvs = { attack = 1, defense = 1, speed = 1, special = 1, hp = 15 }, statExp = {}, stats = { hp = 1 }, hp = 1 }
Shiny.clearShiny(DATA, plain, { Stats = Stats })
eq(calcCalls, calcBefore, "clearShiny: a non-shiny mon is not recomputed")
local fin = Shiny.finalize(DATA, { species = "PIDGEY", level = 5, dvs = { attack = 1, defense = 1, speed = 1, special = 1, hp = 15 }, statExp = {}, stats = {}, hp = 1 }, true, { Stats = Stats })
check(engineIsShiny(fin.dvs) and fin.shiny == true, "finalize(true): real shiny")
local fin2 = Shiny.finalize(DATA, { species = "PIDGEY", level = 5, dvs = { attack = 2, defense = 10, speed = 10, special = 10, hp = 9 }, statExp = {}, stats = {}, hp = 1 }, false, { Stats = Stats })
check(not engineIsShiny(fin2.dvs), "finalize(false): never shiny")

-- ---------------------------------------------------------------- pending hand-off
Shiny.clearPending()
eq(Shiny.pending(), nil, "pending: starts empty")
Shiny.armForBattle({ shiny = true })
check(Shiny.pending() and engineIsShiny(Shiny.pending().dvs), "armForBattle: shiny record -> shiny DVs")
Shiny.armForBattle({ shiny = false })
check(Shiny.pending() and Shiny.pending().none == true and Shiny.pending().dvs == nil, "armForBattle: normal record -> explicit none")
Shiny.armForBattle(nil)
check(Shiny.pending() and Shiny.pending().none == true, "armForBattle: no record -> none")
Shiny.setPending(nil)
eq(Shiny.pending(), nil, "setPending(nil) clears")
Shiny.setPending("none")
Shiny.clearPending()
eq(Shiny.pending(), nil, "clearPending clears")

-- ---------------------------------------------------------------- install + wrappers
local P, B, ok = install(false)
eq(ok, true, "install: ok with injected engine modules")
local origNewFn, origNewWildFn = P.new, B.newWild
local ok2 = Shiny.install(mod, { Pokemon = P, BattleState = B, Stats = Stats, isGen2 = function() return false end })
eq(ok2, true, "install: second call ok")
check(P.new == origNewFn and B.newWild == origNewWildFn, "install: idempotent (no double wrap)")
local bad, why = Shiny.install(mod, { Pokemon = {}, BattleState = {}, Stats = Stats })
eq(bad, false, "install: missing engine functions -> false")
check(type(why) == "string", "install: gives a reason")

-- visible shiny hand-off
P, B = install(false)
setRate("off")
Shiny.setPending(sdv)
local b1 = B.newWild(game, "PIDGEY", 5)
check(b1.enemy.mon.shiny == true and engineIsShiny(b1.enemy.mon.dvs), "newWild: pending shiny DVs -> shiny enemy (even with the rate off)")
eq(b1.enemy.mon.dvs.attack, 7, "newWild: it gets exactly the pending DVs")
eq(b1.enemy.mon.stats.attack, 17, "newWild: stats built from the shiny DVs")
eq(Shiny.pending(), nil, "newWild: pending consumed")

-- visible non-shiny stays non-shiny, even at the highest rate and against a natural shiny spread
setRate("always")
Shiny.setPending("none")
local b2 = B.newWild(game, "PIDGEY", 5)
check(not Shiny.isShiny(b2.enemy.mon) and b2.enemy.mon.shiny == false, "newWild: pending none stays non-shiny at rate Always")
naturalDVs = { attack = 15, defense = 10, speed = 10, special = 10, hp = 15 }
Shiny.setPending("none")
local b3 = B.newWild(game, "PIDGEY", 5)
check(not engineIsShiny(b3.enemy.mon.dvs), "newWild: pending none breaks a natural shiny spread")
naturalDVs = nil

-- classic encounter: no pending, rolls at the rate
setRate("always")
local b4 = B.newWild(game, "PIDGEY", 5)
check(b4.enemy.mon.shiny == true and engineIsShiny(b4.enemy.mon.dvs), "newWild: rate Always -> shiny")
setRate("off")
naturalDVs = { attack = 15, defense = 10, speed = 10, special = 10, hp = 15 }
local b5 = B.newWild(game, "PIDGEY", 5)
check(not engineIsShiny(b5.enemy.mon.dvs), "newWild: rate Off -> no shiny at all, natural ones included")
naturalDVs = nil
setRate("modern")
game.rng = function() return 1 end
local b6 = B.newWild(game, "PIDGEY", 5)
check(b6.enemy.mon.shiny == true, "newWild: modern hits when the engine RNG rolls 1")
game.rng = function() return 3 end
local b7 = B.newWild(game, "PIDGEY", 5)
check(not Shiny.isShiny(b7.enemy.mon), "newWild: modern misses when the engine RNG rolls 3")
game.rng = nil

-- only wild enemies: Pokemon.new outside newWild is untouched
setRate("always")
local outside = P.new(DATA, "PIDGEY", 5)
check(not Shiny.isShiny(outside) and outside.shiny == nil, "Pokemon.new outside newWild is never altered (trainers, gifts, eggs, starters)")

-- pending never leaks: cleared if newWild never reached Pokemon.new, and on errors
P, B = install(false)
local realNewWild = B.newWild
Shiny.install(mod, { Pokemon = P, BattleState = B, Stats = Stats, isGen2 = function() return false end })
Shiny.setPending("none")
B.newWild(game, "PIDGEY", 5)
eq(Shiny.pending(), nil, "pending cleared after a newWild")
local P2, B2 = freshEngine()
function B2.newWild() return { dead = true } end -- never calls Pokemon.new
Shiny.install(mod, { Pokemon = P2, BattleState = B2, Stats = Stats, isGen2 = function() return false end })
Shiny.setPending(sdv)
B2.newWild(game, "PIDGEY", 5)
eq(Shiny.pending(), nil, "stale pending cleared when newWild never created a mon")
local P3, B3 = freshEngine()
function B3.newWild() error("boom") end
Shiny.install(mod, { Pokemon = P3, BattleState = B3, Stats = Stats, isGen2 = function() return false end })
Shiny.setPending(sdv)
local okErr, errMsg = pcall(B3.newWild, game, "PIDGEY", 5)
check(okErr == false and tostring(errMsg):find("boom", 1, true) ~= nil, "newWild: errors propagate")
eq(Shiny.pending(), nil, "pending cleared after an error")
local afterErr = P3.new(DATA, "PIDGEY", 5)
check(not Shiny.isShiny(afterErr), "an error leaves newWild mode (later Pokemon.new is untouched)")

-- Gen 2 games are left alone
setRate("always")
P, B = install(true)
Shiny.setPending(sdv)
local g2 = B.newWild(game, "PIDGEY", 5)
check(not Shiny.isShiny(g2.enemy.mon), "Gen 2: nothing is made shiny")
eq(Shiny.pending(), nil, "Gen 2: pending dropped")

-- ---------------------------------------------------------------- manifest: Shiny Pokemon is a conflict
do
  local f = assert(io.open("manifest.json", "rb"))
  local text = f:read("*a"); f:close()
  local conflicts = text:match('"conflicts"%s*:%s*(%b[])') or ""
  check(conflicts:find('"SHINY_POKEMON"', 1, true) ~= nil, "manifest: SHINY_POKEMON is declared a conflict")
  check(conflicts:find('"overworld_wild_spawns"', 1, true) ~= nil, "manifest: the upstream mod stays a conflict")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
