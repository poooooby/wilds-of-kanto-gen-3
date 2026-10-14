-- Curated map-object -> species table for lib/npc_reskin.lua.
--
-- The engine has no structured per-event species field for these objects
-- (confirmed directly against data/generated/maps.lua) -- only the object's
-- own `name` string encodes which Pokemon it represents (and occasionally a
-- paired script's `play_cry` op). A curated list is therefore the correct
-- design here, the same conclusion Untamed Tohjo's own OBJECT_OVERRIDES
-- table reached, not a shortcut around data that actually exists.
--
-- Deliberately EXCLUDED, and why:
--   - Celadon City Game Corner / Prize Room: no Pokemon-display objects
--     exist there at all (checked directly; only trainer-class NPCs, and
--     the prize catalogue is sign text, not object data). Nothing to
--     retarget.
--   - CERULEANCAVEB1F_MEWTWO: this object carries a structured
--     `pokemon = "MEWTWO"` field, but that field marks the game's
--     LEGENDARY DISGUISE mechanic (same pattern as the Power Plant's
--     Voltorb/Electrode decoys and the legendary birds) -- the point of
--     that sprite is to NOT look like Mewtwo until the encounter starts.
--     Reskinning it would spoil the reveal, so it stays untouched.
--   - FUCHSIACITY_FOSSIL: a fossil display case, not a living Pokemon --
--     no walker sprite makes sense for it.
--   - COPYCATSHOUSE2F_* decoration objects deliberately represent two
--     recolored/alternate plush toys sharing art with the room's two real
--     entries, confirmed with the user directly (not guessed): the room's
--     generic "MONSTER" and "FAIRY" plush are both Clefairy dolls; "BIRD"
--     (alongside the already-Doduo-named "DODUO" object) is also Doduo.
--   - BILLSHOUSE_BILL_POKEMON: checked the actual event script
--     (data/scripts/story.lua, the TEXT_BILLSHOUSE_BILL_POKEMON handler) --
--     this is Bill HIMSELF, mid-teleporter-malfunction, fused into a
--     generic Pokemon-human hybrid, not any specific catchable species.
--     Giving it a real species' sprite would misrepresent the scene.
--
-- Each entry: { name = "<object name>", species = "<internal species key>" }.
-- `name` (not numeric index) is the lookup key passed to
-- `mod.world:npc(mapId, name)` -- stable across any future map-data
-- regeneration, unlike a numeric object index.
local NpcReskinData = {}

NpcReskinData.DATA = {
  FUCHSIA_CITY = {
    { name = "FUCHSIACITY_CHANSEY", species = "CHANSEY" },
    { name = "FUCHSIACITY_VOLTORB", species = "VOLTORB" },
    { name = "FUCHSIACITY_KANGASKHAN", species = "KANGASKHAN" },
    { name = "FUCHSIACITY_SLOWPOKE", species = "SLOWPOKE" },
    { name = "FUCHSIACITY_LAPRAS", species = "LAPRAS" },
  },
  POKEMON_FAN_CLUB = {
    { name = "POKEMONFANCLUB_PIKACHU", species = "PIKACHU" },
    { name = "POKEMONFANCLUB_SEEL", species = "SEEL" },
  },
  SS_ANNE_B1F_ROOMS = {
    { name = "SSANNEB1FROOMS_MACHOKE", species = "MACHOKE" },
  },
  CELADON_CITY = {
    { name = "CELADONCITY_POLIWRATH", species = "POLIWRATH" },
  },
  CELADON_MANSION_1F = {
    { name = "CELADONMANSION1F_MEOWTH", species = "MEOWTH" },
    { name = "CELADONMANSION1F_NIDORANF", species = "NIDORAN_F" },
  },
  CERULEAN_CITY = {
    { name = "CERULEANCITY_SLOWBRO", species = "SLOWBRO" },
  },
  COPYCATS_HOUSE_2F = {
    { name = "COPYCATSHOUSE2F_MONSTER", species = "CLEFAIRY" },
    { name = "COPYCATSHOUSE2F_DODUO", species = "DODUO" },
    { name = "COPYCATSHOUSE2F_BIRD", species = "DODUO" },
    { name = "COPYCATSHOUSE2F_FAIRY", species = "CLEFAIRY" },
  },
  LAVENDER_CUBONE_HOUSE = {
    { name = "LAVENDERCUBONEHOUSE_CUBONE", species = "CUBONE" },
  },
  MR_FUJIS_HOUSE = {
    { name = "MRFUJISHOUSE_PSYDUCK", species = "PSYDUCK" },
    { name = "MRFUJISHOUSE_NIDORINO", species = "NIDORINO" },
  },
  PEWTER_NIDORAN_HOUSE = {
    -- The object's own name doesn't disambiguate gender; NIDORAN_M chosen
    -- as the conventional default (same default this repo's other code
    -- uses when a source gives an ungendered "Nidoran").
    { name = "PEWTERNIDORANHOUSE_NIDORAN", species = "NIDORAN_M" },
  },
  VERMILION_CITY = {
    { name = "VERMILIONCITY_MACHOP", species = "MACHOP" },
  },
}

return NpcReskinData
