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
`mods/wilds_of_kanto_gen3` → repo root.

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
wild encounters, followers, and the New Bark town
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

### Unown letter forms (Gold)

Unown is one species whose letter comes from the DVs (`Unown.letterFromDVs`, 1 = A .. 26 = Z). `GameCompat.wildVariant` (Gen 2 adapter
only) draws a spawn's letter with the engine's own rules -- no puzzle solved means no encounter, otherwise `Unown.wildDVs` rerolls until
the letter is unlocked -- and `SpawnLogic` keeps `unownLetter` / `unownForm` / `unownDvs` on the record. `Entity.new` sets
`entity.spriteForm` (1..25 = the `201-b-n-NN` file suffix; nil = A), which `SpriteResolver` passes through
`SpriteProviders:resolve(style, species, variant, game, form)` to the HGSS/PokeMMO provider only. That provider swaps the id for
`60000 + form` (`lib/unown_forms.lua`), so runtime sheets, True Size packs, geometry, `species_geometry.displayScale` (aliased to 201) and
the atlas all serve the letter unchanged, and it falls back to the base sheet when a letter's sheet is missing. The letter sheets are baked
by the same generators as any species -- `tools/unown_forms.py` synthesizes their mapping entries (they are not in the followsprites
mapping) -- so a fresh bake needs no extra step; run `generate_runtime_sprite_sheets.py` and
`generate_true_size_runtime.py --pack hgss --species 60001,...,60025`. The Poke Followers / GSC style has no per-letter art.
The battle gets the same letter: `GameCompat.startWildBattle(..., { dvs })` swaps `Mon.randomDVs` for a one-shot around the synchronous
`start_battle` queue and always restores it. Tests: `tests/unown_forms_unit_test.lua`, `tests/gen2_unown_unit_test.lua`.

### Pokemon Tower ghosts (Gen 1, Silph Scope)

Without the Silph Scope every wild Pokemon in the Tower is an unidentifiable GHOST. The engine owns the rule (`Map.ghostBattles(def)`:
`{ unlessItem = "SILPH_SCOPE" }` for `POKEMON_TOWER*` maps, applied in `OverworldController`'s step-encounter path); our visible spawns
started their battles through the scripted `start_battle` (plain `BattleState.newWild`, never `makeGhost`), so they leaked. `lib/ghost_disguise.lua`
mirrors the rule from the engine (fallback: id prefix + `SILPH_SCOPE`) and `GameCompat.wildGhostMasked(game, mapDef)` exposes it (Gen 1 only; Gold is
always false). It is evaluated fresh at each use: (1) **sprite** -- at spawn `record.ghostMasked` -> `Entity.new` sets `spriteForm = "TOWER_GHOST"`,
which `SpriteResolver` passes as a string through `SpriteProviders:resolve(..., form)`; the form puts the HGSS/PokeMMO provider FIRST for every sprite
style and it swaps in extra asset id 60100, the baked `TOWER_GHOST.png` (flat sheet + True Size pack + geometry, via `tools/unown_forms.py`, same
mechanism as the Unown letters). (2) **battle** -- `SpawnLogic:_startBattle` calls `GameCompat.startGhostBattle` (`Gen1.startGhostBattle`: `newWild`,
`wild_encounter` checkpoint, `makeGhost`, `ow:afterBattle` on finish, `ow:pushBattle`, exactly the engine's step-encounter block) and never falls back
to a normal battle. (Overworld ball throws, and their dodge, moved out with Overworld Catching.) Picking up the scope changes battles immediately; already-spawned
sprites keep the disguise until the next spawn. The pokemmo provider reports the extra asset id it served as `meta.formAssetId`, and the two places
that re-apply True Size after resolving (`Entity.new` and the bind refresh in `spawn_render.lua`) pass THAT to `VariableSize.applyToDef` instead of the
species: applying the species' pack silently swapped an Unown letter / the ghost back to the base sprite (only the real-engine harness sees it: it
checks the image the entity actually draws). Tests: `tests/ghost_disguise_unit_test.lua` and the
Tower block in the real-engine `tests/overworld_wild_spawns_test.lua`.

### Poke Followers / GSC coverage beyond dex 251 (PokeWilds)

The built-in Poke Followers / GSC style (`followers_ex` provider) ships hand-picked art for dex 1-251 under
`assets/enhanced_overworld/poke_followers/`. `assets/enhanced_overworld/Pokewilds/` extends it with more species,
converted from the [Pokémon Wilds](https://github.com/SheerSt/pokewilds) project's overworld walker sprites by
`tools/generate_pokewilds_overworld.py`: same 16x96 vertical sheet, same `follower_%03d_{normal,shiny}.png`
naming, but sourced from a 96x16 horizontal sheet whose 6 frames read right to left in a fixed, non-obvious order
(`walk_left, idle_left, walk_up, idle_up, walk_down, idle_down`) -- the tool's `SOURCE_ORDER` constant maps that
onto our top-to-bottom `idle_down, idle_up, idle_left, walk_down, walk_up, walk_left` rows and re-verifies the
mapping against a synthetic fixture on every run. Base species only (no regional/alternate forms this pass,
matching `followers_ex`'s existing dex-only scope); species without a genuine hand-made shiny sprite in the
source get no shiny file at all rather than a guessed recolor -- reverse-engineering real normal/shiny pairs
showed the source's `shiny.pal` files don't reduce to a per-species recolor formula, so it isn't used.
`_pokeFollowersPath` / `_pokeFollowersShinyPath` in `lib/sprite_providers.lua` try `poke_followers/` first and
only fall through to `Pokewilds/` when that dex is missing there, so dex 1-251 is completely untouched and a
missing shiny sheet already falls back to normal through the same path the primary folder uses. Both folders
are one `poke_followers` atlas family (`tools/generate_sprite_atlases.py`). Tests:
`tests/poke_followers_assets_unit_test.lua`.

### Town Pokemon body-block prevention (always on)

`lib/ambient_pokemon.lua`'s `AmbientPokemon.isSafeSpawnCell(ow, map, x, y, ignore)` is the single
gate shared by initial placement (`findSpawnCell`) and every wander step in both generations (the
wrapped `npc.update` inside Gen 1's `_makeNpc`, and Gen 2's `_makeGoldGuest`). Beyond the existing
exact-cell checks (walkable / not water / not a warp, door or counter / not already occupied), it
now also rejects a candidate cell within `AmbientPokemon.PROXIMITY_RADIUS` (2, Chebyshev) tiles of:
- a **narrow-passage cell** (`AmbientPokemon.isNarrowPassageCell`): walkable ground whose
  left+right neighbors are both blocked, or whose up+down neighbors are both blocked -- the
  doorway / counter-gap / bridge shape, built from the same `map:inBounds` / `isWalkableCell` /
  `isWaterCell` primitives `isBlockedSpecial` already uses;
- **any other entity** (player, NPC, another Town Pokemon) -- `nearAnyEntity` generalizes the old
  exact-match-only occupancy check to a radius over the same `ow.entities`/`ow.npcs` lists.

A Town Pokemon collides like a normal NPC (`passable = false`), so without this it could stand in
or beside a 1-wide passage and fully block the player's only route through. There is no longer a
TOWN POKEMON toggle -- the feature (curated per-map species/counts for Gen 2 in
`lib/gen2/town_pokemon.lua`, dynamic pool selection for Gen 1) is always on now that placement is
safe. Tests: `tests/ambient_pokemon_unit_test.lua`.

## 6. Runtime image cache

`resolvedAssetBySpeciesId` / `runtimeImageCache` hold paths and bake results.
Optional bake writes `wilds_of_kanto_gen3-cache/<id>.png` as a **LÖVE virtual**
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

The Gen 1 Spawn Table and Random modern-spawn modes (previously `lib/gen9_encounters.lua`,
`lib/random_spawns.lua`, `lib/dex_expansion.lua`, `lib/species_flags_data.lua`, and the
MODERN SPAWNS / LEGEND-MYTHIC / MAX GEN options) have been removed. That functionality now
lives in the separate `g1r_modern_spawns` repo, which will integrate through its own API.

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
- **Swimmer flag for Terrarium's reef:** Terrarium (`lib/WakeFX.lua`) scans `ow.entities` and treats any entity with `surfing`
  set as a swimmer (splash in, wake + foam, stirs lilypads / reeds / kelp, rides the live swell); it is the same flag the player's
  Surf and Terrarium's own water roamers carry, and Terrarium has no other API for it. We set it on (a) followers standing in a
  water CELL (`ControlEngine:_syncSwimmerFlags`, run every frame from `advanceAllTrailers`; trainer trailers skipped) and (b) visible
  wild water spawns (`Surface.isSwimmer`, applied per entity by the behavior tick; hidden / submerged-shadow mons excluded). Gen 1
  only: Gold's engine reads `mover.surfing` as a collision flag. Inert without Terrarium. Tests:
  `tests/terrarium_swimmer_flag_unit_test.lua`.
- Classic Surf `encounter.roll` gated by Classic Enc (`random_encounters`), the same switch as grass and caves.
  Water Mons is locked to swimming sprites (`Config.LOCKED.water_spawns`).
- Silhouette (`wild_silhouettes`) is one option for land and water, decided per wild spawn by where it stands NOW
  (`WaterDisplay.inWaterNow`, never `originSurface`): land -> `SpriteResolver:resolveLandSprite` black-out; in water ->
  `result.waterSilhouette` (Voxel: baked `swimming/levitates_silhouette_runtime` sheets; Flat: draw tint). Followers
  and Town Pokemon never silhouette (`WaterDisplay.wantsWaterSilhouette`).

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
  settings.lua         - Followers count + migration (control mode locked to trainer)
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
| Followers | `follower_count` | 0–6 |

Control Mode and Trainer Trail are locked (`Config.LOCKED`: trainer / off), so the
engine mode is always `follow`. The `lead_trainer` / `pack` / `pokemon` engine paths
remain in code but are unreachable.

**Not duplicated:** `show_in_menu`, `wilds_grass_lift` (use Grass View),
`wilds_town_spawns` (future Wilds feature).

**Sprite refresh / PR 2:** `resolveFollowerSprite({ species, shiny, form,
surface, style, role, game })`.

See `docs/analysis/STANDALONE_CRASH.md` and
`docs/analysis/FOLLOWER_FEATURE_INVENTORY.md`.

## 20. Cave support

- No dependence on grass graphics
- Gold: any map whose header environment is CAVE or DUNGEON counts (`Surface.isIndoorEncounterMap`), the same rule as the engine's
  step encounters; Gen 1 keeps its `field.indoorEncounters` index rule
- Gold reachability is DIRECTED (`CaveReachability.build` picks it when the map exposes `stepPermitted` / `cellCollision`; Gen 1 keeps
  the grid fill + `tilePairs`). Gold's one-way rules live in collision bytes, so a plain 4-neighbour fill fabricated most of a cave: the
  cave tilesets are full of UP_WALL edge cells (you cannot step down onto one or up off one) and ledge hops. The fill follows the engine's
  own offline model (`tools/goldwalk/mapgraph.lua` in Gen1Recomp): steps must pass `map:stepPermitted`, a refused step off a ledge hops two
  cells, and a cell is a hole only when it is a warp tile by collision AND has a warp event (a `warp_event` on plain floor is a ladder
  landing spot that never fires; a warp-collision tile with no event does nothing). Surf is not modelled and ice counts as floor.
  Spawns still avoid every warp-event cell (`classifyCell` says INVALID) even though the fill walks through plain-floor ones. On the real
  Gold data the old fill called ~55% of the cells in wild-table caves reachable when they were not (Dark Cave 96%, Union Cave 1F 59%) and missed
  cells elsewhere (Ruins of Alph inner chamber 144, Tin Tower floors). Tests: `tests/cave_reachability_gold_unit_test.lua` (synthetic
  layouts, engine rules stubbed) and `tests/cave_reachability_gold_data_unit_test.lua` (every Gold cave map from every warp arrival against the
  engine model, pinned to the engine tool's own counts; skips without `../gen1recomp/gold` or `GEN1RECOMP_GOLD_ROOT`)
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
luajit mods/wilds_of_kanto_gen3/tests/overworld_wild_spawns_test.lua
luajit mods/wilds_of_kanto_gen3/tests/voxel_aggressive_compat_test.lua
lua mods/wilds_of_kanto_gen3/tests/battle_art_variable_geometry_unit_test.lua
lua mods/wilds_of_kanto_gen3/tests/voxel_provider_variable_geometry_unit_test.lua
lua mods/wilds_of_kanto_gen3/tests/stadium2_variable_geometry_unit_test.lua
# Follower core (host lua; no engine required)
lua mods/wilds_of_kanto_gen3/tests/follower_core_unit_test.lua
lua mods/wilds_of_kanto_gen3/tests/game_compat_unit_test.lua
lua mods/wilds_of_kanto_gen3/tests/manifest_targets_unit_test.lua
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
