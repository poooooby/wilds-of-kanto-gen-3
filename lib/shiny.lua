-- SHINY RATE (Red/Blue/Yellow): our own shiny system, replacing the Shiny Pokemon mod.
-- Based on the design of masterwebx's Shiny Pokemon mod (MIT, https://github.com/masterwebx/gen1recomp-shiny-pokemon):
-- the rate steps, rolling real shiny DVs on wilds and the newWild / Pokemon.new hand-off come from that mod.
-- See THIRD_PARTY_NOTICES.md.
--
-- A shiny is the engine's RBY "virtual shiny" (Stats.isShiny): Defense/Speed/Special DV 10 and an
-- Attack DV of 2, 3, 6, 7, 10, 11, 14 or 15. Wild Pokemon roll at the SHINY RATE option's chance:
--   * visible spawns roll when they are created (record.shiny -> entity.shiny -> the shiny overworld
--     sprite) and hand the result to the battle they start (setPending / armForBattle), so the mon you
--     fight is the one you saw;
--   * classic encounters (steps, Surf, rods) roll inside BattleState.newWild.
-- A caught shiny keeps its shiny DVs, so the follower and party use the
-- shiny sprite. Trainers, gifts, eggs and starters are never touched: Pokemon.new is only altered while
-- BattleState.newWild is running.
--
-- Gen 2 (Gold) already has a native DV shiny (1/8192), so it is not wrapped: Gold builds every mon through
-- Mon.new, which asks the engine's `shiny.roll` hook whether the DVs make it shiny. See the Gen 2 section at the
-- bottom: a wild encounter or a visible spawn's battle arms a short-lived token, and the hook consumes it once.
--
-- install() wraps Pokemon.new and BattleState.newWild (engine_internals permission, same technique the
-- Shiny Pokemon mod used). Shininess must be decided when the mon is created: the battler is built from
-- it, so patching it afterwards would leave the battle's stats behind.
local V = ...

local Shiny = {}

-- denominator per rate key (0 = always); "off" has none
Shiny.RATE_DENOMINATOR = {
  gen2 = 8192, modern = 4096, common = 1024, frequent = 512, often = 100, high = 10, always = 0,
}
Shiny.DEFAULT_RATE = "modern"
-- Attack DVs that make a shiny (with Defense/Speed/Special = 10); mirrors Stats.isShiny.
Shiny.ATTACK_DVS = { 2, 3, 6, 7, 10, 11, 14, 15 }

local function tryRequire(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
  return nil
end

local function rngFn(rng)
  if type(rng) == "function" then return rng end
  if love and love.math and love.math.random then return love.math.random end
  return math.random
end

-- ------------------------------------------------------------------ rate
--- The SHINY RATE key ("off" | "gen2" | "modern" | ...). Fails to the default if the option can't be read.
function Shiny.rateKey(mod)
  local ok, Config = pcall(function() return V.require("config") end)
  if not (ok and Config and type(Config.shinyRate) == "function") then return Shiny.DEFAULT_RATE end
  local okRead, key = pcall(Config.shinyRate, mod)
  if okRead and (key == "off" or Shiny.RATE_DENOMINATOR[key] ~= nil) then return key end
  return Shiny.DEFAULT_RATE
end

--- true with the option's chance. rng(lo, hi) is the engine's integer RNG.
function Shiny.roll(mod, rng)
  local key = Shiny.rateKey(mod)
  if key == "off" then return false end
  local denom = Shiny.RATE_DENOMINATOR[key]
  if denom == nil then return false end
  if denom <= 1 then return true end
  return rngFn(rng)(1, denom) == 1
end

-- ------------------------------------------------------------------ DVs and mons
--- Shiny DVs: Attack from ATTACK_DVS, Defense/Speed/Special 10, HP DV derived like Stats.randomDVs.
function Shiny.makeDVs(rng)
  rng = rngFn(rng)
  local dvs = {
    attack = Shiny.ATTACK_DVS[rng(1, #Shiny.ATTACK_DVS)],
    defense = 10,
    speed = 10,
    special = 10,
  }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

--- Same rule as the engine's Stats.isShiny, without needing the engine (tests, Gen 2 guard).
function Shiny.dvsAreShiny(dvs)
  if type(dvs) ~= "table" then return false end
  if (dvs.defense or 0) ~= 10 or (dvs.speed or 0) ~= 10 or (dvs.special or 0) ~= 10 then return false end
  for _, a in ipairs(Shiny.ATTACK_DVS) do
    if dvs.attack == a then return true end
  end
  return false
end

function Shiny.isShiny(mon)
  if type(mon) ~= "table" then return false end
  return mon.shiny == true or Shiny.dvsAreShiny(mon.dvs)
end

local function recalc(data, mon, Stats)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def and def.baseStats and Stats and Stats.calc then
    mon.stats = Stats.calc(def, mon.level or 1, mon.dvs, mon.statExp)
    mon.hp = mon.stats.hp
  end
end

--- Make `mon` a shiny with `dvs` (default: fresh shiny DVs) and rebuild its stats. Returns the mon.
function Shiny.applyToMon(data, mon, dvs, deps)
  if type(mon) ~= "table" then return mon end
  deps = deps or {}
  mon.dvs = dvs or Shiny.makeDVs()
  mon.shiny = true
  recalc(data, mon, deps.Stats or tryRequire("src.pokemon.Stats"))
  return mon
end

--- Make sure `mon` is NOT shiny: a natural shiny DV spread (about 1 in 8192) is nudged to Special DV 9.
function Shiny.clearShiny(data, mon, deps)
  if type(mon) ~= "table" then return mon end
  mon.shiny = false
  if Shiny.dvsAreShiny(mon.dvs) then
    mon.dvs.special = 9
    mon.dvs.hp = (mon.dvs.attack % 2) * 8 + (mon.dvs.defense % 2) * 4 + (mon.dvs.speed % 2) * 2
      + (mon.dvs.special % 2)
    deps = deps or {}
    recalc(data, mon, deps.Stats or tryRequire("src.pokemon.Stats"))
  end
  return mon
end

--- Final say for a Pokemon the mod creates itself (overworld catches): shiny when `wantShiny`,
-- otherwise guaranteed not shiny.
function Shiny.finalize(data, mon, wantShiny, deps)
  if wantShiny then return Shiny.applyToMon(data, mon, nil, deps) end
  return Shiny.clearShiny(data, mon, deps)
end

-- ------------------------------------------------------------------ hand-off to the battle
-- pending: nil | { dvs = table } | { none = true }. A visible wild that rolled non-shiny must stay
-- non-shiny in battle, so "none" is an explicit value (never a bare false), consumed by the next
-- newWild exactly like a shiny hand-off.
local state = { pending = nil, inNewWild = false, mod = nil, deps = nil, isGen2 = nil, gen2Pending = nil }
Shiny._state = state

function Shiny.setPending(dvsOrNone)
  if dvsOrNone == "none" then
    state.pending = { none = true }
  elseif type(dvsOrNone) == "table" then
    state.pending = { dvs = dvsOrNone }
  else
    state.pending = nil
  end
end

function Shiny.clearPending()
  state.pending = nil
  state.gen2Pending = nil
end

function Shiny.pending()
  return state.pending
end

--- For a visible spawn that is about to start a wild battle: shiny DVs when its record rolled shiny,
-- "none" otherwise, so the fought mon matches the seen sprite. Gold (isGen2) has no newWild to hand DVs to,
-- so it arms the Gen 2 token instead (see Shiny.armWild).
function Shiny.armForBattle(record, isGen2)
  if isGen2 then
    if type(record) == "table" then Shiny.armWild(record.species, record.level, record.shiny == true) end
    return
  end
  if type(record) == "table" and record.shiny == true then
    Shiny.setPending(Shiny.makeDVs())
  else
    Shiny.setPending("none")
  end
end

-- ------------------------------------------------------------------ install
local function activeFor(game)
  if not state.mod then return false end
  if type(state.isGen2) == "function" then
    local ok, gen2 = pcall(state.isGen2, state.mod, game)
    if ok and gen2 then return false end
  end
  return true
end

--- Wrap Pokemon.new and BattleState.newWild. Idempotent; safe to call again (it only refreshes the
-- mod/deps the wrappers read). `deps` = { Pokemon, BattleState, Stats, isGen2 } is injectable for tests.
-- Returns true when the wrappers are in place, or false plus a reason.
function Shiny.install(mod, deps)
  deps = deps or {}
  local Pokemon = deps.Pokemon or tryRequire("src.pokemon.Pokemon")
  local BattleState = deps.BattleState or tryRequire("src.battle.BattleState")
  local Stats = deps.Stats or tryRequire("src.pokemon.Stats")
  if not (type(Pokemon) == "table" and type(Pokemon.new) == "function"
          and type(BattleState) == "table" and type(BattleState.newWild) == "function"
          and type(Stats) == "table") then
    return false, "engine modules unavailable"
  end

  state.mod = mod
  state.deps = { Stats = Stats }
  state.isGen2 = deps.isGen2 or function(m, game)
    local ok, GameCompat = pcall(function() return V.require("game_compat") end)
    return ok and GameCompat and GameCompat.isGen2(m, game) or false
  end

  if not Pokemon._wildsShinyNew then
    local origNew = Pokemon.new
    local function shinyNew(data, species, level, rng)
      local mon = origNew(data, species, level, rng)
      if not state.inNewWild then return mon end
      -- Inside BattleState.newWild this is the wild enemy: decide its shininess here.
      local pending = state.pending
      if pending then
        state.pending = nil
        if pending.dvs then return Shiny.applyToMon(data, mon, pending.dvs, state.deps) end
        return Shiny.clearShiny(data, mon, state.deps)
      end
      if Shiny.roll(state.mod, rng) then
        return Shiny.applyToMon(data, mon, Shiny.makeDVs(rng), state.deps)
      end
      return Shiny.clearShiny(data, mon, state.deps)
    end
    Pokemon.new = shinyNew
    Pokemon._wildsShinyNew = shinyNew
  end

  if not BattleState._wildsShinyNewWild then
    local origNewWild = BattleState.newWild
    local function shinyNewWild(game, species, level, opts)
      if not activeFor(game) then
        state.pending = nil
        return origNewWild(game, species, level, opts)
      end
      state.inNewWild = true
      local ok, result = pcall(origNewWild, game, species, level, opts)
      state.inNewWild = false
      state.pending = nil -- consumed above, or stale if newWild never reached Pokemon.new
      if not ok then error(result, 0) end
      return result
    end
    BattleState.newWild = shinyNewWild
    BattleState._wildsShinyNewWild = shinyNewWild
  end
  return true
end

-- ------------------------------------------------------------------ Gen 2 (Gold)
-- Gold's Mon.new asks the `shiny.roll` hook chain whether a mon's DVs make it shiny -- for trainers, starters, gifts
-- and eggs too, and again for every non-shiny mon each time its summary opens. A bare random hook would therefore
-- make trainer mons shiny and re-roll on every summary. So the rate goes through a short-lived token: the code that
-- is about to build a WILD mon arms { species, level, shiny } (classic encounters through encounter.species /
-- encounter.fishing, visible spawns through armForBattle), and the `shiny.roll` wrapper consumes it exactly once for
-- that species. Every other call falls through to the vanilla DV check.
--   shiny = true  -> a shiny with ordinary DVs (the engine keeps a forced shiny flag for good)
--   shiny = false -> not shiny even when the DVs happen to read shiny (so "Off" really is off)
Shiny.GEN2_TTL = 5 -- seconds a token survives if its mon is never built (repel filter, cancelled battle)

local function clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

--- Arm the token for the wild `species` (at `level`) that is about to be built. `now` is injectable for tests.
function Shiny.armWild(species, level, shiny, now)
  if species == nil then
    state.gen2Pending = nil
    return
  end
  state.gen2Pending = {
    species = species, level = tonumber(level), shiny = shiny == true,
    expires = (now or clock()) + Shiny.GEN2_TTL,
  }
end

function Shiny.gen2Pending()
  return state.gen2Pending
end

--- The shiny.roll ctx ({ dvs, species, def, level }) against the armed token. Returns handled, shiny.
-- Consumes the token when it matches; an expired token is dropped; anything else is not ours.
function Shiny.consumeGen2(ctx, now)
  local p = state.gen2Pending
  if not p then return false end
  if (now or clock()) > p.expires then
    state.gen2Pending = nil
    return false
  end
  if type(ctx) ~= "table" or ctx.species == nil or ctx.species ~= p.species then return false end
  if p.level ~= nil and ctx.level ~= nil and tonumber(ctx.level) ~= p.level then return false end
  state.gen2Pending = nil
  return true, p.shiny == true
end

--- Register the Gen 2 hooks through mod.hooks:wrap. `deps.isGen2()` gates the arming (the encounter hooks also
-- exist in Gen 1, where the token would never be consumed). Returns one function that removes every wrapper,
-- or nil plus a reason.
function Shiny.installGen2(mod, deps)
  deps = deps or {}
  local hooks = mod and mod.hooks
  if not (hooks and type(hooks.wrap) == "function") then return nil, "mod.hooks unavailable" end
  local function gen2()
    if type(deps.isGen2) ~= "function" then return true end
    local ok, result = pcall(deps.isGen2)
    return ok and result == true
  end
  local function armFromRoll(roll, rng)
    if type(roll) ~= "table" or roll.species == nil or not gen2() then return end
    Shiny.armWild(roll.species, roll.level, Shiny.roll(mod, rng))
  end

  local unwraps = {}
  local function add(name, fn)
    local ok, unwrap = pcall(hooks.wrap, hooks, name, fn)
    if ok and type(unwrap) == "function" then unwraps[#unwraps + 1] = unwrap end
    return ok
  end

  -- The final wild pick (after every mod that transforms it), right before Mon.new builds it.
  add("encounter.species", function(next, enc, ctx)
    local out = next(enc, ctx)
    armFromRoll(out, ctx and ctx.rng)
    return out
  end)
  -- Fishing hands its pick back through this chain (rod, mapId, candidates, ctx).
  add("encounter.fishing", function(next, ...)
    local roll = next(...)
    armFromRoll(roll, nil)
    return roll
  end)
  local hookOk = add("shiny.roll", function(next, ctx)
    if gen2() then
      local handled, shiny = Shiny.consumeGen2(ctx)
      if handled then return shiny end
    end
    return next(ctx)
  end)
  if not hookOk then
    for i = #unwraps, 1, -1 do pcall(unwraps[i]) end
    return nil, "shiny.roll hook unavailable"
  end
  return function()
    for i = #unwraps, 1, -1 do pcall(unwraps[i]) end
    unwraps = {}
  end
end

return Shiny
