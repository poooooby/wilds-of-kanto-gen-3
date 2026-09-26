-- Water Pokémon display modes unit tests.
-- Run: lua tests/water_display_modes_unit_test.lua
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
  sprite_style = "auto",
  spawn_density = "normal",
  random_encounters = true,
  water_spawns = nil,
}

local V = {
  mod = {
    id = "wilds_of_kanto_gen3",
    path = ".",
    log = { info = function() end, warn = function() end },
    options = {
      get = function(_, key) return savedOpts[key] end,
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
local Behavior = V.require("behavior")

-- ------- Schema: Water Mons is no longer an option -------
local schema = assert(loadfile("options.lua"))()
local byKey = {}
for _, row in ipairs(schema) do byKey[row.key] = row end
check(byKey.water_spawns == nil, "Water Mons is not a public option (locked Swim Sprites)")
check(byKey.random_encounters ~= nil, "Classic Encounters option present")
check(byKey.wild_silhouettes ~= nil, "Silhouette option present")

-- ------- Locked water display -------
for _, saved in ipairs({ "classic_encounters", "disabled", "silhouettes", "hidden_silhouettes", false }) do
  savedOpts.water_spawns = saved
  eq(Config.waterDisplayMode(V.mod), "swimming_sprites", "saved " .. tostring(saved) .. " ignored")
  check(Config.waterMons(V.mod) == true, "water wilds spawn with saved " .. tostring(saved))
end
savedOpts.water_spawns = nil
check(WaterDisplay.isSwimmingSprites(V.mod), "WaterDisplay swimming")
check(not WaterDisplay.isSilhouettes(V.mod), "water-only Silhouettes mode gone")
check(not WaterDisplay.isHiddenSilhouettes(V.mod), "water-only Hidden Silhouette mode gone")
check(Config.setWaterMons == nil, "no Water Mons setter")

-- ------- Terrain helpers -------
check(WaterDisplay.isWaterTerrain({ terrain = "water" }), "terrain water")
check(WaterDisplay.isWaterTerrain({ terrain = "fishing" }), "terrain fishing")
check(WaterDisplay.isWaterTerrain({ terrain = "SURF" }), "terrain SURF")
check(not WaterDisplay.isWaterTerrain({ terrain = "grass" }), "terrain grass false")
check(not WaterDisplay.isWaterTerrain({ terrain = "cave" }), "terrain cave false")

check(WaterDisplay.isWaterEntity({ surface = "WATER" }), "entity surface WATER")
check(WaterDisplay.isWaterEntity({ behavior = Behavior.WATER_IDLE }), "entity WATER_IDLE")
check(not WaterDisplay.isWaterEntity({ surface = "GRASS", behavior = Behavior.IDLE_LOOK }),
      "land entity not water")

-- ------- Silhouette tint / proximity -------
local farEnt = { cellX = 10, cellY = 10, surface = "WATER", overworldWildSpawn = true, species = "MAGIKARP" }
local nearEnt = { cellX = 5, cellY = 5, surface = "WATER" }
local player = { cellX = 5, cellY = 5 }
local farB = WaterDisplay.proximityBrightness(farEnt, player)
local nearB = WaterDisplay.proximityBrightness(nearEnt, player)
check(farB <= 1.05, "far brightness ~1")
check(nearB > farB, "near brighter than far")
check(nearB <= (WaterDisplay.SILHOUETTE.nearBright or 1.85) + 0.01,
      "near brightness capped")

local r, g, b, a = WaterDisplay.silhouetteColor(farEnt, player)
check(r < 0.2 and g < 0.25 and b < 0.3, "far tint is dark")
check(a >= 0.75 and a <= 0.90, "alpha in 75–90%")
local r2, g2, b2 = WaterDisplay.silhouetteColor(nearEnt, player)
check(r2 >= r and g2 >= g and b2 >= b, "near tint not darker than far")
check(r2 < 0.4 and g2 < 0.45, "near still detail-free / dark")

-- ------- One Silhouette option: water silhouette only for wilds standing in water -------
savedOpts.wild_silhouettes = "off"
eq(WaterDisplay.silhouetteSink(V.mod, farEnt), 0, "Silhouette OFF: no sink")
check(not WaterDisplay.wantsWaterSilhouette(V.mod, farEnt), "Silhouette OFF: no water silhouette")
savedOpts.wild_silhouettes = "all"
check(WaterDisplay.wantsWaterSilhouette(V.mod, farEnt), "Silhouette ALL: water wild -> water silhouette")
eq(WaterDisplay.silhouetteSink(V.mod, farEnt), 3, "water silhouette sits 3px deeper (Flat)")
eq(WaterDisplay.silhouetteSink(V.mod, nil), 0, "no entity -> no sink")
local landWild = { surface = "GRASS", overworldWildSpawn = true, species = "PIDGEY" }
check(not WaterDisplay.wantsWaterSilhouette(V.mod, landWild),
      "land wild gets the land silhouette, never the water one")
eq(WaterDisplay.silhouetteSink(V.mod, landWild), 0, "land wild never gets the water sink")
local shoreWild = { surface = "GRASS", originSurface = "WATER", behavior = Behavior.WATER_WANDER,
                    overworldWildSpawn = true, species = "PSYDUCK" }
check(not WaterDisplay.wantsWaterSilhouette(V.mod, shoreWild),
      "water-origin wild standing on land is judged by where it is now (land)")
local nowInWater = { spriteState = "water", overworldWildSpawn = true, species = "PSYDUCK" }
check(WaterDisplay.wantsWaterSilhouette(V.mod, nowInWater), "spriteState water counts as in water")
check(not WaterDisplay.wantsWaterSilhouette(V.mod, { surface = "WATER", species = "PSYDUCK" }),
      "follower (not a wild spawn) in water: no silhouette")
check(not WaterDisplay.wantsWaterSilhouette(V.mod,
        { surface = "WATER", overworldWildSpawn = true, wildsAmbientPokemon = true, species = "PSYDUCK" }),
      "Town Pokemon: no silhouette")
check(WaterDisplay.needsOverlayPresentation(V.mod, farEnt) == false,
      "silhouettes do not force overlay (native sheets in Voxel)")
check(WaterDisplay.needsNativeSilhouetteSheet(V.mod, farEnt) == true,
      "Voxel water silhouette uses the native water sheet")
check(WaterDisplay.needsNativeHiddenShadow(V.mod, farEnt) == false,
      "no hidden-circle water marker")
savedOpts.wild_silhouettes = "off"

-- ------- shouldSuppressClassicEncounter: one Classic Encounters option for grass and water -------
local SpawnLogic = V.require("spawn_logic")
local logic = {
  mod = V.mod,
  activeMapId = "ROUTE_19",
}
local suppress = SpawnLogic.shouldSuppressClassicEncounter

-- Mock Safari off by ensuring no safari map helpers trip; use empty world.
V.mod.world.overworld = function()
  return { map = { id = "ROUTE_19" }, player = player }
end

savedOpts.random_encounters = false
for _, terrain in ipairs({ "grass", "cave", "water", "fishing" }) do
  check(suppress(logic, { terrain = terrain, mapId = "ROUTE_19" }) == true,
        "Classic Enc OFF suppresses " .. terrain)
end
savedOpts.random_encounters = true
for _, terrain in ipairs({ "grass", "cave", "water", "fishing" }) do
  check(suppress(logic, { terrain = terrain, mapId = "ROUTE_19" }) == false,
        "Classic Enc ON allows " .. terrain)
end
-- A leftover saved Water Mons mode no longer overrides Classic Encounters for water.
savedOpts.water_spawns = "classic_encounters"
savedOpts.random_encounters = false
check(suppress(logic, { terrain = "water", mapId = "ROUTE_19" }) == true,
      "saved classic_encounters water mode no longer forces water rolls on")
savedOpts.water_spawns = "disabled"
savedOpts.random_encounters = true
check(suppress(logic, { terrain = "water", mapId = "ROUTE_19" }) == false,
      "saved disabled water mode no longer blocks water rolls")
savedOpts.water_spawns = nil

-- ------- Menu -------
local SpriteStyleMenu = assert(loadfile("lib/sprite_style_menu.lua"))(V)
check(SpriteStyleMenu.WATER_CHOICES == nil, "no Water Mons menu choices")

-- ------- Label validator -------
local okPy = dofile("tests/_shell.lua").pythonFile("tools/validate_option_labels.py")
check(okPy, "validate_option_labels passes")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all water_display_modes unit tests passed")
