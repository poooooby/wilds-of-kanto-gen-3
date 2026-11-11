-- Gold / Silver / Crystal roaming legendaries as visible Wilds spawns.
--
-- Raikou and Entei (and Suicune in Gold / Silver) are in no map's wild table: the engine keeps each beast in the
-- save (save.roamers, src/core/gen2/Roamers.lua) on one route at a time, and CheckEncounterRoamMon lets it REPLACE an
-- ordinary step encounter on that route. Wilds' visible spawns are built from the wild tables, so this module does
-- the same thing for a spawn: on the beast's route, the spawn's pick is replaced by the beast at the game's own odds.
--
-- Everything else stays the engine's: the roster, which route each beast is on, and the battle itself
-- (Roamers.beginBattle + World:startBattle{ roaming = index }), so the saved HP and DVs, the first-turn flee, the move
-- to a new route afterwards and the slot clearing once it is caught or beaten all happen exactly as on a step.
--
-- With Classic Enc off, the engine would still roll the beast on a step (CheckEncounterRoamMon runs before the
-- encounter.roll hook Wilds suppresses), so installStepGate puts a gate in front of Roamers.checkEncounter.
local Roam = {}

local function tryRequire(path)
  local ok, mod = pcall(require, path)
  if ok then return mod end
  return nil
end

local function engine(deps)
  if deps and deps.Roamers ~= nil then return deps.Roamers or nil end
  return tryRequire("src.core.gen2.Roamers")
end

local function roster(save, E)
  if E and type(E.list) == "function" then return E.list(save) end
  return type(save) == "table" and save.roamers or nil
end

local function active(slot, E)
  if E and type(E.active) == "function" then return E.active(slot) == true end
  return type(slot) == "table" and slot.species ~= nil and slot.map ~= nil
end

-- 0 .. n-1, the same convention the engine's Roamers uses for an injected random.
local function rand(rng, n)
  if type(rng) == "function" then return rng(n) end
  if love and love.math and love.math.random then return love.math.random(n) - 1 end
  return math.random(n) - 1
end

--- The roster slot `index` when that beast is still out there and standing on `mapId`, else nil.
function Roam.onMap(save, index, mapId, deps)
  if index == nil or mapId == nil then return nil end
  local E = engine(deps)
  local list = roster(save, E)
  local slot = type(list) == "table" and list[index] or nil
  if active(slot, E) and slot.map == mapId then return slot end
  return nil
end

--- CheckEncounterRoamMon's roll, for one visible spawn on `mapId`. Returns { index, species, level, dvs } or nil.
-- One random byte, three gates, exactly as the engine rolls a step: below 100 of 256, then the low two bits pick
-- slot 1-3 (0 = no beast), and that beast must be on this map. About 1 spawn in 10 per beast on its route.
-- `kind` "water" never rolls (the game refuses while surfing). `taken[index]` skips a beast that is already
-- visible, so the same individual is never on screen twice.
function Roam.pickForSpawn(save, mapId, kind, rng, taken, deps)
  if mapId == nil or kind == "water" or kind == "fishing" then return nil end
  local E = engine(deps)
  local list = roster(save, E)
  if type(list) ~= "table" then return nil end
  local value = rand(rng, 256)
  if value >= 100 then return nil end
  local index = value % 4
  if index == 0 then return nil end
  if taken and taken[index] then return nil end
  local slot = list[index]
  if not (active(slot, E) and slot.map == mapId) then return nil end
  local level = tonumber(slot.level) or (E and tonumber(E.LEVEL)) or 40
  -- DVs are only rolled at the first meeting (hp 0 = never met); before that the beast has none yet.
  local dvs = ((tonumber(slot.hp) or 0) > 0) and slot.dvs or nil
  return { index = index, species = slot.species, level = level, dvs = dvs }
end

--- Start the engine's own roaming battle with beast `index` on the live Gold World `world`.
-- Returns true, or nil plus a reason (the beast has moved on, no engine roamers, no world).
function Roam.startBattle(game, world, index, deps)
  local E = engine(deps)
  if not (E and type(E.beginBattle) == "function") then return nil, "engine roamers unavailable" end
  if not (world and type(world.startBattle) == "function") then return nil, "no world" end
  local save = game and game.save
  local mapId = world.map and world.map.id
  if not Roam.onMap(save, index, mapId, deps) then return nil, "roamer is not on this map" end
  local beast = E.beginBattle(save, index, game.data)
  if not beast then return nil, "could not build roamer" end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[beast.species] = true
  world:startBattle({ wild = beast, roaming = index })
  return true
end

--- Put `shouldBlock(save, mapId, onWater, random)` in front of the engine's Roamers.checkEncounter; when it returns
-- true, no beast is rolled on that step. The wrapper is installed once per process (engine modules outlive a mod
-- reload) and reads the CURRENT gate from the module, so a reloaded mod just replaces it. Returns a function that
-- removes this gate, or nil plus a reason.
function Roam.installStepGate(shouldBlock, deps)
  local E = engine(deps)
  if not (E and type(E.checkEncounter) == "function") then return nil, "engine roamers unavailable" end
  if type(shouldBlock) ~= "function" then return nil, "gate must be a function" end
  if not E._wildsStepGateInstalled then
    local original = E.checkEncounter
    E._wildsOriginalCheckEncounter = original
    E.checkEncounter = function(...)
      local gate = E._wildsStepGate
      if type(gate) == "function" then
        local ok, block = pcall(gate, ...)
        if ok and block == true then return nil end
      end
      return E._wildsOriginalCheckEncounter(...)
    end
    E._wildsStepGateInstalled = true
  end
  E._wildsStepGate = shouldBlock
  return function()
    if E._wildsStepGate == shouldBlock then E._wildsStepGate = nil end
  end
end

return Roam
