-- Sprite Fade + Sprite Color defaults, migration, and opacity scope.
-- Run: lua tests/sprite_fade_color_unit_test.lua
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

local savedOpts = {}
local optionStore = {}
local modules = {}
local V = {
  mod = {
    id = "wilds_of_kanto_gen3",
    path = ".",
    log = { info = function() end, warn = function() end },
    options = {
      get = function(_, k)
        if optionStore[k] ~= nil then return optionStore[k] end
        return nil
      end,
      set = function(_, k, v) optionStore[k] = v end,
    },
    world = {
      game = {
        save = { options = { modOptions = { wilds_of_kanto_gen3 = savedOpts } } },
        mods = { modOptions = { wilds_of_kanto_gen3 = savedOpts } },
      },
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
modules.debug_log = { warn = function() end, info = function() end }

local Config = V.require("config")

local schema = assert(loadfile("options.lua"))()
local byKey = {}
for _, row in ipairs(schema) do byKey[row.key] = row end

check(byKey.sprite_fade == nil, "Sprite Fade is not a public option (locked Solid)")
check(byKey.sprite_color == nil, "sprite_color is not a public option")
eq(byKey.town_pokemon.default, true, "town_pokemon default true")

eq(Config.spriteFade(V.mod), "solid", "runtime fade default solid")
eq(Config.spriteOpacity(V.mod), 1.0, "solid alpha == 1.0")
eq(Config.spriteColor(V.mod), "colored", "runtime color default colored")
eq(Config.spriteTrueColor(V.mod), Config.paletteFxRedpp(),
   "trueColor follows PaletteFX ADVANCED, not a public sprite_color option")

-- Sprite Fade is locked Solid: old saved Faded / legacy opacity values change nothing.
savedOpts.sprite_opacity = 0.72
savedOpts.sprite_fade = "faded"
eq(Config.spriteFade(V.mod), "solid", "saved faded ignored")
eq(Config.spriteOpacity(V.mod), 1.0, "opacity stays 1.0")
check(Config.setSpriteFade == nil, "no Sprite Fade setter")
savedOpts.sprite_opacity = nil
savedOpts.sprite_fade = nil

-- Sprite Color is not public. Legacy color_mode / classic requests stay colored.
savedOpts = V.mod.world.game.save.options.modOptions.wilds_of_kanto_gen3
savedOpts.sprite_color = nil
savedOpts.color_mode = "gbc"
eq(Config.spriteColor(V.mod), "colored", "color_mode gbc is ignored (always colored)")
Config.migrateSpriteColorOption(V.mod)
eq(savedOpts.sprite_color, "colored", "migrate forces sprite_color colored")
check(savedOpts.color_mode == "gbc", "legacy color_mode preserved")

Config.setSpriteColor(V.mod, "classic", "test", { confirm = false })
eq(optionStore.sprite_color, "colored", "setSpriteColor ignores classic")
eq(Config.spriteColor(V.mod), "colored", "classic request still colored")

-- isBattleableWild
check(Config.isBattleableWild({
  overworldWildSpawn = true, state = "available",
}) == true, "normal wild battleable")
check(Config.isBattleableWild({
  wildsAmbientPokemon = true, overworldWildSpawn = false,
}) == false, "ambient not battleable")
check(Config.isBattleableWild({
  wildsAmbientPokemon = true, wildsBattleable = false,
  wildsAggressive = false, wildsEncounterEnabled = false,
}) == false, "ambient markers not battleable")
check(Config.isBattleableWild(nil) == false, "nil not battleable")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sprite_fade_color_unit_test: all passed")
