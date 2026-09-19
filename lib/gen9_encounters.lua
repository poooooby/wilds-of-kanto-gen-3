-- Gen 1 wild-table seam. MODERN SPAWNS has three modes (Config.modernSpawnsMode):
--
--   "table"  Modern ("Gen 9") Kanto overlay: replaces the slots of mapped Gen 1 maps with the
--            generated table in gen9_encounters_data.lua (tools/generate_gen9_encounters.py), but
--            only when the runtime dex is actually expanded (DexExpansion.hasModernSpecies).
--            Per-slot, a species that isn't registered falls back to a vanilla slot (see below),
--            so nothing can reference a missing species (the engine's newWild has no guard against
--            a bad species id).
--   "random" Any registered species at the area's level (lib/random_spawns.lua), for EVERY map with
--            a vanilla table, on the vanilla ladder (<= 10 species per bucket, like the engine and
--            Kanto Reforged). No dex gate. The area's level spread comes from the Spawn Table
--            overlay where one applies, vanilla elsewhere. The roster is drawn once per map entry
--            (DexExpansion.invalidate() bumps the epoch) and stays fixed for that visit.
--   "off"    Original tables (this module returns the vanilla object untouched).
--
-- Every result is a COPY: the engine's live game.data.encounters[mapId] is never mutated (the
-- classic roll and other mods keep seeing the vanilla object unless it is routed through here).
-- Only buckets the vanilla table already has are replaced, and the engine's `rate` is preserved.
--
-- Data version 2: grass/water carry their own cumulative `buckets` ladder (any length, ending in
-- 256) with one slot per (species, level). Encounter.roll and EncounterPick both honor a per-bucket
-- `buckets`, so the copy gets the overlay's ladder and slots together. A slot whose species isn't
-- registered is replaced by the vanilla slot at the same PROBABILITY POSITION (the midpoint of the
-- overlay slot's odds interval looked up on the vanilla ladder), since slot indexes no longer line up.
local V = ...

local Gen9Encounters = {}

local DexExpansion = V.require("dex_expansion")
local RandomSpawns = V.require("random_spawns")

local dataModule
local function data()
  if dataModule == nil then
    local ok, t = pcall(function() return V.require("gen9_encounters_data") end)
    dataModule = (ok and type(t) == "table" and t.version == 2 and type(t.maps) == "table") and t or false
  end
  return dataModule or nil
end

local function gameOf(mod)
  return mod and (mod.game or (mod.world and mod.world.game)) or nil
end

local function configOf()
  local ok, Config = pcall(function() return V.require("config") end)
  return ok and Config or nil
end

--- "table" | "random" | "off". Fails closed: if the option can't be read for any reason, "off".
function Gen9Encounters.mode(mod, game)
  if not mod then return "off" end
  local Config = configOf()
  if not (Config and type(Config.modernSpawnsMode) == "function") then return "off" end
  local ok, mode = pcall(Config.modernSpawnsMode, mod)
  if ok and (mode == "table" or mode == "random") then return mode end
  return "off"
end

local function legendaryEnabled(mod)
  local Config = configOf()
  if not (Config and type(Config.legendarySpawnsEnabled) == "function") then return false end
  local ok, on = pcall(Config.legendarySpawnsEnabled, mod)
  return ok and on == true
end

-- Spawn Table prerequisites (independent of the mode): generated data present and a real Gen 4+
-- species registered. Random mode reuses this only to pick its level source.
local function tableAvailable(mod, game)
  return game ~= nil and data() ~= nil and DexExpansion.hasModernSpecies(mod, game)
end

--- Master gate. "table": generated data + expanded dex. "random": always (any registered species).
-- Callers must already know the game is Gen 1 (the Gen 1 adapter / Gen-1-checked hooks).
function Gen9Encounters.active(mod, game)
  game = game or gameOf(mod)
  if not game then return false end
  local mode = Gen9Encounters.mode(mod, game)
  if mode == "random" then return true end
  return mode == "table" and tableAvailable(mod, game)
end

-- A usable overlay bucket: one slot per threshold, strictly increasing integer thresholds ending
-- in exactly 256, and every slot a { level, species }. Anything else fails closed to vanilla.
local ladderValid = setmetatable({}, { __mode = "k" })
local function validLadder(b)
  if type(b) ~= "table" then return false end
  local known = ladderValid[b]
  if known ~= nil then return known end
  local ok = false
  if type(b.buckets) == "table" and type(b.slots) == "table" then
    local n = #b.buckets
    ok = n > 0 and n <= 256 and n == #b.slots
    local prev = 0
    for i = 1, ok and n or 0 do
      local thr, s = b.buckets[i], b.slots[i]
      if type(thr) ~= "number" or thr <= prev or thr % 1 ~= 0
         or type(s) ~= "table" or type(s.species) ~= "string" or type(s.level) ~= "number" then
        ok = false
        break
      end
      prev = thr
    end
    ok = ok and prev == 256
  end
  ladderValid[b] = ok
  return ok
end

local defaultBuckets
local function vanillaLadder(bucket)
  if type(bucket.buckets) == "table" and #bucket.buckets > 0 then return bucket.buckets end
  if defaultBuckets == nil then
    local Config = configOf()
    defaultBuckets = (Config and Config.ENCOUNTER_BUCKETS)
      or { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
  end
  return defaultBuckets
end

-- The vanilla slot the engine would pick at probability position `pos` (0..255.x), i.e. the first
-- slot whose cumulative threshold is above it (Encounter.roll: `pick < threshold`).
local function vanillaSlotAt(bucket, pos)
  local slots = bucket.slots
  for i, thr in ipairs(vanillaLadder(bucket)) do
    if pos < thr then return slots[i] or slots[#slots] end
  end
  return slots[#slots]
end

local overlayCache = {} -- mapId -> { epoch, mode, legend, vanilla, result }
local rodCache = {}     -- mapId -> { epoch, legend, size, result }

--- Drop cached overlays and re-evaluate the dex gate (mods.loaded / game.ready / map entry).
-- Random rosters are redrawn because they are cached per epoch.
function Gen9Encounters.invalidate()
  DexExpansion.invalidate()
  overlayCache = {}
  rodCache = {}
end

local function deepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[k] = deepCopy(v, seen) end
  return out
end

--- Spawn Table copy of `vanilla` for a mapped map, or nil when the table doesn't apply here (no
-- data, no expanded dex, unmapped, or no overlay species registered). Uncached; no mode check.
local function tableOverlay(mod, game, mapId, vanilla)
  if not tableAvailable(mod, game) then return nil end
  local m = data().maps[mapId]
  if not (m and (m.grass or m.water)) then return nil end

  local out = deepCopy(vanilla)
  local changed = false
  for _, kind in ipairs({ "grass", "water" }) do
    local bucket, src = out[kind], m[kind]
    if type(bucket) == "table" and type(bucket.slots) == "table" and #bucket.slots > 0
       and validLadder(src) then
      local vanillaBucket = vanilla[kind]
      local slots, prev, any = {}, 0, false
      for i, thr in ipairs(src.buckets) do
        local s = src.slots[i]
        if DexExpansion.speciesRegistered(mod, game, s.species) then
          slots[i] = { level = s.level, species = s.species }
          any = true
        else
          local v = vanillaSlotAt(vanillaBucket, (prev + thr) / 2)
          slots[i] = { level = v.level, species = v.species }
        end
        prev = thr
      end
      if any then
        local ladder = {}
        for i, thr in ipairs(src.buckets) do ladder[i] = thr end
        bucket.slots = slots
        bucket.buckets = ladder
        changed = true
      end
    end
  end
  return changed and out or nil
end

--- Random copy of `vanilla`: every grass/water bucket the vanilla table has becomes a random
-- bucket on the vanilla ladder (<= 10 slots, so <= 10 species) with the level spread of `base`
-- (the Spawn Table overlay, else vanilla).
local function randomOverlay(mod, game, vanilla, base, includeRestricted)
  local pool = RandomSpawns.pool(mod, game, includeRestricted, DexExpansion.epoch())
  if #pool == 0 then return nil end

  local out = deepCopy(vanilla)
  local changed = false
  for _, kind in ipairs({ "grass", "water" }) do
    local bucket, from = out[kind], base[kind]
    if type(bucket) == "table" and type(bucket.slots) == "table" and #bucket.slots > 0
       and type(from) == "table" then
      local rb = RandomSpawns.bucket(from, pool, nil, vanillaLadder(vanilla[kind]))
      if rb then
        bucket.slots = rb.slots
        bucket.buckets = rb.buckets
        changed = true
      end
    end
  end
  return changed and out or nil
end

--- Encounter table to use for `mapId`. Returns the SAME vanilla object when the mode is off, the
-- overlay doesn't apply (Spawn Table: unmapped map / no expanded dex), or nothing could be drawn;
-- otherwise a cached COPY (never the engine's own table).
function Gen9Encounters.overlayFor(mod, game, mapId, vanilla)
  if type(vanilla) ~= "table" or type(mapId) ~= "string" then return vanilla end
  game = game or gameOf(mod)
  if not game then return vanilla end
  local mode = Gen9Encounters.mode(mod, game)
  if mode == "off" then return vanilla end
  if mode == "table" and not tableAvailable(mod, game) then return vanilla end

  local epoch = DexExpansion.epoch()
  local legend = mode == "random" and legendaryEnabled(mod) or false
  local c = overlayCache[mapId]
  if c and c.epoch == epoch and c.mode == mode and c.legend == legend and c.vanilla == vanilla then
    return c.result
  end

  local result
  if mode == "table" then
    result = tableOverlay(mod, game, mapId, vanilla)
  else
    local base = tableOverlay(mod, game, mapId, vanilla) or vanilla
    result = randomOverlay(mod, game, vanilla, base, legend)
  end
  result = result or vanilla
  overlayCache[mapId] = { epoch = epoch, mode = mode, legend = legend, vanilla = vanilla, result = result }
  return result
end

--- Table for the engine's classic `encounter.roll` hook. The engine passes the map's own table
-- for grass/indoor(cave) rolls but a SYNTHETIC `{ grass = mapTable.water }` for water rolls
-- (OverworldController:onStepComplete), and Encounter.roll only ever reads `.grass`. So the
-- substitution is terrain-aware, and only happens when the incoming table is exactly the
-- engine's vanilla structure (never clobbers a table another mod already replaced).
function Gen9Encounters.rollDef(mod, game, mapId, terrain, encDef)
  if type(encDef) ~= "table" or type(mapId) ~= "string" then return encDef end
  game = game or gameOf(mod)
  local encounters = game and game.data and game.data.encounters
  local real = type(encounters) == "table" and encounters[mapId] or nil
  if type(real) ~= "table" then return encDef end
  local overlay = Gen9Encounters.overlayFor(mod, game, mapId, real)
  if overlay == real then return encDef end
  if terrain == "water" then
    if real.water ~= nil and encDef.grass == real.water and type(overlay.water) == "table" then
      return { grass = overlay.water }
    end
    return encDef
  end
  if encDef == real then return overlay end
  return encDef
end

-- Spawn Table Super Rod group for a mapped map with a vanilla group, else `vanillaPool`.
-- Unregistered entries fall back to the vanilla entry at the same index.
local function tableRod(mod, game, mapId, vanillaPool)
  if not tableAvailable(mod, game) then return vanillaPool end
  local m = data().maps[mapId]
  local src = m and m.superRod
  if type(src) ~= "table" then return vanillaPool end
  local out = {}
  for i, s in ipairs(src) do
    if DexExpansion.speciesRegistered(mod, game, s.species) then
      out[#out + 1] = { level = s.level, species = s.species }
    elseif vanillaPool[i] ~= nil then
      out[#out + 1] = vanillaPool[i]
    end
  end
  if #out == 0 then return vanillaPool end
  return out
end

--- Super Rod candidate list for `mapId` (engine group: <= 4 entries, picked uniformly). Only the
-- Super Rod is overlaid, and only where the vanilla map already has a group ("nothing here" maps
-- stay that way). Random mode redraws the species (levels follow the Spawn Table / vanilla group)
-- and keeps the draw for the rest of the visit.
function Gen9Encounters.fishingPool(mod, game, mapId, rod, vanillaPool)
  if rod ~= "SUPER_ROD" then return vanillaPool end
  if type(vanillaPool) ~= "table" or #vanillaPool == 0 then return vanillaPool end
  game = game or gameOf(mod)
  if not game then return vanillaPool end
  local mode = Gen9Encounters.mode(mod, game)
  if mode == "off" then return vanillaPool end
  if mode == "table" then return tableRod(mod, game, mapId, vanillaPool) end

  local epoch = DexExpansion.epoch()
  local legend = legendaryEnabled(mod)
  local c = rodCache[mapId]
  if c and c.epoch == epoch and c.legend == legend and c.size == #vanillaPool then return c.result end
  local pool = RandomSpawns.pool(mod, game, legend, epoch)
  local result = RandomSpawns.superRod(tableRod(mod, game, mapId, vanillaPool), pool) or vanillaPool
  rodCache[mapId] = { epoch = epoch, legend = legend, size = #vanillaPool, result = result }
  return result
end

return Gen9Encounters
