-- True Size visual follower trail spacing (history lag, not collision).
-- Run: lua tests/follower_trail_spacing_unit_test.lua
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
  DEFAULT_FRAME_WIDTH = 16,
  DEFAULT_FRAME_HEIGHT = 16,
  getFrameGeometry = function() end,
  getPoseGeometry = function() end,
  getScreenOrigin = function() end,
}

local modules = {}
local savedOpts = { pokemon_size = "true_size", sprite_style = "pokemmo" }
local V = {
  mod = {
    path = ".",
    log = { info = function() end },
    find = function() return nil end,
    options = {
      get = function(_, k) return savedOpts[k] end,
      set = function(_, k, v) savedOpts[k] = v end,
    },
    read = function(_, rel)
      local f = io.open(rel, "rb") or io.open("./" .. rel, "rb")
      if not f then return nil end
      local data = f:read("*a"); f:close(); return data
    end,
    assets = { path = function(_, rel) return rel end },
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
  DEFAULTS = { pokemon_size = "classic", sprite_style = "followers" },
  peekSavedOption = function(_, k)
    if savedOpts[k] ~= nil then return savedOpts[k], true end
    return nil, false
  end,
  pokemonSizeMode = function()
    return savedOpts.pokemon_size or "classic"
  end,
  normalizePokemonSize = function(v)
    if v == "true_size" then return "true_size" end
    return "classic"
  end,
  normalizeSpriteStyle = function(v) return v or "followers" end,
  spriteStyle = function() return savedOpts.sprite_style or "followers" end,
  debug = function() return false end,
}
modules.debug_log = { warn = function() end, info = function() end, error = function() end, debug = function() end }
modules.tile = { CELL = 16, WIDTH = 16, HEIGHT = 16 }
modules.json_decode = assert(loadfile("lib/json_decode.lua"))(V)

local SpeciesGeometry = V.require("species_geometry")
local VariableSize = V.require("variable_size")

eq(SpeciesGeometry.followGap(25), 1, "Pikachu S gap=1")
eq(SpeciesGeometry.followGap(19), 1, "Rattata native/S gap=1")
-- Native HGSS Blastoise (~26px) is class L → gap 1 (no longer targetHeight XL).
eq(SpeciesGeometry.followGap(9), 1, "Blastoise native/L gap=1")
eq(SpeciesGeometry.followGap(6), 2, "Charizard XL gap=2")
eq(SpeciesGeometry.followGap(143), 2, "Snorlax override/XXL gap=2")
eq(SpeciesGeometry.followGap(95), 3, "Onix override gap=3")
eq(SpeciesGeometry.followGap(130), 3, "Gyarados override gap=3")
eq(SpeciesGeometry.followGapBetween(9, 25), 1, "Pikachu behind Blastoise uses max=1")
eq(SpeciesGeometry.followGapBetween(nil, 25), 1, "first follower Pikachu gap=1")
eq(SpeciesGeometry.followGapBetween(nil, 9), 1, "first follower Blastoise gap=1")

-- Charizard's exact value is hand-tunable in lib/species_display_scale.lua,
-- so only assert it's a real, non-default override, not a specific number.
check(SpeciesGeometry.displayScale(6) ~= 1, "Charizard has a display scale override")
-- The base table is now a complete, hand-authored 386-entry set (every
-- valid species has a real value) -- so "no entry" can only be tested via a
-- species id outside the valid range, not a real species like Pikachu.
eq(SpeciesGeometry.displayScale(9999), 1, "out-of-range species display scale default")
eq(SpeciesGeometry.displayScale(nil), 1, "nil species display scale default")

-- Per-style overrides layer on top of the shared base table.
modules["species_display_scale_style_overrides"] = { [143] = { pmdcollab = 0.4 } }
eq(SpeciesGeometry.displayScale(143, "pmdcollab"), 0.4, "Snorlax PMD-specific override wins")
check(SpeciesGeometry.displayScale(143, "pokemmo") ~= 0.4,
  "Snorlax HGSS style unaffected by PMD-only override")
eq(SpeciesGeometry.displayScale(9999, "pmdcollab"), 1,
  "out-of-range species with no override stays at 1 under pmdcollab")
-- PMD does NOT inherit the shared base table at all (it's calibrated
-- against HGSS/True Size's own pixel dimensions, unrelated to PMD's own
-- native art) -- Charizard's non-1x base value must not leak into PMD.
eq(SpeciesGeometry.displayScale(6, "pokemmo"), SpeciesGeometry.displayScale(6),
  "Charizard base value still applies under pokemmo (a True Size style)")
eq(SpeciesGeometry.displayScale(6, "pmdcollab"), 1,
  "Charizard base value does NOT leak into pmdcollab")
-- Poke Followers does NOT inherit the shared base table either: its own
-- provider (_makeFollowersExProvider) never sets real frameWidth/frameHeight
-- on its def (no True Size data, unlike pokemmo), so the base table -- HGSS-
-- calibrated -- would apply to an unrelated native art size if it leaked in.
eq(SpeciesGeometry.displayScale(6, "followers"), 1,
  "Charizard base value does NOT leak into followers")
local rdw, rdh, rax, ray = SpeciesGeometry.resolveDisplayGeometry(143, "pmdcollab", 20, 20, 10, 20)
eq(rdw, 8, "resolveDisplayGeometry width uses per-style scale")
eq(rdh, 8, "resolveDisplayGeometry height uses per-style scale")
eq(rax, 4, "resolveDisplayGeometry anchorX scales with width")
eq(ray, 8, "resolveDisplayGeometry anchorY scales with height")
local ndw = SpeciesGeometry.resolveDisplayGeometry(25, "pmdcollab", 20, 20, 10, 20)
eq(ndw, nil, "resolveDisplayGeometry returns nil at scale 1")
SpeciesGeometry.clearCache()

-- Classic effective → visualFollowGap always 1
savedOpts.pokemon_size = "classic"
eq(VariableSize.visualFollowGap(V.mod, 95), 1, "Classic mode Onix gap=1")
savedOpts.pokemon_size = "true_size"
eq(VariableSize.visualFollowGap(V.mod, 95), 3, "True Size Onix gap=3")

-- ControlEngine history lag assignment
local ControlEngine = V.require("follower/control_engine")
local engine = setmetatable({
  mod = V.mod,
  diag = {},
}, ControlEngine)

check(engine:_visualTrailSpacingActive() == true, "trail spacing active in True Size")

local ow = { pokepcTrailHistory = {} }
-- Simulate trainer path: cells vacated in order A B C D E F G H
local path = {
  {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6},{0,7},{0,8},{0,9},
}
for _, c in ipairs(path) do
  engine:_pushTrailHistory(ow, c[1], c[2])
end
-- history[1] is most recent (0,9)

local blastoise = { _wildsFollowerDex = 9, _wildsFollowerSpecies = "BLASTOISE" }
local pikachu = { _wildsFollowerDex = 25, _wildsFollowerSpecies = "PIKACHU" }
local goals = engine:_goalsFromTrailHistory(ow, { blastoise, pikachu }, 0, 9)
-- Native Blastoise gap=1 → history[1]=(0,9); Pikachu stepGap=max(1,1)=1 → lag=2 → history[2]=(0,8)
eq(goals[1].y, 9, "Blastoise follows lag=1")
eq(goals[2].y, 8, "Pikachu follows lag=2 (accumulates behind Blastoise)")

local onix = { _wildsFollowerDex = 95 }
local snorlax = { _wildsFollowerDex = 143 }
local goals2 = engine:_goalsFromTrailHistory(ow, { onix, snorlax, pikachu }, 0, 9)
-- ControlEngine keeps a one-cell Classic snake (order-preserving). Size-aware
-- whole-cell gaps are computed for diagnostics but are not the live lag index.
eq(goals2[1].y, 9, "Onix lag=1 (one-cell snake)")
eq(goals2[2].y, 8, "Snorlax lag=2")
eq(goals2[3].y, 7, "Pikachu lag=3")

-- Classic deactivates spacing
savedOpts.pokemon_size = "classic"
check(engine:_visualTrailSpacingActive() == false, "Classic disables visual trail spacing")
eq(engine:_followGapForSource(onix), 1, "Classic Onix follow gap=1")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("\nPASS follower_trail_spacing_unit_test")
