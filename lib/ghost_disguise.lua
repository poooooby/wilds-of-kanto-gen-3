-- Pokemon Tower ghosts (Gen 1). Without the Silph Scope every wild Pokemon in the Tower is an unidentifiable "GHOST": you cannot
-- attack it, balls are dodged and nothing can be caught. The engine already owns the rule (`Map.ghostBattles(def)`, applied in
-- OverworldController's step-encounter path); our visible overworld spawns start their battles another way, so this module
-- mirrors the same rule for them:
--   * the overworld sprite is replaced by the TOWER_GHOST sheet (baked as extra asset id ASSET_ID, see tools/unown_forms.py),
--   * a battle started from the spawn is a real ghost battle (GameCompat.startGhostBattle),
--   * an overworld Poke Ball thrown at it is dodged (lib/catching).
-- The rule is read from the engine so a map whose def carries its own `ghostBattles` keeps working; the prefix rule below is only
-- the fallback for an engine that is not reachable (unit tests, older builds).
local GhostDisguise = {}

--- Entity/sprite form key handed through SpriteResolver -> SpriteProviders (the Unown letters use numbers 1..25 for the same seam).
GhostDisguise.FORM = "TOWER_GHOST"
--- Extra runtime-sheet / True Size asset id the TOWER_GHOST sheet is baked as (60000+ never collides with a species or a dex form).
GhostDisguise.ASSET_ID = 60100
GhostDisguise.ITEM = "SILPH_SCOPE"

local function tryRequire(path)
  local ok, mod = pcall(require, path)
  if ok then return mod end
  return nil
end

--- The map's ghost rule (`{ unlessItem = "SILPH_SCOPE" }`) or nil when the map has none.
function GhostDisguise.rule(mapDef)
  if type(mapDef) ~= "table" then return nil end
  local Map = tryRequire("src.world.Map")
  if Map and type(Map.ghostBattles) == "function" then
    local ok, rule = pcall(Map.ghostBattles, mapDef)
    if ok then return rule or nil end
  end
  if mapDef.ghostBattles ~= nil then return mapDef.ghostBattles or nil end
  if tostring(mapDef.id or ""):find("POKEMON_TOWER", 1, true) == 1 then
    return { unlessItem = GhostDisguise.ITEM }
  end
  return nil
end

--- True when a wild Pokemon on this map is currently unidentifiable: the map has the ghost rule AND the player lacks its item.
-- Same truthiness test as the engine (`Game.save.inventory[unlessItem]`), evaluated fresh on every call so picking up the
-- scope takes effect on the very next battle / throw.
function GhostDisguise.masked(game, mapDef)
  local rule = GhostDisguise.rule(mapDef)
  if type(rule) ~= "table" then return false end
  local item = rule.unlessItem
  if item == nil then return true end
  local inventory = game and game.save and game.save.inventory
  if type(inventory) == "table" and inventory[item] then return false end
  return true
end

return GhostDisguise
