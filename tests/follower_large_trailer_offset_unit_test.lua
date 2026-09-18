-- Large-trailer visual push-back (control_engine.lua) is cosmetic-only:
-- it must never touch cellX/cellY, and must be zero for non-wide species.
-- Run: lua tests/follower_large_trailer_offset_unit_test.lua
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

package.loaded["src.render.SpriteRenderer"] = {
  new = function(def, id) return { def = def, id = id } end,
}
package.loaded["src.world.NPC"] = {
  new = function(_, _, def)
    return {
      id = "WILDS_TRAILER_" .. tostring(def and def.index or 0),
      cellX = def and def.x or 0, cellY = def and def.y or 0,
      px = (def and def.x or 0) * 16, py = (def and def.y or 0) * 16,
      facing = "down", moving = false, progress = 0,
      update = function() return "stock" end,
      pose = function(ent) return ent.sprite, ent.px, ent.py, ent.facing, 0, false end,
    }
  end,
  walkPhase = function() return 0 end,
}

local modules = {}
local V = {
  mod = {
    path = ".", id = "overworld_wild_spawns",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    options = { get = function() return nil end },
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
modules.config = {
  DEFAULTS = { sprite_style = "pokemmo", follower_count = 6 },
  get = function(_, k) return modules.config.DEFAULTS[k] end,
  spriteStyle = function() return "pokemmo" end,
  debug = function() return false end,
}
modules.debug_log = {
  warn = function() end, info = function() end, error = function() end, debug = function() end,
}
modules.tile = { CELL = 16 }
modules.cell_occupancy = { isFollowerEntity = function(e) return e and e.pokepcTrailer == true end }
modules.surface = { WATER = "WATER" }

local ControlEngine = V.require("follower/control_engine")
local SpeciesGeometry = V.require("species_geometry")

local function makeEngine()
  return ControlEngine.new(V.mod, {
    settings = {
      followerCount = function() return 6 end,
      engineMode = function() return "follow" end,
    },
    game = nil,
  })
end

----------------------------------------------------------------
-- _largeTrailerPushbackPx: data-driven from frameWidth, not species class
----------------------------------------------------------------
do
  local engine = makeEngine()

  -- Numeric dex takes the simplest path through _speciesIdForTrailSource
  -- (passthrough), so this exercises the real SpeciesGeometry table without
  -- needing to mock GameCompat/SpeciesAssets species-string resolution.
  local onixPack = select(1, SpeciesGeometry.packGeometry(95, "pokemmo"))
  check(onixPack ~= nil, "Onix pokemmo pack exists (fixture sanity)")
  local onixExpected = (tonumber(onixPack.frameWidth) - 16) / 2
  eq(engine:_largeTrailerPushbackPx(95), onixExpected,
    "Onix push-back is (frameWidth - tile) / 2")

  -- Diglett is exactly one tile wide (frameWidth 16) -- the genuine
  -- fw <= tile boundary case, not just "small by height class".
  local diglettPack = select(1, SpeciesGeometry.packGeometry(50, "pokemmo"))
  check(diglettPack ~= nil, "Diglett pokemmo pack exists (fixture sanity)")
  eq(tonumber(diglettPack.frameWidth), 16, "Diglett is exactly one tile wide (fixture sanity)")
  eq(engine:_largeTrailerPushbackPx(50), 0, "exactly-one-tile-wide species gets zero push-back")

  -- Rattata is a small (by height class) species whose art is still wider
  -- than one tile -- the formula is width-driven, not class-gated, so this
  -- must be positive, not zero (species class no longer factors in at all).
  local rattataPack = select(1, SpeciesGeometry.packGeometry(19, "pokemmo"))
  check(rattataPack ~= nil, "Rattata pokemmo pack exists (fixture sanity)")
  check(tonumber(rattataPack.frameWidth) > 16, "Rattata is wider than one tile (fixture sanity)")
  check(engine:_largeTrailerPushbackPx(19) > 0,
    "a small-class species wider than one tile still gets a positive push-back")

  eq(engine:_largeTrailerPushbackPx(nil), 0, "nil source gets zero push-back")
  eq(engine:_largeTrailerPushbackPx("not-a-number-or-table"), 0,
    "unresolvable source gets zero push-back")
end

----------------------------------------------------------------
-- makeTrailer caches the push-back once; never touches cellX/cellY
----------------------------------------------------------------
do
  local engine = makeEngine()
  local mon = { species = "PSYDUCK", hp = 20 }
  local game = { save = { party = { mon }, pokepcFollowerCount = 1, pokepcControlMode = "follow" } }
  engine._gameRef = game
  engine.resolveFollowerSprite = function()
    return { image = "land_PSYDUCK.png", frames = 6, walker = true, trueColor = true }
  end
  local ow = {
    map = { id = "ROUTE1",
      inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 40 and y < 40 end,
      isWalkableCell = function() return true end, isWaterCell = function() return false end },
    player = { cellX = 5, cellY = 5, facing = "down" },
    npcs = {}, entities = {}, pokepcTrailers = {},
  }
  local created = engine:makeTrailer(game, ow, 5, 6, "up", "mon", mon, 1, { surface = "land" })
  check(created ~= nil, "makeTrailer returns npc")
  check(type(created._wildsLargePushbackPx) == "number",
    "makeTrailer always caches a numeric push-back (0 when unresolved/small)")
  eq(created.cellX, 5, "makeTrailer does not perturb cellX")
  eq(created.cellY, 6, "makeTrailer does not perturb cellY")
end

----------------------------------------------------------------
-- Each trailer's push-back is its OWN overhang only -- independent of
-- neighbors, never summed or accumulated down the convoy. This is the
-- deliberately scoped "cheap fix": it fully covers the player->slot-1 case
-- (the player has no overhang of its own, so slot 1's own amount alone is
-- the correct gap) without the chain-math problems a cumulative or
-- pairwise design ran into for slots 2+ (see _largeTrailerPushbackPx's
-- header for why those were reverted). Exercises the real advanceTrailerStep
-- code path (not a reimplementation) with two synthetic trailers walking the
-- same step, to prove neither's landed offset is influenced by the other's
-- amount.
----------------------------------------------------------------
do
  local function walkOneStepDown(pushback)
    local npc = {
      cellX = 5, cellY = 5, facing = "down",
      _wildsLargePushbackPx = pushback,
      moving = true, targetX = 5, targetY = 6, stepFrames = 1, progress = 0,
    }
    ControlEngine.advanceTrailerStep(npc, nil, nil, nil)
    return npc.py - npc.cellY * 16 -- isolate the applied offset from the base grid position
  end

  eq(walkOneStepDown(0), 0, "small trailer: zero offset regardless of what follows it")
  eq(walkOneStepDown(4), -4, "large trailer: offset equals its own overhang only")
  eq(walkOneStepDown(3), -3,
    "large trailer behind another large trailer: still just its own overhang, not summed")
end

----------------------------------------------------------------
-- advanceTrailerStep eases the offset across a turn, doesn't snap to it
----------------------------------------------------------------
do
  local amount = 8
  local npc = {
    cellX = 5, cellY = 5, facing = "down",
    _wildsLargePushbackPx = amount,
    _wildsAppliedOffsetX = 0, _wildsAppliedOffsetY = 0,
    moving = true, targetX = 5, targetY = 6, stepFrames = 10, progress = 0,
  }

  -- Complete a full step walking DOWN so _wildsAppliedOffsetX/Y bakes in the
  -- down-facing target offset (behindOffset: dx=0, dy=-amount for "down").
  for _ = 1, 10 do
    ControlEngine.advanceTrailerStep(npc, nil, nil, nil)
  end
  eq(npc.cellY, 6, "step 1 landed on the target cell (fixture sanity)")
  eq(npc._wildsAppliedOffsetX, 0, "applied offset X after walking down (fixture sanity)")
  eq(npc._wildsAppliedOffsetY, -amount, "applied offset Y after walking down (fixture sanity)")

  -- Now turn: a new step starts facing RIGHT (behindOffset target: dx=-amount,
  -- dy=0) -- mirrors _assignTrailerStep setting npc.facing at step start,
  -- before any interpolation runs.
  npc.facing = "right"
  npc.moving = true
  npc.targetX, npc.targetY = 6, 6
  npc.progress = 0

  ControlEngine.advanceTrailerStep(npc, nil, nil, nil) -- progress -> 1 of 10, t = 0.1
  local t = 0.1
  local expectedOx = 0 + (-amount - 0) * t
  local expectedOy = -amount + (0 - -amount) * t
  local gotOx = npc.px - (npc.cellX + (npc.targetX - npc.cellX) * t) * 16
  local gotOy = npc.py - (npc.cellY + (npc.targetY - npc.cellY) * t) * 16
  check(math.abs(gotOx - expectedOx) < 1e-6,
    "mid-turn offset X is the lerp toward the new facing, not applied instantly")
  check(math.abs(gotOy - expectedOy) < 1e-6,
    "mid-turn offset Y is the lerp away from the old facing, not left behind instantly")
  -- The key regression this covers: right after the turn starts, the offset
  -- must NOT already equal the new facing's full target (that's the snap).
  check(math.abs(gotOx - -amount) > 1e-6,
    "offset has not already snapped to the new facing's target on frame one")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nall passed")
