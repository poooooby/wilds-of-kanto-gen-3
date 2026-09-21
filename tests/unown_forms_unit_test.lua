-- Unown letter forms: the id math, the baked per-letter assets (flat runtime sheets + True Size packs + geometry), the
-- geometry seam, and the sprite pipeline handing the form to the HGSS/PokeMMO provider.
-- Run: lua tests/unown_forms_unit_test.lua
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

-- Unown only exists in Gold: the geometry cap (Gen 2 adapter: 251) is what lets dex 201 through normalizeDex.
package.loaded["src.core.GameVersion"] = {
  get = function() return "gold" end,
  isYellow = function() return false end,
  isGold = function() return true end,
  generation = function() return 2 end,
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
}
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
modules.config = { dynScaleEnabled = function() return true end }

local Forms = V.require("unown_forms")

-- ------------------------------------------------------------------ id math
eq(Forms.formForLetter(1), nil, "letter A has no form: it is the base art")
eq(Forms.formForLetter(2), 1, "letter B is form 1 (file suffix -01)")
eq(Forms.formForLetter(26), 25, "letter Z is form 25 (file suffix -25)")
eq(Forms.formForLetter(27), nil, "no form past Z (Gold has no ! or ?)")
eq(Forms.formForLetter(0), nil, "no form for letter 0")
eq(Forms.formForLetter(nil), nil, "no form for nil")
eq(Forms.letterForForm(1), 2, "form 1 is letter B")
eq(Forms.letterForForm(25), 26, "form 25 is letter Z")
eq(Forms.letterForForm(26), nil, "form 26 does not exist")
for letter = 2, 26 do
  eq(Forms.letterForForm(Forms.formForLetter(letter)), letter, "letter " .. letter .. " round-trips through its form")
end
eq(Forms.assetId(1), 60001, "form 1 is asset 60001")
eq(Forms.assetId(25), 60025, "form 25 is asset 60025")
eq(Forms.assetId(26), nil, "no asset for form 26")
check(Forms.isFormId(60001) and Forms.isFormId(60025), "60001..60025 are form ids")
check(not Forms.isFormId(60000) and not Forms.isFormId(60026) and not Forms.isFormId(201) and not Forms.isFormId(50248),
  "real species and dex-expansion forms are never form ids")
eq(Forms.baseId(60007), 201, "a form is sized like Unown (201)")
eq(Forms.baseId(25), 25, "any other id passes through")
eq(Forms.formAssetId(201, 3), 60003, "Unown wearing form 3 -> asset 60003")
eq(Forms.formAssetId(25, 3), nil, "a non-Unown never takes a letter")
eq(Forms.formAssetId(201, nil), nil, "no form -> base art")

-- ------------------------------------------------------------------ baked assets
local TS = "assets/wilds_generated/true_size/hgss/"
local RT = "assets/wilds_generated/followsprites_runtime/"
local manifest = assert(V.require("json_decode").decode(assert(mod.read(nil, RT .. "manifest.json"))))
local missing = {}
for form = 1, Forms.FORM_COUNT do
  local id = Forms.assetId(form)
  for _, variant in ipairs({ "normal", "shiny" }) do
    if not fileExists(string.format("%s%d-%s.png", RT, id, variant)) then missing[#missing + 1] = "runtime " .. id .. "-" .. variant end
    if not fileExists(string.format("%s%d-%s.png", TS, id, variant)) then missing[#missing + 1] = "true_size " .. id .. "-" .. variant end
    local entry = manifest.sheets[id .. ":" .. variant]
    if not (entry and entry.path == string.format("%s%d-%s.png", RT, id, variant)) then missing[#missing + 1] = "manifest " .. id .. ":" .. variant end
  end
  -- the art each letter is baked from exists (the base file is letter A; -NN are B..Z)
  if not fileExists(string.format("assets/enhanced_overworld/followsprites/201-b-n-%02d.png", form)) then
    missing[#missing + 1] = "source " .. form
  end
end
check(#missing == 0, "every letter B..Z has runtime + True Size sheets (normal and shiny), manifest entries and source art"
  .. (#missing > 0 and (": " .. table.concat(missing, ", ")) or ""))
check(fileExists(RT .. "201-normal.png") and fileExists(TS .. "201-normal.png"), "letter A keeps the base Unown sheets")

-- ------------------------------------------------------------------ geometry seam
local SG = V.require("species_geometry")
eq(SG.normalizeDex(60003, nil), 60003, "a form id survives normalizeDex (it is above every species cap)")
eq(SG.normalizeDex(60026, nil), nil, "an id past the forms does not")
local base = select(1, SG.packGeometry(201, "pokemmo", mod))
local form = select(1, SG.packGeometry(60003, "pokemmo", mod))
check(base ~= nil and form ~= nil, "geometry exists for Unown and for a letter form")
check(form and base and form.frameWidth == base.frameWidth and form.frameHeight == base.frameHeight,
  "a letter form is baked on the same frame as Unown")
eq(select(1, SG.relativePath(60003, "pokemmo", "normal", mod)), TS .. "60003-normal.png", "True Size path of a form")
eq(select(1, SG.relativePath(60003, "pokemmo", "shiny", mod)), TS .. "60003-shiny.png", "True Size shiny path of a form")
for form_ = 1, Forms.FORM_COUNT do
  if not SG.packGeometry(Forms.assetId(form_), "pokemmo", mod) then
    check(false, "geometry entry for form " .. form_)
  end
end
eq(SG.displayScale(60003, "pokemmo"), SG.displayScale(201, "pokemmo"), "a letter shares Unown's display scale")
check(SG.displayScale(201, "pokemmo") ~= 1, "and that scale is Unown's tuned one, not 1 (the alias is doing something)")
eq(SG.displayScale(60003, "followers"), 1, "non-True-Size styles stay at scale 1")

-- ------------------------------------------------------------------ provider + resolver hand the form through
package.preload["src.render.Assets"] = function() return { exists = function() return false end } end
modules.config = {
  DEFAULTS = { sprite_style = "followers", use_animated_overworld_sprites = true, grass_occlusion_px = 6, min_sprite_size = 16 },
  dynScaleEnabled = function() return true end,
  spriteStyle = function() return "pokemmo" end,
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
check(render.runtimeSheets:load() == true, "runtime sheets load (with the letter forms in the manifest)")
local providers = assert(loadfile("lib/sprite_providers.lua"))(V).new(mod, render)
local game = { data = { pokemon = { UNOWN = { dex = 201 }, PIKACHU = { dex = 25 } } } }

local function image(style, species, variant, form_)
  local r = providers:resolve(style, species, variant, game, form_)
  return r and r.def and tostring(r.def.image) or nil, r
end
local img = image("pokemmo", "UNOWN", "normal", nil)
check(img and img:find("201-normal.png", 1, true), "Unown without a form uses the base sheet (letter A)")
img = image("pokemmo", "UNOWN", "normal", 6)
check(img and img:find("60006-normal.png", 1, true), "Unown form 6 (letter G) uses its own sheet: " .. tostring(img))
img = image("pokemmo", "UNOWN", "shiny", 6)
check(img and img:find("60006-shiny.png", 1, true), "and its shiny sheet: " .. tostring(img))
img = image("pokemmo", "UNOWN", "normal", 25)
check(img and img:find("60025-normal.png", 1, true), "letter Z (form 25) resolves")
img = image("pokemmo", "UNOWN", "normal", 26)
check(img and img:find("201-normal.png", 1, true), "a form past Z falls back to the base sheet")
img = image("pokemmo", 201, "normal", 3)
check(img and img:find("60003-normal.png", 1, true), "a numeric species id 201 takes the letter too")
img = image("pokemmo", "PIKACHU", "normal", 6)
check(img and img:find("025-normal.png", 1, true), "any other species ignores a form")
local _, followers = image("followers", "UNOWN", "normal", 6)
check(followers and followers.providerId == "followers_ex" and tostring(followers.def.image):find("follower_201", 1, true),
  "the Poke Followers / GSC style keeps its own single Unown sheet")

-- SpriteResolver: the entity's spriteForm reaches the provider (and shows in the cache key)
local recorded
local fakeProviders = {
  resolve = function(_, style, species, variant, gameArg, form_)
    recorded = { style = style, species = species, form = form_ }
    return { def = { image = "x.png", frames = 6, walker = true }, meta = {}, providerId = "pokemmo", steps = {} }
  end,
}
modules.surface = { GRASS = "GRASS", CAVE = "CAVE", WATER = "WATER", INTERIOR = "INTERIOR", OTHER = "OTHER_ENCOUNTER" }
modules.surface_state = { forEntity = function() return "land" end, isWaterEntity = function() return false end }
local okR, Resolver = pcall(function() return assert(loadfile("lib/sprite_resolver.lua"))(V) end)
if okR and Resolver and Resolver.new then
  local resolver = Resolver.new(mod, fakeProviders, nil)
  local entity = { species = "UNOWN", spriteForm = 4 }
  resolver:resolveLandSprite(entity, { style = "pokemmo", game = game })
  eq(recorded and recorded.form, 4, "SpriteResolver passes entity.spriteForm to the provider chain")
  local keyA = resolver:cacheKey({ species = "UNOWN", spriteForm = 4 }, { style = "pokemmo", game = game }, "land")
  local keyB = resolver:cacheKey({ species = "UNOWN", spriteForm = 5 }, { style = "pokemmo", game = game }, "land")
  local keyC = resolver:cacheKey({ species = "UNOWN" }, { style = "pokemmo", game = game }, "land")
  check(keyA ~= keyB and keyA ~= keyC, "different letters never share a cached SpriteDef")
  recorded = nil
  resolver:resolveLandSprite({ species = "UNOWN", spriteForm = "female" }, { style = "pokemmo", game = game })
  eq(recorded and recorded.form, nil, "a non-numeric form (gender) is not mistaken for a letter")
else
  print("skip: sprite_resolver needs more of the engine than this harness stubs (" .. tostring(Resolver) .. ")")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("unown_forms_unit_test: all passed")
