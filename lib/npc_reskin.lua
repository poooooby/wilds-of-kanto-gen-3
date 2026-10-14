-- Reskins a curated list of named vanilla "monster" NPCs (the Fuchsia City
-- zoo pens, the Pokemon Fan Club's pets, assorted city/building Pokemon
-- NPCs -- see lib/npc_reskin_data.lua for the full list and why each entry
-- is or isn't included) with Wilds' own per-species overworld sprite, in
-- place of the generic SPRITE_MONSTER placeholder (or another real sprite
-- standing in for the wrong species).
--
-- Uses `NPC:setAppearance(spriteId, spriteDef)` (src/world/NPC.lua), reached
-- via the public `mod.world:npc(mapId, name):setAppearance(spriteId)` seam
-- (src/world/WorldAPI.lua) -- confirmed unused anywhere else in this repo.
-- This ONLY swaps the object's drawn sprite; its own script/dialogue/index
-- (`npc.def`) is never touched, so the vanilla interaction (text, cry, any
-- script trigger) keeps working exactly as before.
--
-- `spriteId` comes from SpawnRender's OWN already-registered per-species
-- content ids (SpawnRender:spriteIdFor, registered once at load via
-- registerContent()) -- this module never registers/patches content itself,
-- it only consumes the existing registry through a different engine seam.
--
-- Gen1 only: NPC:setAppearance has no equivalent on src/world/gen2/Npc.lua.
local V = ...
local GameCompat = V.require("game_compat")
local DebugLog = V.require("debug_log")
local NpcReskinData = V.require("npc_reskin_data")

local NpcReskin = {}
NpcReskin.__index = NpcReskin

function NpcReskin.new(mod, render)
  return setmetatable({ mod = mod, render = render }, NpcReskin)
end

function NpcReskin:_warn(fmt, ...)
  DebugLog.warn(self.mod, "[npc_reskin] " .. fmt, ...)
end

--- Reskins every curated object on `mapId` (no-op if none are listed for
--- it). Every failure path (missing object, map data drift, no registered
--- sprite for a species) logs and continues -- never throws, never stops
--- the rest of the pass.
function NpcReskin:applyMap(mapId)
  if type(mapId) ~= "string" then return end
  if GameCompat.isGen2(self.mod, self.mod.world and self.mod.world.game) then return end
  local entries = NpcReskinData.DATA[mapId]
  if not entries then return end
  for _, entry in ipairs(entries) do
    local spriteId, idErr = self.render:spriteIdFor(entry.species)
    if spriteId then
      local handle, handleErr = self.mod.world:npc(mapId, entry.name)
      if handle then
        local ok, applyErr = handle:setAppearance(spriteId)
        if not ok then
          self:_warn("setAppearance failed for %s on %s: %s",
            entry.name, mapId, tostring(applyErr))
        end
      else
        self:_warn("no such object %s on %s: %s",
          entry.name, mapId, tostring(handleErr))
      end
    else
      self:_warn("no registered sprite for %s (%s on %s): %s",
        tostring(entry.species), entry.name, mapId, tostring(idErr))
    end
  end
end

return NpcReskin
