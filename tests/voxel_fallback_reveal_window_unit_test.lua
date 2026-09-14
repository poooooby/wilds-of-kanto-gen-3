-- Regression: VoxelAdapter:markFallback must stay silent for the expected,
-- self-healing "no billboard yet" window every freshly-spawned entity goes
-- through (SpawnFx keeps hiddenBody=true for ~0.3-0.6s), while still
-- logging a genuine failure once the body is supposed to be visible.
-- Reported live: Viridian Forest spammed "World billboard failed ...
-- (pose() returned nil sprite)" for every newly-spawned Pokemon; a live
-- simulation confirmed 100% of fresh spawns fail pose() at frame zero and
-- 100% succeed one second later, purely a timing artifact.
-- Run: lua tests/voxel_fallback_reveal_window_unit_test.lua
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

local warnCount = 0
local modules = {}
local V = {
  mod = {
    path = ".",
    log = {
      info = function() end,
      warn = function() warnCount = warnCount + 1 end,
      error = function() end,
    },
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

local VoxelAdapter = V.require("voxel_adapter")
local adapter = VoxelAdapter.new(V.mod)

print("== during the spawn-reveal window (hiddenBody=true): stay silent ==")
warnCount = 0
local reveal = { id = "wilds_of_kanto_entity_51", hiddenBody = true }
adapter:markFallback(reveal, "pose() returned nil sprite")
check(warnCount == 0, "no warning logged while the body is still hidden")
check(reveal.render2DFallback == true, "fallback state still applied (rendering unaffected)")
check(reveal.voxelDisabled == true, "voxel still disabled for this entity")

print("== spawn FX in progress but not yet bodyShown: also silent ==")
warnCount = 0
local revealFx = {
  id = "wilds_of_kanto_entity_52",
  hiddenBody = false,
  spawnFx = { done = false, bodyShown = false },
}
adapter:markFallback(revealFx, "pose() returned nil sprite")
check(warnCount == 0, "no warning logged while spawnFx has not shown the body yet")

print("== body genuinely visible: a real failure still logs ==")
warnCount = 0
local visible = { id = "wilds_of_kanto_entity_53", hiddenBody = false }
adapter:markFallback(visible, "pose() returned nil sprite")
check(warnCount == 1, "warning still logged once the body is supposed to be visible")
check(visible.render2DFallback == true, "fallback state still applied")

print("== reveal finished (spawnFx.done): a real failure still logs ==")
warnCount = 0
local doneFx = {
  id = "wilds_of_kanto_entity_54",
  hiddenBody = false,
  spawnFx = { done = true, bodyShown = true },
}
adapter:markFallback(doneFx, "pose() returned nil sprite")
check(warnCount == 1, "warning logged once the reveal animation has finished")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("voxel_fallback_reveal_window_unit_test: all passed")
