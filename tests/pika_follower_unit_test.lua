-- PIKA FOLLOWER: cosmetic costume choice for the Yellow starter Pikachu
-- companion only (ControlEngine:_pikaFollowerCostumeOverride).
-- Run: lua tests/pika_follower_unit_test.lua
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

package.loaded["src.render.SpriteRenderer"] = { new = function(def, id) return { def = def, id = id } end }
package.loaded["src.world.NPC"] = { new = function() return {} end, walkPhase = function() return 0 end }

local modules = {}
local savedOpts = {}
local liveBucket = {}
local V = {
  mod = { path = ".", id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    options = { get = function(_, k) return savedOpts[k] end },
    -- Mirrors what Config.setOption/writeOptionBucket actually write to at
    -- runtime, and what Config.peekSavedOption reads from -- the SAME live
    -- save-data bucket the in-game Settings menu's optSet() goes through
    -- (settings_menus.lua), which is a DIFFERENT location than mod.options.
    -- This is the exact bucket a stale Config.pikaFollower implementation
    -- (using only Config.get/mod.options:get) silently never checked.
    world = { game = { save = { options = { modOptions = {
      wilds_of_kanto_gen3 = liveBucket,
    } } } } },
  },
  path = ".",
}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end
-- Real config.lua (not a fake stub): this test specifically exercises
-- Config.pikaFollower's own default/validation logic, and control_engine.lua
-- internally V.require()s "config" too, so both call sites must see the
-- same real implementation.
modules.debug_log = { warn = function() end, info = function() end, error = function() end, debug = function() end }
modules.tile = { CELL = 16 }
modules.cell_occupancy = { isFollowerEntity = function(e) return e and e.pokepcTrailer == true end }
modules.surface = { WATER = "WATER" }

local Config = V.require("config")
local ControlEngine = V.require("follower/control_engine")
local engine = ControlEngine.new(V.mod, {
  settings = { followerCount = function() return 6 end, engineMode = function() return "follow" end },
  game = nil,
})

----------------------------------------------------------------
-- Config.pikaFollower: default, round-trip, and stale-value handling
----------------------------------------------------------------
savedOpts = {}
eq(Config.pikaFollower(V.mod), "default", "pika_follower defaults to default when unset")
savedOpts.pika_follower = "alola"
eq(Config.pikaFollower(V.mod), "alola", "pika_follower round-trips a valid saved choice")
savedOpts.pika_follower = "not-a-real-costume"
eq(Config.pikaFollower(V.mod), "default", "pika_follower falls back to default for a stale/invalid saved value")
savedOpts = {}

-- The actual bug this regression-tests: the in-game Settings menu (PIKA
-- FOLLOWER row, settings_menus.lua's optSet) writes through Config.setOption
-- into this live save-data bucket, NOT mod.options. A getter that only
-- checks mod.options:get (as Config.pikaFollower originally did) would see
-- this selection have no effect at all.
liveBucket.pika_follower = "rockstar"
eq(Config.pikaFollower(V.mod), "rockstar",
  "pika_follower reads the live save-data bucket the in-game menu actually writes to")
liveBucket.pika_follower = nil
savedOpts.pika_follower = "belle"
eq(Config.pikaFollower(V.mod), "belle",
  "pika_follower falls back to mod.options when the live bucket has no entry")
savedOpts = {}

----------------------------------------------------------------
-- _pikaFollowerCostumeOverride: non-Pikachu / default choice are no-ops
----------------------------------------------------------------
do
  local resolved = { id = "SPRITE_WILDS_FOLLOWER_MON", image = "x.png", frames = 6, walker = true, trueColor = true }
  local out = engine:_pikaFollowerCostumeOverride("CHARMANDER", resolved)
  check(out == resolved, "non-Pikachu species: resolved def returned unchanged (same table)")

  savedOpts.pika_follower = "default"
  out = engine:_pikaFollowerCostumeOverride("PIKACHU", resolved)
  check(out == resolved, "Pikachu with Default choice: resolved def returned unchanged")
  savedOpts = {}
end

----------------------------------------------------------------
-- _pikaFollowerCostumeOverride: Classic Flat (no frameWidth) swaps image only
----------------------------------------------------------------
do
  savedOpts.pika_follower = "alola"
  -- Realistic "before" value: the real resolver always returns a path
  -- already rooted under the mod's own install folder (mods/<folder>/...),
  -- never a bare "assets/..." string -- see the regression note below.
  local resolved = { id = "SPRITE_WILDS_FOLLOWER_MON",
    image = "./assets/wilds_generated/followsprites_runtime/025-normal.png",
    frames = 6, walker = true, trueColor = true }
  local out = engine:_pikaFollowerCostumeOverride("PIKACHU", resolved)
  -- Regression: the override originally built a bare "assets/..." path
  -- directly, which SpriteRenderer.new/love.filesystem cannot open (it needs
  -- to be rooted under the mod's own path, same as every other resolved
  -- image in this codebase) -- confirmed via a live "Could not open file"
  -- error. modAssetPath must be applied to the override's own image path
  -- exactly like the normal resolver already applies it.
  eq(out.image, "./assets/wilds_generated/pika_follower_runtime/001-normal.png",
    "Classic mode: image swapped to the Alola costume's baked 16x16 sheet, mod-path-rooted (classicId 1)")
  eq(out.frames, 6, "Classic mode: frames preserved from the normal resolve")
  eq(out.walker, true, "Classic mode: walker preserved from the normal resolve")
  check(out.frameWidth == nil, "Classic mode: no explicit frameWidth added (stays fixed-card)")
  savedOpts = {}
end

----------------------------------------------------------------
-- _pikaFollowerCostumeOverride: True Size (has frameWidth) swaps image + geometry
----------------------------------------------------------------
do
  savedOpts.pika_follower = "phd"
  local resolved = { id = "SPRITE_WILDS_FOLLOWER_MON",
    image = "./assets/wilds_generated/true_size/hgss/025-normal.png",
    frames = 6, walker = true, trueColor = true,
    frameWidth = 18, frameHeight = 20, anchorX = 9.0, anchorY = 18.0 }
  local out = engine:_pikaFollowerCostumeOverride("PIKACHU", resolved)
  eq(out.image, "./assets/wilds_generated/true_size/pika_phd/025-normal.png",
    "True Size mode: image swapped to the PhD costume's own baked sheet, mod-path-rooted")
  check(out.frameWidth ~= 18, "True Size mode: geometry overridden too, not Pikachu's own frameWidth")
  check(type(out.frameWidth) == "number" and out.frameWidth > 0, "True Size mode: costume has its own valid frameWidth")
  check(type(out.anchorY) == "number" and out.anchorY > 0, "True Size mode: costume has its own valid anchorY")
  savedOpts = {}
end

----------------------------------------------------------------
-- Unbaked/unknown costume name falls back to unchanged (defensive)
----------------------------------------------------------------
do
  modules.pika_follower_geometry = {} -- simulate a costume missing from the geometry table
  savedOpts.pika_follower = "alola"
  local resolved = { id = "x", image = "y.png", frames = 6, walker = true, trueColor = true }
  local out = engine:_pikaFollowerCostumeOverride("PIKACHU", resolved)
  check(out == resolved, "costume missing from geometry table: resolved def returned unchanged")
  modules.pika_follower_geometry = nil
  savedOpts = {}
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nall passed")
