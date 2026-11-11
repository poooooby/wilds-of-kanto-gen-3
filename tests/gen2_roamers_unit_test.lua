-- Gold's roaming legendaries as visible spawns (lib/gen2/roamers.lua + its spawn_logic / main.lua wiring).
-- Part 1: the module against a fake engine. Part 2: parity with the REAL engine Roamers.checkEncounter
-- (../gen1recomp, skipped when absent). Part 3: main.lua booted on a fake Gold world.
-- Run: lua tests/gen2_roamers_unit_test.lua
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
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end
local function fixed(v) return function() return v end end

package.loaded["src.core.GameVersion"] = {
  get = function() return "crystal" end,
  isYellow = function() return false end,
  isGold = function() return true end,
  generation = function() return 2 end,
  engine = function() return "crystal" end,
}

local Roam = assert(loadfile("lib/gen2/roamers.lua"))()

local function freshSave()
  return {
    roamers = {
      { species = "RAIKOU", level = 40, map = "ROUTE_42", hp = 0 },
      { species = "ENTEI", level = 40, map = "ROUTE_37", hp = 0 },
    },
  }
end

-- ------------------------------------------------------------ Part 1: module, fake engine
local fakeEngine = {
  LEVEL = 40,
  list = function(save) return save and save.roamers end,
  active = function(slot) return type(slot) == "table" and slot.species ~= nil and slot.map ~= nil end,
}
local deps = { Roamers = fakeEngine }

do
  local save = freshSave()
  -- value 1 -> slot 1 (Raikou), 2 -> slot 2 (Entei), 0 / 4 -> low bits 0 = no beast, >= 100 -> no beast.
  local hit = Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(1), nil, deps)
  check(hit ~= nil, "Raikou replaces a spawn on its own route")
  eq(hit and hit.index, 1, "roster slot 1")
  eq(hit and hit.species, "RAIKOU", "species from the save")
  eq(hit and hit.level, 40, "level from the save")
  eq(hit and hit.dvs, nil, "no DVs before the first meeting")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(2), nil, deps), nil, "Entei's roll fails while Entei is elsewhere")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(0), nil, deps), nil, "low bits 0 = no beast")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(4), nil, deps), nil, "low bits 0 = no beast (4)")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(101), nil, deps), nil, "100 and above = no beast")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "water", fixed(1), nil, deps), nil, "never on water")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(1), { [1] = true }, deps), nil, "a beast already visible is not doubled")
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(3), nil, deps), nil, "Crystal has no slot 3")
  local hit2 = Roam.pickForSpawn(save, "ROUTE_37", "grass", fixed(2), nil, deps)
  eq(hit2 and hit2.species, "ENTEI", "Entei on Route 37")

  save.roamers[1].hp = 120
  save.roamers[1].dvs = { attack = 2, defense = 10, speed = 10, special = 10 }
  local met = Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(1), nil, deps)
  check(met and met.dvs == save.roamers[1].dvs, "a met beast carries its kept DVs")

  save.roamers[1].species, save.roamers[1].map = nil, nil
  eq(Roam.pickForSpawn(save, "ROUTE_42", "grass", fixed(1), nil, deps), nil, "a caught / beaten beast never spawns")
  eq(Roam.pickForSpawn({}, "ROUTE_42", "grass", fixed(1), nil, deps), nil, "no roster before the Burned Tower")
end

do
  local save = freshSave()
  local began, started = {}, {}
  local engine = setmetatable({
    beginBattle = function(s, index, data)
      began[#began + 1] = { save = s, index = index, data = data }
      return { species = s.roamers[index].species, level = 40, hp = 150 }
    end,
  }, { __index = fakeEngine })
  local world = {
    map = { id = "ROUTE_37" },
    startBattle = function(_, opts) started[#started + 1] = opts end,
  }
  local game = { save = save, data = { tag = "data" } }
  local ok = Roam.startBattle(game, world, 2, { Roamers = engine })
  eq(ok, true, "roaming battle starts")
  eq(#began, 1, "engine beginBattle used once")
  eq(began[1] and began[1].index, 2, "for the beast's own slot")
  check(began[1] and began[1].data == game.data, "with the game's data")
  eq(started[1] and started[1].roaming, 2, "World:startBattle gets roaming = slot")
  eq(started[1] and started[1].wild and started[1].wild.species, "ENTEI", "the wild mon is the beast")
  eq(save.pokedex and save.pokedex.seen and save.pokedex.seen.ENTEI, true, "marked seen, as the step path does")

  local okMoved, why = Roam.startBattle(game, world, 1, { Roamers = engine })
  eq(okMoved, nil, "no battle with a beast that is on another route")
  check(why ~= nil, "with a reason")
  eq(#began, 1, "no beginBattle for it")
end

do
  local calls = 0
  local engine = { checkEncounter = function() calls = calls + 1; return { index = 1 } end }
  local block = false
  local unwrap = Roam.installStepGate(function() return block end, { Roamers = engine })
  check(type(unwrap) == "function", "step gate installs")
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "gate open: the engine's roll runs")
  block = true
  eq(engine.checkEncounter(nil, "ROUTE_42", false), nil, "gate shut: no beast on the step")
  eq(calls, 1, "and the engine's roll is skipped")
  local wrapper = engine.checkEncounter
  local unwrap2 = Roam.installStepGate(function() return false end, { Roamers = engine })
  check(engine.checkEncounter == wrapper, "a reload swaps the gate, not a second wrapper")
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "the newest gate is the one read")
  unwrap() -- stale unwrap from the old load must not remove the new gate
  check(type(engine._wildsStepGate) == "function", "an old load's unwrap leaves the new gate alone")
  unwrap2()
  eq(engine._wildsStepGate, nil, "unwrap removes the gate")
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "no gate: vanilla")
  local gateErr = Roam.installStepGate(function() error("boom") end, { Roamers = engine })
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "a gate that errors fails open (vanilla)")
  gateErr()
end

-- ------------------------------------------------------------ Part 2: the real engine module
do
  local enginePath = "../gen1recomp/src/core/gen2/Roamers.lua"
  if not readFile(enginePath) then
    print("skip real-engine Roamers checks (no ../gen1recomp)")
  else
    package.loaded["src.battle.gen2.Mon"] = { new = function() return nil end }
    package.loaded["src.mods.Runtime"] = {
      wants = function() return false end,
      emit = function() end,
    }
    local Real = assert(loadfile(enginePath))()
    local realDeps = { Roamers = Real }
    local save = {}
    Real.init(save, {})
    check(type(save.roamers) == "table" and #save.roamers >= 2, "real InitRoamMons roster")
    -- Same byte, same answer, for every byte: our spawn roll IS the step roll.
    for _, mapId in ipairs({ save.roamers[1].map, save.roamers[2].map, "ROUTE_29" }) do
      local mismatches = 0
      for v = 0, 255 do
        local stepHit = Real.checkEncounter(save, mapId, false, fixed(v))
        local spawnHit = Roam.pickForSpawn(save, mapId, "grass", fixed(v), nil, realDeps)
        local a = stepHit and stepHit.index or nil
        local b = spawnHit and spawnHit.index or nil
        if a ~= b then mismatches = mismatches + 1 end
      end
      eq(mismatches, 0, "spawn roll matches the engine's step roll for all 256 bytes on " .. tostring(mapId))
    end
    local unwrap = Roam.installStepGate(function() return true end, realDeps)
    eq(Real.checkEncounter(save, save.roamers[1].map, false, fixed(1)), nil, "real checkEncounter gated shut")
    unwrap()
    check(Real.checkEncounter(save, save.roamers[1].map, false, fixed(1)) ~= nil, "real checkEncounter vanilla again")
    package.loaded["src.battle.gen2.Mon"] = nil
    package.loaded["src.mods.Runtime"] = nil
  end
end

-- ------------------------------------------------------------ Part 3: main.lua on a fake Gold world
local optionStore = {
  enabled = true,
  sprite_style = "followers",
  sprite_fade = "solid",
  follow_control = "trainer",
  trainer_trail = false,
  follower_count = 1,
  random_encounters = true,
}
local events, battles, worldBattles, contentSprites = {}, {}, {}, {}
local began = {}

local engineRoamers = {
  LEVEL = 40,
  list = fakeEngine.list,
  active = fakeEngine.active,
  checkEncounter = function() return { index = 1, species = "RAIKOU", level = 40 } end,
  beginBattle = function(save, index)
    began[#began + 1] = index
    return { species = save.roamers[index].species, level = 40, hp = 150 }
  end,
}
package.loaded["src.core.gen2.Roamers"] = engineRoamers

local goldWorld = {
  map = {
    id = "ROUTE_42",
    widthCells = 12,
    heightCells = 8,
    isWaterCell = function() return false end,
    isGrassCell = function(_, x, y) return y == 2 and x >= 2 and x <= 9 end,
    isWalkableCell = function() return true end,
    inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 12 and y < 8 end,
    warpAtCell = function() return nil end,
  },
  player = { cellX = 8, cellY = 7, facing = "up" },
  playerState = "normal",
  daytime = "DAY",
  entities = {},
  npcs = {},
  queueScript = function(_, rows) battles[#battles + 1] = rows; return true end,
  startBattle = function(_, opts) worldBattles[#worldBattles + 1] = opts end,
}
local slots = {}
for i = 1, 7 do slots[i] = { species = "SPEAROW", level = 13 } end
local goldGame = {
  save = { party = { { species = "CYNDAQUIL", level = 20 } }, playerState = "normal", roamers = freshSave().roamers },
  world = goldWorld,
  data = {
    pokemon = {
      SPEAROW = { name = "SPEAROW", dex = 21, index = 21 },
      RAIKOU = { name = "RAIKOU", dex = 243, index = 243 },
      ENTEI = { name = "ENTEI", dex = 244, index = 244 },
      CYNDAQUIL = { name = "CYNDAQUIL", dex = 155, index = 155 },
    },
    gen2Encounters = {
      grass = { ROUTE_42 = { rates = { MORN = 25, DAY = 25, NITE = 25 }, slots = { MORN = slots, DAY = slots, NITE = slots } } },
    },
  },
}
local mod = {
  path = ".",
  id = "wilds_of_kanto_gen3",
  game = goldGame,
  log = {
    info = function() end, debug = function() end,
    warn = function() end,
    error = function(_, fmt, ...) io.stderr:write("ERROR " .. string.format(tostring(fmt), ...) .. "\n") end,
  },
  read = function(_, rel) return readFile(rel) or readFile("./" .. rel) end,
  find = function() return nil end,
  save = { get = function() return nil end, set = function() end },
  options = {
    define = function() end,
    get = function(_, k) return optionStore[k] end,
    set = function(_, k, v) optionStore[k] = v end,
  },
  content = {
    sprites = {
      get = function(_, id) return contentSprites[id] end,
      register = function(_, id, def) contentSprites[id] = def end,
      patch = function(_, id, def) contentSprites[id] = def end,
    },
    pokemon = { get = function() return nil end, each = function() return function() return nil end end },
    render_pipelines = { register = function() end },
    screens = { register = function() end },
  },
  assets = { path = function(_, rel) return rel end },
  events = {
    on = function(_, name, fn)
      events[name] = events[name] or {}
      events[name][#events[name] + 1] = fn
    end,
  },
  hooks = { wrap = function() return function() end end },
  ui = {},
  exports = {},
  world = {
    game = goldGame,
    overworld = function() return goldWorld end,
    queueScript = function(_, rows) battles[#battles + 1] = rows; return true end,
  },
}

local entry = assert(loadfile("main.lua"))()
local bootOk, bootErr = pcall(entry, mod)
check(bootOk, "Wilds boots on Gold (" .. tostring(bootErr) .. ")")
local logic = mod.exports.logic

check(events["roamer.moved"] ~= nil, "Gold subscribes to roamer.moved")
check(type(engineRoamers._wildsStepGate) == "function", "Gold gates the engine's step roll for a beast")
check(engineRoamers.checkEncounter(goldGame.save, "ROUTE_42", false) ~= nil, "Classic Enc on: the step roll stays vanilla")
optionStore.random_encounters = false
eq(engineRoamers.checkEncounter(goldGame.save, "ROUTE_42", false), nil, "Classic Enc off: no unseen beast on a step")
optionStore.random_encounters = true

-- A spawn on the beast's route, with the beast's roll forced: the spawn IS Raikou.
logic._roamerRandom = fixed(1)
logic.targetSpawnCount = 10 -- no map.entered ran, so there is no region budget yet
-- No engine renderer here: a bare entity stands in, the record is what is under test.
local realRender = logic.render
logic.render = setmetatable({
  makeEntity = function(_, _, record)
    return { id = record.id, species = record.species, cellX = record.x, cellY = record.y, facing = "down",
             overworldWildSpawn = true }
  end,
}, { __index = realRender })
logic._attach = function() return true end
local spawnOk, spawnId, spawnWhy = pcall(function() return logic:trySpawn(goldGame, {}) end)
check(spawnOk, "trySpawn runs (" .. tostring(spawnId) .. ")")
check(spawnId ~= nil, "trySpawn spawned (" .. tostring(spawnWhy) .. ")")
local raikou
for _, record in pairs(logic.spawns) do
  if record.roamerIndex then raikou = record end
end
check(raikou ~= nil, "a visible spawn became the roaming beast")
eq(raikou and raikou.species, "RAIKOU", "it is Raikou")
eq(raikou and raikou.level, 40, "at the beast's level")
eq(raikou and raikou.roamerIndex, 1, "tied to roster slot 1")
eq(raikou and raikou.shiny, false, "not shiny before its DVs exist")
-- With Raikou on screen, the same roll never makes a second Raikou.
pcall(function() return logic:trySpawn(goldGame, {}) end)
local count = 0
for _, record in pairs(logic.spawns) do
  if record.roamerIndex == 1 then count = count + 1 end
end
eq(count, 1, "never two of the same beast on screen")
logic._roamerRandom = nil

if raikou then
  -- Touching it starts the engine's roaming battle, not a scripted start_battle.
  local before = #battles
  local started = logic:_startBattle(raikou)
  eq(started, true, "touching Raikou starts a battle")
  eq(#battles, before, "not through start_battle")
  eq(#worldBattles, 1, "through World:startBattle")
  eq(worldBattles[1] and worldBattles[1].roaming, 1, "as the roaming battle for slot 1")
  eq(began[1], 1, "built by the engine's beginBattle")
  logic.pendingBattle = nil
end

-- A beast that moved on since it spawned is gone: no battle, the spawn is removed.
do
  local record = {
    id = "wilds_of_kanto_entity_test_entei", mapId = "ROUTE_42", x = 3, y = 2,
    species = "ENTEI", level = 40, state = "available", behavior = "IDLE_LOOK", roamerIndex = 2,
  }
  logic.spawns[record.id] = record
  logic.byMap.ROUTE_42 = logic.byMap.ROUTE_42 or {}
  table.insert(logic.byMap.ROUTE_42, record.id)
  local before = #worldBattles
  eq(logic:_startBattle(record), false, "no battle with a beast that has left (Entei is on Route 37)")
  eq(#worldBattles, before, "no roaming battle started")
  eq(logic.spawns[record.id], nil, "its spawn is removed")
end

-- roamer.moved: the visible beast leaves with it.
do
  local record = {
    id = "wilds_of_kanto_entity_test_raikou2", mapId = "ROUTE_42", x = 5, y = 2,
    species = "RAIKOU", level = 40, state = "available", behavior = "IDLE_LOOK", roamerIndex = 1,
  }
  logic.spawns[record.id] = record
  logic.byMap.ROUTE_42 = logic.byMap.ROUTE_42 or {}
  table.insert(logic.byMap.ROUTE_42, record.id)
  for _, fn in ipairs(events["roamer.moved"] or {}) do
    fn({ index = 2, from = "ROUTE_37", to = "ROUTE_38" })
  end
  check(logic.spawns[record.id] ~= nil, "another beast moving leaves Raikou alone")
  for _, fn in ipairs(events["roamer.moved"] or {}) do
    fn({ index = 1, from = "ROUTE_42", to = "ROUTE_43" })
  end
  eq(logic.spawns[record.id], nil, "Raikou's spawn leaves with Raikou")
end

package.loaded["src.core.gen2.Roamers"] = nil

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nAll Gen 2 roaming-beast tests passed.")
