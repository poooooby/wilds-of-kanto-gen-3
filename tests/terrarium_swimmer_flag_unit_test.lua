-- Terrarium's reef (lib/WakeFX.lua) treats any entity with `surfing` set as a swimmer: it stirs the lilypads, reeds and kelp,
-- throws a wake and rides the swell. This mod sets that flag on followers standing in water (ControlEngine:_syncSwimmerFlags)
-- and on our visible wild water spawns (Surface.isSwimmer, applied by the behavior tick). Gen 1 only.
-- Run: lua tests/terrarium_swimmer_flag_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

-- ---------------------------------------------------------------- Surface.isSwimmer (wild water spawns)
do
  local mods = { encounter_pick = {} }
  local V1 = { mod = {}, path = "." }
  function V1.require(name)
    if mods[name] ~= nil then return mods[name] end
    local value = assert(loadfile("lib/" .. name .. ".lua"))(V1)
    mods[name] = value
    return value
  end
  local Surface = V1.require("surface")

  check(Surface.isSwimmer({ surface = Surface.WATER }, false), "a wild mon on the water surface is a swimmer")
  check(Surface.isSwimmer({ surface = Surface.GRASS, behavior = "WATER_WANDER" }, false),
    "a water behaviour counts even before the surface flips")
  check(not Surface.isSwimmer({ surface = Surface.GRASS, behavior = "IDLE_LOOK" }, false), "a land mon is not")
  check(not Surface.isSwimmer({ surface = Surface.WATER }, true), "Gen 2: never (the engine reads the flag as collision)")
  check(not Surface.isSwimmer({ surface = Surface.WATER, hiddenEncounter = true }, false), "a hidden mon is not a drawn body")
  check(not Surface.isSwimmer({ surface = Surface.WATER, visibleSprite = false }, false), "an invisible mon is not")
  check(not Surface.isSwimmer(nil, false), "nil entity")
end

-- ---------------------------------------------------------------- followers: ControlEngine:_syncSwimmerFlags
package.loaded["src.render.SpriteRenderer"] = { new = function(def, id) return { def = def, id = id } end }
package.loaded["src.world.NPC"] = { new = function() return {} end, walkPhase = function() return 0 end }

local modules = {}
local V = {
  mod = { path = ".", id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    options = { get = function() return nil end },
  },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
modules.debug_log = { warn = function() end, info = function() end, error = function() end, debug = function() end }
modules.tile = { CELL = 16 }
modules.cell_occupancy = { isFollowerEntity = function(e) return e and e.pokepcTrailer == true end }
modules.surface = { WATER = "WATER" }

local GameCompat = V.require("game_compat")
local currentGame = { gen2 = false }
GameCompat.isGen2 = function(_, game) return game ~= nil and game.gen2 == true end

local ControlEngine = V.require("follower/control_engine")
local engine = ControlEngine.new(V.mod, {
  settings = { followerCount = function() return 6 end, engineMode = function() return "follow" end },
  game = nil,
})
engine._game = function() return currentGame end

local water = { ["1,1"] = true, ["2,1"] = true }
local ow = {
  map = { isWaterCell = function(_, x, y) return water[x .. "," .. y] == true end },
  pokepcTrailers = {},
}
local function trailer(x, y, kind)
  return { cellX = x, cellY = y, pokepcTrailer = true, pokepcTrailerKind = kind or "mon", moving = false }
end
local a, b, c = trailer(1, 1), trailer(5, 5), trailer(2, 1, "trainer")
ow.pokepcTrailers = { a, b, c }

engine:_syncSwimmerFlags(ow)
eq(a.surfing, true, "a follower standing in a water cell is a swimmer")
eq(b.surfing, nil, "a follower on land is not")
eq(c.surfing, nil, "a trainer trailer is never flagged, even in water")

-- it steps out of the water, another wades in: the flag follows the cell
a.cellX, a.cellY = 5, 1
b.cellX, b.cellY = 2, 1
engine:_syncSwimmerFlags(ow)
eq(a.surfing, nil, "stepping onto land clears the flag")
eq(b.surfing, true, "wading in sets it")

-- the per-frame entry point applies it
b.cellX, b.cellY = 5, 5
a.cellX, a.cellY = 1, 1
engine:advanceAllTrailers(ow)
eq(a.surfing, true, "advanceAllTrailers keeps the flags current")
eq(b.surfing, nil, "advanceAllTrailers clears it for a follower on land")

-- Gold: never set, and cleared if it was
currentGame = { gen2 = true }
engine:_syncSwimmerFlags(ow)
eq(a.surfing, nil, "Gen 2: the flag is cleared and never set")
currentGame = { gen2 = false }

-- no map / no cells must not error
local noMap = { pokepcTrailers = { trailer(1, 1) } }
local okNoMap = pcall(function() engine:_syncSwimmerFlags(noMap) end)
check(okNoMap, "a missing map is tolerated")
eq(noMap.pokepcTrailers[1].surfing, nil, "no map: not a swimmer")
check(pcall(function() engine:_syncSwimmerFlags(nil) end), "nil overworld is tolerated")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
