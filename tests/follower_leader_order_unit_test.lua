-- Follower trail order always matches party order -- no leader override.
-- ControlEngine:getLeaderMon must ignore save.pokepcLeader,
-- save.followerPartyIndex, and Yellow's old forced-slot-2 case; it always
-- returns the first healthy party mon.
-- Run: luajit tests/follower_leader_order_unit_test.lua
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
  new = function(def, id) return { def = def, id = id, draw = function() end } end,
}
package.loaded["src.world.NPC"] = {
  new = function(_, _, def)
    return {
      id = "WILDS_TRAILER_" .. tostring(def and def.index or 0),
      cellX = def and def.x or 0, cellY = def and def.y or 0,
      px = (def and def.x or 0) * 16, py = (def and def.y or 0) * 16,
      facing = "down", moving = false, progress = 0,
      update = function() end,
      pose = function(ent) return ent.sprite, ent.px, ent.py, ent.facing, 0, false end,
    }
  end,
  walkPhase = function() return 0 end,
}
package.loaded["src.world.OverworldController"] = {
  update = function() end, interact = function() end, talkTo = function() end,
}
package.loaded["src.core.GameVersion"] = {
  get = function() return "red" end,
  isYellow = function() return false end,
  isGold = function() return false end,
  generation = function() return 1 end,
}

local modules = {}
local optionStore = { follower_count = 1, control_mode = "follow", sprite_style = "pokemmo" }
local V = {
  mod = {
    path = ".", id = "wilds_of_kanto_gen3",
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
  DEFAULTS = { sprite_style = "pokemmo", follower_count = 1 },
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
  isFollowerEntity = function(e) return e and (e.pokepcTrailer == true or e.wildsFollower == true) end,
  isBlockingEntity = function(e)
    if not e then return false end
    if e.fxOnly == true or e.pureFx == true then return false end
    return e.pokepcTrailer == true or e.wildsFollower == true
  end,
}
modules.surface = { WATER = "WATER" }

local ControlEngine = V.require("follower/control_engine")
local Selection = V.require("follower/selection")
local State = V.require("follower/state")

local function makeMon(species, slot, hp)
  return {
    species = species, hp = hp or 20, otId = 1000 + slot,
    dvs = { attack = slot, defense = 2, speed = 3, special = 4 }, catchRate = 45,
  }
end

local function makeEngine(game, count)
  optionStore.follower_count = count
  local state = State.new(V.mod)
  local selection = Selection.new(V.mod, state)
  local engine = ControlEngine.new(V.mod, {
    selection = selection,
    settings = {
      engineMode = function() return "follow" end,
      followerCount = function(_, g) return (g and g.save and g.save.pokepcFollowerCount) or optionStore.follower_count end,
      setFollowerCount = function(_, g, n)
        optionStore.follower_count = n
        if g and g.save then g.save.pokepcFollowerCount = n end
        return n
      end,
      alignSaveFromOptions = function() end,
      onOptionsChanged = function() end,
    },
    spriteService = {
      resolveFollowerSprite = function() return { id = "SPRITE_TEST", image = "land.png", frames = 6, walker = true } end,
    },
  })
  engine._gameRef = game
  return engine
end

--------------------------------------------------------------------
-- getLeaderMon ignores save.pokepcLeader entirely
--------------------------------------------------------------------
do
  local m1, m2 = makeMon("CHARMANDER", 1), makeMon("SQUIRTLE", 2)
  local game = {
    save = {
      party = { m1, m2 }, pokepcFollowerCount = 1,
      -- An explicit (now-inert) party-source leader pointing at slot 2.
      pokepcLeader = { source = "party", index = 2 },
    },
  }
  local engine = makeEngine(game, 1)
  local leader, src = engine:getLeaderMon(game)
  eq(leader, m1, "pokepcLeader party-source override is ignored -- always slot 1")
  eq(src, "party", "source is still reported as party")
end

--------------------------------------------------------------------
-- getLeaderMon ignores a box-leader pick (zero callers set this in
-- practice, but confirm it's truly inert now, not just unreachable)
--------------------------------------------------------------------
do
  local m1 = makeMon("BULBASAUR", 1)
  local game = {
    save = {
      party = { m1 }, pokepcFollowerCount = 1,
      pokepcLeader = { source = "box", box = 1, index = 1 },
      boxes = { { { species = "MEWTWO", hp = 100 } } },
    },
  }
  local engine = makeEngine(game, 1)
  local leader, src = engine:getLeaderMon(game)
  eq(leader, m1, "box-leader pick is ignored -- always first healthy party mon")
  eq(src, "party", "source is party, never box")
end

--------------------------------------------------------------------
-- getLeaderMon ignores save.followerPartyIndex
--------------------------------------------------------------------
do
  local m1, m2, m3 = makeMon("PIDGEY", 1), makeMon("RATTATA", 2), makeMon("WEEDLE", 3)
  local game = {
    save = { party = { m1, m2, m3 }, pokepcFollowerCount = 1, followerPartyIndex = 3 },
  }
  local engine = makeEngine(game, 1)
  local leader = engine:getLeaderMon(game)
  eq(leader, m1, "followerPartyIndex is ignored -- always slot 1")
end

--------------------------------------------------------------------
-- getLeaderMon ignores Yellow's old forced-slot-2 case (Pikachu in slot 1,
-- healthy slot 2 used to jump ahead of it -- not anymore)
--------------------------------------------------------------------
do
  package.loaded["src.core.GameVersion"] = {
    get = function() return "yellow" end, isYellow = function() return true end,
    isGold = function() return false end, generation = function() return 1 end,
  }
  local pikachu, eevee = makeMon("PIKACHU", 1), makeMon("EEVEE", 2)
  local game = { save = { party = { pikachu, eevee }, pokepcFollowerCount = 1 } }
  local engine = makeEngine(game, 1)
  local leader = engine:getLeaderMon(game)
  eq(leader, pikachu, "Yellow: slot 1 (Pikachu) leads, not the old forced slot-2 override")
  package.loaded["src.core.GameVersion"] = {
    get = function() return "red" end, isYellow = function() return false end,
    isGold = function() return false end, generation = function() return 1 end,
  }
end

--------------------------------------------------------------------
-- getLeaderMon: fainted slot 1 still correctly fails over to the next
-- healthy mon, in party order (this part of the rule is unchanged)
--------------------------------------------------------------------
do
  local fainted, healthy = makeMon("CHARMANDER", 1, 0), makeMon("SQUIRTLE", 2, 20)
  local game = { save = { party = { fainted, healthy }, pokepcFollowerCount = 1 } }
  local engine = makeEngine(game, 1)
  local leader = engine:getLeaderMon(game)
  eq(leader, healthy, "fainted slot 1 fails over to the next healthy party mon")
end

--------------------------------------------------------------------
-- getLeaderMon: reordering the party changes the leader, instantly
--------------------------------------------------------------------
do
  local m1, m2 = makeMon("ODDISH", 1), makeMon("GASTLY", 2)
  local game = { save = { party = { m1, m2 }, pokepcFollowerCount = 1 } }
  local engine = makeEngine(game, 1)
  eq((engine:getLeaderMon(game)), m1, "leader is slot 1 before reorder")
  game.save.party = { m2, m1 }
  eq((engine:getLeaderMon(game)), m2, "leader follows the party reorder instantly")
end

print(string.format("\n%d failures", failures))
os.exit(failures == 0 and 0 or 1)
