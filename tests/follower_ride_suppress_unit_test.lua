-- Bike/Fly: temporary follower suppress, same shape as Poké Center heal
-- (see tests/follower_pokecenter_heal_unit_test.lua, the template this
-- mirrors) -- plus GameCompat.isBiking/isFlying detection for both
-- generations.
-- Run: luajit tests/follower_ride_suppress_unit_test.lua
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
  new = function(def, id)
    return { def = def, id = id, draw = function() end }
  end,
}
package.loaded["src.world.NPC"] = {
  new = function(_, _, def)
    return {
      id = "WILDS_TRAILER_" .. tostring(def and def.index or 0),
      cellX = def and def.x or 0,
      cellY = def and def.y or 0,
      px = (def and def.x or 0) * 16,
      py = (def and def.y or 0) * 16,
      facing = "down",
      moving = false,
      progress = 0,
      update = function() end,
      pose = function(ent)
        return ent.sprite, ent.px, ent.py, ent.facing, 0, false
      end,
    }
  end,
  walkPhase = function() return 0 end,
}
package.loaded["src.world.OverworldController"] = {
  update = function() end,
  interact = function() end,
  talkTo = function() end,
}
package.loaded["src.core.GameVersion"] = {
  get = function() return "red" end,
  isYellow = function() return false end,
  isGold = function() return false end,
  generation = function() return 1 end,
}

local modules = {}
local optionStore = {
  follower_count = 3,
  control_mode = "follow",
  sprite_style = "pokemmo",
}
local V = {
  mod = {
    path = ".",
    id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end, error = function() end },
    find = function() return nil end,
    options = {
      get = function(_, key) return optionStore[key] end,
      set = function(_, key, val) optionStore[key] = val end,
    },
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
  DEFAULTS = { sprite_style = "pokemmo", follower_count = 3 },
  get = function(_, k)
    if k == "follower_count" then return optionStore.follower_count end
    return modules.config.DEFAULTS[k]
  end,
  spriteStyle = function() return optionStore.sprite_style or "pokemmo" end,
  debug = function() return false end,
}
modules.debug_log = {
  warn = function() end, info = function() end, error = function() end, debug = function() end,
  followerGen2 = function() end, followerGen2Always = function() end,
}
modules.tile = { CELL = 16 }
modules.cell_occupancy = {
  isFollowerEntity = function(e)
    return e and (e.pokepcTrailer == true or e.wildsFollower == true)
  end,
  isBlockingEntity = function(e)
    if not e then return false end
    if e.fxOnly == true or e.pureFx == true then return false end
    return e.pokepcTrailer == true or e.wildsFollower == true
  end,
}
modules.surface = { WATER = "WATER" }

local GameCompat = V.require("game_compat")
local ControlEngine = V.require("follower/control_engine")
local Selection = V.require("follower/selection")
local State = V.require("follower/state")

local function makeMon(species, slot)
  return {
    species = species,
    hp = 20,
    otId = 1000 + slot,
    dvs = { attack = slot, defense = 2, speed = 3, special = 4 },
    catchRate = 45,
  }
end

local function makeOw(mapId)
  return {
    map = {
      id = mapId or "ROUTE_1",
      inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 40 and y < 40 end,
      isWalkableCell = function() return true end,
      isWaterCell = function() return false end,
    },
    player = { cellX = 10, cellY = 10, facing = "up", px = 160, py = 160, onBike = false },
    npcs = {},
    entities = {},
    pokepcTrailers = {},
    pokepcTrailCells = {},
  }
end

local function makeParty(n)
  local names = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIDGEY", "RATTATA", "PIKACHU" }
  local party = {}
  for i = 1, n do
    party[i] = makeMon(names[i] or ("MON" .. i), i)
  end
  return party
end

local function makeEngine(game, count)
  optionStore.follower_count = count
  local state = State.new(V.mod)
  local selection = Selection.new(V.mod, state)
  if game.save.party[1] then
    selection:selectFollower(game.save.party[1], game, {})
  end
  local engine = ControlEngine.new(V.mod, {
    selection = selection,
    settings = {
      engineMode = function() return "follow" end,
      followerCount = function(_, g)
        return (g and g.save and g.save.pokepcFollowerCount) or optionStore.follower_count
      end,
      setFollowerCount = function(_, g, n)
        optionStore.follower_count = n
        if g and g.save then g.save.pokepcFollowerCount = n end
        return n
      end,
      alignSaveFromOptions = function() end,
      onOptionsChanged = function() end,
    },
    spriteService = {
      resolveFollowerSprite = function(_, opts)
        return {
          id = "SPRITE_TEST", image = "land.png", frames = 6, walker = true,
          frameWidth = 24, frameHeight = 28, anchorX = 12, anchorY = 26,
        }
      end,
    },
  })
  engine._gameRef = game
  return engine
end

local function seedTrailers(engine, game, ow, n)
  game.save.pokepcFollowerCount = n
  optionStore.follower_count = n
  engine._rideSuppressFollowers = false
  engine:beginPresentationIntent(nil)
  engine._presentationIntent = nil
  engine:syncAll(game, ow)
  return #(ow.pokepcTrailers or {})
end

--------------------------------------------------------------------
-- GameCompat.isBiking / isFlying: Gen1
--------------------------------------------------------------------
do
  local Gen1 = V.require("game_compat/gen1")
  local ow = makeOw()
  check(Gen1.isBiking(nil, ow) == false, "Gen1: not biking by default")
  ow.player.onBike = true
  check(Gen1.isBiking(nil, ow) == true, "Gen1: player.onBike -> biking")
  ow.player.onBike = false
  local game = { save = { onBike = true } }
  check(Gen1.isBiking(game, ow) == true, "Gen1: save.onBike -> biking (no ow.player flag needed)")

  check(Gen1.isFlying(nil, ow) == false, "Gen1: not flying by default")
  ow.flyAnim = { phase = 1 }
  check(Gen1.isFlying(nil, ow) == true, "Gen1: ow.flyAnim -> flying")
  ow.flyAnim = nil
  ow.flyArrive = { t = 0 }
  check(Gen1.isFlying(nil, ow) == true, "Gen1: ow.flyArrive -> flying")
  ow.flyArrive = nil
  ow.flyFade = {}
  check(Gen1.isFlying(nil, ow) == true, "Gen1: ow.flyFade -> flying")
  ow.flyFade = nil
  check(Gen1.isFlying(nil, ow) == false, "Gen1: flying clears once all fly fields are nil")
end

--------------------------------------------------------------------
-- GameCompat.isBiking / isFlying: Gen2 (Gold)
--------------------------------------------------------------------
do
  local Gen2 = V.require("game_compat/gen2")
  package.loaded["src.world.gen2.FieldMoves"] = {
    isBiking = function(state) return state == "bike" end,
  }
  local world = { playerState = "normal", flyAnim = nil, flyHidden = nil }
  check(Gen2.isBiking(nil, world) == false, "Gen2: not biking by default")
  world.playerState = "bike"
  check(Gen2.isBiking(nil, world) == true, "Gen2: FieldMoves.isBiking true -> biking")
  world.playerState = "normal"

  check(Gen2.isFlying(nil, world) == false, "Gen2: not flying by default")
  world.flyAnim = { phase = 1 }
  check(Gen2.isFlying(nil, world) == true, "Gen2: world.flyAnim -> flying")
  world.flyAnim = nil
  world.flyHidden = true
  check(Gen2.isFlying(nil, world) == true, "Gen2: world.flyHidden -> flying")
  world.flyHidden = nil
  check(Gen2.isFlying(nil, world) == false, "Gen2: flying clears")
  package.loaded["src.world.gen2.FieldMoves"] = nil
end

--------------------------------------------------------------------
-- CASE 1: Biking — start once / stay / finish once (mirrors heal CASE1)
--------------------------------------------------------------------
do
  local ow = makeOw()
  local game = {
    save = { party = makeParty(3), pokepcFollowerCount = 3, pokepcControlMode = "follow" },
    data = {}, overworld = ow, generation = 1,
  }
  local engine = makeEngine(game, 3)
  eq(seedTrailers(engine, game, ow, 3), 3, "CASE1 seeded 3 trailers")
  eq(engine:runtimeTrailerCount(game), 3, "CASE1 runtime 3 before biking")

  ow.player.onBike = true
  engine:_pollRideSuppress(game, ow, {})
  check(engine._rideSuppressFollowers == true, "CASE1 suppressed once biking starts")
  eq(engine:followerCount(game), 3, "CASE1 configured count untouched")
  eq(engine:runtimeTrailerCount(game), 0, "CASE1 runtime 0 while biking")
  eq(#(ow.pokepcTrailers or {}), 0, "CASE1 trailers recalled")

  -- Many ticks while still biking — no repeated recall burst / no error.
  for _ = 1, 20 do
    engine:_pollRideSuppress(game, ow, { dt = 1 / 60 })
  end
  check(engine._rideSuppressFollowers == true, "CASE1 still suppressed mid-ride")
  eq(#(ow.pokepcTrailers or {}), 0, "CASE1 still no trailers mid-ride")

  ow.player.onBike = false
  engine:_pollRideSuppress(game, ow, {})
  check(engine._rideSuppressFollowers == false, "CASE1 suppress cleared on dismount")
  eq(engine:runtimeTrailerCount(game), 3, "CASE1 runtime restored to 3")
  eq(#(ow.pokepcTrailers or {}), 3, "CASE1 trailers released")

  -- Finish edge only once.
  for _ = 1, 5 do
    engine:_pollRideSuppress(game, ow, {})
  end
  eq(#(ow.pokepcTrailers or {}), 3, "CASE1 no duplicate trailers after idle polls")
end

--------------------------------------------------------------------
-- CASE 2: Flying — same suppress/restore shape, via ow.flyAnim
--------------------------------------------------------------------
do
  local ow = makeOw()
  local game = {
    save = { party = makeParty(2), pokepcFollowerCount = 2, pokepcControlMode = "follow" },
    data = {}, overworld = ow, generation = 1,
  }
  local engine = makeEngine(game, 2)
  eq(seedTrailers(engine, game, ow, 2), 2, "CASE2 seeded 2 trailers")

  ow.flyAnim = { phase = "takeoff" }
  engine:_pollRideSuppress(game, ow, {})
  eq(#(ow.pokepcTrailers or {}), 0, "CASE2 trailers recalled during flight")
  eq(engine:followerCount(game), 2, "CASE2 configured count untouched")

  ow.flyAnim = nil
  engine:_pollRideSuppress(game, ow, {})
  eq(#(ow.pokepcTrailers or {}), 2, "CASE2 trailers restored on landing")
end

--------------------------------------------------------------------
-- CASE 3: configured 0 — no FX / no error while biking
--------------------------------------------------------------------
do
  local ow = makeOw()
  local game = {
    save = { party = makeParty(1), pokepcFollowerCount = 0, pokepcControlMode = "follow" },
    data = {}, overworld = ow, generation = 1,
  }
  local engine = makeEngine(game, 0)
  seedTrailers(engine, game, ow, 0)
  eq(#(ow.pokepcTrailers or {}), 0, "CASE3 no trailers")
  ow.player.onBike = true
  local ok = pcall(function() engine:_pollRideSuppress(game, ow, {}) end)
  check(ok, "CASE3 bike start no error")
  ow.player.onBike = false
  ok = pcall(function() engine:_pollRideSuppress(game, ow, {}) end)
  check(ok, "CASE3 bike finish no error")
  eq(#(ow.pokepcTrailers or {}), 0, "CASE3 still no trailers")
end

--------------------------------------------------------------------
-- CASE 4: biking and flying are independent of Poké Center heal suppress
--------------------------------------------------------------------
do
  local ow = makeOw()
  local game = {
    save = { party = makeParty(1), pokepcFollowerCount = 1, pokepcControlMode = "follow" },
    data = {}, overworld = ow, generation = 1,
  }
  local engine = makeEngine(game, 1)
  seedTrailers(engine, game, ow, 1)

  ow.player.onBike = true
  engine:_pollRideSuppress(game, ow, {})
  eq(#(ow.pokepcTrailers or {}), 0, "CASE4 recalled by bike")
  check(engine:isHealingFollowerSuppressed() == false, "CASE4 heal suppress untouched by bike")

  ow.player.onBike = false
  engine:_pollRideSuppress(game, ow, {})
  eq(#(ow.pokepcTrailers or {}), 1, "CASE4 restored after dismount")
end

--------------------------------------------------------------------
-- Map exit clears stuck ride suppress (same safety valve as heal)
--------------------------------------------------------------------
do
  local ow = makeOw()
  local game = {
    save = { party = makeParty(1), pokepcFollowerCount = 1, pokepcControlMode = "follow" },
    data = {}, overworld = ow, generation = 1,
  }
  local engine = makeEngine(game, 1)
  engine._rideSuppressFollowers = true
  engine._wasRideActive = true
  engine._healingSuppressFollowers = true
  engine._wasHealMachineActive = true
  engine:_clearHealSuppress()
  check(engine._rideSuppressFollowers == false, "map-exit clears ride suppress")
  check(engine._wasRideActive == false, "map-exit clears wasRideActive")
  check(engine:isHealingFollowerSuppressed() == false, "map-exit still clears heal suppress too")
end

print(string.format("\n%d failures", failures))
os.exit(failures == 0 and 0 or 1)
