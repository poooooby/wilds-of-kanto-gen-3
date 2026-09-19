-- lib/shiny_sparkle.lua: the one-time battle sparkle + chime (SHINY SPARKLE option).
-- Run: lua tests/shiny_sparkle_unit_test.lua
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

-- ---------------------------------------------------------------- fixtures
local savedOpts = {}
local mod = {
  id = "wilds_of_kanto_gen3", path = ".",
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k) return savedOpts[k] end },
}
local modules = {}
local V = { mod = mod, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Config = V.require("config")
local Sparkle = V.require("shiny_sparkle")

local SHINY_DVS = { attack = 15, defense = 10, speed = 10, special = 10, hp = 9 }
local function shinyMon(level) return { species = "PIDGEY", level = level or 5, shiny = true, dvs = SHINY_DVS } end
local function plainMon() return { species = "RATTATA", level = 5, dvs = { attack = 1, defense = 1, speed = 1, special = 1, hp = 15 } } end

-- a battle whose intro is over
local function readyBattle(enemyMon, playerMon)
  return {
    introSlide = 0,
    enemy = { mon = enemyMon },
    player = { mon = playerMon },
  }
end

local now, sfx = 0, 0
local deps = { now = function() return now end, playSfx = function() sfx = sfx + 1 end }
local function step(battle) return Sparkle.step(mod, battle, deps) end
local function reset() now, sfx = 0, 0 end

-- ---------------------------------------------------------------- option
savedOpts = {}
eq(Config.shinySparkleEnabled(mod), true, "option: defaults ON")
savedOpts.shiny_sparkle = false
eq(Config.shinySparkleEnabled(mod), false, "option: schema value false")
savedOpts = {}
local schema = assert(loadfile("options.lua"))()
local row
for _, r in ipairs(schema) do if r.key == "shiny_sparkle" then row = r end end
check(row ~= nil and row.type == "toggle" and row.default == true, "options: shiny_sparkle toggle, default ON")
check(row and #row.label <= 14, "options: label fits")

-- ---------------------------------------------------------------- off / non-shiny
reset()
savedOpts.shiny_sparkle = false
eq(#step(readyBattle(shinyMon(), nil)), 0, "off: no sparkle")
eq(sfx, 0, "off: no chime")
savedOpts = {}
reset()
eq(#step(readyBattle(plainMon(), plainMon())), 0, "non-shiny: no sparkle")
eq(sfx, 0, "non-shiny: no chime")
eq(#step(nil), 0, "no battle: nothing")

-- ---------------------------------------------------------------- wild shiny plays once
reset()
local b = readyBattle(shinyMon(), plainMon())
local bursts = step(b)
eq(#bursts, 1, "wild shiny: one burst starts")
eq(bursts[1].side, "enemy", "wild shiny: on the enemy")
eq(bursts[1].x, 120, "wild shiny: enemy anchor x")
eq(bursts[1].y, 32, "wild shiny: enemy anchor y")
eq(bursts[1].progress, 0, "wild shiny: starts at progress 0")
eq(sfx, 1, "wild shiny: chime once")
now = 0.5
bursts = step(b)
check(#bursts == 1 and math.abs(bursts[1].progress - 0.5 / Sparkle.DURATION) < 1e-9, "wild shiny: progresses with time")
eq(sfx, 1, "wild shiny: no second chime mid-burst")
now = Sparkle.DURATION + 0.01
eq(#step(b), 0, "wild shiny: burst ends after its duration")
now = Sparkle.DURATION + 5
eq(#step(b), 0, "wild shiny: never replays in the same battle")
eq(sfx, 1, "wild shiny: exactly one chime for the whole battle")

-- ---------------------------------------------------------------- waits for the intro
local function notReadyCases()
  return {
    { "introSlide", { introSlide = 3 } },
    { "trainer shown", { showEnemyTrainer = true } },
    { "enemy sending out", { enemySendingOut = true } },
    { "enemy growing in", { growInScale = function() return 0 end } },
  }
end
for _, case in ipairs(notReadyCases()) do
  reset()
  local nb = readyBattle(shinyMon(), nil)
  for k, v in pairs(case[2]) do nb[k] = v end
  eq(#step(nb), 0, "enemy not ready (" .. case[1] .. "): no sparkle yet")
  eq(sfx, 0, "enemy not ready (" .. case[1] .. "): no chime yet")
  for k in pairs(case[2]) do nb[k] = (k == "introSlide") and 0 or nil end
  nb.growInScale = nil
  now = 1
  eq(#step(nb), 1, "enemy ready after (" .. case[1] .. "): sparkle starts")
  eq(sfx, 1, "enemy ready after (" .. case[1] .. "): chime once")
end

-- ---------------------------------------------------------------- your own shiny lead
reset()
local both = readyBattle(shinyMon(7), nil)
both.player.mon = shinyMon(9)
bursts = step(both)
eq(#bursts, 2, "both shiny: two bursts")
local sides = {}
for _, burst in ipairs(bursts) do sides[burst.side] = burst end
check(sides.enemy and sides.player, "both shiny: enemy and player")
eq(sides.player and sides.player.x, 40, "both shiny: player anchor x")
eq(sides.player and sides.player.y, 88, "both shiny: player anchor y")
eq(sfx, 2, "both shiny: one chime per side")

reset()
local pb = readyBattle(plainMon(), shinyMon())
pb.showPlayerBack = true
eq(#step(pb), 0, "player: waits while the back pic is shown")
pb.showPlayerBack = false
pb.sendingOut = true
eq(#step(pb), 0, "player: waits while sending out")
pb.sendingOut = false
eq(#step(pb), 1, "player: sparkles once sent out")

reset()
local safari = readyBattle(plainMon(), shinyMon())
safari.safari = true
eq(#step(safari), 0, "safari: player side never sparkles")
local demo = readyBattle(plainMon(), shinyMon())
demo.demo = true
eq(#step(demo), 0, "demo: player side never sparkles")

-- ---------------------------------------------------------------- layouts, faint, DVs-only shinies
reset()
local wide = readyBattle(shinyMon(), shinyMon())
wide.wide = true
bursts = step(wide)
sides = {}
for _, burst in ipairs(bursts) do sides[burst.side] = burst end
check(sides.enemy and sides.enemy.x == 200 and sides.enemy.y == 40, "wide layout: enemy anchor")
check(sides.player and sides.player.x == 60 and sides.player.y == 100, "wide layout: player anchor")
reset()
local wideFn = readyBattle(shinyMon(), nil)
wideFn.wideLayout = function() return true end
eq(step(wideFn)[1].x, 200, "wide layout: wideLayout() is honored")

reset()
local fainted = readyBattle(shinyMon(), nil)
fainted.enemy.fainted = true
eq(#step(fainted), 0, "fainted enemy: no sparkle")

reset()
local dvOnly = readyBattle({ species = "PIDGEY", level = 5, dvs = SHINY_DVS }, nil)
eq(#step(dvOnly), 1, "shiny DVs without the flag still sparkle")

-- ---------------------------------------------------------------- once per Pokemon per battle
reset()
local sw = readyBattle(plainMon(), shinyMon(5))
step(sw)
eq(sfx, 1, "swap: first shiny chimes")
now = 10
eq(#step(sw), 0, "swap: same mon does not replay")
sw.player.mon = shinyMon(6) -- a different shiny is sent in
now = 11
eq(#step(sw), 1, "swap: a newly sent-in shiny gets its own burst")
eq(sfx, 2, "swap: and its own chime")
local sameMonNewBattle = readyBattle(plainMon(), sw.player.mon)
now = 12
eq(#step(sameMonNewBattle), 1, "a new battle starts fresh")

-- ---------------------------------------------------------------- drawBurst
local calls = { rect = 0, color = 0, last = nil }
love = {
  graphics = {
    rectangle = function() calls.rect = calls.rect + 1 end,
    setColor = function(...) calls.color = calls.color + 1; calls.last = { ... } end,
  },
}
Sparkle.drawBurst(120, 32, 0.1, 8)
check(calls.rect >= 8, "drawBurst: paints the sparks (" .. calls.rect .. " rects)")
check(calls.last and calls.last[1] == 1 and calls.last[2] == 1 and calls.last[3] == 1 and calls.last[4] == 1,
  "drawBurst: restores the color to white")
calls.rect = 0
Sparkle.drawBurst(120, 32, 0.9, 8)
check(calls.rect >= 8, "drawBurst: late frames still paint")
love = nil
local okNoLove = pcall(Sparkle.drawBurst, 1, 2, 0.5, 3)
check(okNoLove, "drawBurst: safe without love.graphics")

-- ---------------------------------------------------------------- install
local wrapped = {}
local fakeMod = {
  id = "wilds_of_kanto_gen3", path = ".",
  options = mod.options,
  hooks = { wrap = function(self, name, fn) wrapped[#wrapped + 1] = { name = name, fn = fn }; return function() end end },
}
love = { graphics = { rectangle = function() calls.rect = calls.rect + 1 end, setColor = function() end } }
local okInstall = Sparkle.install(fakeMod)
eq(okInstall, true, "install: ok")
eq(#wrapped, 1, "install: one hook registered")
eq(wrapped[1] and wrapped[1].name, "battle.overlay", "install: uses the engine's battle.overlay hook")
eq(Sparkle.install(fakeMod), true, "install: second call ok")
eq(#wrapped, 1, "install: idempotent (not wrapped twice)")

local nextCalls = 0
local ovBattle = readyBattle(shinyMon(), nil)
calls.rect = 0
wrapped[1].fn(function(bt) nextCalls = nextCalls + 1 end, ovBattle)
eq(nextCalls, 1, "overlay wrapper: calls the rest of the chain first")
check(calls.rect >= 8, "overlay wrapper: paints the sparkle")
local okBad = pcall(wrapped[1].fn, function() end, { enemy = "garbage", player = 12 })
check(okBad, "overlay wrapper: never throws into the engine")
love = nil

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
