-- Shape/consistency checks on the generated modern encounter data
-- (lib/gen9_encounters_data.lua, version 2, produced by tools/generate_gen9_encounters.py).
-- Run: lua tests/gen9_encounters_data_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local data = assert(loadfile("lib/gen9_encounters_data.lua"))()
check(type(data) == "table" and data.version == 2, "data: table with version 2")
check(type(data.maps) == "table", "data: has maps")

-- The 59 Gen 1 engine encounter maps (red/yellow data/generated/encounters.lua) plus the towns
-- that have a vanilla Super Rod group (data.field.superRod).
local VALID = {}
for id in ([[
CERULEAN_CAVE_1F CERULEAN_CAVE_2F CERULEAN_CAVE_B1F DIGLETTS_CAVE MT_MOON_1F MT_MOON_B1F MT_MOON_B2F
POKEMON_MANSION_1F POKEMON_MANSION_2F POKEMON_MANSION_3F POKEMON_MANSION_B1F POKEMON_TOWER_1F
POKEMON_TOWER_2F POKEMON_TOWER_3F POKEMON_TOWER_4F POKEMON_TOWER_5F POKEMON_TOWER_6F POKEMON_TOWER_7F
POWER_PLANT ROCK_TUNNEL_1F ROCK_TUNNEL_B1F ROUTE_1 ROUTE_2 ROUTE_3 ROUTE_4 ROUTE_5 ROUTE_6 ROUTE_7
ROUTE_8 ROUTE_9 ROUTE_10 ROUTE_11 ROUTE_12 ROUTE_13 ROUTE_14 ROUTE_15 ROUTE_16 ROUTE_17 ROUTE_18
ROUTE_19 ROUTE_20 ROUTE_21 ROUTE_22 ROUTE_23 ROUTE_24 ROUTE_25 SAFARI_ZONE_CENTER SAFARI_ZONE_EAST
SAFARI_ZONE_NORTH SAFARI_ZONE_WEST SEAFOAM_ISLANDS_1F SEAFOAM_ISLANDS_B1F SEAFOAM_ISLANDS_B2F
SEAFOAM_ISLANDS_B3F SEAFOAM_ISLANDS_B4F VICTORY_ROAD_1F VICTORY_ROAD_2F VICTORY_ROAD_3F VIRIDIAN_FOREST
CELADON_CITY CERULEAN_CITY CINNABAR_ISLAND FUCHSIA_CITY PALLET_TOWN VERMILION_CITY VIRIDIAN_CITY
]]):gmatch("%S+") do VALID[id] = true end

local function checkSlot(s, where)
  check(type(s.level) == "number" and s.level % 1 == 0, where .. " level is an integer")
  check(s.level >= 1 and s.level <= 100, where .. " level in 1..100")
  check(type(s.species) == "string" and s.species:match("^[A-Z][A-Z0-9_]*$") ~= nil, where .. " species key format")
  local d = s.dex
  check(type(d) == "number" and ((d >= 1 and d <= 1025) or (d >= 30001 and d <= 50248)),
    where .. " dex in 1..1025 or 30001..50248")
end

local maps, ladders, rods, slotsChecked, biggest = 0, 0, 0, 0, 0

for mapId, entry in pairs(data.maps) do
  maps = maps + 1
  check(VALID[mapId] == true, "map id is a real Gen 1 engine map: " .. tostring(mapId))
  check(type(entry) == "table" and next(entry) ~= nil, mapId .. ": not empty")
  for kind, list in pairs(entry) do
    local where = mapId .. "." .. tostring(kind)
    if kind == "superRod" then
      rods = rods + 1
      check(type(list) == "table" and #list >= 1 and #list <= 4, where .. " has 1..4 entries (engine rolls a 2-bit index)")
      for i, s in ipairs(list) do checkSlot(s, where .. "[" .. i .. "]"); slotsChecked = slotsChecked + 1 end
    elseif kind == "grass" or kind == "water" then
      ladders = ladders + 1
      local b, sl = list.buckets, list.slots
      check(type(b) == "table" and type(sl) == "table", where .. " has buckets + slots")
      if type(b) == "table" and type(sl) == "table" then
        local n = #b
        biggest = math.max(biggest, n)
        check(n >= 1 and n <= 256, where .. " has 1..256 slots (odds are whole 256ths)")
        check(n == #sl, where .. " has one slot per threshold")
        local prev, pctSum = 0, 0
        for i = 1, n do
          local thr = b[i]
          check(type(thr) == "number" and thr % 1 == 0 and thr > prev,
            where .. " threshold " .. i .. " is a strictly increasing integer")
          local s = sl[i]
          if s then
            checkSlot(s, where .. "[" .. i .. "]")
            slotsChecked = slotsChecked + 1
            local width = (thr or 0) - prev
            check(type(s.pct) == "number" and math.abs(s.pct - width / 256 * 100) < 0.01,
              where .. "[" .. i .. "] pct matches its bucket width")
            pctSum = pctSum + (s.pct or 0)
          end
          prev = thr or prev
        end
        check(prev == 256, where .. " ladder ends at 256")
        -- pct is rounded to 2 decimals per slot, so allow n * 0.005 of accumulated rounding.
        check(math.abs(pctSum - 100) <= n * 0.005 + 0.01,
          string.format("%s percentages sum to ~100 (got %.2f over %d slots)", where, pctSum, n))
      end
    else
      check(false, where .. ": unknown bucket kind")
    end
  end
end

check(maps >= 40, "data covers a meaningful number of maps (" .. maps .. ")")
check(biggest > 10, "tables extend past the engine's default 10 slots (largest " .. biggest .. ")")

-- ------------------------------------------------ per-level spread (the user's Roggenrola example)
-- Source: [013] Monte Moon "20%,ROGGENROLA,15,17" -> MT_MOON_B2F. The block's rows add up to 97%
-- (20+20+10+10+10+10+10+7), so the generator normalizes: Roggenrola is 20/97 = 20.6%. That share
-- must be spread over levels 15, 16 and 17 (~6.9% each), not collapsed to one level.
local ROGGENROLA_PCT = 20 / 97 * 100
local function speciesInfo(mapId, kind, species)
  local t = data.maps[mapId] and data.maps[mapId][kind]
  local levels, width, prev = {}, 0, 0
  for i, thr in ipairs(t.buckets) do
    local s = t.slots[i]
    if s.species == species then
      levels[s.level] = (levels[s.level] or 0) + (thr - prev)
      width = width + (thr - prev)
    end
    prev = thr
  end
  return levels, width
end

do
  local levels, width = speciesInfo("MT_MOON_B2F", "grass", "ROGGENROLA")
  check(levels[15] and levels[16] and levels[17], "MT_MOON_B2F ROGGENROLA has slots at levels 15, 16 and 17")
  local n = 0
  for _ in pairs(levels) do n = n + 1 end
  check(n == 3, "MT_MOON_B2F ROGGENROLA spans exactly the source range 15-17 (got " .. n .. " levels)")
  check(math.abs(width / 256 * 100 - ROGGENROLA_PCT) < 0.4,
    string.format("MT_MOON_B2F ROGGENROLA totals ~%.1f%% (got %.2f%%)", ROGGENROLA_PCT, width / 256 * 100))
  for lv, w in pairs(levels) do
    check(math.abs(w / 256 * 100 - ROGGENROLA_PCT / 3) < 0.4,
      string.format("MT_MOON_B2F ROGGENROLA level %d is ~%.1f%% (got %.2f%%)", lv, ROGGENROLA_PCT / 3, w / 256 * 100))
  end
end

-- Route 1 (source rows are 2-4 wide): every species should carry more than one level.
do
  local t = data.maps.ROUTE_1.grass
  local perSpecies = {}
  for _, s in ipairs(t.slots) do
    perSpecies[s.species] = perSpecies[s.species] or {}
    perSpecies[s.species][s.level] = true
  end
  for sp, lv in pairs(perSpecies) do
    local n = 0
    for _ in pairs(lv) do n = n + 1 end
    check(n >= 2, "ROUTE_1 " .. sp .. " has more than one level (got " .. n .. ")")
  end
end

-- Regression: ROM species dex must be the real Gen 1 dex (the national_dex NDEX text ids are not).
local KNOWN = { PARASECT = 47, MUK = 89, GRIMER = 88, KADABRA = 64, MR_MIME = 122, NIDORAN_F = 29 }
for _, entry in pairs(data.maps) do
  for _, list in pairs(entry) do
    local slots = list.slots or list
    for _, s in ipairs(slots) do
      if KNOWN[s.species] then
        check(s.dex == KNOWN[s.species],
          string.format("%s has dex %s (want %d)", s.species, tostring(s.dex), KNOWN[s.species]))
      end
    end
  end
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print(string.format("all passed (%d maps, %d ladders, %d super rod groups, %d slots, largest table %d)",
  maps, ladders, rods, slotsChecked, biggest))
