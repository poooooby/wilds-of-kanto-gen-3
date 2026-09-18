-- ControlEngine:_trailerCatchUpDivisor -- the shared catch-up speed formula
-- used by both _assignTrailerStep and _chainCatchUpSteps. This is the
-- safety net for the anti-slingshot property (see the "chain break" bug
-- history in docs/analysis/TRUE_SIZE_SYSTEM.md / CHANGELOG.md's "2.0.1"
-- entry): a fold in the player's path must NOT make the whole pack dash at
-- once, but a genuinely-behind trailer (e.g. after a long, fast player
-- dash) should close its gap faster the further behind it is.
-- Run: lua tests/follower_catchup_divisor_unit_test.lua
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
package.loaded["src.world.NPC"] = {
  new = function() return {} end,
  walkPhase = function() return 0 end,
}

local modules = {}
local V = {
  mod = { path = ".", id = "overworld_wild_spawns",
    log = { info = function() end, warn = function() end },
    find = function() return nil end,
    options = { get = function() return nil end } },
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
modules.debug_log = { warn = function() end, info = function() end, error = function() end, debug = function() end }
modules.tile = { CELL = 16 }
modules.cell_occupancy = { isFollowerEntity = function(e) return e and e.pokepcTrailer == true end }
modules.surface = { WATER = "WATER" }

local ControlEngine = V.require("follower/control_engine")
local engine = ControlEngine.new(V.mod, {
  settings = { followerCount = function() return 6 end, engineMode = function() return "follow" end },
  game = nil,
})

----------------------------------------------------------------
-- Steady state: every slot at its expected head-distance -> no catch-up.
----------------------------------------------------------------
for slot = 1, 6 do
  eq(engine:_trailerCatchUpDivisor(slot, slot), 1,
    "slot " .. slot .. " at its own steady-state head-distance: no catch-up")
  -- The documented "+1 slack": exactly one cell beyond steady-state is
  -- still normal, not yet a genuine straggler.
  eq(engine:_trailerCatchUpDivisor(slot + 1, slot), 1,
    "slot " .. slot .. " one cell beyond steady-state (the slack): still no catch-up")
end

----------------------------------------------------------------
-- Anti-slingshot: a normal fold bump must NOT trigger catch-up for anyone.
-- The original bug was every slot simultaneously reading "lagging" during
-- a reversal fold and dashing through it at once.
----------------------------------------------------------------
do
  local FOLD_BUMP = 2 -- doubled-back lag indexing can jump a couple of cells
  for slot = 1, 6 do
    local headDist = slot + FOLD_BUMP
    -- A bump of exactly 2 still only exceeds the +1 slack by 1 -- expect at
    -- most a mild divisor, never the pack-wide dash the fold protection
    -- exists to prevent. This pins down that a small, expected fold bump
    -- doesn't explode into a large multiplier for every slot at once.
    local divisor = engine:_trailerCatchUpDivisor(headDist, slot)
    check(divisor <= 2,
      "slot " .. slot .. " with a normal fold bump (+" .. FOLD_BUMP
        .. ") stays at a mild divisor, not a full dash (got " .. tostring(divisor) .. ")")
  end
end

----------------------------------------------------------------
-- Genuine straggler: proportional scaling, not a flat 2x for any amount.
----------------------------------------------------------------
do
  local slot = 6
  -- Just past the slack -> the smallest real catch-up bump.
  eq(engine:_trailerCatchUpDivisor(slot + 2, slot), 2,
    "just past the slack: smallest catch-up bump (2x)")
  -- Meaningfully behind (e.g. after a long dash) -> faster than 2x.
  check(engine:_trailerCatchUpDivisor(slot + 6, slot) > 2,
    "well behind its slot: divisor scales up beyond a flat 2x")
  -- A very large gap must still cap out (never truly unbounded / a literal
  -- teleport-speed value) -- the existing jam-recovery system handles the
  -- genuinely-stuck case; this formula only ever speeds up walking.
  eq(engine:_trailerCatchUpDivisor(slot + 1000, slot), 4,
    "an extreme gap still caps at a bounded maximum divisor")
end

----------------------------------------------------------------
-- Monotonic: divisor never decreases as the gap grows (no weird dips).
----------------------------------------------------------------
do
  local slot = 3
  local prev = engine:_trailerCatchUpDivisor(slot, slot)
  for headDist = slot, slot + 20 do
    local d = engine:_trailerCatchUpDivisor(headDist, slot)
    check(d >= prev, "divisor is monotonically non-decreasing as headDist grows (headDist="
      .. headDist .. ")")
    prev = d
  end
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nall passed")
