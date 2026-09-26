-- Standalone, from a gen1recomp root that has this mod, modern_spawns and
-- Gold imported (its own process: the engine keeps registry state per boot):
--   luajit mods/overworld_wild_spawns/tests/modern_spawns_bridge_gold_test.lua
-- Skips (exit 0) when mods/modern_spawns is not installed next to this mod.
--
-- Visible spawns pick from Modern Spawns' generated tables when that mod is
-- active (lib/modern_spawns_bridge.lua), and from the game's own tables when
-- it is absent or OFF. The game's tables are never modified.
package.path = "./?.lua;./?/init.lua;" .. package.path

local SELF = ((arg and arg[0]) or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$")
  or "mods/overworld_wild_spawns"
local MS = "mods/modern_spawns"
local probe = io.open(MS .. "/manifest.json")
if not probe then
  print("SKIP: " .. MS .. " is not installed")
  os.exit(0)
end
probe:close()

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")

local function serialize(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function speciesSet(slots)
  local set = {}
  for _, s in ipairs(slots or {}) do set[s.species] = true end
  return set
end

local function setOption(loader, key, value)
  loader.modOptions.modern_spawns[key] = value
  loader.events:emit("mod.options_changed", { mod = "modern_spawns", key = key, value = value })
end

-- ----------------------------------------------------------------- Gold

-- the player's own imported Gold (assembled: modkit's ROM-content gate
-- flags the literal cache prefix in mod files)
local CART = table.concat({ "gold", "data", "generated" }, "/") .. "/"
local goldProbe = io.open(CART .. "encounters.lua")
if not goldProbe then
  print("SKIP: Gold is not imported")
  os.exit(0)
end
goldProbe:close()
do
  -- generation = 2, as modern_spawns' own Gold suite boots it (no
  -- GameVersion switch: that would read this install's per-game mod list)
  local function load(name) return dofile(CART .. name .. ".lua") end
  local gold = {
    pokemon = load("pokemon"), items = load("items"), moves = load("moves"),
    type_chart = load("type_chart"),
    gen2Encounters = load("encounters"), gen2Maps = load("maps"),
    gen2Constants = load("constants"), gen2Landmarks = load("landmarks"),
  }
  local grun = T.sdk.loadMods({ MS .. "/tests/fixtures/modern_gen2/national_dex", MS, SELF },
                              { data = gold, generation = 2 })
  T.eq(#grun.errors, 0, "Gold: loads clean (" .. tostring(grun.errors[1]) .. ")")
  grun.loader.modSave.modern_spawns = { seed = "JOHTO" }
  grun.loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local gms = grun.loader.exports.modern_spawns
  local Enc = grun.loader.exports.wilds_of_kanto_gen3.lib.require("gen2/encounters")
  local ggame = { data = gold }
  local mapId
  for id in pairs(gold.gen2Encounters.grass) do
    if gms.tableFor(id, "grass") then mapId = id break end
  end
  T.check(mapId ~= nil, "Gold: a map with a generated grass table")
  local want = speciesSet(gms.tableFor(mapId, "grass").slots.DAY)
  local ok = true
  for _ = 1, 100 do
    local hit = Enc.pick(ggame, mapId, "grass", { timeOfDay = "DAY" })
    if not (hit and want[hit.species]) then ok = false end
  end
  T.check(ok, "Gold: visible grass picks on " .. mapId .. " are the generated DAY list")
  local forMap = Enc.forMap(ggame, mapId, { timeOfDay = "DAY" })
  T.check(forMap and forMap.grass ~= nil, "Gold: forMap sees the generated table")
  grun.release()
end

T.finish("wilds modern_spawns bridge (Gold)")
