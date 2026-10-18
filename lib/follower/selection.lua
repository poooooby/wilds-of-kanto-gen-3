-- Party follower selection (PokéPC concepts adapted for Wilds).
-- Owns: active mon resolution, fingerprint, health, select API.
-- Does NOT resolve sprites or touch renderers.
local V = ...
local Constants = V.require("follower/constants")

local Selection = {}
Selection.__index = Selection

local function healthy(mon)
  return type(mon) == "table" and (tonumber(mon.hp) or 0) > 0
end

-- Can this mon be in the follower trail right now? Healthy, and not sent
-- back with talk -> Ball (mon.stopFollowing, undone by party-menu FOLLOW).
local function following(mon)
  return healthy(mon) and mon.stopFollowing ~= true
end

-- Fingerprint from stable engine fields. Species alone is insufficient when
-- the party has duplicates; include species + OT + DVs + catchRate.
-- Gold Mon.new (src/battle/gen2/Mon.lua) still stores otId (via stampOT) and
-- dvs.attack/defense/speed/special. It does not set catchRate; that slot
-- becomes "-1" for every Gold mon and does not collide two different DVs/OTs.
-- Do not add Gold-only fields here: Gen1 selectedMonKey migration depends on
-- this exact colon-separated shape.
local function monFingerprint(mon)
  if type(mon) ~= "table" then return nil end
  local dvs = type(mon.dvs) == "table" and mon.dvs or {}
  return table.concat({
    tostring(mon.species or ""),
    tostring(mon.otId or -1),
    tostring(dvs.attack or -1),
    tostring(dvs.defense or -1),
    tostring(dvs.speed or -1),
    tostring(dvs.special or -1),
    tostring(mon.catchRate or -1),
  }, ":")
end

-- Legacy PokéPC key without species (ot:dvs:catchRate).
function Selection.new(mod, state)
  local self = setmetatable({}, Selection)
  self.mod = mod
  self.state = state
  return self
end

Selection.healthy = healthy
Selection.following = following
Selection.monFingerprint = monFingerprint

function Selection:getParty(game)
  local GameCompat = V.require("game_compat")
  return GameCompat.party(game)
end

--- Resolve the active follower mon -- always the first party mon, in
-- party order, that is actually following (first HEALTHY one when
-- needHealthy; a mon sent back with talk -> Ball is always skipped). No
-- override: the stored selection (`selectedMonKey`/`selectedSlot`) and the
-- legacy `game.save.followerPartyIndex` are no longer consulted, so trail
-- order can never disagree with party order.
-- @param needHealthy when true, fainted mons are skipped
-- @return mon, slot or nil
function Selection:getActiveFollowerMon(game, needHealthy)
  local party = self:getParty(game)
  if not party or #party == 0 then return nil end

  for i, mon in ipairs(party) do
    if needHealthy then
      if following(mon) then return mon, i end
    elseif type(mon) == "table" and mon.stopFollowing ~= true then
      return mon, i
    end
  end
  if needHealthy then return nil end
  return party[1], 1
end

--- Persist an explicit party selection (canonical selection path).
-- Updates selectedMonKey / selectedSlot and compatibility save mirrors so
-- visible follower, party-menu DISMISS, and persisted state stay aligned.
function Selection:selectFollower(mon, game, opts)
  opts = opts or {}
  if not (mon and game and healthy(mon)) then return false end
  local party = self:getParty(game)
  if not party then return false end
  local slot
  for i, candidate in ipairs(party) do
    if candidate == mon then
      slot = i
      break
    end
  end
  if not slot then return false end

  local key = monFingerprint(mon)
  if not key then return false end
  self.state:setSelection(key, slot)

  -- Mirror legacy keys for compatibility with older companion mods (write-only).
  if game.save then
    game.save.followerPartyIndex = slot
    game.save.followerSpecies = mon.species
    -- Keep pokepcLeader in sync so trailer packing uses the same slot.
    game.save.pokepcLeader = { source = "party", index = slot }
  end

  if opts.onSelected then
    pcall(opts.onSelected, mon, slot, game)
  end
  return true, slot
end

local function clearPersistedSelection(self, game)
  self.state:clearSelection()
  if game and game.save then
    game.save.followerPartyIndex = nil
    game.save.followerSpecies = nil
    local lead = game.save.pokepcLeader
    if lead and lead.source == "party" then
      game.save.pokepcLeader = nil
    end
  end
end

--- Keep the stored selection mirrored to party order after any party change.
-- The selection is derived, never chosen: it is always the first party mon
-- that is following (healthy, not sent back with talk -> Ball). A reorder,
-- faint, revive, recall or FOLLOW simply moves it to whoever is first now.
function Selection:reconcile(game)
  local party = self:getParty(game)
  if not party or #party == 0 then
    clearPersistedSelection(self, game)
    return nil
  end

  for i, mon in ipairs(party) do
    if following(mon) then
      local key = monFingerprint(mon)
      if key and (key ~= self.state.selectedMonKey or i ~= self.state.selectedSlot) then
        self:selectFollower(mon, game)
      elseif game and game.save then
        -- Keep compatibility mirrors aligned even when key/slot match.
        game.save.followerPartyIndex = i
        game.save.followerSpecies = mon.species
        game.save.pokepcLeader = { source = "party", index = i }
      end
      return mon, i
    end
  end

  -- Nobody can follow (all fainted or all sent back): no leader, no bogus slot.
  clearPersistedSelection(self, game)
  return nil
end

return Selection
