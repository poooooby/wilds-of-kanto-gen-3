-- PMDCollab dialogue-portrait unit tests (no full SpriteCollab).
-- The overworld PMDCollab sprite style was removed -- see CHANGELOG.md --
-- so this file now covers only the portrait subsystem (lib/portrait_registry.lua,
-- lib/pokemon_dialogue.lua, lib/pmdcollab_assets.lua) plus unrelated option
-- label/ASCII tooling validation.
-- Run: luajit tests/pmdcollab_unit_test.lua
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

------------------------------------------------------------------------
-- Importer fixture: portrait output from checked-in mini fixture
------------------------------------------------------------------------
print("== importer fixture ==")
local rc = os.execute([[python3 - <<'PY'
import sys
from pathlib import Path
import importlib.util
spec = importlib.util.spec_from_file_location("import_pmdcollab", "scripts/import_pmdcollab.py")
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)
imp.ROOT = Path("/tmp/wilds_pmd_import_test")
imp.OUT = imp.ROOT / "assets" / "pmdcollab"
sys.argv = ["import_pmdcollab.py", "tests/fixtures/spritecollab_mini", "--dex-max", "2", "--clean"]
raise SystemExit(imp.main())
PY]])
check(rc == true or rc == 0, "importer exits 0 on fixture")

local function exists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end
check(exists("/tmp/wilds_pmd_import_test/assets/pmdcollab/portraits/001/normal/normal.png"),
  "fixture produced bulbasaur normal portrait")
check(exists("/tmp/wilds_pmd_import_test/assets/pmdcollab/SOURCE.json"), "SOURCE.json written")
check(exists("/tmp/wilds_pmd_import_test/assets/pmdcollab/CREDITS.txt"), "CREDITS.txt written")
check(exists("/tmp/wilds_pmd_import_test/assets/pmdcollab/LICENSE.txt"), "LICENSE.txt written")

------------------------------------------------------------------------
-- Portraits independent of sprite style
------------------------------------------------------------------------
print("== portraits vs sprite styles ==")
local modules = {}
local savedOpts = { sprite_style = "followers" }
local V = {
  mod = {
    path = ".",
    id = "wilds_of_kanto_gen3",
    log = { info = function() end, warn = function() end, error = function() end },
    find = function() return nil end,
    options = {
      get = function(_, key) return savedOpts[key] end,
    },
    assets = {
      path = function(_, rel) return "mods/wilds_of_kanto_gen3/" .. rel end,
    },
    read = function(_, rel)
      local f = io.open(rel, "rb") or io.open("./" .. rel, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
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

local SpeciesAssets = V.require("species_assets")
local PortraitRegistry = V.require("portrait_registry")
local styles = { "followers", "pokemmo", "pokedex" }
for _, style in ipairs(styles) do
  savedOpts.sprite_style = style
  local p = PortraitRegistry.resolve("PIKACHU", {
    mod = V.mod,
    randomGeneric = false,
    mood = "normal",
  })
  check(p ~= nil and p.rel ~= nil,
    "portrait resolves with sprite style=" .. style)
  check(p.rel:find("pmdcollab/portraits", 1, true) ~= nil,
    "portrait path is pmdcollab for style=" .. style)
end

-- Species identity: PIKACHU -> 25, not dex position
eq(SpeciesAssets.idFor("PIKACHU"), 25, "PIKACHU asset id")
eq(SpeciesAssets.idFor("FAKEMON_X"), nil, "unknown fakemon -> nil asset id")

-- Random generic from safe pool, stable call returns one emotion
local seed = 0.42
local p2 = PortraitRegistry.resolve("PIKACHU", {
  mod = V.mod,
  randomGeneric = true,
  rng = function() return seed end,
})
check(p2 and p2.emotion, "random generic emotion picked")
local pool = {}
for _, e in ipairs(PortraitRegistry.GENERIC_POOL) do pool[e] = true end
check(pool[p2.emotion] == true, "emotion in safe pool")

-- Missing portrait / fakemon -> nil (normal TextBox)
local miss = PortraitRegistry.resolve("FAKEMON_X", { mod = V.mod, randomGeneric = true })
check(miss == nil, "fakemon portrait nil")

-- PokemonDialogue wrapper does not crash without love
local PokemonDialogue = V.require("pokemon_dialogue")
modules.game_compat = {
  presentText = function() return "textBox" end,
  presentTextChoice = function() return "textBoxChoice" end,
}
local r = PokemonDialogue.presentText(V.mod, { stack = { top = function() return nil end } },
  nil, "Pika!", function() end, { species = "PIKACHU", randomGeneric = true })
eq(r, "textBox", "presentText delegates")

------------------------------------------------------------------------
-- Option label validation
------------------------------------------------------------------------
print("== option labels ==")
local labelRc = os.execute("python3 tools/validate_option_labels.py >/tmp/opt_labels.txt 2>&1")
check(labelRc == true or labelRc == 0, "validate_option_labels ok")
local asciiRc = os.execute("python3 scripts/validate-manager-ascii.py >/tmp/ascii.txt 2>&1")
check(asciiRc == true or asciiRc == 0, "validate-manager-ascii ok")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("ALL PASSED")
