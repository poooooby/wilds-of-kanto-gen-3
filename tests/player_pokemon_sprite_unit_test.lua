-- Control Mode = Pokemon on Red/Blue/Yellow: the player's Pokemon sprite must be built from the resolver's
-- full geometry-carrying def (True Size frame size / anchor, animation, presentation flags), like followers,
-- not a bare 16x16 def (which drew half sprites for HGSS / PokeMMO sheets).
-- Run: lua tests/player_pokemon_sprite_unit_test.lua
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

-- A Red/Blue game (generation 1).
package.loaded["src.core.GameVersion"] = {
  get = function() return "red" end,
  isYellow = function() return false end,
  isGold = function() return false end,
  generation = function() return 1 end,
}

-- SpriteRenderer stand-in: records the def it is built from and exposes draw / resolveImage like the real one.
local built = {}
package.loaded["src.render.SpriteRenderer"] = {
  new = function(def, id)
    local sprite = {
      def = def, id = id, image = { stub = true },
      frameWidth = tonumber(def.frameWidth) or 16, frameHeight = tonumber(def.frameHeight) or 16,
      anchorX = tonumber(def.anchorX) or 8, anchorY = tonumber(def.anchorY) or 16,
      frames = {},
    }
    function sprite:draw() end
    function sprite:resolveImage() return self.image end
    built[#built + 1] = sprite
    return sprite
  end,
}

local optionStore = { follow_control = "pokemon", follower_count = 0, sprite_style = "pokemmo", trainer_trail = false }
local modules = {}
local V = {
  mod = {
    path = ".", id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    options = { get = function(_, k) return optionStore[k] end, set = function(_, k, v) optionStore[k] = v end },
    events = { on = function() return function() end end },
    hooks = { wrap = function() return function() end end },
    world = { game = nil },
  },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local ControlEngine = V.require("follower/control_engine")

-- The resolver output for a True Size (HGSS / PokeMMO) species: 32x32 frames, custom anchor, animation, flags.
local TRUE_SIZE = {
  image = "mods/wilds/assets/wilds_generated/true_size/016-normal.png",
  id = "SPRITE_PLAYER_POKEMON", frames = 6, walker = true, trueColor = true,
  frameWidth = 32, frameHeight = 32, anchorX = 16, anchorY = 28,
  idleFrameCount = 2, idleDurations = { 0.4, 0.4 },
  walkFrameCount = 4, walkDurations = { 0.15, 0.15, 0.15, 0.15 }, walkCycleBase = 2,
  disableVerticalStepFlip = true, forceRawTrueColor = true,
  assetId = 16, dex = 16,
}
-- The resolver output for the classic 16x16 Followers style: no geometry, no flags.
local CLASSIC = {
  image = "mods/wilds/assets/wilds_generated/followsprites_runtime/016-normal.png",
  id = "SPRITE_PLAYER_POKEMON", frames = 6, walker = true, trueColor = true,
  assetId = 16, dex = 16,
}

local function newRig(resolved, mon)
  built = {}
  local player = { surfing = false }
  local ow = { player = player }
  local game = {
    data = { pokemon = { PIDGEY = { name = "PIDGEY", dex = 16 } } },
    save = { party = { mon }, followerPartyIndex = 1 },
  }
  V.mod.world = { game = game }
  V.mod.game = game
  local engine = ControlEngine.new(V.mod, {
    selection = { getActiveFollowerMon = function() return mon end },
  })
  engine._gameRef = game
  engine.getLeaderMon = function() return mon end
  engine.resolveFollowerSprite = function() return resolved end
  return engine, game, ow, player
end

local pidgey = { species = "PIDGEY", level = 5, hp = 20, dvs = { attack = 1, defense = 1, speed = 1, special = 1 } }

-- ------------------------------------------------------------ True Size keeps its geometry and flags
do
  local engine, game, ow, player = newRig(TRUE_SIZE, pidgey)
  engine:applyPlayerAsPokemon(game, ow, true)
  eq(#built, 1, "True Size: one sprite built")
  local def = built[1] and built[1].def or {}
  eq(def.id, "SPRITE_PLAYER_POKEMON", "True Size: id stays SPRITE_PLAYER_POKEMON")
  eq(def.image, TRUE_SIZE.image, "True Size: image")
  eq(def.frameWidth, 32, "True Size: frameWidth (a bare def made this 16)")
  eq(def.frameHeight, 32, "True Size: frameHeight")
  eq(def.anchorX, 16, "True Size: anchorX")
  eq(def.anchorY, 28, "True Size: anchorY")
  eq(def.idleFrameCount, 2, "True Size: idleFrameCount")
  eq(def.walkFrameCount, 4, "True Size: walkFrameCount")
  eq(def.walkCycleBase, 2, "True Size: walkCycleBase")
  check(def.idleDurations and def.walkDurations and #def.walkDurations == 4, "True Size: animation durations")
  eq(def.disableVerticalStepFlip, true, "True Size: disableVerticalStepFlip")
  eq(def.forceRawTrueColor, true, "True Size: forceRawTrueColor")
  eq(def.frames, 6, "True Size: frames")
  eq(def.walker, true, "True Size: walker")
  eq(def.trueColor, true, "True Size: trueColor")
  eq(def.pokepcShiny, false, "True Size: not shiny")
  eq(player.sprite, built[1], "True Size: the player now wears it")
  eq(player._pokepcAsPokemon, true, "True Size: control-as-Pokemon marker set")
  eq(player._pokepcControlSpecies, "PIDGEY", "True Size: species recorded")
  eq(built[1].frameWidth, 32, "True Size: the renderer really uses 32x32 frames")
  check(built[1]._wildsPresWrapped == true, "True Size: presentation wrap attached (no vertical step flip / raw blit)")
end

-- ------------------------------------------------------------ classic 16x16 stays plain
do
  local engine, game, ow, player = newRig(CLASSIC, pidgey)
  engine:applyPlayerAsPokemon(game, ow, true)
  local def = built[1] and built[1].def or {}
  eq(#built, 1, "Classic: one sprite built")
  eq(def.id, "SPRITE_PLAYER_POKEMON", "Classic: id")
  eq(def.frameWidth, nil, "Classic: no custom frameWidth")
  eq(def.anchorX, nil, "Classic: no custom anchor")
  eq(def.frames, 6, "Classic: frames")
  eq(def.walker, true, "Classic: walker")
  check(built[1]._wildsPresWrapped == nil, "Classic: no presentation wrap needed")
end

-- ------------------------------------------------------------ shiny
do
  local shiny = { species = "PIDGEY", level = 5, hp = 20, shiny = true, dvs = { attack = 15, defense = 10, speed = 10, special = 10 } }
  local engine, game, ow = newRig(TRUE_SIZE, shiny)
  engine:applyPlayerAsPokemon(game, ow, true)
  eq(built[1] and built[1].def.pokepcShiny, true, "Shiny: pokepcShiny rides on the def")
end

-- ------------------------------------------------------------ unchanged inputs do not rebuild
do
  local engine, game, ow, player = newRig(TRUE_SIZE, pidgey)
  engine:applyPlayerAsPokemon(game, ow, true)
  engine:applyPlayerAsPokemon(game, ow)
  eq(#built, 1, "Unchanged species / style / image: no rebuild")
  engine:applyPlayerAsPokemon(game, ow, true)
  eq(#built, 2, "force rebuilds")
end

-- ------------------------------------------------------------ surfing never applies the Pokemon sprite
do
  local engine, game, ow, player = newRig(TRUE_SIZE, pidgey)
  player.surfing = true
  engine:applyPlayerAsPokemon(game, ow, true)
  eq(player._pokepcAsPokemon, nil, "Surfing: player is not switched to the Pokemon sprite")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
