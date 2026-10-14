-- Named vanilla NPC reskin (lib/npc_reskin.lua, lib/npc_reskin_data.lua).
-- Run: lua tests/npc_reskin_unit_test.lua
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

local modules = {}
local isGen2 = false
local V = {
  mod = { id = "wilds_of_kanto_gen3", path = ".", log = { info = function() end, warn = function() end } },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end
modules.debug_log = { warn = function() end, info = function() end, error = function() end }
modules.game_compat = { isGen2 = function() return isGen2 end }
-- A small, controlled fixture -- isolated from the real curated list so
-- these tests don't drift if that list grows/changes.
modules.npc_reskin_data = {
  DATA = {
    TEST_MAP = {
      { name = "TESTMAP_PIKACHU", species = "PIKACHU" },
      { name = "TESTMAP_MISSING_OBJECT", species = "EEVEE" },
      { name = "TESTMAP_UNKNOWN_SPECIES", species = "NOT_A_REAL_MON" },
    },
  },
}

local NpcReskin = V.require("npc_reskin")

-- ------- fake render + fake mod.world, tracking every call made
local spriteIdsBySpecies = {
  PIKACHU = "SPRITE_OW_WILD_PIKACHU",
  EEVEE = "SPRITE_OW_WILD_EEVEE", -- resolves fine; the OBJECT itself is what's missing below
  -- NOT_A_REAL_MON deliberately absent -- this is the unresolvable-species case
}
local fakeRender = {
  spriteIdFor = function(_, species)
    local id = spriteIdsBySpecies[species]
    if id then return id end
    return nil, "No pre-registered overworld sprite for species " .. tostring(species)
  end,
}

local setAppearanceCalls = {}
local npcHandles = {
  TESTMAP_PIKACHU = {
    setAppearance = function(_, spriteId)
      table.insert(setAppearanceCalls, { name = "TESTMAP_PIKACHU", spriteId = spriteId })
      return true
    end,
  },
  -- TESTMAP_MISSING_OBJECT deliberately has no handle -- mod.world:npc returns nil, err
}
local npcLookupCalls = {}
local mod = {
  id = "wilds_of_kanto_gen3",
  world = {
    game = nil,
    npc = function(_, mapId, name)
      table.insert(npcLookupCalls, { mapId = mapId, name = name })
      local handle = npcHandles[name]
      if handle then return handle end
      return nil, "no such object: " .. tostring(name)
    end,
  },
}

local reskin = NpcReskin.new(mod, fakeRender)

-- ------- a map with no curated entries is a silent no-op
setAppearanceCalls, npcLookupCalls = {}, {}
reskin:applyMap("SOME_OTHER_MAP")
eq(#npcLookupCalls, 0, "no curated entries for this map -> mod.world:npc is never called")

-- ------- nil / non-string mapId is a silent no-op, never throws
reskin:applyMap(nil)
reskin:applyMap(42)
eq(#npcLookupCalls, 0, "nil/non-string mapId never calls mod.world:npc")

-- ------- the full curated pass for TEST_MAP. Only 2 of the 3 entries reach
-- mod.world:npc at all -- the unresolvable-species entry short-circuits
-- on spriteIdFor's own failure, never spending an engine lookup on a
-- species we already know has no art.
setAppearanceCalls, npcLookupCalls = {}, {}
reskin:applyMap("TEST_MAP")
eq(#npcLookupCalls, 2, "mod.world:npc is looked up only for entries spriteIdFor actually resolved")

-- The resolvable entry: spriteIdFor -> setAppearance with the right id.
eq(#setAppearanceCalls, 1, "exactly one setAppearance call (the only fully-resolvable entry)")
eq(setAppearanceCalls[1].name, "TESTMAP_PIKACHU", "setAppearance called on the right object")
eq(setAppearanceCalls[1].spriteId, "SPRITE_OW_WILD_PIKACHU", "setAppearance got the registered sprite id")

-- ------- a species with no registered sprite id logs and skips, never throws
-- (TESTMAP_UNKNOWN_SPECIES=NOT_A_REAL_MON above) -- mod.world:npc must not
-- even be consulted for this entry since spriteIdFor already failed.
local sawUnknownLookup = false
for _, call in ipairs(npcLookupCalls) do
  if call.name == "TESTMAP_UNKNOWN_SPECIES" then sawUnknownLookup = true end
end
check(not sawUnknownLookup, "an unresolvable species never reaches mod.world:npc at all")

-- ------- an object name not found on the live map logs and skips, never throws
-- (TESTMAP_MISSING_OBJECT has a registered species but no npc handle)
local sawMissingLookup = false
for _, call in ipairs(npcLookupCalls) do
  if call.name == "TESTMAP_MISSING_OBJECT" then sawMissingLookup = true end
end
check(sawMissingLookup, "a resolvable species still gets looked up even if the object itself is missing")

-- ------- Gen2: applyMap never touches mod.world at all
isGen2 = true
setAppearanceCalls, npcLookupCalls = {}, {}
reskin:applyMap("TEST_MAP")
eq(#npcLookupCalls, 0, "Gen2 skips the whole pass -- no mod.world:npc calls")
eq(#setAppearanceCalls, 0, "Gen2 skips the whole pass -- no setAppearance calls")
isGen2 = false

-- ------- the real curated data loads cleanly and has the expected shape
-- (loaded directly, NOT via V.require -- "npc_reskin_data" is cached above
-- as the small test fixture, not the real file)
local RealData = assert(loadfile("lib/npc_reskin_data.lua"))(V)
check(type(RealData.DATA) == "table", "real npc_reskin_data.DATA is a table")
local realMapCount, realEntryCount = 0, 0
for mapId, entries in pairs(RealData.DATA) do
  realMapCount = realMapCount + 1
  check(type(mapId) == "string" and mapId ~= "", "real data: map id is a non-empty string")
  check(type(entries) == "table" and #entries > 0, "real data: " .. tostring(mapId) .. " has at least one entry")
  for _, entry in ipairs(entries) do
    realEntryCount = realEntryCount + 1
    check(type(entry.name) == "string" and entry.name ~= "",
      "real data: entry in " .. tostring(mapId) .. " has a non-empty name")
    check(type(entry.species) == "string" and entry.species ~= "",
      "real data: entry in " .. tostring(mapId) .. " has a non-empty species")
  end
end
check(realMapCount > 0, "real npc_reskin_data has at least one map")
check(realEntryCount > 0, "real npc_reskin_data has at least one entry")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("npc_reskin_unit_test: all passed")
