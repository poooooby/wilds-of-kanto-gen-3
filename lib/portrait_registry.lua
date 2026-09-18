-- PMDCollab portrait resolution — independent of overworld Sprite Style.
local V = ...

local PortraitRegistry = {}

PortraitRegistry.GENERIC_POOL = {
  "happy",
  "joyous",
  "inspired",
  "determined",
  "normal",
}

local _pathCache = {}

local function normalizeVariant(variant)
  if variant == true or variant == "shiny" or variant == "s" or variant == "SHINY" then
    return "shiny"
  end
  return "normal"
end

local function rng01(rng)
  if type(rng) == "function" then
    local v = rng()
    if type(v) == "number" then
      if v < 0 then return 0 end
      if v > 1 then return 1 end
      return v
    end
  end
  return math.random()
end

function PortraitRegistry.loadPath(mod, rel)
  if type(rel) ~= "string" or rel == "" then return nil end
  local cached = _pathCache[rel]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local path = nil
  if mod and mod.assets and type(mod.assets.path) == "function" then
    local ok, p = pcall(function() return mod.assets:path(rel) end)
    if ok and type(p) == "string" and p ~= "" then
      path = p
    end
  end
  if not path and mod and type(mod.path) == "string" then
    path = mod.path .. "/" .. rel
  end
  if not path then
    path = rel
  end
  _pathCache[rel] = path
  return path
end

function PortraitRegistry.resetCache()
  _pathCache = {}
end

local function ensureAssets(mod)
  local Assets = V.require("pmdcollab_assets")
  if not Assets.isReady() then
    Assets.load(mod)
  end
  return Assets
end

-- gen1recomp-national-dex registers alternate forms (Mega/regional/gender
-- variants, etc.) as separate name-keyed entries with a synthetic dex in
-- this range instead of a real National Dex number (see
-- lib/species_assets.lua's idForRuntime doc comment). portrait_table.lua is
-- keyed by real National Dex 1-1025 only, so a synthetic id can never have
-- an entry there -- resolveDex below falls back to the form's baseSpecies.
local SYNTHETIC_FORM_DEX_MIN = 30000

-- Mirrors the local `pokemonDef` helper in lib/game_compat/gen1.lua and
-- gen2.lua (not exported on GameCompat) -- needed here to read a form
-- entry's `baseSpecies` field, which GameCompat.speciesId doesn't expose.
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

--- Resolve a species key to the numeric id used for portrait/overworld
-- asset lookups, the same way lib/variable_size.lua's resolveDex does:
-- idFor's hardcoded 1..386 table first, then GameCompat.speciesId's runtime
-- dex (which can be a real National Dex number OR a synthetic form id).
local function resolveRuntimeDex(species, game, mod, SpeciesAssets)
  local okGC, GameCompat = pcall(function() return V.require("game_compat") end)
  local runtimeDex = nil
  if okGC and GameCompat and type(GameCompat.speciesId) == "function" then
    local okId, result = pcall(GameCompat.speciesId, species, game, mod)
    if okId then runtimeDex = result end
  end
  return SpeciesAssets.idForRuntime(species, runtimeDex)
end

local function emotionRel(entry, slug)
  if type(entry) ~= "table" or type(entry.emotions) ~= "table" then
    return nil
  end
  return entry.emotions[slug]
end

function PortraitRegistry.pickGenericEmotion(dex, variant, rng, mod)
  local Assets = ensureAssets(mod)
  local entry = select(1, Assets.portraitEntry(dex, variant))
  if not entry then return nil end
  local available = {}
  for _, slug in ipairs(PortraitRegistry.GENERIC_POOL) do
    if emotionRel(entry, slug) then
      available[#available + 1] = slug
    end
  end
  if #available == 0 then
    if emotionRel(entry, "normal") then return "normal" end
    return nil
  end
  local idx = math.floor(rng01(rng) * #available) + 1
  if idx < 1 then idx = 1 end
  if idx > #available then idx = #available end
  return available[idx]
end

--- Resolve a portrait for canonical species identity.
-- opts: shiny, mood, randomGeneric, rng, mod, game
-- Fallback: requested mood → normal → nil (no empty frame). Dex resolution
-- also falls back: a synthetic alternate-form id with no portrait_table.lua
-- entry retries against the form's baseSpecies (see resolveRuntimeDex /
-- SYNTHETIC_FORM_DEX_MIN above) so e.g. a registered form of Archen still
-- gets Archen's own portrait instead of none at all.
function PortraitRegistry.resolve(species, opts)
  opts = opts or {}
  local mod = opts.mod
  local game = opts.game
  local Assets = ensureAssets(mod)
  local SpeciesAssets = V.require("species_assets")
  local dex = resolveRuntimeDex(species, game, mod, SpeciesAssets)
  if not dex then
    return nil
  end
  local variant = normalizeVariant(opts.shiny or opts.variant)
  local entry, usedVariant = Assets.portraitEntry(dex, variant)
  if not entry and dex >= SYNTHETIC_FORM_DEX_MIN and type(species) == "string" then
    local def = pokemonDef(species, game, mod)
    local baseSpecies = def and def.baseSpecies
    if type(baseSpecies) == "string" and baseSpecies ~= "" and baseSpecies ~= species then
      local baseDex = resolveRuntimeDex(baseSpecies, game, mod, SpeciesAssets)
      if baseDex and baseDex ~= dex then
        local baseEntry, baseVariant = Assets.portraitEntry(baseDex, variant)
        if baseEntry then
          dex, entry, usedVariant = baseDex, baseEntry, baseVariant
        end
      end
    end
  end
  if not entry then
    return nil
  end

  local mood = opts.mood
  if type(mood) == "string" then
    mood = string.lower(mood)
  else
    mood = nil
  end

  if opts.randomGeneric == true and not mood then
    mood = PortraitRegistry.pickGenericEmotion(dex, usedVariant or variant, opts.rng, mod)
  end
  if not mood then
    mood = "normal"
  end

  local rel = emotionRel(entry, mood)
  if not rel and mood ~= "normal" then
    mood = "normal"
    rel = emotionRel(entry, "normal")
  end
  if not rel then
    return nil
  end
  return {
    dex = dex,
    emotion = mood,
    rel = rel,
    path = PortraitRegistry.loadPath(mod, rel),
    variant = usedVariant or variant,
  }
end

return PortraitRegistry
