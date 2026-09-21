-- Pokemon Tower ghosts: an overworld Poke Ball thrown at a wild Pokemon there is DODGED (vanilla ItemUseBall can't-be-caught
-- text, ball spent, no catch attempt) until the player has the Silph Scope. Fixture copied from overworld_catch_easter_unit_test.
-- Run: lua tests/overworld_catch_ghost_dodge_unit_test.lua
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

local catchAttempts = 0
package.preload["src.inventory.Bag"] = function()
  return {
    remove = function(save, id, qty)
      local n = (save.inventory[id] or 0) - (qty or 1)
      if n <= 0 then save.inventory[id] = nil else save.inventory[id] = n end
    end,
  }
end
package.preload["src.battle.Catching"] = function()
  return {
    attempt = function() catchAttempts = catchAttempts + 1 return true, 3 end,
  }
end
package.preload["src.render.TextBox"] = function()
  return {
    new = function(game, msg, onDone)
      game._lastText = msg
      game._textCount = (game._textCount or 0) + 1
      return { msg = msg, onDone = onDone, isOpaque = true }
    end,
  }
end
package.preload["src.render.Pipelines"] = function()
  return { setLevel = function() end, rows = function() return {} end }
end

local optionStore = {
  enabled = true, overworld_catching = true, wilds_ai = true, dev_overlay = false,
}
local game = {
  save = {
    inventory = { POKE_BALL = 20, GREAT_BALL = 0, ULTRA_BALL = 0, MASTER_BALL = 0 },
    party = {},
    options = { modOptions = { overworld_wild_spawns = optionStore } },
  },
  mods = { modOptions = { overworld_wild_spawns = optionStore } },
  data = { pokemon = { PIDGEY = { name = "PIDGEY", catchRate = 255 } } },
  audio = { playSfx = function() end },
  _textCount = 0,
}
game.stack = {
  _top = nil,
  top = function(self) return self._top end,
  push = function(self, box)
    self._top = box
    if box and box.msg then
      local cb = box.onDone
      self._top = game._ow
      if cb then cb() end
    end
  end,
}

local modules = {}
local V = {
  mod = {
    id = "overworld_wild_spawns",
    path = ".",
    log = { info = function() end, warn = function() end },
    options = {
      get = function(_, k)
        if optionStore[k] ~= nil then return optionStore[k] end
        return nil
      end,
    },
    world = { game = game, overworld = function() return game._ow end },
    assets = { path = function(_, rel) return rel end },
    content = {
      sprites = {
        _defs = {},
        get = function(self, id) return self._defs[id] end,
        register = function(self, id, def) self._defs[id] = def end,
      },
      render_pipelines = { register = function() end },
    },
    ui = {},
  },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end
modules.debug_log = { warn = function() end, info = function() end, error = function() end }
modules.tile = { CELL = 16 }
modules.spawn_regions = {}
modules.cell_occupancy = {
  ownerKey = function() return nil end,
  isFollowerEntity = function() return false end,
  isBlockingEntity = function() return true end,
}
modules.surface = { WATER = "WATER", GRASS = "GRASS", CAVE = "CAVE", BEHAVIORS = {} }
modules.safari_compat = {
  STATUS = { INACTIVE = "INACTIVE", ACTIVE = "ACTIVE", FALLBACK_VANILLA = "FALLBACK_VANILLA" },
  LAND_WEIGHTS = { SAFARI_IDLE = 35, SAFARI_WANDER = 40, SAFARI_FLEE = 25 },
  status = function() return "INACTIVE" end,
  isSafariMap = function() return false end,
}
modules.movement = {
  stop = function() end,
  setFacing = function(e, f) e.facing = f end,
  init = function() end,
  STATE = { ALERT = "ALERT", IDLE = "IDLE", CATCHING = "CATCHING" },
}

local Config = V.require("config")
modules.config = Config
local Behavior = V.require("behavior")
modules.behavior = Behavior
local OverworldCatching = V.require("catching/init")
local Target = OverworldCatching.Target
local Hit = Target.HitKind

local logic = {
  entities = {},
  spawns = {},
  pendingBattle = nil,
  voxel = { unregister = function() end },
  occupancy = { releaseEntity = function() end },
  _despawn = function() end,
  _detachFromWorld = function(_, e) e.registeredInWorld = false end,
  _attach = function(_, e) e.registeredInWorld = true end,
  _onAggressiveAlert = function() end,
}
local catching = OverworldCatching.new(V.mod, logic)
logic.catching = catching
catching:registerContent()

local ow = {
  player = { cellX = 5, cellY = 5, facing = "right" },
  entities = {},
  npcs = {},
  map = { id = "PALLET_TOWN" },
  runner = { isRunning = function() return false end },
}
game._ow = ow
game.stack._top = ow

-- Legacy fixture (top-level index) — still supported.
local function placeHuman(x, y, id)
  local npc = {
    id = id or "npc_1",
    index = 12,
    cellX = x, cellY = y,
    facing = "down",
    sprite = { def = { walker = true } },
    name = "YOUNGSTER",
    trainer = true,
  }
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
  return npc
end

-- Canonical Gen1Recomp NPC shape: index/trainer live on entity.def only
-- (see src/world/NPC.lua — NPC.new does NOT copy objDef.index to self.index).
local function placeNativePerson(x, y, opts)
  opts = opts or {}
  local index = opts.index or 3
  local npc = {
    id = opts.id or ("PALLET_TOWN_obj_" .. tostring(index)),
    def = {
      index = index,
      x = x,
      y = y,
      sprite = opts.spriteId or "SPRITE_GIRL",
      movement = opts.movement or "STAY",
      range = opts.range or "DOWN",
      text = opts.text or "TEXT_PALLETTOWN_GIRL",
      name = opts.name or "GIRL",
      trainerClass = opts.trainerClass,
      trainerParty = opts.trainerParty,
      item = opts.item,
      pokemon = opts.pokemon,
      pushable = opts.pushable,
    },
    cellX = x,
    cellY = y,
    facing = opts.facing or "down",
    sprite = { def = { walker = true, frames = 6 } },
    wanders = false,
  }
  if opts.trainerClass then
    -- Native trainers also only expose trainerClass on def, not entity.
  end
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
  return npc
end

local function placeTown(x, y, id)
  local mon = {
    id = id or "town_1",
    cellX = x, cellY = y,
    facing = "left",
    sprite = {},
    wildsAmbientPokemon = true,
    ambientSpecies = "MEOWTH",
    overworldWildSpawn = false,
    visibleSprite = true,
  }
  table.insert(ow.entities, mon)
  return mon
end

local function placeWild(x, y, id)
  local ent = {
    id = id or "wild_1",
    cellX = x, cellY = y,
    species = "PIDGEY",
    level = 5,
    facing = "left",
    overworldWildSpawn = true,
    visibleSprite = true,
    canTriggerBattle = true,
    state = "available",
    behavior = Behavior.GRASS_WANDER,
  }
  Behavior.attach(ent, Behavior.GRASS_WANDER, nil, function() return 1 end)
  logic.entities[ent.id] = ent
  logic.spawns[ent.id] = {
    id = ent.id, mapId = "PALLET_TOWN", x = x, y = y,
    species = "PIDGEY", level = 5, state = Config.STATE.AVAILABLE,
    behavior = Behavior.GRASS_WANDER,
  }
  table.insert(ow.entities, ent)
  return ent
end

local function finishFlight()
  for _ = 1, 120 do
    catching.projectile:update(game, ow, 0.05, logic.voxel)
    if catching.phase == "idle" and not catching.projectile:isBusy() then break end
  end
end


-- ------------------------------------------------------------------ the Tower
local function setMap(id) ow.map = { id = id, def = { id = id } } end
local function throwAtWildAhead(map, hasScope)
  setMap(map)
  if hasScope then game.save.inventory.SILPH_SCOPE = 1 else game.save.inventory.SILPH_SCOPE = nil end
  ow.npcs, ow.entities, logic.entities, logic.spawns = {}, {}, {}, {}
  local wild = placeWild(8, 5, "wild_ahead") -- distance 3
  game._lastText, game._textCount = nil, 0
  catchAttempts = 0
  local before = catching:ballCount(game, "POKE_BALL")
  catching.meter.active = true
  catching.meter.power = 3
  catching.phase = "metering"
  catching:_releaseThrow(game, ow)
  local phaseAfterRelease = catching.phase
  finishFlight()
  return wild, before, phaseAfterRelease
end

-- No scope in the Tower: dodged.
local wild, before, phase = throwAtWildAhead("POKEMON_TOWER_3F", false)
eq(phase, "flying", "tower, no scope: the ball still flies at the ghost")
check(type(game._lastText) == "string" and game._lastText:find("dodged the", 1, true) ~= nil,
  "tower, no scope: the vanilla \"It dodged the thrown BALL!\" text is shown (got " .. tostring(game._lastText) .. ")")
check(game._lastText and game._lastText:find("can't be caught", 1, true) ~= nil, "tower, no scope: 'can't be caught' page included")
check(game._lastText and not game._lastText:find("{PROMPT}", 1, true), "the ROM prompt token is not printed")
eq(catchAttempts, 0, "tower, no scope: no catch attempt is ever made")
eq(catching:ballCount(game, "POKE_BALL"), before - 1, "tower, no scope: the ball is spent, as in the game")
check(not catching.projectile:isBusy(), "tower, no scope: the ball is cleaned up")
eq(catching.phase, "idle", "tower, no scope: back to idle")
check(wild.wildsCatchLocked ~= true and wild.wildsCatchPending ~= true and wild.wildsCatchState == nil,
  "tower, no scope: the ghost is not frozen, locked or captured")
check(logic.entities["wild_ahead"] == wild, "tower, no scope: the ghost is still on the map")
check(wild.visibleSprite == true, "tower, no scope: the ghost stays visible")

-- Every tower floor.
for _, floor in ipairs({ "POKEMON_TOWER_1F", "POKEMON_TOWER_2F", "POKEMON_TOWER_4F", "POKEMON_TOWER_7F" }) do
  local _, b = throwAtWildAhead(floor, false)
  check(game._lastText and game._lastText:find("dodged the", 1, true) ~= nil and catchAttempts == 0, floor .. ": dodged")
end

-- With the scope: a normal throw (a catch attempt happens, no dodge text).
wild, before = throwAtWildAhead("POKEMON_TOWER_3F", true)
check(catchAttempts >= 1, "tower, WITH the scope: a normal catch attempt runs (" .. catchAttempts .. ")")
check(not (game._lastText and game._lastText:find("dodged the", 1, true)), "tower, with the scope: no dodge text")

-- Any other map: unchanged.
wild, before = throwAtWildAhead("ROUTE_1", false)
check(catchAttempts >= 1, "other map, no scope: a normal catch attempt runs")
check(not (game._lastText and game._lastText:find("dodged the", 1, true)), "other map: no dodge text")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("overworld_catch_ghost_dodge_unit_test: all passed")
