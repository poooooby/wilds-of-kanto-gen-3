-- Gen 1 adapter for Wilds game compatibility.
--
-- Thin wrappers around the current Red / Blue / Yellow logic. Do not change
-- semantics here — future generations get their own adapter.
local V = ...

local Gen1 = {}
Gen1.supported = true
Gen1.generation = 1
-- National Dex cap for Gen1-only consumers (True Size, etc.). Shared
-- GameCompat.speciesId does not apply this cap. This is the TRUE vanilla
-- Gen1 count (151) -- a static baseline, not a ceiling: SpeciesGeometry's
-- activeMaxSpecies() live-scans game.data.pokemon and raises the effective
-- cap when an expansion mod (Kanto Reforged and others) actually registers
-- more, so this constant never needs bumping by hand for a specific mod.
Gen1.MAX_SPECIES = 151

Gen1.capabilities = {
  core = true,
  species = true,
  party = true,
  surf = true,
  encounters = true,
  followers = true,
  ambient = true,
  townPokemon = true,
  safari = true,
  healDetect = true,
}

-- Existing Gen1 name → dex fallback (moved from follower/sprite_service.lua).
-- Used only when the engine species resolver cannot resolve a key.
Gen1.SPECIES_TO_DEX = {
  BULBASAUR=1, IVYSAUR=2, VENUSAUR=3, CHARMANDER=4, CHARMELEON=5, CHARIZARD=6,
  SQUIRTLE=7, WARTORTLE=8, BLASTOISE=9, CATERPIE=10, METAPOD=11, BUTTERFREE=12,
  WEEDLE=13, KAKUNA=14, BEEDRILL=15, PIDGEY=16, PIDGEOTTO=17, PIDGEOT=18,
  RATTATA=19, RATICATE=20, SPEAROW=21, FEAROW=22, EKANS=23, ARBOK=24,
  PIKACHU=25, RAICHU=26, SANDSHREW=27, SANDSLASH=28, NIDORAN_F=29, NIDORINA=30,
  NIDOQUEEN=31, NIDORAN_M=32, NIDORINO=33, NIDOKING=34, CLEFAIRY=35, CLEFABLE=36,
  VULPIX=37, NINETALES=38, JIGGLYPUFF=39, WIGGLYTUFF=40, ZUBAT=41, GOLBAT=42,
  ODDISH=43, GLOOM=44, VILEPLUME=45, PARAS=46, PARASECT=47, VENONAT=48,
  VENOMOTH=49, DIGLETT=50, DUGTRIO=51, MEOWTH=52, PERSIAN=53, PSYDUCK=54,
  GOLDUCK=55, MANKEY=56, PRIMEAPE=57, GROWLITHE=58, ARCANINE=59, POLIWAG=60,
  POLIWHIRL=61, POLIWRATH=62, ABRA=63, KADABRA=64, ALAKAZAM=65, MACHOP=66,
  MACHOKE=67, MACHAMP=68, BELLSPROUT=69, WEEPINBELL=70, VICTREEBEL=71, TENTACOOL=72,
  TENTACRUEL=73, GEODUDE=74, GRAVELER=75, GOLEM=76, PONYTA=77, RAPIDASH=78,
  SLOWPOKE=79, SLOWBRO=80, MAGNEMITE=81, MAGNETON=82, FARFETCHD=83, DODUO=84,
  DODRIO=85, SEEL=86, DEWGONG=87, GRIMER=88, MUK=89, SHELLDER=90,
  CLOYSTER=91, GASTLY=92, HAUNTER=93, GENGAR=94, ONIX=95, DROWZEE=96,
  HYPNO=97, KRABBY=98, KINGLER=99, VOLTORB=100, ELECTRODE=101, EXEGGCUTE=102,
  EXEGGUTOR=103, CUBONE=104, MAROWAK=105, HITMONLEE=106, HITMONCHAN=107, LICKITUNG=108,
  KOFFING=109, WEEZING=110, RHYHORN=111, RHYDON=112, CHANSEY=113, TANGELA=114,
  KANGASKHAN=115, HORSEA=116, SEADRA=117, GOLDEEN=118, SEAKING=119, STARYU=120,
  STARMIE=121, MR_MIME=122, SCYTHER=123, JYNX=124, ELECTABUZZ=125, MAGMAR=126,
  PINSIR=127, TAUROS=128, MAGIKARP=129, GYARADOS=130, LAPRAS=131, DITTO=132,
  EEVEE=133, VAPOREON=134, JOLTEON=135, FLAREON=136, PORYGON=137, OMANYTE=138,
  OMASTAR=139, KABUTO=140, KABUTOPS=141, AERODACTYL=142, SNORLAX=143, ARTICUNO=144,
  ZAPDOS=145, MOLTRES=146, DRATINI=147, DRAGONAIR=148, DRAGONITE=149, MEWTWO=150, MEW=151,
}

local function tryVRequire(name)
  local ok, mod = pcall(function() return V.require(name) end)
  if ok then return mod end
  return nil
end

local function tryRequire(path)
  local ok, mod = pcall(require, path)
  if ok then return mod end
  return nil
end

--- Resolve a species key to a numeric id using current Gen1 paths.
-- 1. numeric id → return as-is if a positive integer
-- 2. engine species resolver (AnimatedSprites / game.data / content)
-- 3. existing Gen1 name mapping fallback
function Gen1.speciesId(species, game, mod)
  if species == nil then return nil end
  local n = tonumber(species)
  if n and n >= 1 and math.floor(n) == n then
    return math.floor(n)
  end
  if type(species) ~= "string" and type(species) ~= "number" then
    return nil
  end

  local AnimatedSprites = tryVRequire("animated_sprites")
  if AnimatedSprites and AnimatedSprites.resolveSpeciesId then
    local ok, dex = pcall(AnimatedSprites.resolveSpeciesId, species, game, mod)
    if ok and type(dex) == "number" and dex >= 1 then
      return math.floor(dex)
    end
  end

  if type(species) == "string" and species ~= "" then
    local mapped = Gen1.SPECIES_TO_DEX[species:upper()]
    if mapped then return mapped end
  end
  return nil
end

--- Current Red/Blue/Yellow surf detection (ControlEngine / water-compat).
function Gen1.isSurfing(game, ow)
  ow = ow or (game and game.overworld)
  local player = ow and ow.player
  if not player then return false end
  if player.surfing == true or player.isSurfing == true then return true end
  if player.surface == "water" or player.surface == "WATER" then return true end
  if game and game.player and game.player.surfing == true then return true end
  if ow and ow.map and player.cellX ~= nil and player.cellY ~= nil then
    return Gen1.isWaterCell(ow.map, player.cellX, player.cellY)
  end
  return false
end

function Gen1.isWaterCell(map, x, y)
  if not (map and type(map.isWaterCell) == "function") then return false end
  local ok, water = pcall(map.isWaterCell, map, x, y)
  return ok and water == true
end

function Gen1.party(game)
  if not (game and game.save and type(game.save.party) == "table") then
    return nil
  end
  return game.save.party
end

function Gen1.currentMapId(game, ow)
  ow = ow or (game and game.overworld)
  if ow and ow.map and ow.map.id ~= nil then
    return ow.map.id
  end
  return nil
end

--- Per-map encounter table: game.data.encounters[mapId], with Modern Spawns'
-- generated grass / water tables in place when that mod is active
-- (lib/modern_spawns_bridge.lua). The game's own table is never modified.
function Gen1.encountersForMap(game, mapId)
  if not game or not game.data or type(game.data.encounters) ~= "table" then
    return nil
  end
  return V.require("modern_spawns_bridge").gen1Def(mapId, game.data.encounters[mapId])
end

--- Exact current Gen1 wild battle entry: queue start_battle wild species level.
function Gen1.startWildBattle(world, species, level)
  if not (world and type(world.queueScript) == "function") then
    return nil, "no world"
  end
  return world:queueScript({
    { "start_battle", "wild", species, tonumber(level) or 5 },
  })
end

--- True when a wild Pokemon on `mapDef` is an unidentifiable GHOST right now (the Pokemon Tower without the Silph Scope).
function Gen1.wildGhostMasked(game, mapDef)
  return V.require("ghost_disguise").masked(game, mapDef) == true
end

--- Ghost battle for a visible spawn, built the way the engine's own step encounter builds one
-- (OverworldController: BattleState.newWild, wild_encounter checkpoint, battle:makeGhost, afterBattle on finish) --
-- the scripted start_battle path never calls makeGhost. Never falls back to a normal battle. Returns true, battle | nil, err.
function Gen1.startGhostBattle(game, ow, species, level, mapId)
  local BattleState = tryRequire("src.battle.BattleState")
  if not (BattleState and type(BattleState.newWild) == "function") then
    return nil, "BattleState.newWild unavailable"
  end
  local okNew, battle = pcall(BattleState.newWild, game, species, tonumber(level) or 5)
  if not okNew or not battle then
    return nil, "newWild failed: " .. tostring(battle)
  end
  if type(battle.makeGhost) ~= "function" then
    return nil, "battle:makeGhost unavailable"
  end
  local okGhost, ghostErr = pcall(battle.makeGhost, battle)
  if not okGhost then
    return nil, "makeGhost failed: " .. tostring(ghostErr)
  end
  if not battle.ghost then
    return nil, "makeGhost did not mark the battle"
  end
  battle.checkpointOrigin = {
    kind = "wild_encounter",
    map = mapId or (ow and ow.map and ow.map.id),
  }
  battle.onFinish = function(result)
    if ow and type(ow.afterBattle) == "function" then
      pcall(ow.afterBattle, ow, result, battle)
    end
  end
  if ow and type(ow.pushBattle) == "function" then
    local okPush, pushErr = pcall(ow.pushBattle, ow, battle)
    if not okPush then return nil, "pushBattle failed: " .. tostring(pushErr) end
    return true, battle
  end
  if game and game.stack and type(game.stack.push) == "function" then
    local okPush, pushErr = pcall(game.stack.push, game.stack, battle)
    if not okPush then return nil, "stack.push failed: " .. tostring(pushErr) end
    return true, battle
  end
  return nil, "no battle push path"
end

--- Gen1 trailer NPC: exact ControlEngine makeTrailer constructor.
function Gen1.makeGuestNpc(game, ow, spec)
  spec = spec or {}
  local NPC = tryRequire("src.world.NPC")
  if not (NPC and NPC.new) then return nil, "no NPC" end
  if not (game and game.data and ow and ow.map and ow.map.id) then
    return nil, "no data/map"
  end
  return NPC.new(game.data, ow.map.id, {
    index = spec.index,
    name = spec.name,
    sprite = spec.spriteId or "SPRITE_PIKACHU",
    movement = spec.movement or "STAY",
    range = spec.range or "NONE",
    x = spec.x, y = spec.y,
  })
end

--- Gen1 CONTROL=POKEMON: assign SpriteRenderer onto player.sprite.
function Gen1.applyControlledPokemonSprite(player, renderer, _game)
  if not (player and renderer) then return false, "missing player or renderer" end
  player.sprite = renderer
  player._pokepcAsPokemon = true
  return true, "player.sprite"
end

--- Gen1 Pokédex seen table is keyed by internal species id.
function Gen1.hasSeenSpecies(game, species)
  local dex = game and game.save and game.save.pokedex
  if not (dex and species) then return false end
  local seen = dex.seen
  if type(seen) ~= "table" then return false end
  return seen[species] == true
end

--- Gen1 capture registration: owned (BattleState.markOwned) or caught.
function Gen1.hasCaughtSpecies(game, species)
  local dex = game and game.save and game.save.pokedex
  if not (dex and species) then return false end
  if type(dex.owned) == "table" and dex.owned[species] == true then
    return true
  end
  if type(dex.caught) == "table" and dex.caught[species] == true then
    return true
  end
  return false
end

--- True while the Poké Center nurse heal machine animation is running.
-- Gen1 only sets ow.healAnim after HEAL is accepted (CANCEL never sets it).
function Gen1.isPokecenterHealActive(ow, _game)
  return ow ~= nil and ow.healAnim ~= nil
end

--- Gen1 must not destroy the talked-to follower inside the ChoiceBox callback.
-- OverworldController.interact never sets ow.engaging for ordinary talk
-- (that flag is trainer-sight). TextBox.choice pops ChoiceBox then TextBox
-- before choice(yes) runs — still on the UI call stack. Recalling there
-- (or attaching FX ghosts to ow.npcs) races the next Overworld tick.
function Gen1.shouldDeferFollowerRecall(_ow, _game, _npc)
  return true
end

--- True while a non-overworld state owns the Gen1 StateStack.
-- Only the top state updates. When stack:top() is the live OverworldState,
-- follower talk UI is finished. Do not wait on npc.frozen (Wilds trailers
-- are not frozen by interact wrap) or ow.engaging (trainer sight only).
function Gen1.followerInteractionBusy(ow, game, _npc)
  local stack = game and game.stack
  if not (stack and type(stack.top) == "function") then
    return false
  end
  local ok, top = pcall(stack.top, stack)
  if not ok or top == nil then return false end
  if ow ~= nil and top == ow then return false end
  return true
end

return Gen1
