-- lib/shiny.lua Gen 2 (Gold) half: SHINY RATE through the engine's shiny.roll hook, gated by an armed token so trainers,
-- starters, gifts, eggs and summary re-checks stay vanilla.
-- Run: lua tests/shiny_gen2_unit_test.lua
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
local gen2 = true
local hookChains = {}
local hooks = {}
-- Same shape as the engine's Runtime hook chain: wrap(name, fn(next, ...)) -> unwrap; call(name, vanilla, ...).
function hooks:wrap(name, fn)
  hookChains[name] = hookChains[name] or {}
  local list = hookChains[name]
  list[#list + 1] = fn
  return function()
    for i, f in ipairs(list) do if f == fn then table.remove(list, i) break end end
    if #list == 0 then hookChains[name] = nil end
  end
end
local function callHook(name, vanilla, ...)
  local list = hookChains[name]
  if not list then return vanilla(...) end
  local function run(i, ...)
    local w = list[i]
    if not w then return vanilla(...) end
    return w(function(...) return run(i + 1, ...) end, ...)
  end
  return run(1, ...)
end

local mod = {
  id = "wilds_of_kanto_gen3", path = ".", hooks = hooks,
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
V.require("config")
local Shiny = V.require("shiny")
local function setRate(key) savedOpts.shiny_rate = key end

-- Gen 2's Mon.new / Mon.syncIdentity as far as shininess goes (src/battle/gen2/Mon.lua).
local function vanillaShiny(dvs)
  if not dvs then return false end
  if dvs.speed ~= 10 or dvs.defense ~= 10 or dvs.special ~= 10 then return false end
  local a = dvs.attack or 0
  return a % 4 == 2 or a % 4 == 3
end
local function isShiny(dvs, ctx)
  if not hookChains["shiny.roll"] then return vanillaShiny(dvs) end
  return callHook("shiny.roll", function(c) return vanillaShiny(c.dvs) end,
    { dvs = dvs, species = ctx.species, level = ctx.level }) and true or false
end
local function newMon(species, level, dvs, opts)
  opts = opts or {}
  return { species = species, level = level, dvs = dvs,
    shiny = opts.shiny or isShiny(dvs, { species = species, level = level }) }
end
local function syncIdentity(mon)
  mon.shiny = mon.shiny or isShiny(mon.dvs, { species = mon.species, level = mon.level })
  return mon
end
local PLAIN = { attack = 5, defense = 5, speed = 5, special = 5 }
local SHINY_DVS = { attack = 14, defense = 10, speed = 10, special = 10 }

-- One wild encounter as the engine runs it: the pick goes through encounter.species, then Mon.new builds it.
local function wildEncounter(species, level, dvs)
  local pick = callHook("encounter.species", function(enc) return enc end, { species = species, level = level },
    { rng = function() return 1 end })
  return newMon(pick.species, pick.level, dvs)
end

local function install(isGen2Fn)
  return Shiny.installGen2(mod, { isGen2 = isGen2Fn or function() return gen2 end })
end

-- ---------------------------------------------------------------- install
do
  local unwrap = install()
  check(type(unwrap) == "function", "installGen2 returns an unwrap function")
  check(hookChains["shiny.roll"] ~= nil, "shiny.roll wrapped")
  check(hookChains["encounter.species"] ~= nil, "encounter.species wrapped")
  check(hookChains["encounter.fishing"] ~= nil, "encounter.fishing wrapped")
  unwrap()
  check(hookChains["shiny.roll"] == nil and hookChains["encounter.species"] == nil and hookChains["encounter.fishing"] == nil,
    "the unwrap function removes every wrapper")
  local none, why = Shiny.installGen2({ hooks = nil })
  check(none == nil and type(why) == "string", "installGen2 without mod.hooks fails cleanly")
end

-- ---------------------------------------------------------------- classic wild encounter: rate "always"
local unwrap = install()
Shiny.clearPending()
setRate("always")
do
  local wild = wildEncounter("PIDGEY", 5, PLAIN)
  eq(wild.shiny, true, "always: a wild encounter is shiny (ordinary DVs, hook-made shiny)")
  eq(Shiny.gen2Pending(), nil, "the token is consumed by the wild mon")
  local second = wildEncounter("PIDGEY", 5, PLAIN)
  eq(second.shiny, true, "always: the next encounter arms a fresh token")
  -- a mon built with no encounter (trainer team, starter, gift, egg) is vanilla
  local trainerMon = newMon("PIDGEY", 5, PLAIN)
  eq(trainerMon.shiny, false, "no token: a trainer/gift mon with plain DVs is not shiny")
  local naturalTrainer = newMon("PIDGEY", 5, SHINY_DVS)
  eq(naturalTrainer.shiny, true, "no token: shiny-reading DVs stay shiny (vanilla rule untouched)")
  -- summary re-check never creates a shiny
  local party = newMon("PIDGEY", 5, PLAIN)
  syncIdentity(party); syncIdentity(party); syncIdentity(party)
  eq(party.shiny, false, "summary re-checks do not re-roll a non-shiny mon")
  -- ...and never takes a shiny back
  local caught = wildEncounter("PIDGEY", 5, PLAIN)
  syncIdentity(caught)
  eq(caught.shiny, true, "a shiny stays shiny after the summary re-check")
end

-- ---------------------------------------------------------------- rate "off" really is off
setRate("off")
do
  local wild = wildEncounter("PIDGEY", 5, SHINY_DVS)
  eq(wild.shiny, false, "off: even shiny-reading DVs are not shiny for a wild encounter")
  eq(Shiny.gen2Pending(), nil, "off: the token is consumed")
  eq(newMon("PIDGEY", 5, SHINY_DVS).shiny, true, "off: only wild encounters are governed (a gift keeps its DVs)")
end

-- ---------------------------------------------------------------- gating
setRate("always")
do
  Shiny.clearPending()
  callHook("encounter.species", function(enc) return enc end, { species = "PIDGEY", level = 5 }, { rng = function() return 1 end })
  local other = newMon("RATTATA", 5, PLAIN)
  eq(other.shiny, false, "a different species does not take the armed token")
  check(Shiny.gen2Pending() ~= nil, "the token is still waiting for its own species")
  local wrongLevel = newMon("PIDGEY", 9, PLAIN)
  eq(wrongLevel.shiny, false, "a different level does not take the armed token")
  local mine = newMon("PIDGEY", 5, PLAIN)
  eq(mine.shiny, true, "the matching mon takes it")
  eq(Shiny.gen2Pending(), nil, "consumed")
end

-- ---------------------------------------------------------------- expiry and clearing
do
  Shiny.armWild("PIDGEY", 5, true, 100)
  local handled = Shiny.consumeGen2({ species = "PIDGEY", level = 5 }, 100 + Shiny.GEN2_TTL + 1)
  eq(handled, false, "an expired token is not consumed")
  eq(Shiny.gen2Pending(), nil, "an expired token is dropped")
  Shiny.armWild("PIDGEY", 5, true, 100)
  local h2, s2 = Shiny.consumeGen2({ species = "PIDGEY", level = 5 }, 101)
  check(h2 == true and s2 == true, "a live token is consumed with its answer")
  Shiny.armWild("PIDGEY", 5, true)
  Shiny.clearPending()
  eq(Shiny.gen2Pending(), nil, "clearPending drops the Gen 2 token too")
end

-- ---------------------------------------------------------------- fishing
do
  Shiny.clearPending()
  local seenArgs
  local roll = callHook("encounter.fishing", function(...)
    seenArgs = { ... }
    return { species = "MAGIKARP", level = 10 }
  end, "OLD_ROD", "ROUTE_32", { "x" }, { tod = "day" })
  eq(roll.species, "MAGIKARP", "the fishing chain still returns the pick")
  check(seenArgs and seenArgs[1] == "OLD_ROD" and seenArgs[4] and seenArgs[4].tod == "day",
    "the fishing wrapper passes every argument through")
  local hooked = newMon("MAGIKARP", 10, PLAIN)
  eq(hooked.shiny, true, "always: a fished-up mon takes the shiny roll")
  -- a fishing chain that returns nothing arms nothing
  callHook("encounter.fishing", function() return nil end, "OLD_ROD", "ROUTE_32", nil, {})
  eq(Shiny.gen2Pending(), nil, "no roll, no token")
end

-- ---------------------------------------------------------------- visible spawn hand-off
do
  Shiny.clearPending()
  Shiny.armForBattle({ species = "PIDGEY", level = 5, shiny = true }, true)
  eq(newMon("PIDGEY", 5, PLAIN).shiny, true, "a shiny spawn's battle mon is shiny")
  setRate("off")
  Shiny.armForBattle({ species = "PIDGEY", level = 5, shiny = false }, true)
  eq(newMon("PIDGEY", 5, SHINY_DVS).shiny, false, "a non-shiny spawn's battle mon stays non-shiny (matches the sprite)")
  Shiny.clearPending()
  -- Gen 1 hand-off is unchanged
  Shiny.armForBattle({ species = "PIDGEY", level = 5, shiny = true }, false)
  check(Shiny.pending() and Shiny.pending().dvs ~= nil, "Gen 1 armForBattle still sets shiny DVs")
  eq(Shiny.gen2Pending(), nil, "Gen 1 armForBattle does not touch the Gen 2 token")
  Shiny.clearPending()
end

-- ---------------------------------------------------------------- Gen 1 running: nothing is armed
do
  gen2 = false
  setRate("always")
  Shiny.clearPending()
  callHook("encounter.species", function(enc) return enc end, { species = "PIDGEY", level = 5 }, { rng = function() return 1 end })
  eq(Shiny.gen2Pending(), nil, "Gen 1: the encounter hook does not arm a Gen 2 token")
  eq(newMon("PIDGEY", 5, PLAIN).shiny, false, "Gen 1: shiny.roll is untouched")
  gen2 = true
end

unwrap()

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
