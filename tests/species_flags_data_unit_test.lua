-- Shape/consistency checks on the generated restricted-species data
-- (lib/species_flags_data.lua, produced by tools/generate_species_flags.py).
-- Run: lua tests/species_flags_data_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local data = assert(loadfile("lib/species_flags_data.lua"))()
check(type(data) == "table" and data.version == 1, "data: table with version 1")
check(type(data.restricted) == "table", "data: has restricted")

local KINDS = { legendary = true, mythical = true, ultra_beast = true, paradox = true }
local counts, total = {}, 0
for dex, kind in pairs(data.restricted) do
  check(type(dex) == "number" and dex % 1 == 0 and dex >= 1 and dex <= 1025, "dex is a national dex number: " .. tostring(dex))
  check(KINDS[kind] == true, "known kind for #" .. tostring(dex) .. ": " .. tostring(kind))
  counts[kind] = (counts[kind] or 0) + 1
  total = total + 1
end

-- Counts from the PokeAPI species table (71 legendary, 23 mythical) plus the 11 Ultra Beasts and
-- 20 Paradox Pokemon listed in the generator.
check(counts.legendary == 71, "71 legendary (got " .. tostring(counts.legendary) .. ")")
check(counts.mythical == 23, "23 mythical (got " .. tostring(counts.mythical) .. ")")
check(counts.ultra_beast == 11, "11 Ultra Beasts (got " .. tostring(counts.ultra_beast) .. ")")
check(counts.paradox == 20, "20 Paradox (got " .. tostring(counts.paradox) .. ")")
check(total == 125, "125 restricted species (got " .. total .. ")")

local WANT = {
  [144] = "legendary", [150] = "legendary", [151] = "mythical", [250] = "legendary", [251] = "mythical",
  [493] = "mythical", [793] = "ultra_beast", [806] = "ultra_beast", [984] = "paradox",
  [1023] = "paradox", [1007] = "legendary", [1008] = "legendary", [1025] = "mythical",
}
for dex, kind in pairs(WANT) do
  check(data.restricted[dex] == kind, string.format("#%d is %s (got %s)", dex, kind, tostring(data.restricted[dex])))
end

-- Ordinary species (including babies, pseudo-legendaries and starters) stay eligible.
for _, dex in ipairs({ 1, 25, 39, 133, 172, 149, 248, 373, 445, 658, 1000, 1019 }) do
  check(data.restricted[dex] == nil, "#" .. dex .. " is NOT restricted")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print(string.format("all passed (%d restricted species)", total))
