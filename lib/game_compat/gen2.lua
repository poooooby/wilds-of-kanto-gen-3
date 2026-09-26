-- Gen 2 / Pokémon Gold adapter for Wilds game compatibility.
--
-- Gold adapter: species, party, surf, map, water, wild encounters and followers.
-- Encounter tables live in lib/gen2/encounters.lua.
-- Safari / special-session compatibility remains separate.
-- Town Pokémon: curated Johto catalog.
--
-- Engine pointers (verified against current Gen1Recomp Gold):
--   party:        game.save.party (src/core/gen2/Save.lua)
--   inventory:    save.inventory id→count (Bag.remove; PackMenu pockets)
--   mon:          src.battle.gen2.Mon.new + stampOT
--   boxes:        src.core.gen2.Boxes.box; SendMonIntoBox inserts at head
--   dex:          save.pokedex.caught / .seen keyed by species id
--   world:        game.world (src/world/gen2/World.lua), not Gen1 overworld
--   map id:       world.map.id (e.g. ROUTE_29)
--   isSurfing:    src.world.gen2.FieldMoves.isSurfing(playerState)
--                 PLAYER_SURF = "surf", PLAYER_SURF_PIKA = "surf_pika"
--   isWaterCell:  src.world.gen2.Map:isWaterCell → Permissions.isWater
--   speciesId:    data.pokemon[id].dex or .index (World.monIndex uses index)
--
-- Wild encounters: lib/gen2/encounters.lua over data.gen2Encounters.
-- Town Pokémon: lib/gen2/town_pokemon.lua (curated Johto towns).
local V = ...

local Gen2 = {}
Gen2.supported = true
Gen2.generation = 2
-- National Dex span for True Size / geometry consumers. This is the TRUE
-- vanilla Gen1+2 count (251) -- a static baseline, not a ceiling:
-- SpeciesGeometry's activeMaxSpecies() live-scans game.data.pokemon and
-- raises the effective cap when an expansion mod (Kanto Reforged and
-- others) actually registers more, so this constant never needs bumping
-- by hand for a specific mod.
Gen2.MAX_SPECIES = 251

Gen2.capabilities = {
  core = true,
  species = true,
  party = true,
  surf = true,
  encounters = true,
  followers = true,
  ambient = true,
  townPokemon = true,
  safari = false,
  healDetect = true,
}

local function tryRequire(path)
  local ok, mod = pcall(require, path)
  if ok then return mod end
  return nil
end

local function goldWorld(game, ow)
  if game and game.world and (game.world.map or game.world.playerState ~= nil) then
    return game.world
  end
  if ow and (ow.playerState ~= nil or ow.map) then
    return ow
  end
  if game and game.overworld then
    return game.overworld
  end
  return ow
end

local function pokemonDef(species, game, mod)
  if type(species) ~= "string" or species == "" then return nil end
  if game and game.data and type(game.data.pokemon) == "table" then
    local def = game.data.pokemon[species]
    if def then return def end
  end
  if mod and mod.content and mod.content.pokemon and mod.content.pokemon.get then
    local ok, def = pcall(mod.content.pokemon.get, mod.content.pokemon, species)
    if ok and def then return def end
  end
  return nil
end

--- Resolve a species key to a numeric National Dex / Gold index.
-- 1. numeric id → return as-is if a positive integer
-- 2. engine pokemon record dex (schema requires dex) or index (World.monIndex)
-- 3. AnimatedSprites.resolveSpeciesId (reads dex on the record)
-- No hand-maintained 251-name table.
function Gen2.speciesId(species, game, mod)
  if species == nil then return nil end
  local n = tonumber(species)
  if n and n >= 1 and math.floor(n) == n then
    return math.floor(n)
  end
  if type(species) ~= "string" and type(species) ~= "number" then
    return nil
  end

  local def = pokemonDef(species, game, mod or V.mod)
  if def then
    local dex = tonumber(def.dex) or tonumber(def.index)
    if dex and dex >= 1 then return math.floor(dex) end
  end

  local okAS, AnimatedSprites = pcall(function() return V.require("animated_sprites") end)
  if okAS and AnimatedSprites and AnimatedSprites.resolveSpeciesId then
    local ok, dex = pcall(AnimatedSprites.resolveSpeciesId, species, game, mod or V.mod)
    if ok and type(dex) == "number" and dex >= 1 then
      return math.floor(dex)
    end
  end
  return nil
end

--- Gold surf: FieldMoves.isSurfing(world.playerState / save.playerState).
-- Does not use Gen1 player.surfing.
function Gen2.isSurfing(game, ow)
  local world = goldWorld(game, ow)
  local state = (world and world.playerState)
    or (game and game.save and game.save.playerState)

  local FieldMoves = tryRequire("src.world.gen2.FieldMoves")
  if FieldMoves and type(FieldMoves.isSurfing) == "function" then
    local ok, surfing = pcall(FieldMoves.isSurfing, state)
    if ok then return surfing == true end
  end
  -- Engine string values when FieldMoves is not on package.path (unit tests).
  return state == "surf" or state == "surf_pika"
end

function Gen2.isWaterCell(map, x, y)
  if map and type(map.isWaterCell) == "function" then
    local ok, water = pcall(map.isWaterCell, map, x, y)
    if ok then return water == true end
  end
  if map and type(map.cellCollision) == "function" then
    local Permissions = tryRequire("src.world.gen2.Permissions")
    if Permissions and type(Permissions.isWater) == "function" then
      local ok, coll = pcall(map.cellCollision, map, x, y)
      if ok then
        local okWater, water = pcall(Permissions.isWater, coll)
        if okWater then return water == true end
      end
    end
  end
  return false
end

function Gen2.party(game)
  if not (game and game.save and type(game.save.party) == "table") then
    return nil
  end
  return game.save.party
end

function Gen2.currentMapId(game, ow)
  local world = goldWorld(game, ow)
  if world and world.map and world.map.id ~= nil then
    return world.map.id
  end
  if ow and ow.map and ow.map.id ~= nil then
    return ow.map.id
  end
  return nil
end

function Gen2.encountersForMap(game, mapId, ctx)
  local Enc = V.require("gen2/encounters")
  return Enc.forMap(game, mapId, ctx)
end

function Gen2.pickEncounter(game, mapId, kind, ctx)
  local Enc = V.require("gen2/encounters")
  return Enc.pick(game, mapId, kind, ctx)
end

--- Per-spawn variation the engine decides by DVs rather than by species. Only Unown today: the Ruins of Alph chambers
-- roll an UNOWN slot, the LETTER (read off the DVs) is what the player sees, and which letters can appear depends on
-- which wall puzzles are solved. Mirrors World:tryWildEncounter's Unown arm (src/world/gen2/World.lua):
--   * no puzzle solved  -> the slot is NO encounter;
--   * otherwise         -> DVs are rerolled until the letter is unlocked (Unown.wildDVs).
-- Returns nil when the species has no variation (or the engine cannot say), `false, reason` when the encounter must
-- not happen, else { unownLetter = 1..26, unownForm = 1..25 | nil, dvs = {...} }. `ctx.forced` (debug / test spawns)
-- skips the unlock rule and takes any letter.
function Gen2.wildVariant(game, species, ctx)
  if species ~= "UNOWN" then return nil end
  ctx = ctx or {}
  local Unown = tryRequire("src.core.gen2.Unown")
  local Mon = tryRequire("src.battle.gen2.Mon")
  if not (Unown and Mon and type(Mon.randomDVs) == "function") then return nil end
  local UnownForms = V.require("unown_forms")
  local dvs
  if ctx.forced then
    dvs = Mon.randomDVs()
  else
    local world = goldWorld(game, ctx.ow)
    if not (world and type(world.unownUnlockFlags) == "function") then return nil end
    local ok, flags = pcall(world.unownUnlockFlags, world)
    if not ok or type(flags) ~= "table" then return nil end
    if not Unown.anyUnlocked(flags) then return false, "no Unown puzzle solved" end
    dvs = Unown.wildDVs(flags, Mon.randomDVs)
  end
  local letter = Unown.letterFromDVs(dvs)
  if not letter then return nil end
  return { unownLetter = letter, unownForm = UnownForms.formForLetter(letter), dvs = dvs }
end

--- Gold wild battle: WorldAPI.queueScript start_battle wild species level.
-- WorldAPI builds src.battle.gen2.Mon and World:startBattle({ wild = mon }).
-- `opts.dvs` (Unown: the DVs whose letter the player saw) is handed to that Mon: the queue builds the mon
-- synchronously with Mon.randomDVs(), so it is swapped for a one-shot that returns our DVs and always put back.
function Gen2.startWildBattle(world, species, level, opts)
  if not (world and type(world.queueScript) == "function") then
    return nil, "no world"
  end
  local dvs = opts and opts.dvs
  local Mon = type(dvs) == "table" and tryRequire("src.battle.gen2.Mon") or nil
  local original = Mon and type(Mon.randomDVs) == "function" and Mon.randomDVs or nil
  local swapped = false
  if original then
    swapped = pcall(function()
      Mon.randomDVs = function()
        Mon.randomDVs = original
        return { attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special }
      end
    end)
  end
  local ok, res, err = pcall(world.queueScript, world, {
    { "start_battle", "wild", species, tonumber(level) or 5 },
  })
  if swapped then pcall(function() Mon.randomDVs = original end) end
  if not ok then return nil, tostring(res) end
  return res, err
end

-- STANDING_DOWN (src/world/gen2/Npc.lua MOVE table). STILL=1 carries
-- FIXED_FACING and cannot turn. Same constant Follower.lua uses.
local GOLD_STANDING_DOWN = 6

--- Native Gold NPC module.
-- Prefer `src.world.gen2.Npc` (the path `src/world/gen2/Follower.lua` uses)
-- so construction does not depend on Loader's Gen2Compat alias.
--
-- `pcall(require, "src.world.NPC")` can miss that alias: Loader's shim
-- uses callerIsMod(3), a C `pcall` frame makes the call look like engine
-- code, and Gold then loads Gen1 `src/world/NPC.lua` (no MOVE, draw is
-- `draw(camX, camY)` — invisible under Gold `draw(ox, oy, scale)`).
-- An extra Lua frame makes callerIsMod(3) see this mod chunk.
local function loadGoldNpc(name)
  local ok, Npc = pcall(function()
    return require(name)
  end)
  if ok and type(Npc) == "table" and type(Npc.new) == "function" then
    return Npc, name
  end
  return nil, nil
end

function Gen2.npcModule()
  local Npc, name = loadGoldNpc("src.world.gen2.Npc")
  if Npc then return Npc, name end
  return loadGoldNpc("src.world.NPC")
end

--- Gold trailer NPC: native Npc.new(mapId, objDef, spriteDef).
-- Same contract as src/world/gen2/Follower.lua makeFollower.
-- Never sniffs NPC.MOVE to choose Gen1 arity. Never calls
-- NPC.new(data, mapId, objDef) — that is Gen1.makeGuestNpc only.
function Gen2.makeGuestNpc(game, ow, spec)
  spec = spec or {}
  local NPC, npcSource = Gen2.npcModule()
  if not (NPC and NPC.new) then
    return nil, "no Gold NPC (src.world.gen2.Npc)"
  end
  if not (ow and ow.map and ow.map.id) then return nil, "no map" end
  local spriteDef = spec.spriteDef
  if type(spriteDef) ~= "table" or not spriteDef.image then
    return nil, "Gold trailer requires spriteDef.image"
  end
  local mapId = ow.map.id
  local MOVE = type(NPC.MOVE) == "table" and NPC.MOVE or {}
  local movement = MOVE.STANDING_DOWN or GOLD_STANDING_DOWN
  local objDef = {
    index = spec.index,
    name = spec.name,
    sprite = spec.spriteId,
    movement = movement,
    x = spec.x, y = spec.y,
  }
  local ok, npc = pcall(NPC.new, mapId, objDef, spriteDef)
  if not ok then
    return nil, tostring(npc)
  end
  if not npc then
    return nil, "NPC.new returned nil (" .. tostring(npcSource) .. ")"
  end
  npc.spriteDef = npc.spriteDef or spriteDef
  npc.mapId = npc.mapId or mapId
  npc.passable = true
  npc._wildsGoldGuest = true
  if spec.facing then npc.facing = spec.facing end
  npc._wildsGoldNpcSource = npcSource
  npc._wildsGoldMovement = movement
  return npc
end

--- Gold CONTROL=POKEMON: Player:setSprite(spriteDef). Keeps the same
-- player object (cell, input, collision, scripts, warps, surf).
function Gen2.applyControlledPokemonSprite(player, def, _game)
  if not (player and def) then return false, "missing player or def" end
  if type(player.setSprite) == "function" then
    local ok, err = pcall(player.setSprite, player, def)
    if not ok then return false, err end
    player._pokepcAsPokemon = true
    return true, "setSprite"
  end
  local SpriteRenderer = tryRequire("src.render.SpriteRenderer")
  if not (SpriteRenderer and SpriteRenderer.new) then
    return false, "no SpriteRenderer"
  end
  local ok, sprite = pcall(SpriteRenderer.new, def, "player")
  if not ok or not sprite then return false, tostring(sprite) end
  player.sprite = sprite
  player.spriteDef = def
  player._pokepcAsPokemon = true
  return true, "player.sprite"
end

--- Gold Pokédex seen table is keyed by internal species id.
function Gen2.hasSeenSpecies(game, species)
  local dex = game and game.save and game.save.pokedex
  if not (dex and species) then return false end
  local seen = dex.seen
  if type(seen) ~= "table" then return false end
  return seen[species] == true
end

--- Gold capture registration: pokedex.caught (SetSeenAndCaughtMon).
function Gen2.hasCaughtSpecies(game, species)
  local dex = game and game.save and game.save.pokedex
  if not (dex and species) then return false end
  local caught = dex.caught
  if type(caught) ~= "table" then return false end
  return caught[species] == true
end

--- Gold talk/choice already closes through World:showText / TextBox.choice
-- without owning the follower NPC the way Gen1 OverworldController does.
-- Immediate manualRecallFollower in the choice callback is the working path.
function Gen2.shouldDeferFollowerRecall(_ow, _game, _npc)
  return false
end

--- Gold interaction ownership: World.textbox / choicebox / engaging / freeze.
-- Unused for talk-Ball (shouldDeferFollowerRecall is false) but kept accurate.
function Gen2.followerInteractionBusy(ow, _game, npc)
  if not ow then return false end
  if ow.engaging then return true end
  if ow.textbox or ow.choicebox then return true end
  if npc and npc.frozen == true then return true end
  if type(ow.busy) == "function" then
    local ok, busy = pcall(ow.busy, ow)
    if ok and busy then return true end
  end
  return false
end

--- True while a Poké Center HealMachineAnim is running.
-- Hall of Fame (hof) and Elm's Lab maps are excluded — only nurse PC.
function Gen2.isPokecenterHealActive(ow, game)
  ow = goldWorld(game, ow) or ow
  if not (ow and ow.healAnim) then return false end
  if ow.healAnim.hof == true then return false end
  local mapId = tostring(ow.map and ow.map.id or ""):upper()
  if mapId == "" then return false end
  if mapId:find("HALL_OF_FAME", 1, true) or mapId:find("HALL OF FAME", 1, true) then
    return false
  end
  if mapId:find("LAB", 1, true) then return false end
  -- Nurse scripts run on *CENTER / POKECENTER maps.
  if mapId:find("POKECENTER", 1, true) or mapId:find("_CENTER", 1, true)
      or mapId:find("CENTER", 1, true) then
    return true
  end
  return false
end

--- Gold restore: World:applyPlayerState picks SPRITE_CHRIS / bike / surf.
function Gen2.restoreTrainerSprite(player, game, ow)
  ow = goldWorld(game, ow)
  if ow and type(ow.applyPlayerState) == "function" then
    local ok, err = pcall(ow.applyPlayerState, ow, ow.playerState)
    if not ok then return false, err end
    if player then
      player._pokepcAsPokemon = nil
      player._pokepcControlSpecies = nil
      player._pokepcShiny = nil
      player._pokepcControlStyle = nil
    end
    return true, "applyPlayerState"
  end
  return false, "no applyPlayerState"
end

return Gen2
