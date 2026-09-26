-- Poke Followers / GSC assets + default sprite style.
-- Run: lua tests/poke_followers_assets_unit_test.lua
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

-- Asset inventory: the built-in GSC pack ships one normal and one shiny sheet per species, National Dex 1..251
-- (submerged art is derived at load, not shipped).
do
  local COUNT = 251
  local missing, extra = {}, {}
  for _, kind in ipairs({ "normal", "shiny" }) do
    for i = 1, COUNT do
      local path = string.format("assets/enhanced_overworld/poke_followers/follower_%03d_%s.png", i, kind)
      local f = io.open(path, "rb")
      if f then f:close() else missing[#missing + 1] = path end
    end
  end
  for _, name in ipairs({ "follower_000_normal.png", string.format("follower_%03d_normal.png", COUNT + 1) }) do
    local f = io.open("assets/enhanced_overworld/poke_followers/" .. name, "rb")
    if f then f:close(); extra[#extra + 1] = name end
  end
  eq(#missing, 0, "every poke_followers normal + shiny sheet 1.." .. COUNT .. " is present"
    .. (#missing > 0 and (" (first missing: " .. missing[1] .. ")") or ""))
  eq(#extra, 0, "no poke_followers sheet outside 1.." .. COUNT)
end

local optionStore = {}
local modules = {}
local V = {
  mod = {
    path = ".",
    id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    read = function(_, rel)
      local f = io.open(rel, "rb") or io.open("./" .. rel, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    options = {
      get = function(_, k)
        if optionStore[k] ~= nil then return optionStore[k] end
        if k == "sprite_style" then return "followers" end
        return nil
      end,
      set = function(_, k, v) optionStore[k] = v end,
    },
    assets = {
      path = function(_, rel) return "mods/wilds_of_kanto_gen3/" .. rel end,
    },
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

modules.config = nil -- load real
modules.debug_log = {
  warn = function() end, info = function() end, error = function() end, debug = function() end,
}
modules.json_decode = { decode = function() return nil end }
modules.tile = { CELL = 16, WIDTH = 16, HEIGHT = 16 }

local Config = V.require("config")
modules.config = Config

-- Defaults / migration
eq(Config.DEFAULTS.sprite_style, "followers", "default sprite_style is followers")
eq(Config.normalizeSpriteStyle("followers_ex"), "followers", "followers_ex migrates")
eq(Config.normalizeSpriteStyle("poke_followers"), "followers", "poke_followers migrates")
eq(Config.normalizeSpriteStyle("pokemmo"), "pokemmo", "explicit pokemmo kept")
eq(Config.normalizeSpriteStyle("pokedex"), "pokedex", "explicit pokedex kept")
eq(Config.normalizeSpriteStyle("nope"), "followers", "invalid → followers default")

-- Fresh: no saved style → followers
do
  optionStore = {}
  eq(Config.spriteStyle(V.mod), "followers", "fresh save uses followers default")
end

-- Existing explicit HGSS preserved via peek
do
  local saveBucket = { sprite_style = "pokemmo" }
  V.mod.world = { game = { save = { options = { modOptions = {
    wilds_of_kanto_gen3 = saveBucket,
  } } } } }
  eq(Config.spriteStyle(V.mod), "pokemmo", "existing HGSS save preserved")
  saveBucket.sprite_style = "pokedex"
  eq(Config.spriteStyle(V.mod), "pokedex", "existing pokedex save preserved")
  V.mod.world = nil
end

-- Provider resolves dex → follower_%03d
do
  modules.animated_sprites = {
    normalizeVariant = function(variant)
      if variant == true or variant == "shiny" or variant == "s" or variant == "SHINY" then
        return "shiny"
      end
      return "normal"
    end,
    resolveSpeciesId = function(speciesId)
      local map = {
        BULBASAUR = 1, PIKACHU = 25, MANKEY = 56,
        SNORLAX = 143, MEWTWO = 150, MEW = 151,
      }
      if type(speciesId) == "number" then return speciesId end
      return map[tostring(speciesId):upper()]
    end,
  }
  -- Reload providers against the stubbed AnimatedSprites helpers.
  modules.sprite_providers = nil
  modules.runtime_sheets = {
    ready = true,
    isReady = function() return true end,
    load = function() end,
    spriteDef = function() return nil end,
  }

  local fakeRender = {
    runtimeSheets = modules.runtime_sheets,
    _modAssetPath = function(_, rel)
      return "mods/wilds_of_kanto_gen3/" .. rel
    end,
  }
  local SpriteProviders = V.require("sprite_providers")
  local providers = SpriteProviders.new(V.mod, fakeRender)
  -- Replace animated resolve used inside providers
  local p = providers.providers.followers_ex
  check(p ~= nil, "followers_ex provider registered")
  local ok, why = p:isAvailable(nil)
  check(ok == true, "followers_ex available built-in: " .. tostring(why))

  local function resolveDex(species, dex)
    -- Monkeypatch resolveDex via resolve using numeric dex
    local def, meta, err = p:resolve(dex, "normal", nil)
    check(def ~= nil, species .. " resolves (" .. tostring(err) .. ")")
    if def then
      check(def.image:find(string.format("follower_%03d", dex), 1, true),
            species .. " maps to follower_" .. string.format("%03d", dex))
      eq(def.frames, 6, species .. " frames=6")
      check(def.walker == true, species .. " walker")
    end
  end
  resolveDex("Bulbasaur", 1)
  resolveDex("Pikachu", 25)
  resolveDex("Mankey", 56)
  resolveDex("Snorlax", 143)
  resolveDex("Mewtwo", 150)
  resolveDex("Mew", 151)

  -- PokeWilds fallback (assets/enhanced_overworld/Pokewilds/, see
  -- tools/generate_pokewilds_overworld.py): fills dex the primary
  -- poke_followers/ folder doesn't have, without touching dex 1-251.
  do
    -- Dex 1 exists in poke_followers/: must NOT fall through to Pokewilds.
    local def = p:resolve(1, "normal", nil)
    check(def ~= nil, "Bulbasaur still resolves")
    if def then
      check(def.image:find("poke_followers", 1, true) ~= nil
        and def.image:find("Pokewilds", 1, true) == nil,
        "dex present in poke_followers/ is preferred over Pokewilds")
    end

    -- Dex 252 (Treecko) exists only under Pokewilds/, with real shiny art.
    local normalDef = p:resolve(252, "normal", nil)
    check(normalDef ~= nil, "Pokewilds-only dex resolves via fallback")
    if normalDef then
      check(normalDef.image:find("Pokewilds", 1, true) ~= nil,
        "Pokewilds-only dex serves from the Pokewilds/ fallback folder")
      eq(normalDef.frames, 6, "Pokewilds fallback sheet frames=6")
    end
    -- landArtUsesLuminance defaults true headlessly (paletteFxRedpp() has no
    -- engine PaletteFX to read), which resolves any "shiny" request to the
    -- normal sheet's path regardless of source folder (pre-existing
    -- behavior, not specific to the Pokewilds fallback). Force ADVANCED mode
    -- for these two checks so shiny actually reads the shiny/normal file it
    -- claims to.
    local realPaletteFxRedpp = Config.paletteFxRedpp
    Config.paletteFxRedpp = function() return true end

    local shinyDef = p:resolve(252, "shiny", nil)
    check(shinyDef ~= nil, "Pokewilds-only dex resolves shiny via fallback")
    if shinyDef then
      check(shinyDef.image:find("follower_252_shiny", 1, true) ~= nil,
        "Pokewilds-only dex serves its own shiny sheet when one exists")
    end

    -- Dex 501 (Oshawott) exists only under Pokewilds/, with no shiny art.
    local noShinyDef = p:resolve(501, "shiny", nil)
    check(noShinyDef ~= nil, "Pokewilds-only dex without shiny still resolves")
    if noShinyDef then
      check(noShinyDef.image:find("follower_501_normal", 1, true) ~= nil,
        "Pokewilds-only dex with no shiny art falls back to its own normal sheet")
    end

    Config.paletteFxRedpp = realPaletteFxRedpp
  end
end

-- Options schema default
do
  local schema = assert(loadfile("options.lua"))()
  local style
  for _, row in ipairs(schema) do
    if row.key == "sprite_style" then style = row end
  end
  check(style ~= nil, "sprite_style option present")
  eq(style.default, "followers", "options default followers")
  eq(style.choices[1][2], "followers", "followers listed first")
  check(style.choices[1][1]:find("GSC", 1, true), "GSC in label")
end

-- Settings menu keys match options
do
  local SettingsMenus = V.require("settings_menus")
  check(SettingsMenus.LABEL_FOLLOWERS == "POKE FOLLOW EX", "followers menu label")
  check(SettingsMenus.LABEL_WILDS == "WILDS OF KANTO", "wilds menu label")
  check(#SettingsMenus.LABEL_FOLLOWERS <= 14, "followers label ≤14")
  check(#SettingsMenus.LABEL_WILDS <= 14, "wilds label ≤14")
end

-- HGSS runtime regenerated for Gen1
do
  local missing = {}
  for i = 1, 151 do
    local path = string.format("assets/wilds_generated/followsprites_runtime/%03d-normal.png", i)
    local f = io.open(path, "rb")
    if not f then missing[#missing + 1] = i else f:close() end
  end
  eq(#missing, 0, "HGSS runtime normal sheets 1..151 present")
  local man = io.open("assets/wilds_generated/followsprites_runtime/manifest.json", "r")
  check(man ~= nil, "HGSS manifest present")
  if man then
    local body = man:read("*a")
    man:close()
    check(body:find("NEAREST", 1, true) or body:find("nearest", 1, true)
          or body:find("integer_full_tile", 1, true)
          or body:find("shared_bbox", 1, true),
          "manifest documents scale method")
  end
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nAll poke_followers_assets tests passed.")
