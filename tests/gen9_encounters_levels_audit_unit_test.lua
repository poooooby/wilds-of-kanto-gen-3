-- Audit: the Spawn Table overlay's LEVELS follow the base game's area, for every mapped map of the real generated data
-- against the ROM's own encounter tables (Gen1Recomp's extracted data). The modern data's levels run far above the ROM's
-- (median +13, up to +56); lib/gen9_encounters.lua re-anchors them onto the vanilla bucket's level distribution.
-- Needs the extracted engine data (.deps/gen1recomp/data/generated); skips without it, like manifest_targets_unit_test.
-- Run: lua tests/gen9_encounters_levels_audit_unit_test.lua   (optional: GEN1RECOMP_ROOT=/path/to/gen1recomp)
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end
local function engineRoot()
  local candidates = {}
  local env = os.getenv("GEN1RECOMP_ROOT")
  if type(env) == "string" and env ~= "" then candidates[#candidates + 1] = env end
  candidates[#candidates + 1] = ".deps/gen1recomp"
  candidates[#candidates + 1] = "/tmp/gen1recomp-src"
  for _, root in ipairs(candidates) do
    if fileExists(root .. "/data/generated/encounters.lua") and fileExists(root .. "/data/generated/field.lua") then
      return root
    end
  end
  return nil
end
local root = engineRoot()
if not root then
  print("skip: no extracted Gen1Recomp data (.deps/gen1recomp/data/generated); run scripts/bootstrap.sh")
  os.exit(0)
end

-- ---------------------------------------------------------------- fixtures
local ROM = dofile(root .. "/data/generated/encounters.lua")
local FIELD = dofile(root .. "/data/generated/field.lua")
local DATA = dofile("lib/gen9_encounters_data.lua")
local AUTHORED = dofile("lib/gen9_encounters_authored.lua") -- the areas the generated data lacks (merged in by gen9_encounters)

local savedOpts = {}
local liveBucket = {}
local mod = {
  id = "wilds_of_kanto_gen3", path = ".",
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k) return savedOpts[k] end },
}
local modules = { gen9_encounters_data = DATA, gen9_encounters_authored = AUTHORED }
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local game = { data = { pokemon = {}, encounters = ROM, field = FIELD } }
-- every species the modern data names is "registered" (with its dex, so the expanded-dex gate opens)

local function registerBlock(m)
  for _, kind in ipairs({ "grass", "water" }) do
    for _, s in ipairs(m[kind] and m[kind].slots or {}) do
      game.data.pokemon[s.species] = game.data.pokemon[s.species] or { dex = s.dex or 400 }
    end
  end
  for _, s in ipairs(m.superRod or {}) do
    game.data.pokemon[s.species] = game.data.pokemon[s.species] or { dex = s.dex or 400 }
  end
end
local function registerAll(maps)
  for _, m in pairs(maps) do
    registerBlock(m)
    if m.classic then registerBlock(m.classic) end
  end
end
registerAll(DATA.maps)
registerAll(AUTHORED.maps)
mod.world = { game = game }
game.save = { options = { modOptions = { [mod.id] = liveBucket } } }
liveBucket.modern_spawns = "table"

V.require("config")
local DexExpansion = V.require("dex_expansion")
local Gen9 = V.require("gen9_encounters")
DexExpansion.invalidate()
Gen9.invalidate()
check(Gen9.active(mod, game) == true, "audit setup: the Spawn Table overlay is active")

-- ---------------------------------------------------------------- weighted level stats
local DEFAULT = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
local function bucketStats(bucket)
  local lo, hi, sum, total, prev = 999, 0, 0, 0, 0
  local ladder = (type(bucket.buckets) == "table" and #bucket.buckets > 0) and bucket.buckets or DEFAULT
  for i, thr in ipairs(ladder) do
    local s = bucket.slots[i]
    if s then
      lo, hi = math.min(lo, s.level), math.max(hi, s.level)
      sum = sum + s.level * (thr - prev)
      total = total + (thr - prev)
    end
    prev = thr
  end
  return lo, hi, sum / total
end
local function poolStats(pool)
  local lo, hi, sum = 999, 0, 0
  for _, e in ipairs(pool) do lo, hi, sum = math.min(lo, e.level), math.max(hi, e.level), sum + e.level end
  return lo, hi, sum / #pool
end

local MEAN_TOL = 1.0     -- grass / water: quantile mapping on 256 units
local ROD_MEAN_TOL = 2.0 -- Super Rod: four equal picks, so coarser
local compared, worst, worstMap = 0, 0, ""
local allMaps = Gen9.dataMaps() -- generated + authored, merged
check(allMaps and allMaps.ROUTE_24 and allMaps.VICTORY_ROAD_2F, "audit setup: the authored areas are part of the merged data")
local mapIds = {}
for id in pairs(allMaps) do mapIds[#mapIds + 1] = id end
table.sort(mapIds)
for _, id in ipairs(mapIds) do
  local m = allMaps[id]
  local vanilla = ROM[id]
  if vanilla then
    local overlay = Gen9.overlayFor(mod, game, id, vanilla)
    for _, kind in ipairs({ "grass", "water" }) do
      if m[kind] and vanilla[kind] and vanilla[kind].slots and #vanilla[kind].slots > 0 then
        compared = compared + 1
        check(overlay ~= vanilla and overlay[kind] and overlay[kind].buckets, id .. " " .. kind .. ": the overlay applies")
        if overlay[kind] and overlay[kind].buckets then
          local vlo, vhi, vmean = bucketStats(vanilla[kind])
          local olo, ohi, omean = bucketStats(overlay[kind])
          check(olo >= vlo and ohi <= vhi,
            string.format("%s %s: levels %d-%d stay inside the ROM's %d-%d", id, kind, olo, ohi, vlo, vhi))
          local d = math.abs(omean - vmean)
          if d > worst then worst, worstMap = d, id .. " " .. kind end
          check(d <= MEAN_TOL, string.format("%s %s: weighted mean %.1f is the ROM's %.1f (+-%.1f)", id, kind, omean, vmean, MEAN_TOL))
        end
      end
    end
  end
  -- Super Rod groups also exist for towns and gyms that have no grass/water table
  local vrod = FIELD.superRod and FIELD.superRod[id]
  if m.superRod and type(vrod) == "table" and #vrod > 0 then
    compared = compared + 1
    local pool = Gen9.fishingPool(mod, game, id, "SUPER_ROD", vrod)
    local vlo, vhi, vmean = poolStats(vrod)
    local olo, ohi, omean = poolStats(pool)
    check(olo >= vlo and ohi <= vhi, string.format("%s Super Rod: levels %d-%d stay inside the ROM's %d-%d", id, olo, ohi, vlo, vhi))
    check(math.abs(omean - vmean) <= ROD_MEAN_TOL,
      string.format("%s Super Rod: mean %.1f is the ROM's %.1f (+-%.1f)", id, omean, vmean, ROD_MEAN_TOL))
  end
end
check(compared >= 90, "audit covered every mapped table (got " .. compared .. ")")
print(string.format("audited %d tables against the ROM; worst weighted-mean gap %.2f (%s)", compared, worst, worstMap))

-- ---------------------------------------------------------------- generation caps
-- A Gen 2 cap drops every Gen 3-9 species. Every table that then has no slot left must be served from the map's Gen 2
-- `classic` table (never the original), with only Gen 2 species and levels still inside the ROM's; under a Gen 1 cap
-- (nothing left at all) the original table stays.
local function speciesDex(name) return game.data.pokemon[name] and game.data.pokemon[name].dex end
local function overCap(list, cap)
  for _, s in ipairs(list.slots or list) do
    if s.dex and s.dex <= cap then return false end
  end
  return true
end
local function sameSpecies(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i].species ~= b[i].species or a[i].level ~= b[i].level then return false end end
  return true
end
local function capPass(cap, label)
  liveBucket.max_generation = label
  Gen9.invalidate()
  local emptied, served = 0, 0
  for _, id in ipairs(mapIds) do
    local m = allMaps[id]
    local vanilla = ROM[id]
    local function verify(kind, primary, vBucketSlots, ovBucket)
      -- primary: the table with all generations; the cap leaves it empty
      emptied = emptied + 1
      if cap >= 251 then
        served = served + 1
        check(m.classic and m.classic[kind], id .. " " .. kind .. ": has a Gen 2 classic table")
        check(ovBucket ~= nil, id .. " " .. kind .. ": still overlaid under the cap (classic), not reverted to the original")
        if ovBucket then
          for _, sl in ipairs(ovBucket.slots) do
            local dex = speciesDex(sl.species)
            check(dex and dex >= 152 and dex <= 251, string.format("%s %s: %s (dex %s) is Gen 2 under a Gen 2 cap", id, kind, sl.species, tostring(dex)))
          end
        end
      else
        check(ovBucket == nil, id .. " " .. kind .. ": a Gen 1 cap keeps the original table")
      end
    end
    for _, kind in ipairs({ "grass", "water" }) do
      if m[kind] and overCap(m[kind], cap) and vanilla and vanilla[kind] and vanilla[kind].slots and #vanilla[kind].slots > 0 then
        local overlay = Gen9.overlayFor(mod, game, id, vanilla)
        local ov = overlay ~= vanilla and overlay[kind] and overlay[kind].buckets and overlay[kind] or nil
        verify(kind, m[kind], vanilla[kind].slots, ov)
        if ov then
          local vlo, vhi, vmean = bucketStats(vanilla[kind])
          local olo, ohi, omean = bucketStats(ov)
          check(olo >= vlo and ohi <= vhi, string.format("%s %s classic: levels %d-%d stay inside the ROM's %d-%d", id, kind, olo, ohi, vlo, vhi))
          check(math.abs(omean - vmean) <= MEAN_TOL, string.format("%s %s classic: mean %.1f is the ROM's %.1f", id, kind, omean, vmean))
        end
      end
    end
    local vrod = FIELD.superRod and FIELD.superRod[id]
    if m.superRod and type(vrod) == "table" and #vrod > 0 and overCap(m.superRod, cap) then
      local pool = Gen9.fishingPool(mod, game, id, "SUPER_ROD", vrod)
      local ov = (not sameSpecies(pool, vrod)) and pool or nil
      verify("superRod", m.superRod, vrod, ov and { slots = pool } or nil)
      if ov then
        check(#pool == #vrod, id .. " Super Rod classic: keeps the original group's size (" .. #pool .. " vs " .. #vrod .. ")")
        local vlo, vhi, vmean = poolStats(vrod)
        local olo, ohi, omean = poolStats(pool)
        check(olo >= vlo and ohi <= vhi, string.format("%s Super Rod classic: levels %d-%d stay inside the ROM's %d-%d", id, olo, ohi, vlo, vhi))
        check(math.abs(omean - vmean) <= ROD_MEAN_TOL, string.format("%s Super Rod classic: mean %.1f is the ROM's %.1f", id, omean, vmean))
      end
    end
  end
  return emptied, served
end
local e2, s2 = capPass(251, "2")
check(e2 >= 20, "Gen 2 cap: the audit saw the emptied tables (got " .. e2 .. ")")
print(string.format("Gen 2 cap: %d tables would be empty, %d served by their Gen 2 classic table", e2, s2))
-- A higher cap includes everything a lower one does: for every grass/water table the species at each cap are a subset of the
-- species at the next cap up. A Super Rod group holds at most four picks, so a joined group cannot keep every Gen 2 entry;
-- it must still hold at least one Gen 2 species at every cap from Gen 2 up wherever the map has a classic group.
local CAPS = { "2", "3", "4", "5", "6", "7", "8", "9" }
local sets = {} -- cap label -> id.kind -> { species = true }
local rodHasGen2 = {}
for _, label in ipairs(CAPS) do
  liveBucket.max_generation = label
  Gen9.invalidate()
  local bySlot = {}
  sets[label] = bySlot
  for _, id in ipairs(mapIds) do
    local vanilla = ROM[id]
    if vanilla then
      local overlay = Gen9.overlayFor(mod, game, id, vanilla)
      for _, kind in ipairs({ "grass", "water" }) do
        if overlay ~= vanilla and overlay[kind] and vanilla[kind] and overlay[kind] ~= vanilla[kind] then
          local set = {}
          for _, sl in ipairs(overlay[kind].slots) do set[sl.species] = true end
          bySlot[id .. "." .. kind] = set
        end
      end
    end
    local vrod = FIELD.superRod and FIELD.superRod[id]
    local m = allMaps[id]
    if m and m.classic and m.classic.superRod and type(vrod) == "table" and #vrod > 0 then
      local pool = Gen9.fishingPool(mod, game, id, "SUPER_ROD", vrod)
      local has = false
      for _, e in ipairs(pool) do
        local dex = speciesDex(e.species)
        if dex and dex >= 152 and dex <= 251 then has = true end
      end
      check(has, id .. " Super Rod at cap Gen " .. label .. ": still holds a Gen 2 species")
    end
  end
end
local grew = 0
for i = 1, #CAPS - 1 do
  for key, low in pairs(sets[CAPS[i]]) do
    local high = sets[CAPS[i + 1]][key]
    check(high ~= nil, key .. ": overlaid at cap Gen " .. CAPS[i] .. " but not at Gen " .. CAPS[i + 1])
    if high then
      for name in pairs(low) do
        check(high[name], string.format("%s: %s at cap Gen %s is missing at Gen %s", key, name, CAPS[i], CAPS[i + 1]))
      end
      grew = grew + 1
    end
  end
end
check(grew > 100, "the monotonic check compared many cap steps (" .. grew .. ")")
print(string.format("caps 2..9: %d table/cap steps only ever gained species", grew))

local e1 = capPass(151, "1")
check(e1 >= e2, "Gen 1 cap: at least as many tables are empty as under a Gen 2 cap (" .. e1 .. " vs " .. e2 .. ")")
liveBucket.max_generation = nil
Gen9.invalidate()

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
