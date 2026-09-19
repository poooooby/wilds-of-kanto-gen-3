-- Runtime check for an expanded Pokedex: are species above Gen 3 actually registered?
--
-- Deliberately separate from SpeciesGeometry's file-local max-dex scan, which (a) also counts the
-- synthetic alternate-form records (dex >= 30000) that a national-dex mod registers, so it can't
-- say "Gen 4-9 is present", and (b) caches its first non-zero result forever, so a scan that runs
-- before an expansion mod's species are visible pins the baseline permanently.
--
-- Results are cached per game object but keyed to an epoch that is bumped on mods.loaded /
-- game.ready / map entry (see DexExpansion.invalidate), so a stale "no" cannot outlive the event
-- that would have made it "yes".
local V = ...

local DexExpansion = {}

-- Gen 3 tops out at #386 (Kanto Reforged); everything the national-dex mod adds for real species
-- is 387..1025. Alternate forms live at 30000+ and are NOT evidence of an expanded dex.
DexExpansion.MODERN_MIN = 387
DexExpansion.FORM_MIN = 30000

-- Last national dex number of each generation (contiguous: G1 1-151, G2 152-251, G3 252-386,
-- G4 387-493, G5 494-649, G6 650-721, G7 722-809, G8 810-905, G9 906-1025).
DexExpansion.GENERATION_LAST_DEX = { 151, 251, 386, 493, 649, 721, 809, 905, 1025 }

--- Highest dex a "max generation" cap allows, or nil for no cap (generation 9, or anything that is not
-- a whole number 1..9), so a stray species above #1025 is never cut by a cap that means "all".
function DexExpansion.lastDexOf(generation)
  local g = tonumber(generation)
  if not g or g % 1 ~= 0 or g < 1 or g >= #DexExpansion.GENERATION_LAST_DEX then return nil end
  return DexExpansion.GENERATION_LAST_DEX[math.floor(g)]
end

local epoch = 0
local cache = setmetatable({}, { __mode = "k" }) -- game -> { epoch, value }

function DexExpansion.invalidate()
  epoch = epoch + 1
end

function DexExpansion.epoch()
  return epoch
end

local function isModern(def)
  local d = type(def) == "table" and tonumber(def.dex) or nil
  return d ~= nil and d >= DexExpansion.MODERN_MIN and d < DexExpansion.FORM_MIN
end

local function scan(mod, game)
  local pokemon = game and game.data and game.data.pokemon
  if type(pokemon) == "table" then
    for _, def in pairs(pokemon) do
      if isModern(def) then return true end
    end
  end
  local content = mod and mod.content and mod.content.pokemon
  if content and type(content.each) == "function" then
    local found = false
    local ok = pcall(function()
      for _, def in content:each() do
        if isModern(def) then found = true; break end
      end
    end)
    if ok and found then return true end
  end
  return false
end

--- True when at least one real species above #386 (and below the 30000 form range) is registered.
function DexExpansion.hasModernSpecies(mod, game)
  if not game then return false end
  local c = cache[game]
  if c and c.epoch == epoch then return c.value end
  local value = scan(mod, game)
  cache[game] = { epoch = epoch, value = value }
  return value
end

--- Is this exact species key registered right now?
function DexExpansion.speciesRegistered(mod, game, key)
  if type(key) ~= "string" then return false end
  local pokemon = game and game.data and game.data.pokemon
  if type(pokemon) == "table" and pokemon[key] ~= nil then return true end
  local content = mod and mod.content and mod.content.pokemon
  if content and type(content.get) == "function" then
    local ok, def = pcall(function() return content:get(key) end)
    if ok and def ~= nil then return true end
  end
  return false
end

return DexExpansion
