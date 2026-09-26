-- Voxel water-shadow presentation unit tests (no Gen1Recomp / DS required).
-- Run: luajit tests/water_shadow_unit_test.lua
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

local savedOpts = {
  sprite_style = "pokemmo",
  water_spawns = "swimming_sprites",
}

local V = {
  mod = {
    id = "wilds_of_kanto_gen3",
    path = ".",
    log = { info = function() end, warn = function() end },
    options = {
      get = function(_, key) return savedOpts[key] end,
    },
    assets = {
      path = function(_, rel) return "mods/wilds_of_kanto_gen3/" .. rel end,
    },
    read = function(_, rel)
      local f = io.open(rel, "rb") or io.open("./" .. rel, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    world = {
      game = {
        save = { options = { modOptions = { wilds_of_kanto_gen3 = savedOpts } } },
        mods = { modOptions = { wilds_of_kanto_gen3 = savedOpts } },
      },
      overworld = function()
        return { cameraMode = "FLAT", player = { cellX = 1, cellY = 1 } }
      end,
    },
  },
  path = ".",
}

local modules = {}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local Config = V.require("config")
local WaterDisplay = V.require("water_display")
local WaterShadowRenderer = V.require("water_shadow_renderer")
local SpriteResolver = V.require("sprite_resolver")

-- Asset
local asset = WaterShadowRenderer.HIDDEN_RELATIVE
local f = io.open(asset, "rb")
check(f ~= nil, "hidden-water-shadow.png exists")
if f then
  local data = f:read("*a")
  f:close()
  check(data:sub(1, 8) == "\137PNG\r\n\26\n", "asset is PNG")
  -- IHDR width/height
  local w = data:byte(17) * 16777216 + data:byte(18) * 65536
    + data:byte(19) * 256 + data:byte(20)
  local h = data:byte(21) * 16777216 + data:byte(22) * 65536
    + data:byte(23) * 256 + data:byte(24)
  eq(w, 16, "asset width 16")
  eq(h, 96, "asset height 96 (6×16)")
end

local def = WaterShadowRenderer.hiddenDef(V.mod)
eq(def.frames, 6, "hidden def frames=6")
check(def.walker == true, "hidden def walker")
check(WaterShadowRenderer.isWaterShadowDef(def), "hidden def tagged")
eq(def[WaterShadowRenderer.DEF_KIND], "hidden", "hidden kind")
eq(WaterShadowRenderer.sinkFor(def), WaterShadowRenderer.HIDDEN_SINK, "hidden sink")

local silDef = WaterShadowRenderer.tagDef({
  image = "assets/wilds_generated/swimming_silhouette_runtime/054-normal.png",
  frames = 6, walker = true, trueColor = true,
}, "silhouette")
check(WaterShadowRenderer.isWaterShadowDef(silDef), "silhouette def tagged")
eq(WaterShadowRenderer.sinkFor(silDef), WaterShadowRenderer.SILHOUETTE_SINK,
   "silhouette sink")

local waterEnt = { surface = "WATER", behavior = "WATER_IDLE", overworldWildSpawn = true, species = "PSYDUCK" }
eq(WaterShadowRenderer.shadowModeFor(V.mod, waterEnt, false),
   WaterShadowRenderer.MODE.NONE, "flat → no shadow mode")
savedOpts.wild_silhouettes = "all"
eq(WaterShadowRenderer.shadowModeFor(V.mod, waterEnt, true),
   WaterShadowRenderer.MODE.FLAT_WORLD, "voxel water silhouette → flat_world")
savedOpts.wild_silhouettes = "off"
eq(WaterShadowRenderer.shadowModeFor(V.mod, waterEnt, true),
   WaterShadowRenderer.MODE.NONE, "voxel, Silhouette OFF → none")
savedOpts.water_spawns = "hidden_silhouettes"
eq(WaterShadowRenderer.shadowModeFor(V.mod, waterEnt, true),
   WaterShadowRenderer.MODE.NONE, "a leftover saved hidden_silhouettes mode does nothing")
savedOpts.water_spawns = "swimming_sprites"

-- Flat 2D presentation helpers
check(WaterDisplay.needsOverlayPresentation(V.mod, waterEnt) == false,
      "no emergency overlay")
check(WaterDisplay.useNativeHiddenShadow(V.mod, waterEnt, true) == false,
      "no hidden-circle marker (mode removed)")
savedOpts.wild_silhouettes = "all"
eq(WaterDisplay.silhouetteSink(V.mod, waterEnt), 3, "flat water silhouette sink")
eq(WaterDisplay.silhouetteSink(V.mod, { surface = "WATER", overworldWildSpawn = true,
                                        species = "PSYDUCK", waterSilhouetteSheet = true }),
   0, "native sheet skips runtime sink")

-- Resolver: Voxel water silhouette serves the pre-baked silhouette sheet
local RuntimeSheets = V.require("runtime_sheets")
local render = { runtimeSheets = RuntimeSheets.new(V.mod) }
render.runtimeSheets:load()
local SpriteProviders = V.require("sprite_providers")
local providers = SpriteProviders.new(V.mod, render)
local WaterSpriteRegistry = V.require("water_sprite_registry")
local reg = WaterSpriteRegistry.new(V.mod)
reg:load()
local resolver = SpriteResolver.new(V.mod, providers, reg)

local silo = resolver:resolveWaterSprite(waterEnt, {
  style = "pokemmo", speciesId = 54, variant = "normal", voxelActive = true,
})
check(silo ~= nil and silo.def ~= nil, "voxel water silhouette resolves")
if silo and silo.def then
  check(silo.waterSilhouetteSheet == true, "voxel water silhouette uses the native sheet")
  check(silo.def.image:find("silhouette_runtime", 1, true) ~= nil, "image is a water silhouette sheet")
  eq(silo.waterSilhouette, true, "flagged as water silhouette")
end
local flat = resolver:resolveWaterSprite(waterEnt, {
  style = "pokemmo", speciesId = 54, variant = "normal", voxelActive = false,
})
check(flat ~= nil and flat.def ~= nil and flat.waterSilhouetteSheet ~= true,
      "flat water silhouette keeps the colour sheet (tinted at draw)")
check(flat == nil or flat.providerId ~= "water_hidden_shadow", "flat never binds the hidden marker")

-- Cache key includes shadow mode + voxel
local keyFlat = resolver:cacheKey(waterEnt, {
  style = "pokemmo", speciesId = 54, variant = "normal", form = nil,
  voxelActive = false,
}, "water")
local keyVoxel = resolver:cacheKey(waterEnt, {
  style = "pokemmo", speciesId = 54, variant = "normal", form = nil,
  voxelActive = true,
}, "water")
check(keyFlat ~= keyVoxel, "flat/voxel cache keys differ")
check(keyVoxel:find("flat_world", 1, true) ~= nil, "voxel key includes shadow mode")
savedOpts.wild_silhouettes = "off"
local keyOff = resolver:cacheKey(waterEnt, {
  style = "pokemmo", speciesId = 54, variant = "normal", form = nil,
  voxelActive = true,
}, "water")
check(keyOff ~= keyVoxel, "Silhouette OFF/ALL cache keys differ")

-- Tilt / pivot constants
check(WaterShadowRenderer.FLAT_TILT_RAD > math.rad(70)
      and WaterShadowRenderer.FLAT_TILT_RAD < math.rad(90),
      "tilt between 70° and 90°")
check(WaterShadowRenderer.HIDDEN_SINK >= 1 and WaterShadowRenderer.HIDDEN_SINK <= 2,
      "hidden sink 1–2 px")
check(WaterShadowRenderer.SILHOUETTE_SINK >= 2 and WaterShadowRenderer.SILHOUETTE_SINK <= 3,
      "silhouette sink 2–3 px")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all water_shadow unit tests passed")
