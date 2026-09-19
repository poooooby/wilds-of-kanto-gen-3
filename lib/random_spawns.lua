-- RANDOM spawn mode (MODERN SPAWNS = "random"): any registered species at the area's level.
--
-- Pure table builders used by lib/gen9_encounters.lua (the single encounter seam). Nothing here
-- reads options or touches game.data.encounters; the caller passes the area's base table (the
-- Spawn Table overlay where one applies, vanilla elsewhere) and gets a same-shape bucket back.
--
--   * Species pool: every registered real species (dex 1..29999 -- alternate forms at 30000+ are
--     skipped), minus lib/species_flags_data.lua's restricted set (legendary, mythical, Ultra
--     Beast, Paradox) unless the caller asks to include it. Independent of the national-dex gate,
--     so Random also works on a plain Gen 1 dex.
--   * Shape: one slot per threshold of the VANILLA ladder (the engine's 10-slot default, or the
--     bucket's own custom ladder), so an area never shows more than ~10 species. Every distinct
--     species costs sprite work (asset probe, SpriteDef, renderer), so a wide roster is expensive.
--   * Species: distinct, from a shuffled copy of the pool (it only cycles if the pool is smaller
--     than the ladder).
--   * Levels: each slot takes the base table's level at a random probability unit inside that
--     slot's own odds interval, so common slots keep common levels and the area's spread is kept.
local V = ...

local RandomSpawns = {}

RandomSpawns.UNITS = 256
RandomSpawns.MAX_DEX = 29999 -- 30000+ are alternate forms (see DexExpansion.FORM_MIN)

-- ------------------------------------------------------------------ rng
-- Own generator (Park-Miller): the engine's math.random state must not be reseeded or consumed by
-- a cosmetic table shuffle, and LuaJIT's default stream is identical on every launch.
function RandomSpawns.newRng(seed)
  local state = math.floor(tonumber(seed) or 1) % 2147483647
  if state <= 0 then state = 1 end
  return function(lo, hi)
    state = (state * 48271) % 2147483647
    return lo + (state - 1) % (hi - lo + 1)
  end
end

local defaultRng
local function rngOrDefault(rng)
  if rng then return rng end
  if not defaultRng then
    local t = os.time() or 0
    local c = math.floor((os.clock() or 0) * 1000003)
    local a = tonumber((tostring({}):match("0x(%x+)") or "1"), 16) or 1
    defaultRng = RandomSpawns.newRng(t * 31 + c + a)
  end
  return defaultRng
end

local function shuffle(list, rng)
  for i = #list, 2, -1 do
    local j = rng(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function copyList(list)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  return out
end

-- ------------------------------------------------------------------ restricted set
local restrictedCache
local function restricted()
  if restrictedCache == nil then
    local ok, t = pcall(function() return V.require("species_flags_data") end)
    restrictedCache = (ok and type(t) == "table" and t.version == 1 and type(t.restricted) == "table")
      and t.restricted or false
  end
  return restrictedCache or {}
end

--- "legendary" | "mythical" | "ultra_beast" | "paradox" for a restricted national dex, else nil.
function RandomSpawns.restrictedKind(dex)
  return restricted()[dex]
end

-- ------------------------------------------------------------------ species pool
local poolCache = setmetatable({}, { __mode = "k" }) -- game -> { epoch, [includeRestricted] = list }

local function realDex(def)
  local d = type(def) == "table" and tonumber(def.dex) or nil
  if d and d >= 1 and d <= RandomSpawns.MAX_DEX and d % 1 == 0 then return d end
  return nil
end

--- Sorted (by dex, then key) list of eligible species keys. Cached per game until `epoch` changes
-- (pass DexExpansion.epoch(), bumped on every load boundary / map entry). Do not mutate the result.
function RandomSpawns.pool(mod, game, includeRestricted, epoch)
  if not game then return {} end
  includeRestricted = includeRestricted == true
  local c = poolCache[game]
  if c and c.epoch == epoch and c[includeRestricted] then return c[includeRestricted] end
  if not c or c.epoch ~= epoch then
    c = { epoch = epoch }
    poolCache[game] = c
  end

  local skip = includeRestricted and {} or restricted()
  local seen, entries = {}, {}
  local function consider(key, def)
    if type(key) ~= "string" or seen[key] then return end
    local dex = realDex(def)
    if not dex or skip[dex] then return end
    seen[key] = true
    entries[#entries + 1] = { key = key, dex = dex }
  end

  local pokemon = game.data and game.data.pokemon
  if type(pokemon) == "table" then
    for key, def in pairs(pokemon) do consider(key, def) end
  end
  local content = mod and mod.content and mod.content.pokemon
  if content and type(content.each) == "function" then
    pcall(function()
      for key, def in content:each() do consider(key, def) end
    end)
  end

  table.sort(entries, function(a, b)
    if a.dex ~= b.dex then return a.dex < b.dex end
    return a.key < b.key
  end)
  local list = {}
  for i, e in ipairs(entries) do list[i] = e.key end
  c[includeRestricted] = list
  return list
end

-- ------------------------------------------------------------------ table builders
local defaultLadder
local function engineLadder()
  if defaultLadder == nil then
    local ok, Config = pcall(function() return V.require("config") end)
    defaultLadder = (ok and Config and Config.ENCOUNTER_BUCKETS)
      or { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
  end
  return defaultLadder
end

local function ladderOf(bucket)
  if type(bucket.buckets) == "table" and #bucket.buckets > 0 then return bucket.buckets end
  return engineLadder()
end

-- Level of the base slot covering probability unit `u` (0..255): first threshold above it.
local function levelsByUnit(bucket)
  local slots = bucket.slots
  local levels, u = {}, 0
  for i, thr in ipairs(ladderOf(bucket)) do
    local slot = slots[i] or slots[#slots]
    local level = slot and tonumber(slot.level) or 1
    while u < thr and u < RandomSpawns.UNITS do
      levels[#levels + 1] = level
      u = u + 1
    end
  end
  local last = levels[#levels] or 1
  while #levels < RandomSpawns.UNITS do levels[#levels + 1] = last end
  return levels
end

--- Random bucket shaped like the engine's (`buckets` + `slots`, `{ level, species }`) with one slot
-- per threshold of `ladder` (default: the engine's 10-slot ladder; pass the vanilla bucket's own
-- ladder so custom ones keep their shape) and `base`'s level distribution. Returns nil when there
-- is nothing to draw from.
function RandomSpawns.bucket(base, pool, rng, ladder)
  if type(base) ~= "table" or type(base.slots) ~= "table" or #base.slots == 0 then return nil end
  if type(pool) ~= "table" or #pool == 0 then return nil end
  if type(ladder) ~= "table" or #ladder == 0 then ladder = engineLadder() end
  rng = rngOrDefault(rng)

  local levels = levelsByUnit(base)
  local order, buckets, slots, prev = {}, {}, {}, 0
  for i, thr in ipairs(ladder) do
    if #order == 0 then
      order = shuffle(copyList(pool), rng)
    end
    -- A random unit inside this slot's own odds interval [prev, thr).
    local unit = math.min(rng(prev, math.max(prev, thr - 1)), RandomSpawns.UNITS - 1)
    buckets[i] = thr
    slots[i] = { level = levels[unit + 1] or 1, species = table.remove(order) }
    prev = thr
  end
  return { buckets = buckets, slots = slots }
end

--- Random Super Rod group with the base group's shape (same length, <= 4; levels kept in order),
-- species drawn without repeats while the pool allows. Returns nil when there is nothing to draw.
function RandomSpawns.superRod(baseGroup, pool, rng)
  if type(baseGroup) ~= "table" or #baseGroup == 0 then return nil end
  if type(pool) ~= "table" or #pool == 0 then return nil end
  rng = rngOrDefault(rng)

  local n = math.min(#baseGroup, 4)
  local order, out = {}, {}
  for i = 1, n do
    if #order == 0 then
      order = shuffle(copyList(pool), rng)
    end
    out[i] = { level = tonumber(baseGroup[i].level) or 1, species = table.remove(order) }
  end
  return out
end

return RandomSpawns
