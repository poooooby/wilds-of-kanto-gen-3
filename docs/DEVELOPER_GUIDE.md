# Wilds of Kanto Revival — Developer Guide (1.0.2)

> Follow-sprites → native 16×96 SpriteRenderer sheets, NPC pose contract,
> and Dramatic Shape billboards match the 1.0.2 implementation.

Public name: **Wilds of Kanto Revival**. Technical id: `wilds_of_kanto_gen3` (the upstream project's is `overworld_wild_spawns`).

This document describes the **implemented** architecture. It does not invent Gen1Recomp APIs.

## Dramatic Shape integration (1.0.0)

Verified NPC contract: `pose()` returns
`sprite, visualX, visualY, facing, phase, flip [, hop]`.

Success path:
1. Entity stays in `ow.entities`
2. Stable native `SpriteRenderer` (`frames=6`, `walker=true`, static sheet)
3. `def.image` → `assets/wilds_generated/followsprites_runtime/...`
4. Dramatic Shape SpriteBillboards (depth, occlusion, grass, shadows, FP)

`EnhancedWorldSprite` is deprecated and unused for the body.

```text
Renderer: NATIVE_SPRITE_RENDERER
```


## 1. Project structure

Repository root **is** the mod (DramaticShape layout):

```text
manifest.json  main.lua  options.lua  mod.card
assets/  lib/  docs/  tests/  scripts/  tools/
```

Local engine: `./scripts/bootstrap.sh` → `.deps/gen1recomp` with symlink
`mods/overworld_wild_spawns` → repo root.

Follow-sprite assets:

```text
assets/enhanced_overworld/followsprites/*.png
assets/enhanced_overworld/followsprites_mapping/followsprites_mapping.json
```

Legacy Anima mappings under `pokedex_mapping/` remain unused. Commercial
`Pokemon_Sprites/POKEMON 1.png` must not ship.

See `docs/ANIMATED_SPRITE_FORMAT.md`.

## 2. Mod lifecycle

`main.lua` returns `function(mod)`. During load:

1. Virtual `V.require` loads `lib/*.lua`
2. `Config.defineOptions`
3. `SpawnRender:registerContent()` — **only** content-registry writes
4. `AnimatedSprites:load()` — shared follow-sprite mapping (no registry writes)
5. Register HUD / preview / behaviour-tick pipelines
6. Hook `encounter.roll` + `movement.collision` when enabled
7. Subscribe to map/world/battle/save/options events

Generation gate: `GameCompat.supportsFeature` decides which subsystems
install. Red / Blue / Yellow keep full Gen1 capabilities. Gold installs
wild encounters, followers, overworld catching, and the New Bark town
Pokémon; Safari stays off. Content registration and the options schema still run.

Gen1Recomp freezes content registries after all mods load.
`GameVersion.set()` runs in `bootGame` before `Loader:load`, so
generation detection is reliable at mod entry.

See `docs/analysis/GEN2_PREPARATION.md`. Production manifest claims
`"games": ["gen1", "gen2"]` (Mod Manager **Gen 1+2**).

## 3. Content registration

`SpawnRender:registerContent()` registers:

- `SPRITE_OW_WILD_PLACEHOLDER`
- `SPRITE_OW_WILD_FALLBACK` → `assets/fallback/pokemon_missing.png`
- `SPRITE_OW_WILD_<SPECIES>` per `mod.content.pokemon` entry (battle front or fallback)

Sets `contentRegistrationOpen = false` afterward.

## 4. Registry freeze

Never call `mod.content.sprites:register|override|patch|remove` from map callbacks,
test spawn, or preview. Runtime uses `speciesSpriteIds` lookup + image path resolve only.

## 5. Sprite resolution

### Follow-sprites (preferred when option on)

Identity = numeric `mon.dex` / `speciesId` only:

```lua
local speciesId = AnimatedSprites.resolveSpeciesId(entity.species, game, mod)
local mapping = mappingsBySpeciesId[speciesId]
local variant = AnimatedSprites.resolveRuntimeVariant(entity) -- currently always normal
```

Never: `mappingByName[pokemon.name]` or filename from localized names.

### Legacy candidates (species **id** first, not display name alone)

explicit map → dex-padded PNG → species_id PNG → display-name token →
battle front/back → menu icon → optional save-dir cache → fallback

Fallback chain: **follow variant → follow normal → legacy PNG → black fallback**.

## 6. Runtime image cache

`resolvedAssetBySpeciesId` / `runtimeImageCache` hold paths and bake results.
Optional bake writes `overworld_wild_spawns-cache/<id>.png` as a **LÖVE virtual**
path (never `getSaveDirectory()` absolute paths).

## 7. Fallback sprite

`assets/fallback/pokemon_missing.png` is always registered. Hidden behaviours
**do not** load fallback art — they draw shake/dust only.

## 8. Encounter data source

`game.data.encounters[mapId]` plus Gen1Recomp `field.fishing` / `field.superRod`:

| Kind | Free overworld spawn? |
|---|---|
| `grass` | Yes (routes + caves) |
| `water` (Surf) | Yes — visible Water Mons + classic Surf rolls |
| `field.fishing.OLD_ROD` / `GOOD_ROD` / `SUPER_ROD` | Visible Water Mons pools only (zone-gated); classic rod battles stay engine-side |
| `encounters[].fishing` (legacy/preview) | Indexed for preview; may contribute to visible pools when structured |

Visible water spawns use `lib/water_spawn.lua` (cell → shore zone → pool → species).
`EncounterPick.pick(..., "fishing")` still returns nil.

### 8.1 Modern encounter overlay (Gen 1 only)

`lib/gen9_encounters.lua` is the single Gen 1 wild-table seam. `modern_spawns` is a three-way choice
(`Config.modernSpawnsMode`, peekSavedOption-first; legacy boolean saves migrate `true` -> `table`,
`false` -> `off`):

- **`table`** (default) replaces the slots of mapped Gen 1 maps with the generated table in
  `lib/gen9_encounters_data.lua`. It is **inactive unless** `lib/dex_expansion.lua` finds a real
  species above #386 (and below the 30000 alternate-form range) in `game.data.pokemon` — i.e. a
  Pokedex-expansion mod such as National Dex is active. Kanto Reforged alone (max #386) does not
  activate it.
- **`random`** (see 8.2) draws any registered species for every map with a vanilla table; no dex gate.
- **`off`** returns the vanilla object untouched.

- **Seam:** `Gen1.encountersForMap` returns the overlay (a cached **copy**; the original table objects are
  never modified). The classic roll is covered by the
  `encounter.roll` wrapper via `Gen9Encounters.rollDef` (the engine passes a synthetic
  `{ grass = map.water }` for water rolls, so it is terrain-aware) and Super Rod by an
  `encounter.fishing` wrapper via `Gen9Encounters.fishingPool`. `encounter_index`, `ambient_pokemon`
  and `water_spawn` read through the same overlay.
- **Only existing buckets are replaced** (grass/cave, water, and vanilla Super Rod groups), so the
  engine's `rate` survives; maps or buckets the vanilla data lacks stay vanilla.
- **Variable-length ladders (data version 2):** grass/water are NOT limited to the default 10
  slots. Each overlay bucket carries its own cumulative `buckets` list (ending 256, one threshold
  per slot) with one slot per (species, level); `Encounter.roll` and `EncounterPick` both honor a
  per-bucket `buckets`. A source row's percentage is spread evenly over every level in its min-max
  range (20% Roggenrola 15-17 -> L15/L16/L17 at ~6.9% each after normalizing), in whole 256ths
  (the roll is `rng(0,255)`, so a slot's odds are integers out of 256). Tables run 6-88 slots.
- **Per-slot fallback:** a slot whose species is not registered is replaced by the vanilla slot at
  the same *probability position* (the midpoint of the overlay slot's odds interval looked up on the
  vanilla ladder), so nothing can reference a missing species and the probability mass is kept.
  Malformed ladders (length mismatch, non-increasing, not ending 256) fail closed to vanilla.
- **Data:** generated by `tools/generate_gen9_encounters.py` (Essentials PBS-style `encounters.txt`
  + `national_dex` species keys; location mapping in `tools/data/gen9_location_map.json`). Rounding
  is two-stage largest-remainder (species totals first, then split across levels), each pair >= 1/256.
  Super Rod stays <= 4 uniformly-picked entries (hard engine limit, so it cannot spread levels).
  The sources live outside the repo; only the generated Lua is committed. Re-run the generator and
  review its printed report (per-table slot counts and max error, unused sections, form-token table)
  before committing.

### 8.0 Shiny system (SHINY RATE)

`lib/shiny.lua` replaces the Shiny Pokemon mod for Red/Blue/Yellow, and applies the same rate in Gold (Gen 2, see the last bullet below; that mod is a manifest conflict: with Voxel off
its `SpriteRenderer.draw` wrap redraws `SPRITE_PIKACHU` / `SPRITE_PLAYER_POKEMON` followers with a hardcoded 16x16
quad at `(px - camX, py - camY - 4)`, ignoring `frameWidth` / `frameHeight` / `anchorX` / `anchorY`).

- **Definition:** the engine's RBY virtual shiny (`Stats.isShiny`): Defense/Speed/Special DV 10 and Attack DV in
  {2,3,6,7,10,11,14,15}. `Shiny.makeDVs` builds them, `Shiny.applyToMon` sets `dvs`/`shiny` and recomputes stats.
- **Gold (Gen 2):** Gold builds every mon through `Mon.new`, which asks the `shiny.roll` hook whether the DVs make it shiny -- for trainers,
  starters, gifts and eggs too, and again on every summary open. So `Shiny.installGen2` (called from `main.lua` `installHooks`) uses an
  arm-then-consume token: `encounter.species` / `encounter.fishing` (classic encounters) and `Shiny.armForBattle(record, true)` (visible spawns) arm
  `{ species, level, shiny }` right before the wild mon is built, and the `shiny.roll` wrapper consumes it once for that species (TTL
  `Shiny.GEN2_TTL`; also cleared by `Shiny.clearPending`). Everything else is the vanilla DV check. A hook-made shiny keeps ordinary DVs (it will not
  breed shiny) and a wild that rolled non-shiny but reads shiny by DV can flip shiny on a summary open (~1/8192); static script encounters and roamers
  are not armed. `SHINY SPARKLE` stays Gen 1 only (Gold has its own shiny flash). Tests: `tests/shiny_gen2_unit_test.lua`.
- **Rate:** `Config.shinyRate` (`off`, `gen2` 1/8192, `modern` 1/4096 default, `common` 1/1024, `frequent` 1/512,
  `often` 1/100, `high` 1/10, `always`), `Shiny.roll` draws `rng(1, denom) == 1`.
- **Where it rolls:** visible land spawns roll at creation (`SpawnLogic:_rollShiny` -> `record.shiny` ->
  `Entity.shiny` -> `AnimatedSprites.resolveRuntimeVariant` = the shiny sheet; water scenery does not roll because
  it cannot start a battle). Before the contact battle starts, `Shiny.armForBattle(record)` hands the result to the
  engine, so the fought mon is the seen one. Classic encounters roll inside `BattleState.newWild`.
- **How:** `Shiny.install` (main.lua, Gen 1 only, `engine_internals`) wraps `BattleState.newWild` and `Pokemon.new`.
  `Pokemon.new` is only altered while `newWild` runs (trainers, gifts, eggs and starters are untouched). The pending
  hand-off is `{ dvs }` or an explicit `{ none = true }` (a visible non-shiny stays non-shiny even against a natural
  shiny spread), cleared after every `newWild` (also on error), on `map.entered` and on `battle.ended`.
- **Off means none:** wilds and overworld catches (`Gen1.createCaughtPokemon` -> `Shiny.finalize`) nudge a natural
  shiny spread (about 1 in 8192) to Special DV 9.
- **Battle sparkle (`lib/shiny_sparkle.lua`, SHINY SPARKLE option, default ON, Gen 1 only):** a wrapper on the
  engine's draw-only `battle.overlay` hook (called at the end of `BattleState` / `WideBattle` draw, 160x144
  coordinates) paints one 1.35 s burst of sparks over a shiny enemy and over the player's shiny lead, with the
  engine SFX `Dex_Page_Added`. It waits for the intro to finish (`introSlide`, `showEnemyTrainer`, `enemySendingOut`,
  `showPlayerBack`, `sendingOut`, `growInScale`), fires once per Pokemon per battle (state is weak-keyed by battle and
  mon, so a swapped-in shiny gets its own), and skips a fainted enemy and the player side in Safari / demo battles.
  Anchors: classic (120,32) enemy / (40,88) player; wide layout (200,40) / (60,100). The colors are opaque because
  alpha vanishes under some of the engine's palette passes. Visual placement has not been verified in every layout
  (Voxel / Dramatic Shape battle HUDs).
- **Not included:** shiny recolor in battle (Shiny Pokemon did that), Safari Zone encounters (separate battle path),
  Gold (native shiny, `shiny.roll` hook).

### 8.1.0 Generation cap (MAX GEN)

`max_generation` (`"1"`..`"9"`, default `"9"` = no cap; `Config.maxGeneration`, peekSavedOption-first) caps
the species **Spawn Table and Random** may use by national dex number (`DexExpansion.GENERATION_LAST_DEX`:
151 / 251 / 386 / 493 / 649 / 721 / 809 / 905 / 1025; `DexExpansion.lastDexOf` returns nil for 9 = no cap).
Off is never capped, and species other mods put into the original tables are not touched.

- **Spawn Table (`tableOverlay` / `capLadder`):** slots whose `dex` is above the cap are dropped and their odds
  are shared among the surviving slots (largest-remainder rounding back to exactly 256, every survivor >= 1
  unit). The existing "uninstalled species -> original slot at the same odds position" fallback then runs on
  the renormalized ladder. A bucket with no allowed slot stays as the original. Super Rod entries above the cap
  are dropped (the roll is uniform, so the rest share it), or the original pool is kept if none survive.
- **Random:** `RandomSpawns.pool(..., maxDex)` filters the pool (cached per cap); levels come from the capped
  Spawn Table where the map is mapped.
- Alternate forms have dex >= 30000, so any cap below All excludes them.
- The cap is part of the `overlayCache` / `rodCache` keys, so changing it rebuilds without `invalidate()`;
  `SpawnLogic:onOptionsChanged` re-publishes and rebuilds the current map for `max_generation`.

### 8.1.1 Publishing the current map (DexNav compatibility)

Other mods read `game.data.encounters[mapId]` and `game.data.field.superRod[mapId]` directly -- Kanto
Reforged's DexNav (`ui/dexnav.lua`, `DexNav.sourcesForMap`) builds its list from them at open time -- so a
copy that only our seams hand out is invisible to them. `Gen9Encounters.publish(mod, game, mapId)` therefore
swaps the overlay into those two slots **by reference for the current map only**; nothing else changes.

- **Originals are never modified.** `restoreAll` puts the same objects back, but only into a slot that still
  holds our overlay (a table another mod put there since is left alone). That is why turning MODERN SPAWNS Off
  (or leaving the map) hands Kanto Reforged's own tables back exactly as they were.
- **Seams normalize.** `overlayFor`, `rollDef` and `fishingPool` map a published overlay back to its source
  (`byOverlay`) first, so a published table is not overlaid again, Random never builds on its own previous
  roster, and the engine's classic roll (which now reads the overlay) sees `overlay == real` and is left alone.
- **Lifecycle** (`main.lua`): `map.entered` -> `invalidate()` (restores, redraws Random) -> `publish`;
  `map.exited` -> `restoreAll`; `game.ready` / `mods.loaded` -> `invalidate()`;
  `SpawnLogic:onOptionsChanged` (`modern_spawns` / `legendary_spawns`) -> `publish` before rebuilding the map.
  Gen 1 only; every call is pcall-guarded and a failure restores and stays vanilla.
- **Tamper guard:** if something merges into the published object and leaves it half-shaped (Kanto Reforged
  re-applying its mix mid-visit; `#slots ~= #buckets` makes `Encounter.roll` skip slots or hand `newWild` a
  bad one), the next seam call restores
  the original, drops the caches and rebuilds. The one thing not covered: that re-apply's new mix for the
  current map is lost on our next restore until it re-applies or the game restarts.
- Limits: only the current map is published (the Pokedex Town Map, which iterates `game.data.encounters`, sees
  the overlay for that map only), and readers that cache tables at load are not covered.

### 8.2 Random spawn mode

`lib/random_spawns.lua` holds the pure builders; `Gen9Encounters.overlayFor`/`fishingPool` dispatch to
them when the mode is `random`.

- **Pool:** every entry of `game.data.pokemon` (plus `mod.content.pokemon`) with an integer dex in
  1..29999 (alternate forms at 30000+ are skipped), minus the restricted set unless the
  `legendary_spawns` option (LEGEND/MYTHIC) is on. Independent of the dex gate, so a plain Gen 1 dex
  randomizes among Gen 1 species.
- **Restricted set:** `lib/species_flags_data.lua` (generated by `tools/generate_species_flags.py` from a
  PokeAPI `pokemon_species.csv`; source stays outside the repo): 71 legendary + 23 mythical from the CSV
  flags, plus the 11 Ultra Beasts and 20 Paradox Pokemon (no flag in the CSV, listed by dex and verified
  against CSV identifiers). Keyed by national dex. Babies stay eligible. Static/gift/trainer Pokemon are
  not affected, only wild tables.
- **Shape:** each grass/water bucket the vanilla table has keeps the **vanilla ladder** (the engine's
  10-slot default, or the bucket's own custom `buckets`), so an area has <= 10 distinct species, like the
  engine and Kanto Reforged's `pure_random`. Species are distinct, from a shuffled pool (it only cycles if the
  pool is smaller than the ladder). A slot's level is the *base* table's level at a random probability unit
  inside that slot's own odds interval (base = the Spawn Table overlay where the map is mapped and the dex is
  expanded, else vanilla), so common slots keep common levels. Vanilla `rate` is preserved; buckets vanilla
  lacks are not created. Super Rod keeps the vanilla group length (<= 4) with levels from the same base
  group; Old/Good Rod stay vanilla.
- **Why the roster is kept small:** every distinct species costs sprite work (`resolveAsset` decodes a PNG,
  then SpriteDef/renderer creation). A first version used 256 one-unit slots (up to ~146-256 species per
  area, redrawn every map entry) and caused a large CPU spike on map entry, mostly from the per-species
  asset probe. `SpawnLogic:onMapEntered` now runs `SpawnRender:countAssets` (diagnostics only) only when
  `Config.debug`/dev mode is on. Do not widen the roster without measuring `spriteResolves` /
  `spriteRendererNews` (PerfStats, debug on).
- **Lifetime:** the roster is cached per `DexExpansion.epoch()` (bumped by `Gen9Encounters.invalidate()` on
  `map.entered`, `game.ready`, `mods.loaded`), so it is redrawn on each map entry and fixed within a
  visit. The cache key also carries the mode and the legendary flag, and
  `SpawnLogic:onOptionsChanged` rebuilds the current map when either option changes.
- Uses its own Park-Miller RNG (`RandomSpawns.newRng`) rather than `math.random`, so the engine's stream
  is never reseeded or consumed; tests inject a seeded `rng`.

## 9. Map analysis

`Surface.resolve(game, map, encDef)`:

1. Grass table + `isGrassCell` tiles → `GRASS`
2. Grass table + indoor/cave rule → `CAVE` (walkable tiles)
3. Water table → `WATER`
4. Else unsupported → vanilla left intact

Indoor rule mirrors Gen1Recomp:
`map.def.index >= field.indoorEncounters.firstIndoorMap` and
`tileset ~= excludedTileset` (FOREST), with tileset/id fallbacks for fixtures.

## 10. Encounter-tile detection

| Mode | Source |
|---|---|
| grass | `Map:isGrassCell` |
| water | `Map:isWaterCell` |
| walkable (cave) | walkable ∧ ¬warp ∧ ¬water |

Rejects: blocked, warp, NPC, other wild, player, distance band.

## 11. Spawn regions

`SpawnRegions.build` flood-fills 4-connected eligible tiles.
`allocate` spreads target count by region size (tiny patches ≤1, ~6 tiles/mon cap).

## 12. Spawn capacity

```text
raw = minVisible + floor(eligibleTiles / tilesPerAdditional) + softSpanBonus
raw *= densityFactor(low/normal/high/very_high)
clamp to [minVisible, maxVisible] and eligible/3
```

Eligible tiles dominate; raw width×height is not used alone.

## 13. Entity lifecycle

`AVAILABLE` → (`ENCOUNTER_STARTING`) → despawn → battle → `REMOVED`
Records in `logic.spawns` / `logic.entities` / `logic.byMap`.

## 14. Render path

Entities implement `pose()` / `draw()` on `ow.entities`.
Scaled draw uses `love.graphics.draw` + nearest filter; feet-biased growth.
Engine `TileRenderer:drawCellBottom` after every entity on grass provides
the GB feet-overdraw (bottom 8px of the cell) in **Classic** mode.

**True Size Flat** wraps that call: Immersed paints only a clipped feet band
(`GrassOcclusion.computeTrueSizeCover`, ~4–6px); Above skips overdraw.
Classic behavior is unchanged.

Option `pokemon_grass_render_mode` (`immersed` default / `above`):
- `immersed` — Classic: full `drawCellBottom`; True Size: clipped feet band
- `above` — Classic: lift clears flat overdraw; True Size: skip overdraw

`inGrassOverlay` tracks live grass tiles (source + step target).

## 15. Grass overlay

Implemented by Gen1Recomp for all `ow.entities` on grass cells.
Mod sets `grass_tuck_px = 0` by default so sprites are not pushed into the turf.
`inGrassOverlay` tracks live cell grass for HUD.
Relative occlusion via `lib/grass_occlusion.lua` with a small upward lift so
small sprites are not fully covered.
Aggressive entities clear the grass flag when their committed tile leaves grass.

## 16. Sprite scaling (one tile)

Gen1Recomp tile size is **16×16** (`lib/tile.lua`, matching `NPC.lua`).

```text
visibleBounds = non-transparent pixel box (cached)
desiredScale  = readability / species preference / min_sprite_size option
maximumScale  = min(usableW / visW, usableH / visH)   -- usable ≈ 0.90×0.95 tile
final2DScale  = min(desiredScale, maximumScale)
```

- Source PNGs may be larger; transparent margins are ignored.
- Aspect ratio preserved; nearest-neighbor filter.
- Logical footprint stays one tile (collision / sight / contact unchanged).
- Camera zoom is engine-only and is not folded into `final2DScale`.
- With Dramatic Shape active, wild Pokemon use `WILDS_2D_POST_VOXEL` (same
  `Entity:draw` / atlas path after the voxel world). No 16×16 card bake.

## 17. Behaviour state machines

See `lib/behavior.lua`. Tick via `lib/behavior_tick.lua` present pipeline
(`owwild_behavior_tick`) because Gen1Recomp has no `world.tick` and only
updates `ow.npcs`. Movement goes through `lib/movement.lua` (NPC-compatible
previous/current pixel lerp; cell finalizes after the step).

Aggressive SM: `IDLE → PLAYER_DETECTED → ALERT → CHASE_START → CHASING →
BATTLE_PENDING → IN_BATTLE → CLEANUP`.

Alert reuses `ow.emote = { npc = entity, frames = 60, onDone = ... }`
(same emotion-bubble path as trainers). The bubble is **not** a wild/Voxel
entity. Chase starts only from `onDone` (`Behavior.markChaseReady`).
AI decisions hold while `ow.emote` / `ow.engaging` owns the world.

Stable ids: `wilds_of_kanto_entity_<n>` for the full lifetime.

## 18. Battle trigger

`world:queueScript({ { "start_battle", "wild", species, level } })`
`pendingBattle` + entity state prevent double starts.
Contact: `world.stepped` tile match + `movement.collision` bump.

## 19. Water support

- Surf + Old/Good/Super Rod pools → visible water entities on water tiles
- Shore-distance zones (near ≤2, mid ≤5, deep ≥6); Super-Rod-only in deep
- Zone empty → Surf pool → full local water pool (never empty a zone for diversity)
- `WaterSpawn.isWaterCapable`: species `types` WATER → swimming/levitates → local encounters
- Behaviours: `WATER_IDLE` / `WATER_WANDER` / `WATER_AGGRESSIVE`
- Land and water aggressive use separate tick paths (`tickLandAggressive` / `tickWaterAggressive`)
- Stay on connected water; never chase onto land
- Land→water chase only with Swimming/Levitates sprite (entity preserved)
- Slight visual sink (`waterSink = 2`)
- Classic Surf / fishing `encounter.roll` gated by Random Enc, with Water Mons
  overrides: `classic_encounters` forces water rolls ON; `disabled` forces them OFF

### Deferred: Followers EX water integration

**Superseded.** Water follower presentation is already implemented via
`lib/followers_water_compat.lua` + `mod.exports.resolveWaterSprite`.
Follower movement/entity ownership is now handled by the unified follower
core (`lib/follower/`) when Followers EX is not driving trailers.

Do not mix private Followers tables into Wilds water spawn/aggro fixes.

## Unified follower core (`lib/follower/`)

Standalone module layout (no Followers EX / PokéPC required):

```text
lib/follower/
  init.lua             - install / exports / wiring
  constants.lua        - state keys, save keys, external mod IDs
  state.lua            - selection persistence
  selection.lua        - party resolve, fingerprint (+ species), health
  settings.lua         - Control Mode / Trainer Trail / Followers + migration
  sprite_service.lua   - resolveFollowerSprite + SPRITE_PIKACHU registration
  control_engine.lua   - pack/trailers/modes (Followers EX concepts)
  lifecycle.lua        - fallback hooks, party submenu, sprite refresh
  interaction.lua      - talk helpers
  compatibility.lua    - legacy mod detect / restore / migrate
  diagnostics.lua      - HUD lines
```

**Ownership:** Wilds always owns runtime. Legacy mods → migrate + warn.

**Settings (Wilds Mod Settings):**

| Label | Key | Values |
|-------|-----|--------|
| Control Mode | `follow_control` | trainer / pokemon |
| Trainer Trail | `trainer_trail` | off / on |
| Followers | `follower_count` | 0–6 |

Engine mapping: trainer→`follow`; pokemon+trail→`lead_trainer`;
pokemon+count>0→`pack`; pokemon+count0→`pokemon`.

**Not duplicated:** `show_in_menu`, `wilds_grass_lift` (use Grass View),
`wilds_town_spawns` (future Wilds feature).

**Sprite refresh / PR 2:** `resolveFollowerSprite({ species, shiny, form,
surface, style, role, game })`.

See `docs/analysis/STANDALONE_CRASH.md` and
`docs/analysis/FOLLOWER_FEATURE_INVENTORY.md`.

## 20. Cave support

- No dependence on grass graphics
- Walkable indoor tiles
- Hidden uses dust/shadow, never grass shake

## 21. Dev Mode

HUD pipeline `owwild_debug_hud`: Target / Active / Regions / Surface + nearest
entity detail (stable id, behaviour state, source/visible/rendered size,
desired vs one-tile max scale, Voxel registration / fallback, alert/battle).
Overlays: spawn tiles + optional behaviour/sight fills.

## 22. Preview browser

`ui.options.rows` activate row + Start Menu item (no button option type).
Global encounter index; Test spawn 7 phases; never mutates registries.

## 23. Logging

`[WildsOfKanto][LEVEL]` via `debug_log.lua`. Forced on when `dev_mode`.

## 24. Tests

```sh
python3 tools/validate_option_labels.py
python3 tools/validate_release_version.py
cd .deps/gen1recomp
luajit mods/overworld_wild_spawns/tests/overworld_wild_spawns_test.lua
luajit mods/overworld_wild_spawns/tests/voxel_aggressive_compat_test.lua
lua mods/overworld_wild_spawns/tests/battle_art_variable_geometry_unit_test.lua
lua mods/overworld_wild_spawns/tests/voxel_provider_variable_geometry_unit_test.lua
lua mods/overworld_wild_spawns/tests/stadium2_variable_geometry_unit_test.lua
# Follower core (host lua; no engine required)
lua mods/overworld_wild_spawns/tests/follower_core_unit_test.lua
lua mods/overworld_wild_spawns/tests/game_compat_unit_test.lua
lua mods/overworld_wild_spawns/tests/manifest_targets_unit_test.lua
```

## 25. Release build

```sh
./scripts/bootstrap.sh   # once
./scripts/build-mod.py
```

Produces `dist/wilds-of-kanto-v1.0.2.zip` (plus local technical-id aliases) with
`manifest.json` at ZIP root.
Includes `docs/` and `LICENSE`. Excludes `tests/`, `scripts/`, `.deps/`, root `ARCHITECTURE.md`.

**Slim ZIP.** The manual pack (which is what CI produces: the real modkit's `pack` runs `validate --strict` and
refuses on its "dump check skipped" warnings, so `.modkitignore` never shapes the release) leaves out the
**source art** the build uses to generate `assets/wilds_generated/`: `assets/enhanced_overworld/followsprites/`
(atlas PNGs), `pokedex_mapping/` (legacy, unused), `pika_follower_mapping/` (tool input) and the water source PNGs
under `water_sprites/`. The game draws from the generated sheets; only the developer-mode Pokemon preview reads the
follow-sprite atlases, and `WaterSpriteRegistry` stores the source path but loads `water_runtime` sheets. The mapping
JSONs read at runtime (`followsprites_mapping.json`, the water swimming/levitates mappings) still ship. The build's ZIP
check requires those JSONs and the generated sheets, not the source PNGs. Pass `--with-source-art` to
`scripts/build-mod.py` for a full archive.

Tag-triggered GitHub Release (`.github/workflows/release.yml`):

```text
git tag v1.0.2 && git push origin v1.0.2
```

Manifest field `github` = `YoDrehDenSwagAuf/overworld-spawn-mod` enables Mod Manager
update detection. Upload only the public `wilds-of-kanto-v*.zip` asset.

### 25.1 Sprite atlases (default in `build-mod.py`)

The runtime sheets are ~15,400 small PNGs (classic 16x96, True Size, water, silhouettes, poke_followers, pika) plus the 8,088
PMD dialogue portraits (40x40). That is nearly all of the file count of a release ZIP. Since 2.7.0 `python3 scripts/build-mod.py`
(and so the release CI) bakes them into shard PNGs plus JSON indexes and ships those instead. `--atlas=classic,hgss,...` bakes only
some families and `--no-atlas` builds the old per-file ZIP (the fallback if a sprite ever misbehaves only on the atlas build).
`scripts/build-mod.ps1` does not bake atlases; it still produces the per-file layout.

- **Generator** `tools/generate_sprite_atlases.py`: one *family* per sprite directory group (`classic`, `hgss`, `true_followers`,
  `true_pokedex`, `true_swimming`, `true_levitate`, `water_swimming`, `water_levitates`, `silhouette_swimming`,
  `silhouette_levitates`, `poke_followers`, `pika`, `portraits`); bare `--atlas` and `--atlas=all` = every family,
  `--atlas=classic,hgss` picks some. `FAMILY_OPTIONS` overrides shard sizing per family (portraits use ~400 kpx / 10,000 px-tall
  shards so the first dialogue decodes a few MB, not tens) and can declare `prefixes`.
  Output `assets/atlas/` (gitignored build output): `index.json`, `<family>.json` (`dirs -> { file name -> [shard,x,y,w,h] }`,
  shard numbers 0-based) and `<family>_<n>.png`. The root index lists each family's `dirs`; a **prefix family** (`portraits`) lists
  `prefixes` instead (`assets/pmdcollab/portraits/`), so the root index parsed at every launch stays tiny while its 2,050
  directories live in the lazily read family index (343 KB, ~21 ms to decode in LuaJIT, once, at the first dialogue).
- **Layout is one column per shard** (sprites stacked, width = the widest sprite, under 32,768 px tall). PNG compresses row by row
  with a 32 KB deflate window, so mixing sprites in a row made a shelf-packed atlas 33-67% LARGER than the per-file sheets; a
  column is 4-16% smaller (measured). Every sprite is copied pixel for pixel; `tools/validate_sprite_atlases.py` re-slices all of
  them against the source PNGs, checks bounds, overlaps and coverage, and `build-mod.py` runs it every time.
- **Runtime** `lib/sprite_atlas.lua` (installed first in `main.lua`): wraps the engine's central `src.render.Assets`
  (`image`, `imageData`, `exists`), maps `mods/<folder>/assets/...` (or bare / `./` / backslash forms) to the index key, decodes a
  shard on demand into a byte-capped LRU (96 MB), cuts the sprite out into an ordinary small Image (a fresh ImageData copy for
  `imageData`, which the recolor bake mutates) and caches it. Anything not indexed falls through to the original function. It is
  registered with `Assets.register` (invalidate + session-end release). `spawn_render.probeImageLoad`,
  `luminance_sheet.deriveAndPersist` and `pokemon_dialogue`'s portrait loader, which load by path themselves, ask the atlas first.
  The credit / license files under `assets/pmdcollab/` (`CREDITS.txt`, `LICENSE.txt`, `SOURCE.json`, `portrait_table.lua`) stay
  ordinary files and the ZIP check requires them.
- **Source mode:** a family whose real files exist on disk (a repo checkout) is never served from the atlas, so a stale atlas can not
  shadow freshly generated sheets. With no `assets/atlas/index.json` the module does nothing.
- **Not a shared GPU atlas:** the engine's `SpriteRenderer` assumes each sheet starts at x=0 (topHalf / oamRow quads,
  `getFrameGeometry`, recolor baking), so drawing from an atlas offset would mean patching engine internals other mods use. Each
  sprite is still its own small image at draw time, so this reduces file count and per-file IO, not draw cost.
- **Packaging:** the manual pack leaves out the per-file sheets the indexes cover and ships `assets/atlas/`; the ZIP check reads the
  indexes inside the ZIP, requires every shard, and fails if a sprite ships both ways. an atlas build forces the manual pack (the modkit
  cannot apply the exclusion). Measured with every family baked: **23,698 -> 277 files, 33.9 -> 20.1 MB** (the portraits alone go
  from 13.4 MB in 8,088 files to 7.0 MB in 33 shards).
- Not verified in the game: only the wiring (unit test against fakes, the engine's real `Assets` / `SpriteRenderer`, and the whole
  suite on a tree with the per-file sheets removed). Check first-spawn hitches and Voxel / recolor modes on a real ZIP.

## 26. Known technical constraints / Voxel compatibility

- No public wild-battle helper beyond script verb `start_battle`
- No continuous mod tick except present pipelines / events listed above
- Trainer sight has no wall LOS in vanilla; this mod **does** block aggressive sight on non-walkable tiles
- Single-frame sheets ignore SpriteRenderer facing; Idle Look flips in custom draw
- Voxel path uses the public `pose()` billboard contract only; it does **not**
  apply 2D `final2DScale` (cards are always 16×16 from the sheet)
- Hidden markers are logical-only (not in `ow.entities`) because VoxelScene
  retires the whole DRAMATIC_SHAPE pipeline on a nil `sprite.def`
- Per-entity Voxel failures fall back to 2D for that entity; we cannot un-break
  a pipeline Gen1Recomp already marked `broken` after a throw
- Emote (`!`) is drawn by the engine FX overlay, not as a Voxel Pokemon entity
- Full in-game Voxel chase→battle→overworld restore still needs a ROM + both mods

## 27. Adding behaviours

1. Add constant + weights in `lib/behavior.lua`
2. Allow on surfaces in `Surface.BEHAVIORS`
3. Implement branch in `Behavior.tick`
4. Expose option toggle if player-facing
5. Extend tests + docs

## 28. Species configuration

Central tables only:

- `SPECIES_AFFINITY` in `behavior.lua`
- `SPECIES_SCALE` in `sprite_scale.lua`
- Optional `speciesAssetPaths` in `spawn_render.lua`

Avoid scattered `if speciesId == ...` in spawn_logic.

## Implemented knacks (carry forward)

- ZIP root = mod root
- ASCII-only manager metadata (`manifest.json` / `mod.card` / `options.lua`)
- No registry writes after load
- Pre-register all species sprites at load
- Species id for asset identity
- Real art vs fallback
- LÖVE virtual paths only for images
- Vanilla encounter fail-safe
- Pokédex independence
- Entity create ≠ render success diagnostics
- Debug phases on Test spawn
- Preview browser without freezing registries
