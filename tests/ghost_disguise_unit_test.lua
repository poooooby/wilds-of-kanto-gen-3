-- Pokemon Tower ghosts (Gen 1): the Silph Scope rule, the ghost battle a masked spawn starts, and the TOWER_GHOST sprite every
-- style shows for it. (The Poke Ball dodge lives in tests/overworld_catch_ghost_dodge_unit_test.lua.)
-- Run: lua tests/ghost_disguise_unit_test.lua
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
local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end

local engine = { version = "red", generation = 1 }
package.loaded["src.core.GameVersion"] = {
  get = function() return engine.version end,
  isYellow = function() return engine.version == "yellow" end,
  isGold = function() return engine.version == "gold" end,
  generation = function() return engine.generation end,
}

local modules = {}
local savedOpts = { sprite_style = "pokemmo" }
local mod = {
  id = "wilds_of_kanto_gen3", path = ".",
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k) return savedOpts[k] end },
  find = function() return nil end,
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
  assets = { path = function(_, rel) return rel end },
  content = { pokemon = { get = function() return nil end, each = function() return function() end end }, sprites = { get = function() return nil end } },
}
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local Ghost = V.require("ghost_disguise")
local GameCompat = V.require("game_compat")

-- ------------------------------------------------------------------ the rule, with and without the engine's own Map
local function tower(id) return { id = id or "POKEMON_TOWER_3F" } end
local function gameWith(inv) return { save = { inventory = inv } } end

local function ruleSuite(label)
  check(Ghost.masked(gameWith({}), tower()), label .. ": Tower, no scope: masked")
  check(Ghost.masked(gameWith({ POTION = 3 }), tower("POKEMON_TOWER_7F")), label .. ": Tower 7F, other items only: masked")
  check(not Ghost.masked(gameWith({ SILPH_SCOPE = 1 }), tower()), label .. ": Tower with the Silph Scope: not masked")
  check(not Ghost.masked(gameWith({}), { id = "ROUTE_1" }), label .. ": another map: not masked")
  check(not Ghost.masked(gameWith({}), { id = "MT_MOON_1F" }), label .. ": another cave: not masked")
  check(not Ghost.masked(gameWith({}), nil), label .. ": no map def: not masked")
  check(Ghost.masked({}, tower()), label .. ": no save / inventory at all: masked (nothing to pass the check)")
  for _, f in ipairs({ "1F", "2F", "3F", "4F", "5F", "6F", "7F" }) do
    check(Ghost.masked(gameWith({}), tower("POKEMON_TOWER_" .. f)), label .. ": " .. f .. " is masked")
  end
  -- a map def that names its own rule
  local custom = { id = "SOME_MAP", ghostBattles = { unlessItem = "OTHER_ITEM" } }
  check(Ghost.masked(gameWith({ SILPH_SCOPE = 1 }), custom), label .. ": a def-level rule names its own item")
  check(not Ghost.masked(gameWith({ OTHER_ITEM = 1 }), custom), label .. ": and that item unmasks it")
  check(Ghost.masked(gameWith({ SILPH_SCOPE = 1 }), { id = "X", ghostBattles = {} }), label .. ": a rule with no item is always masked")
  check(not Ghost.masked(gameWith({}), { id = "POKEMON_TOWER_3F", ghostBattles = false }), label .. ": a def can switch the rule off")
end
package.loaded["src.world.Map"] = nil
ruleSuite("fallback rule")
package.loaded["src.world.Map"] = { -- the engine's Map.ghostBattles (src/world/Map.lua)
  ghostBattles = function(def)
    if def.ghostBattles ~= nil then return def.ghostBattles end
    if def.id:find("POKEMON_TOWER", 1, true) == 1 then return { unlessItem = "SILPH_SCOPE" } end
    return nil
  end,
}
ruleSuite("engine rule")
package.loaded["src.world.Map"] = { ghostBattles = function() error("boom") end }
check(Ghost.masked(gameWith({}), tower()), "a throwing engine rule falls back to the prefix rule")
package.loaded["src.world.Map"] = nil

-- ------------------------------------------------------------------ the adapter seam
local red = { save = { inventory = {} } }
check(GameCompat.wildGhostMasked(red, tower()), "Red/Blue/Yellow adapter: masked in the Tower without the scope")
red.save.inventory.SILPH_SCOPE = 1
check(not GameCompat.wildGhostMasked(red, tower()), "and unmasked the moment the scope is in the bag")
engine.version, engine.generation = "gold", 2
check(not GameCompat.wildGhostMasked({ save = { inventory = {} } }, tower()), "Gold has no Silph Scope: never masked")
local nilBattle, nilWhy = GameCompat.startGhostBattle({}, {}, "GASTLY", 20, "POKEMON_TOWER_3F")
eq(nilBattle, nil, "Gold has no ghost battle path")
check(type(nilWhy) == "string", "with a reason")
engine.version, engine.generation = "red", 1

-- ------------------------------------------------------------------ the ghost battle
local function fakeBattleState(opts)
  opts = opts or {}
  return {
    newWild = function(game, species, level)
      if opts.newWildError then error("newWild exploded") end
      local battle = { species = species, level = level }
      if not opts.noMakeGhost then
        battle.makeGhost = function(self)
          if opts.makeGhostError then error("makeGhost exploded") end
          if not opts.ghostNotSet then self.ghost = true end
        end
      end
      return battle
    end,
  }
end
local function ghostOw()
  local ow = { map = { id = "POKEMON_TOWER_3F" }, pushed = nil, after = nil }
  ow.pushBattle = function(self, b) self.pushed = b end
  ow.afterBattle = function(self, result, b) self.after = { result = result, battle = b } end
  return ow
end

package.loaded["src.battle.BattleState"] = fakeBattleState()
local ow = ghostOw()
local ok, battle = GameCompat.startGhostBattle(red, ow, "GASTLY", 20, "POKEMON_TOWER_3F")
eq(ok, true, "a ghost battle starts")
check(battle and battle.ghost == true, "it is the engine's ghost battle (makeGhost ran)")
eq(battle and battle.species, "GASTLY", "with the spawn's real species (the engine disguises it)")
eq(battle and battle.level, 20, "and its level")
eq(ow.pushed, battle, "pushed through the overworld like the engine's own step encounter")
eq(battle.checkpointOrigin and battle.checkpointOrigin.kind, "wild_encounter", "checkpointed as a wild encounter")
eq(battle.checkpointOrigin and battle.checkpointOrigin.map, "POKEMON_TOWER_3F", "on the Tower map")
battle.onFinish("win")
check(ow.after and ow.after.result == "win" and ow.after.battle == battle, "finishing hands the result to ow:afterBattle")

-- no overworld push: the game stack
package.loaded["src.battle.BattleState"] = fakeBattleState()
local stackGame = { save = { inventory = {} }, stack = { pushed = nil, push = function(self, b) self.pushed = b end } }
ok, battle = GameCompat.startGhostBattle(stackGame, { map = { id = "POKEMON_TOWER_2F" } }, "HAUNTER", 25, "POKEMON_TOWER_2F")
check(ok == true and stackGame.stack.pushed == battle, "without ow:pushBattle the battle goes on the game stack")

-- failures never fall back to a normal battle
local function failing(opts, expect, label)
  package.loaded["src.battle.BattleState"] = fakeBattleState(opts)
  local o, err = GameCompat.startGhostBattle(red, ghostOw(), "GASTLY", 20, "POKEMON_TOWER_3F")
  eq(o, nil, label .. ": reports failure")
  check(tostring(err):find(expect, 1, true) ~= nil, label .. ": reason mentions '" .. expect .. "' (got " .. tostring(err) .. ")")
end
failing({ newWildError = true }, "newWild failed", "newWild throws")
failing({ noMakeGhost = true }, "makeGhost unavailable", "no makeGhost")
failing({ makeGhostError = true }, "makeGhost failed", "makeGhost throws")
failing({ ghostNotSet = true }, "did not mark", "makeGhost leaves the battle un-ghosted")
package.loaded["src.battle.BattleState"] = nil
local noEngine, noEngineWhy = GameCompat.startGhostBattle(red, ghostOw(), "GASTLY", 20, "POKEMON_TOWER_3F")
check(noEngine == nil and tostring(noEngineWhy):find("unavailable", 1, true) ~= nil, "no BattleState: fails, no fallback")
package.loaded["src.battle.BattleState"] = fakeBattleState()
local nowhere, nowhereWhy = GameCompat.startGhostBattle({ save = {} }, { map = {} }, "GASTLY", 20, "POKEMON_TOWER_3F")
check(nowhere == nil and tostring(nowhereWhy):find("no battle push path", 1, true) ~= nil, "nowhere to push: fails")
package.loaded["src.battle.BattleState"] = nil

-- ------------------------------------------------------------------ the sprite
local TS = "assets/wilds_generated/true_size/hgss/"
local RT = "assets/wilds_generated/followsprites_runtime/"
check(fileExists("assets/enhanced_overworld/followsprites/TOWER_GHOST.png"), "the TOWER_GHOST source art is in the repo")
check(fileExists(RT .. "60100-normal.png") and fileExists(TS .. "60100-normal.png"), "the ghost is baked as a flat runtime sheet and a True Size pack")
local manifest = assert(V.require("json_decode").decode(assert(mod.read(nil, RT .. "manifest.json"))))
local entry = manifest.sheets["60100:normal"]
check(entry and entry.path == RT .. "60100-normal.png", "and is in the runtime manifest")
eq(Ghost.ASSET_ID, 60100, "runtime asset id")
eq(Ghost.FORM, "TOWER_GHOST", "form key")

local SG = V.require("species_geometry")
engine.version, engine.generation = "gold", 2 -- the geometry cap only needs to admit the id, not the species
eq(SG.normalizeDex(60100, nil), 60100, "geometry accepts the ghost id")
check(SG.packGeometry(60100, "pokemmo", mod) ~= nil, "True Size geometry exists for the ghost")
eq(SG.displayScale(60100, "pokemmo"), 1, "the ghost keeps scale 1")
engine.version, engine.generation = "red", 1

package.preload["src.render.Assets"] = function() return { exists = function() return false end } end
modules.config = {
  DEFAULTS = { sprite_style = "followers", use_animated_overworld_sprites = true, grass_occlusion_px = 6, min_sprite_size = 16 },
  dynScaleEnabled = function() return true end,
  spriteStyle = function() return savedOpts.sprite_style end,
  spriteTrueColor = function() return true end,
  landArtUsesLuminance = function() return false end,
  waterDisplayMode = function() return "swimming_sprites" end,
  peekSavedOption = function(_, key)
    if savedOpts[key] ~= nil then return savedOpts[key], true end
    return nil, false
  end,
  usesTrueSize = function() return false end,
  pokemonSizeMode = function() return "classic" end,
  pokemonSize = function() return "classic" end,
  get = function(_, key) return savedOpts[key] end,
}
modules.debug_log = { info = function() end, warn = function() end, error = function() end, debug = function() end }
modules.tile = { CELL = 16, WIDTH = 16, HEIGHT = 16, size = function() return 16, 16 end }
modules.json_decode = V.require("json_decode")
modules.animated_sprites = assert(loadfile("lib/animated_sprites.lua"))(V)
modules.runtime_sheets = assert(loadfile("lib/runtime_sheets.lua"))(V)
local render = {
  runtimeSheets = modules.runtime_sheets.new(mod),
  registrationInfo = {},
  _modAssetPath = function(_, rel) return "mods/wilds/" .. rel end,
  _fallbackPath = function() return "assets/fallback/pokemon_missing.png" end,
  resolveAsset = function(_, species) return { path = "assets/pokemon/" .. tostring(species) .. ".png", source = "battle_front" } end,
}
check(render.runtimeSheets:load() == true, "runtime sheets load")
local providers = assert(loadfile("lib/sprite_providers.lua"))(V).new(mod, render)
local game = { data = { pokemon = { GASTLY = { dex = 92 }, HAUNTER = { dex = 93 }, PIDGEY = { dex = 16 } } } }

local function image(style, species, variant, form)
  local r = providers:resolve(style, species, variant, game, form)
  return r and r.def and tostring(r.def.image) or nil, r
end
for _, style in ipairs({ "pokemmo", "followers" }) do
  local img, r = image(style, "GASTLY", "normal", "TOWER_GHOST")
  check(img and img:find("60100-normal.png", 1, true), style .. " style: a masked Gastly is drawn as the ghost (" .. tostring(img) .. ")")
  check(r and r.providerId == "pokemmo", style .. " style: served by the HGSS/PokeMMO provider that owns the sheet")
  img = image(style, "HAUNTER", "shiny", "TOWER_GHOST")
  check(img and img:find("60100-normal.png", 1, true), style .. " style: a shiny disguise falls back to the one ghost sheet")
  img = image(style, "PIDGEY", "normal", "TOWER_GHOST")
  check(img and img:find("60100-normal.png", 1, true), style .. " style: the disguise does not depend on the species")
end
local plain = image("pokemmo", "GASTLY", "normal", nil)
check(plain and plain:find("092-normal.png", 1, true) and not plain:find("60100", 1, true), "without the disguise Gastly is Gastly (unmasked / with the scope)")
local gsc = image("followers", "GASTLY", "normal", nil)
check(gsc and gsc:find("follower_092", 1, true), "and the GSC style keeps its own art for it")
local unown = image("pokemmo", "UNOWN", "normal", 6)
game.data.pokemon.UNOWN = { dex = 201 }
unown = image("pokemmo", "UNOWN", "normal", 6)
check(unown and unown:find("60006-normal.png", 1, true), "Unown's letter forms still resolve beside the ghost")

-- SpriteResolver hands the string form through (and only that string)
local recorded
local fakeProviders = {
  resolve = function(_, style, species, variant, gameArg, form)
    recorded = { form = form }
    return { def = { image = "x.png", frames = 6, walker = true }, meta = {}, providerId = "pokemmo", steps = {} }
  end,
}
modules.surface = { GRASS = "GRASS", CAVE = "CAVE", WATER = "WATER", INTERIOR = "INTERIOR", OTHER = "OTHER_ENCOUNTER" }
modules.surface_state = { forEntity = function() return "land" end, isWaterEntity = function() return false end }
local okR, Resolver = pcall(function() return assert(loadfile("lib/sprite_resolver.lua"))(V) end)
if okR and Resolver and Resolver.new then
  local resolver = Resolver.new(mod, fakeProviders, nil)
  resolver:resolveLandSprite({ species = "GASTLY", spriteForm = "TOWER_GHOST" }, { style = "followers", game = game })
  eq(recorded and recorded.form, "TOWER_GHOST", "SpriteResolver passes the ghost form to the provider chain")
  resolver:resolveLandSprite({ species = "UNOWN", spriteForm = 4 }, { style = "pokemmo", game = game })
  eq(recorded and recorded.form, 4, "Unown's numeric form still goes through as a number")
  resolver:resolveLandSprite({ species = "GASTLY", spriteForm = "female" }, { style = "pokemmo", game = game })
  eq(recorded and recorded.form, nil, "a gender word is not mistaken for a form")
  local a = resolver:cacheKey({ species = "GASTLY", spriteForm = "TOWER_GHOST" }, { style = "pokemmo", game = game }, "land")
  local b = resolver:cacheKey({ species = "GASTLY" }, { style = "pokemmo", game = game }, "land")
  check(a ~= b, "the ghost and the real Gastly never share a cached SpriteDef")
else
  print("skip: sprite_resolver needs more of the engine than this harness stubs (" .. tostring(Resolver) .. ")")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("ghost_disguise_unit_test: all passed")
