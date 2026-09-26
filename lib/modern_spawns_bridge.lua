-- Modern Spawns bridge: visible spawns pick from the tables Modern Spawns
-- generated, when that mod is installed and active.
--
-- Wilds suppresses the engine's step encounters and picks visible species
-- straight from the encounter tables, so Modern Spawns' encounter hooks never
-- run for them. Modern Spawns never rewrites game.data.encounters either; it
-- publishes its tables instead (mod.exports.tableFor / drawFor, in each
-- game's own shape). Every raw-table read in Wilds goes through here, so a
-- map's visible Pokemon are the species Modern Spawns would roll there.
--
-- Soft integration: no dependency. Absent, OFF, GEN 1 or no table for a map
-- -> the raw table passes through untouched.
local V = ...

local Bridge = {}

-- The Modern Spawns exports when installed and active, else nil.
function Bridge.api()
  local mod = V.mod
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, other = pcall(mod.find, mod, "modern_spawns")
  local api = ok and other and other.exports
  if type(api) ~= "table" or (tonumber(api.apiVersion) or 0) < 1 then return nil end
  local okActive, active = pcall(api.isActive)
  if not (okActive and active) then return nil end
  return api
end

local function generation(api)
  local ok, gen = pcall(api.generation)
  return ok and gen or nil
end

-- One generated table for a map/terrain in the running game's shape, or nil.
-- drawFor (Modern Spawns 0.7.0+) answers RANDOM with a fresh draw per call; `fixed`
-- asks for the fixed table only (tableFor: nil under RANDOM), for reads that
-- walk every map at once rather than pick one spawn.
function Bridge.table(mapId, terrain, fixed)
  local api = mapId ~= nil and Bridge.api() or nil
  if not api then return nil end
  local fn = (not fixed and api.drawFor) or api.tableFor
  local ok, t = pcall(fn, mapId, terrain)
  if ok and type(t) == "table" and type(t.slots) == "table" then return t end
  return nil
end

-- Gen 1 per-map definition { grass, water, ... } with Modern Spawns' tables
-- in place of the game's. The raw table itself is never modified.
function Bridge.gen1Def(mapId, raw, fixed)
  local api = Bridge.api()
  if not api or generation(api) ~= 1 then return raw end
  local grass = raw and raw.grass and Bridge.table(mapId, "grass", fixed)
  local water = raw and raw.water and Bridge.table(mapId, "water", fixed)
  if not (grass or water) then return raw end
  local def = {}
  for k, v in pairs(raw) do def[k] = v end
  if grass then def.grass = grass end
  if water then def.water = water end
  return def
end

-- Gen 2 kind-first tables { grass = {[mapId]=...}, water = {...} } whose
-- per-map entries answer from Modern Spawns first. A read-only view: the
-- engine's own Encounter.grassSlot / waterSlot index it unchanged. `cart` is
-- the game's own tables: an entry that differs from the cart's (an active
-- swarm swapped in) is kept, as Modern Spawns does for step encounters.
local function kindView(rawKind, cartKind, terrain)
  return setmetatable({}, {
    __index = function(_, mapId)
      local base = rawKind and rawKind[mapId]
      if base == nil then return nil end
      if cartKind and cartKind[mapId] ~= base then return base end
      return Bridge.table(mapId, terrain) or base
    end,
    __pairs = function() return pairs(rawKind or {}) end,
  })
end

function Bridge.gen2Tables(raw, cart)
  if type(raw) ~= "table" then return raw end
  local api = Bridge.api()
  if not api or generation(api) ~= 2 then return raw end
  cart = type(cart) == "table" and cart or raw
  return setmetatable({
    grass = kindView(raw.grass, cart.grass, "grass"),
    water = kindView(raw.water, cart.water, "water"),
  }, { __index = raw })
end

-- Gen 1 Super Rod group for a map: Modern Spawns' catches, or the raw group.
function Bridge.superRod(mapId, raw)
  local api = mapId ~= nil and Bridge.api() or nil
  if not api or generation(api) ~= 1 or type(api.superRodFor) ~= "function" then
    return raw
  end
  local ok, group = pcall(api.superRodFor, mapId)
  if ok and type(group) == "table" and #group > 0 then return group end
  return raw
end

-- The LEGENDARIES roll for one visible spawn: a species id or nil
-- (Modern Spawns 0.7.0+; nil on older versions or with LEGENDARIES OFF).
function Bridge.legendary(mapId, terrain)
  local api = mapId ~= nil and Bridge.api() or nil
  if not (api and type(api.legendaryFor) == "function") then return nil end
  local ok, id = pcall(api.legendaryFor, mapId, terrain or "grass")
  return ok and type(id) == "string" and id or nil
end

return Bridge
