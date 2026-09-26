-- Option schema for Wilds of Kanto (id: wilds_of_kanto_gen3).
-- Loaded via mod.options:define() from main.lua and referenced by
-- manifest options_schema for Mod Manager lazy-load.
--
-- Visible labels for Gen1 ListMenu entries must be <= 14 characters
-- (Gen1Recomp truncates longer names). Mod Settings choice labels may be
-- longer when clarity requires it (e.g. "Poke Followers / GSC").
-- Internal keys are stable so saved settings survive across releases.
--
-- Types match Gen1Recomp ManagerState.OPTION_TYPES: toggle, choice, number, text.
--
-- All options are live-toggleable through Mod Manager (mod.options_changed).
--
-- Behaviour that used to be configurable is fixed (see Config.LOCKED in lib/config.lua):
-- Idle + Roam wilds, no Chase / Hidden wilds, trainer control without a trainer trail,
-- Sprite Scale on, solid sprites, Normal spawn amount, Shiny Sparkle on, water wilds as
-- swimming sprites, cave wilds only on tiles the player can reach. Dev Overlay / Test Spawn are developer-only (wilds_dev.flag).
--
-- UI submenu mapping (both write the SAME mod.options keys):
--   Poke Followers EX -> follower_count (+ Leader via party menu hint)
--   Wilds of Kanto    -> enabled, random_encounters, shiny_rate, sprite_style,
--                       town_pokemon, pokemon_grass_render_mode, wild_silhouettes
--
-- Pokemon size is not a separate option: it is tied to Sprite Style.
--   GSC sprites (followers)   -> Classic (one-tile 16x16 presentation)
--   HGSS sprites (pokemmo)    -> True Size (larger relative species sizes)
-- Pokedex is no longer a selectable style, but the Pokedex art provider
-- stays registered internally as the last-resort fallback the other
-- styles fall through to when their own art is missing for a species.

return {
  -- ------- Core gameplay
  {
    key = "enabled",
    label = "Show Wild Mons",
    type = "toggle",
    default = true,
    description = "Spawn visible wild Pokemon in eligible overworld encounter areas.",
  },
  {
    key = "sprite_style",
    label = "Sprite Style",
    type = "choice",
    default = "followers",
    choices = {
      { "Poke Followers / GSC", "followers" },
      { "HGSS / PokeMMO", "pokemmo" },
    },
    description = "Overworld sprite style for wild Pokemon and followers. Poke Followers / GSC is the built-in default. Sprite size follows the style: GSC Classic (16x16), HGSS True Size. PMDCollab dialogue portraits are separate and appear for Wilds Pokemon talk regardless of Sprite Style. Water Pokemon still use Swimming or Levitates sprites when available.",
  },
  {
    key = "pika_follower",
    label = "PIKA FOLLOWER",
    type = "choice",
    default = "default",
    choices = {
      { "Default", "default" },
      { "Alola", "alola" },
      { "Belle", "belle" },
      { "Hoenn", "hoenn" },
      { "Kalos", "kalos" },
      { "Libre", "libre" },
      { "OG Cap", "og-cap" },
      { "Partner", "partner" },
      { "PhD", "phd" },
      { "Pop Star", "popstar" },
      { "Rock Star", "rockstar" },
      { "Sinnoh", "sinnoh" },
      { "Unova", "unova" },
    },
    description = "Cosmetic costume for the Yellow starter Pikachu companion only -- does not affect any other Pikachu you use as a follower.",
  },
  {
    key = "follower_count",
    label = "Followers",
    type = "choice",
    default = 1,
    choices = {
      { "0", 0 },
      { "1", 1 },
      { "2", 2 },
      { "3", 3 },
      { "4", 4 },
      { "5", 5 },
      { "6", 6 },
    },
    description = "Number of additional party Pokemon following the active leader.",
  },
  {
    key = "random_encounters",
    label = "Classic Enc",
    type = "toggle",
    default = true,
    description = "Classic Encounters: the original step-based random encounters in grass, caves and water (Surf). Visible overworld Pokemon stay active either way.",
  },
  {
    key = "shiny_rate",
    label = "SHINY RATE",
    type = "choice",
    default = "modern",
    choices = {
      { "Off", "off" },
      { "1/8192 (Gen 2)", "gen2" },
      { "1/4096 Modern", "modern" },
      { "1/1024", "common" },
      { "1/512", "frequent" },
      { "1/100", "often" },
      { "1/10", "high" },
      { "Always", "always" },
    },
    description = "Chance that a wild Pokemon is shiny (Red/Blue/Yellow and Gold). A shiny shows its shiny overworld sprite, is a real shiny in battle, and stays shiny when caught; its follower uses the shiny sprite. Off means none. Replaces the Shiny Pokemon mod, which cannot run alongside this one.",
  },
  {
    key = "town_pokemon",
    label = "Town Pokemon",
    type = "toggle",
    default = true,
    description = "Adds peaceful Pokemon to safe towns and interiors. They behave like NPCs, cannot start battles, and never block your path.",
  },
  {
    key = "pokemon_grass_render_mode",
    label = "Grass View",
    type = "choice",
    default = "immersed",
    choices = {
      { "Above", "above" },
      { "Immersed", "immersed" },
    },
    description = "Draw wild Pokemon fully above tall grass, or partially hidden inside it like the player and trainers.",
  },
  {
    key = "wild_silhouettes",
    label = "Silhouette",
    type = "choice",
    default = "off",
    choices = {
      { "Off", "off" },
      { "Undiscovered", "undiscovered" },
      { "All", "all" },
    },
    description = "Silhouettes for visible wild Pokemon on land and in water. On land they are blacked out; in the water they show as a dark underwater shape. Undiscovered silhouettes only species you have not caught yet; All silhouettes every wild.",
  },
}
