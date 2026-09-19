-- One-time shiny sparkle + chime in battle (Red/Blue/Yellow), the SHINY SPARKLE option.
-- Based on the battle sparkle intro of masterwebx's Shiny Pokemon mod (MIT,
-- https://github.com/masterwebx/gen1recomp-shiny-pokemon): the battle.overlay approach, waiting for the intro,
-- the spark burst and the "Dex Page Added" chime follow that mod. See THIRD_PARTY_NOTICES.md.
--
-- Uses the engine's own draw-only `battle.overlay` hook (BattleState / WideBattle call it at the end of
-- the battle draw, in 160x144 Game Boy coordinates). When a shiny Pokemon appears -- the wild enemy, or
-- your own lead when it is sent out -- a short burst of sparks plays over it once, with the game's
-- "Dex Page Added" chime. It waits for the intro (slide-in, trainer/send-out, grow-in) to finish, and it
-- plays once per Pokemon per battle (a shiny that is swapped in later gets its own burst).
--
-- Only the sparkle and chime live here: shininess itself comes from lib/shiny.lua. No recolor.
local V = ...

local ShinySparkle = {}

ShinySparkle.DURATION = 1.35 -- seconds
ShinySparkle.SFX = "Dex_Page_Added" -- a known engine SFX key (src/core/Sound.lua)

-- Where the burst is centered, in 160x144 battle coordinates (over the enemy pic / the player's back pic).
ShinySparkle.ANCHORS = {
  classic = { enemy = { 120, 32 }, player = { 40, 88 } },
  wide = { enemy = { 200, 40 }, player = { 60, 100 } },
}

local function enabled(mod)
  local ok, Config = pcall(function() return V.require("config") end)
  if not (ok and Config and type(Config.shinySparkleEnabled) == "function") then return false end
  local okRead, on = pcall(Config.shinySparkleEnabled, mod)
  return okRead and on == true
end

local function nowSeconds()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function isShinyMon(mon)
  local ok, Shiny = pcall(function() return V.require("shiny") end)
  if ok and Shiny and type(Shiny.isShiny) == "function" then return Shiny.isShiny(mon) end
  return type(mon) == "table" and mon.shiny == true
end

--- The battle intro for that side is over (slide-in done, no trainer / send-out / grow-in animation).
function ShinySparkle.ready(battle, isEnemy)
  if type(battle) ~= "table" then return false end
  if (battle.introSlide or 0) > 0 then return false end
  local growing = type(battle.growInScale) == "function"
  if isEnemy then
    if battle.showEnemyTrainer or battle.enemySendingOut then return false end
    if growing and battle:growInScale(battle.enemy) then return false end
  else
    if battle.showPlayerBack or battle.sendingOut then return false end
    if growing and battle:growInScale(battle.player) then return false end
  end
  return true
end

local function isWide(battle)
  if battle.wide then return true end
  if type(battle.wideLayout) == "function" then
    local ok, wide = pcall(battle.wideLayout, battle)
    return ok and wide == true
  end
  return false
end

local function playChime(battle)
  local data = (battle.game and battle.game.data) or battle.data
  if not data then return false end
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and Sound and type(Sound.play) == "function") then return false end
  return pcall(Sound.play, data, ShinySparkle.SFX)
end

-- battle -> { [mon] = { t0 } }, both weak, so finished battles and swapped-out mons are collected.
local triggered = setmetatable({}, { __mode = "k" })

--- Advance the sparkle state for one overlay draw and return the bursts to paint now:
-- { { side, progress (0..1), x, y, seed }, ... }. `deps` = { now, playSfx } is injectable for tests.
function ShinySparkle.step(mod, battle, deps)
  local out = {}
  if type(battle) ~= "table" or not enabled(mod) then return out end
  deps = deps or {}
  local t = (deps.now or nowSeconds)()
  local seen = triggered[battle]
  if not seen then
    seen = setmetatable({}, { __mode = "k" })
    triggered[battle] = seen
  end
  local anchors = isWide(battle) and ShinySparkle.ANCHORS.wide or ShinySparkle.ANCHORS.classic

  for _, side in ipairs({ "enemy", "player" }) do
    local isEnemy = side == "enemy"
    local battler = battle[side]
    local mon = type(battler) == "table" and battler.mon or nil
    local hidden = (not isEnemy) and (battle.safari or battle.demo)
    if mon and not hidden and not battler.fainted and isShinyMon(mon) then
      local entry = seen[mon]
      if not entry and ShinySparkle.ready(battle, isEnemy) then
        entry = { t0 = t }
        seen[mon] = entry
        pcall(deps.playSfx or playChime, battle)
      end
      if entry then
        local progress = (t - entry.t0) / ShinySparkle.DURATION
        if progress >= 0 and progress < 1 then
          local a = anchors[side]
          out[#out + 1] = {
            side = side, progress = progress, x = a[1], y = a[2],
            seed = (mon.level or 1) + (isEnemy and 3 or 7),
          }
        end
      end
    end
  end
  return out
end

--- Paint one burst: eight sparks fly out from (x, y) and shrink and fade, with a brief center flash.
-- Opaque colors only: alpha blending disappears under some of the engine's palette passes.
function ShinySparkle.drawBurst(x, y, progress, seed, scale)
  if not (love and love.graphics) then return end
  scale = scale or 1.25
  local burst = math.min(1, progress / 0.18)
  local fadingOut = progress > 0.65
  local sparks = 8
  for i = 1, sparks do
    local angle = (i / sparks) * math.pi * 2 + (seed or 0) * 0.2
    local radius = (4 + progress * 14 + (i % 3) * 2) * scale
    local sx = x + math.cos(angle) * radius * burst
    local sy = y + math.sin(angle * 1.05) * radius * 0.75 * burst - 2 * scale
    local size = math.max(2, math.floor((2.5 - progress) * scale + 0.5))
    love.graphics.setColor(1, 1, 0.35, 1)
    love.graphics.rectangle("fill", math.floor(sx), math.floor(sy), size, size)
    if not fadingOut then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", math.floor(sx) - 1, math.floor(sy), 1, size)
    end
  end
  if progress < 0.4 then
    local s = math.max(3, math.floor(3 * scale + 0.5))
    love.graphics.setColor(1, 1, 0.7, 1)
    love.graphics.rectangle("fill", math.floor(x) - math.floor(s / 2), math.floor(y) - math.floor(s / 2), s, s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- The `battle.overlay` body: advance the state and paint whatever is active.
function ShinySparkle.draw(mod, battle)
  for _, burst in ipairs(ShinySparkle.step(mod, battle)) do
    ShinySparkle.drawBurst(burst.x, burst.y, burst.progress, burst.seed)
  end
end

local unwrap

--- Register the `battle.overlay` wrapper (once). Returns true, or false plus a reason. Never throws.
function ShinySparkle.install(mod)
  if unwrap then return true end
  if not (mod and mod.hooks and type(mod.hooks.wrap) == "function") then return false, "hooks unavailable" end
  local ok, result = pcall(mod.hooks.wrap, mod.hooks, "battle.overlay", function(next, battle)
    next(battle)
    pcall(ShinySparkle.draw, mod, battle)
  end)
  if not ok then return false, tostring(result) end
  unwrap = result or true
  return true
end

return ShinySparkle
