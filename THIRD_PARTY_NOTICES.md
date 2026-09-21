# Third-Party Notices

The MIT License in this repository applies to the original Wilds of Kanto
source code and original project assets.

Third-party assets remain subject to their respective licenses and are not
relicensed under the Wilds of Kanto MIT License.

See the asset-specific documentation and credits for details.

## Notable third-party material

- **PMDCollab / SpriteCollab** dialogue portraits under
  `assets/pmdcollab/` are derived at build time from
  [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab)
  (CC BY-NC 4.0). See `THIRD_PARTY_ASSETS.md`, `assets/pmdcollab/LICENSE.txt`,
  and `assets/pmdcollab/CREDITS.txt`. Wilds does not ship the full upstream
  repository; only selected portrait emotions. Dialogue portraits are
  independent of the selected overworld Sprite Style. (An earlier release
  also shipped PMDCollab-derived overworld walker sprites as a selectable
  Sprite Style; that style was removed as redundant bloat — see
  CHANGELOG.md.)
- Follow-sprite / overworld Pokemon art under `assets/enhanced_overworld/`
  remains under the license of its original authors and sources. It is not
  covered by this project's MIT License.
- Built-in **Poke Followers / GSC** sheets under
  `assets/enhanced_overworld/poke_followers/` are third-party follower /
  overworld walker art integrated for standalone use. Credits follow the
  upstream Followers EX / PokéPC / ShockSlayer (Pokémon Crystal Clear) lineage;
  Wilds does not claim authorship of those sprites.
- Generated runtime sheets under `assets/wilds_generated/followsprites_runtime/`
  are derived from those third-party follow-sprites and inherit the same
  third-party licensing constraints. In the mod menu these are labeled
  **HGSS / PokeMMO** (Wilds of Kanto's built-in HGSS-style option).
- Optional companion sprites from
  [Followers EX](https://github.com/masterwebx/gen1recomp-followers-ex)
  / [PokePC Followers](https://github.com/gamecorner-033/PokePCFollowers)
  remain owned by those projects. Wilds ships a built-in GSC walker pack and
  only optionally probes those mods for migration / advanced resolution.
- Additional overworld follow-sprites merged into the HGSS / PokeMMO set (originally
  sourced/attributed as "Gen9" overworld sprites, later merged for gap-filling species
  the original HGSS art didn't cover):
  MissingLukey, help-14, Kymoyonian, cSc-A7X, 2and2makes5, Pokegirl4ever, Fernandojl, Silver-Skies, TyranitarDark, Getsuei-H, Kid1513, Milomilotic11, Kyt666, kdiamo11, Chocosrawlooid, Syledude, Gallanty, Gizamimi-Pichu, 2and2makes5, Zyon17,LarryTurbo, spritesstealer, LarryTurbo, princess-pheonix, LunarDusk, Wolfang62, TintjeMadelintje101, piphybuilder88, Larry Turbo, princess-pheonix, SageDeoxys, Wolfang62, LarryTurbo, tammyclaydon, Boonzeet, DarkusShadow, princess-phoenix, Ezeart, WolfPP, Azria, DarkusShadow, EduarPokeN, Carmanekko, StarWolff, Caruban, DarkusShadow
- The **Pokémon Tower ghost** overworld sprite
  (`assets/enhanced_overworld/followsprites/TOWER_GHOST.png`, and the runtime and True Size
  sheets generated from it) is art by **Nuclear-Blizzard**. It is shown for wild Pokémon in
  the Pokémon Tower until the player has the Silph Scope. Like the other follow-sprites it
  remains the work of its author and is not covered by this project's MIT License.
- Selection, fingerprint, talk, control modes, pack trailers, and lifecycle
  **concepts** adapted from PokéPC Followers (gamecorner-033) and Followers EX
  (masterwebx) live under `lib/follower/`. Upstream assets are not required at
  runtime; Wilds uses built-in Poke Followers / GSC or HGSS/PokeMMO sheets.
- **Shiny Pokemon** by [masterwebx](https://github.com/masterwebx/gen1recomp-shiny-pokemon)
  (MIT License, Copyright (c) 2026 masterwebx). The SHINY RATE and SHINY SPARKLE
  features (`lib/shiny.lua`, `lib/shiny_sparkle.lua`) are based on that mod's design:
  rolling real shiny DVs on wild Pokemon at a configurable rate (same rate steps and
  denominators, Gen 2 shiny DV rule), handing a visible spawn's roll to its battle, and a
  one-time battle sparkle with the "Dex Page Added" chime that waits for the intro to finish.
  The code was written for Wilds, not copied file-for-file, but the approach and constants
  follow the original. Shiny Pokemon is a declared manifest conflict and is not bundled or
  required. Its MIT permission notice: permission is granted, free of charge, to use, copy,
  modify, merge, publish, distribute, sublicense and/or sell copies of the software, subject
  to including the copyright and permission notice in copies or substantial portions.
- Optional overworld catching **concepts** (Ball selection, 1–6 tile throws,
  projectile arc, wobble, native catch attempt, Party/Box deposit) were
  reimplemented for Wilds under `lib/catching/`, inspired by
  [Gen1PC-OverworldEncounters](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters)
  (`src/catching.lua`) by gamecorner-033. Wilds does not copy that module
  verbatim and routes failure through its own aggressive / battle pipeline.
- ShockSlayer / Pokémon Crystal Clear overworld art remains credited via the
  PokéPC / follower lineage for GSC-style walker art.
- TRW / DAX / Antigravity and other authors named in upstream follower credits
  remain credited there; Wilds does not relicense their work.
- Optional battle-front art from
  [Gold Sprites](https://github.com/OtaconRevengeance/gold_sprites)
  (`Gold_Silver_Sprites` by OtaconRevengeance) is likewise read-only at runtime
  and is not redistributed by Wilds. That release ships without a LICENSE file
  and asks users not to reupload the pack.
- Legacy Pokédex / battle art references used as fallbacks are game-adjacent
  assets and are not relicensed under MIT.
- Gen1Recomp engine APIs and Dramatic Shape Voxel Mod contracts belong to
  their respective projects and licenses.
- **Kanto Reforged** (GNU GPLv3) is an independent companion mod that extends
  the base Gen1Recomp/Gen2 game's own content registry (`mod.content.pokemon`)
  with Gen 2 and Gen 3 species — stats, types, moves, abilities, and dex
  entries — up to National Dex #386. Wilds of Kanto does not bundle, copy, or
  modify any Kanto Reforged code or data; it only reads already-loaded
  `game.data.pokemon` fields at runtime (read-only interop, the same pattern
  used for the base Gen1Recomp/Gold content) to resolve species names to
  canonical sprite/asset ids in `lib/species_assets.lua`. No GPLv3 obligations
  attach to this repository from that interop. Kanto Reforged's own battle
  sprites are intentionally grayscale, hand-authored Game Boy–style art (its
  README: "wholesale replaces Pokémon battle sprites across Gens 1-3 with
  custom classic-styled art"), which is a design choice of that project, not
  a Wilds asset or bug.
