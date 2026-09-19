# True Size system (1.14.0)

## Sizing philosophy (native HGSS)

True Size means **preserve original HGSS / PokeMMO follower artwork scale**,
not “Pokédex metres → XS–XXL targetHeight”.

- **Authority:** shared alpha bounds of original `followsprites` (not runtime 16×16)
- **Default:** no resampling (`TRUE_SIZE_PADDING = 2` only)
- **Optional:** declarative `visualScale` / anchor offsets (nearest-neighbor)
- **Other packs:** match HGSS *visible* body height, then their own padded canvas
- **Prototype first:** Rattata / Blastoise / Onix — see `TRUE_SIZE_NATIVE_HGSS.md`
- Logical footprint stays **one cell**. Classic + Voxel unchanged.

## Architecture

```
pokemon_size option  →  requestedMode
                              │
                 ┌────────────┴────────────┐
                 ▼                         ▼
            Flat renderer            Voxel renderer
                 │                         │
                 ▼                         ▼
            TRUE SIZE               capability check
                                         │
                          ┌──────────────┴──────────────┐
                          ▼                             ▼
                   supports geometry              incompatible
                          │                             │
                          ▼                             ▼
                     TRUE SIZE                       CLASSIC
```

`requestedMode` is the saved user preference. `effectiveMode` is what rendering
uses. **Voxel never writes `pokemon_size`.**

## Assets

| Pack | Path | Count (normal+shiny) | Source |
|------|------|----------------------|--------|
| HGSS | `true_size/hgss` | 302 | original `followsprites` |
| Followers | `true_size/followers` | 302 | `poke_followers` strips |
| Pokédex | `true_size/pokedex` | 302 | HGSS idle-down 1-frame stand-in |
| Swimming | `true_size/swimming` | 824 species | original `water_sprites/swimming` |
| Levitate | `true_size/levitate` | 184 species | original `water_sprites/levitates` |

Classic assets under `followsprites_runtime` / `water_runtime` / `poke_followers`
are never overwritten.

Swimming/Levitate generation used to cap at dex 386 regardless of available source art
(`tools/generate_true_size_runtime.py`'s `water_sources(kind, max_dex=386)` default, now raised
to 1025) even though HGSS land sprites cover the full National Dex. Source art itself currently
tops out around dex 1010 (swimming) / 1005 (levitate), so a handful of the newest species still
lack dedicated art pending additional sourcing — species without source art keep whatever
existing fallback rendering applies.

### Pitfall: `legacy_target_height` species have no `nativeVisualHeight`

Many species (including Pikachu, dex 25) are still on the older `legacy_target_height` sizing
method rather than `native` — for these, `species_geometry.json`'s top-level
`nativeVisualHeight`/`scaledVisualHeight` fields are `None`, even though their `packs.pokemmo`
entry has a perfectly real `frameHeight`/`anchorY`. Only the per-pack fields are populated; the
top-level "what height should other packs match" fields simply were never computed for these
species.

This matters for any NEW code that bakes art for such a species and wants to fit it to that
species' existing size — e.g. `generate_matched_pack_for_dex`'s `reference_visible_height`
path, or a bespoke script reading `entry.get("nativeVisualHeight")`. A fallback chain like
`entry.get("scaledVisualHeight") or entry.get("nativeVisualHeight") or 16` silently lands on the
hardcoded `16` default for these species (since both real fields are `None`), not their actual
frame size — producing a needlessly downscaled, blurry result with no error or warning anywhere.
This is exactly what happened baking `tools/generate_pika_follower_true_size.py`'s Pikachu
costume art the first time: every costume was forced to fit a 16px target when Pikachu's real
`pokemmo` frame is 18px, and diagnosing it required a live in-game screenshot comparison, not
anything the build script itself surfaced.

Two ways to avoid this:
- If the new art shares the exact same source scale/grid as the species' own real art (as the
  Pikachu costumes do — same 128×128, 4×4-grid `followsprites` convention), skip height-matching
  entirely and bake it the same way `generate_hgss_for_dex` treats the authority pack itself:
  `compose_native_sheet(tiles, visual_scale=1.0, allow_resample=False)`, no reference height
  needed.
- If height-matching against another pack genuinely is needed, read the height from that pack's
  own already-baked `packs.<packId>.frameHeight` (e.g. `packs.pokemmo.frameHeight`), not the
  top-level `nativeVisualHeight`/`scaledVisualHeight` fields, since only the per-pack fields are
  guaranteed populated regardless of sizing method.

## Consumers

Wild spawn_render · sprite_providers · water_sprite_registry ·
follower sprite_service / control_engine / water_compat · ambient_pokemon

All call `VariableSize.applyToDef` / preserve geometry fields.

## Follower visual trail spacing

Logical footprint is **one cell for every species, always** — `ControlEngine:_goalsFromTrailHistory`
lags each trailer by its own plain sequential convoy slot (1st, 2nd, 3rd...) into
`pokepcTrailHistory`, order-preserving by construction ("the Classic snake that never breaks").

A per-species cumulative-gap version of this (`gap = max(gap(previous), gap(current))` from
`SpeciesGeometry.followGap`) was tried and reverted in the same week it was introduced
(`6ce85ccc` → `1e46102c`, see CHANGELOG's "2.0.1 — Follower convoy fixes"): whole-cell lag
jumps let a follower's goal land past an intermediate follower's goal on a doubled-back path,
and strict cell reservations then deadlocked the pack ("chain break"), resolved only by a
jam-recovery teleport (the "slingshot" pop). `SpeciesGeometry.followGap` /
`VariableSize.visualFollowGap` / `ControlEngine:_followGapForSource` still exist but are dead
code — nothing in the movement path calls them.

Because plain one-cell lag means a trailer that falls meaningfully behind (e.g. after the
player dashes several tiles quickly) doesn't automatically close the gap, both `_assignTrailerStep`
and `_chainCatchUpSteps` halve a lagging trailer's `stepFrames` via a shared
`ControlEngine:_trailerCatchUpDivisor(headDist, slot)`. The formula only engages once a
trailer's head-distance exceeds its slot's steady-state distance by more than one cell of
slack (`excess = headDist - (slot + 1)`) — preserving the original anti-slingshot trigger point
exactly, so a normal fold in the player's path (which can bump `headDist` by a cell or two for
every slot at once) does not make the whole convoy dash simultaneously. Past that slack, the
divisor scales proportionally with how far behind the trailer actually is
(`min(4, 1 + ceil(excess / 2))`) rather than a flat 2x regardless of gap size, so a trailer
that's fallen far behind (e.g. tail-end of a long convoy after a fast player dash) closes the
gap faster than one that's only barely lagging — capped at 4x so this only ever speeds up
walking, never approaches teleport speed (the separate jam-recovery system still handles the
genuinely-stuck case).

A render-only per-trailer pixel push-back for species wider than one tile
(`ControlEngine:_largeTrailerPushbackPx`, data-driven from `(frameWidth - Tile.CELL) / 2`)
pushes the trailer back along its facing direction so its True Size art doesn't visually overlap
the entity ahead of it. Each trailer's amount is its OWN overhang only, cached once at creation
by `makeTrailer` and applied independently by `placeTrailerAt`/`ControlEngine.advanceTrailerStep`
— deliberately never summed with a neighbor's amount. Two chain-aware designs were tried and
reverted first: the offset is an absolute value added to a trailer's own `px`/`py`, but the
actual visual gap between adjacent trailers N-1 and N is the *difference* of their two offsets,
not either one alone — so getting every adjacent pair correctly spaced requires a full
running-total cumulative sum down the whole convoy (`offset_N = offset_{N-1} + own_{N-1} +
own_N`). That sum grows unboundedly with convoy length and how many large species are in it, and
interpolating a large accumulated offset across a single ~16px turn step (needed to avoid a
"snap" when facing changes — see below) traces a big, visually wrong diagonal "floating" sweep.
A pairwise compromise (own + immediate predecessor's own, no further chain) avoided floating but
turned out mathematically wrong for anything past slot 1, since it doesn't satisfy the
difference equation above either. Own-overhang-only was kept instead: it fully and correctly
spaces the player→slot-1 gap (the player has no overhang of its own, so slot 1's own amount
alone is the correct gap — the one case that never needed cross-trailer math at all) and never
makes any other adjacent pair worse than doing nothing, but doesn't guarantee a fully cleared
gap when two wide species are adjacent deeper in the convoy.

`ControlEngine.advanceTrailerStep` smooths the offset itself across a turn: it tracks
`npc._wildsAppliedOffsetX/Y` (the offset baked in as of the trailer's last completed step) and
linearly blends from that toward the new target offset using the step's own `t`, rather than
snapping to the new facing's offset the instant `npc.facing` changes at step start. This fixed
an earlier "snapping" regression where the offset jumped instantly on a turn while position
eased in normally. Since own-overhang-only never accumulates across the convoy, the magnitude
being interpolated stays bounded to a single species' own overhang, which is small enough not to
reintroduce the "floating" sweep described above.

## Wild vs Follower geometry (root cause of Wild clipping)

**Symptom:** True Size Wilds clipped on land, grass, **and** water; Followers
of the same species rendered correctly. Grass alone was not the root cause.
Onix artwork + Follower Onix proved Gen1Recomp variable SpriteRenderer works.

**Root cause (final):** `applyProviderSprite` re-called `VariableSize.applyToDef`
with `speciesId = entity.species` (a **name** like `"ONIX"`). `packGeometry`
only accepts dex `1..151`, so apply failed with `no_geometry`, **stripped**
`frameWidth`/`frameHeight`, but **left the `true_size/` image**.  
`SpriteRenderer.new` then baked **16×16 quads** on the tall sheet → cropped
Wild. Followers pass numeric dex via `spriteDefWithGeometry`.

Secondary issues fixed earlier: Wild def copies dropping geometry; water rebind
without `presentation`/`packId`; skip checks using `(frameWidth or 16)`.

**Fix:** Prefer `enhancedDexId` / resolved dex in `applyProviderSprite`; resolve
species names inside `applyToDef`; **never** clear geometry while a `true_size/`
image remains; compare SpriteRenderer **instance** `frameWidth`/`frameHeight`
in skip-rebuild checks (draw uses instance values, not only `def`).

Logical footprint stays 16×16. Visual geometry comes from `sprite.frameWidth`
/ `getPoseGeometry()`.

## Grass / scaleInfo

Native True Size entities mirror `frameWidth`/`frameHeight` into `scaleInfo`
for diagnostics / feet-band cover only — SpriteScale one-tile clamp must not
drive native True Size draws.

**Classic Flat:** engine `TileRenderer:drawCellBottom` (bottom **8px** of the
16×16 cell) — unchanged.

**True Size Flat:** `GrassOcclusion.installTileRendererWrap` intercepts
`drawCellBottom` for entities that queued a feet-band during `Entity:draw`:

- Immersed → `setScissor` to `computeTrueSizeCover()` (~4–6px at feet)
- Above → skip overdraw entirely

Scissor restore is guarded with `pcall`. Voxel untouched. Feet-band remains a
separate native Tall Grass overdraw concern after the geometry fix.

## Dramatic Shape / Battle Art / Potato / Dramaless / Stadium2 / Terrarium Voxel

Capability is tied to the **active** Voxel renderer
(`VariableSize.activeVoxelProvider()`). Installing Battle Art while Potato,
Dramaless, Stadium2, or Terrarium is the live pipeline does not enable True Size.

| Provider | Mod ID | Public `exports.lib.require` | HGSS in Voxel |
| --- | --- | --- | --- |
| Battle Art Voxel Fork | `BATTLE_ART_VOXEL_FORK` | yes (1.8.3) | True Size via existing adapter |
| Potato Voxel | `potato_voxel` | yes (1.4.0) | True Size via adapter; `shadowBlob()` unchanged |
| Dramaless Shape | `DRAMALESS_SHAPE` | yes (1.6.4) | True Size via adapter |
| Stadium2 Overworld Models | `STADIUM2_OVERWORLD_MODELS` | yes (current Gen 2 voxel) | True Size via adapter |
| Terrarium | `TERRARIUM` | yes (1.35.0-beta) | True Size via adapter |
| Original Dramatic Shape | `DRAMATIC_SHAPE` | n/a for Wilds wrap | Classic unless native `variableSpriteGeometry` |

Wilds does **not** copy VoxelScene / SpriteBillboards / shaders. Failure or
a missing public accessor keeps Classic 16×16 and logs once (DEV).

`VariableSize.canUseTrueSizeInVoxel()` reports live capability of the active
provider (adapter or upstream export), not a version number.

Stadium2 support is **renderer compatibility only** (Wilds SpriteDef geometry
→ Stadium2 `SpriteBillboards`). Some Stadium2 builds have embedded their own
Wilds runtime. Wilds probes public exports (`embeddedWilds` / `wilds` table)
and logs the situation; it does not disable Stadium2 handlers or rewrite
Stadium2 files. Dual-runtime coexistence is an external Stadium2 change.

## KNOWN BUG: floating True Size sprites under Battle Art Voxel

Variable-geometry wild Pokemon (True Size, i.e. any species
whose `anchorY` differs from `frameHeight`) render floating well above the
ground specifically when **Battle Art Voxel Fork** is the active Voxel
renderer with Voxel mode on. Worse for species whose anchor sits further
from `frameHeight` (Squirtle, Onix, Lapras all confirmed). Confirmed correct:

- Voxel mode off (Classic 2D path) — correct.
- Terrarium as the active Voxel renderer — correct.
- Battle Art as the active Voxel renderer — floating, ~2x too high.

Ruled out during investigation (2026-09-12):

- Wilds' own quad-construction math (`localQuad` / `uvRect` /
  `resolveGeometry`) is byte-for-byte identical between
  `compat/battle_art_variable_geometry.lua` and the shared
  `compat/voxel_sprite_billboards_adapter.lua` factory Terrarium uses — the
  bug is not Wilds treating the two providers differently.
- Neither engine reads `def.anchorY` / `sprite.anchorY` directly anywhere in
  its own source; both only see geometry through the mesh vertices Wilds
  hands them via the wrapped `SpriteBillboards.mesh()` — no double-counting
  of the anchor value on the engine side.
- The ground/feet point is constructed to sit at local mesh origin (Y=0),
  which should in principle be invariant under any pure rotation.

One confirmed, real difference between the two engines that has not yet been
proven (or ruled out) as the mechanism: Battle Art's `Mat4.billboard` rotates
the card by raw `pitch`; Terrarium's `billboardMatrix` rotates by
`cardPitch() - math.pi / 2` — a 90-degree difference in camera-tilt
convention between the two forks' own, independently-written camera code.
Whether/how this interacts with non-origin-pivoted quads (or whether the
real cause is elsewhere, e.g. in how each engine computes the ground-height
`y` parameter passed into the billboard matrix) has not been isolated —
needs either live visual testing at varying camera pitch, or a from-scratch
reverse-engineering of Battle Art's ground-height calculation for entities.
To be corrected later.
