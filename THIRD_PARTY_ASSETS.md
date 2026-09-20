# Third-Party Assets — PMDCollab / SpriteCollab

## Source

- Repository: [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab)
- Browse: http://sprites.pmdcollab.org/
- Imported revision: `a3acb77f05fb6649df2790031a1285066ffa32f2`
- Importer: `scripts/import_pmdcollab.py` (version 4)

## License

SpriteCollab materials are licensed under **Creative Commons
Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)**.

- Full license text shipped at `assets/pmdcollab/LICENSE.txt`
- Upstream: https://creativecommons.org/licenses/by-nc/4.0/

Non-commercial use only. Attribution required. See upstream LICENSE.md and
README use policy.

Official Chunsoft-origin graphics that appear in SpriteCollab are credited as
`CHUNSOFT` in upstream `credits.txt` (license field often `Unspecified`).

## What Wilds redistributes

In atlas builds (`scripts/build-mod.py --atlas`) the derived portrait PNGs are packed, pixel for pixel, into a few shard PNGs with a
JSON index instead of shipping as individual files. The art, license and credits are unchanged: `assets/pmdcollab/LICENSE.txt`,
`CREDITS.txt` and `SOURCE.json` still ship as ordinary files.

Under `assets/pmdcollab/` Wilds ships **derived** dialogue-portrait assets
only:

- Selected portrait emotions for Pokémon dialogue (Normal + safe generic pool)
- Generated metadata table and contributor credits

Wilds does **not** ship the full SpriteCollab repository, XML sources,
overworld walker sprites, or dungeon-only animations.

## Attribution

See `assets/pmdcollab/CREDITS.txt` for contributor credits collected from
upstream `credit_names.txt` and per-folder `credits.txt`.

Also listed in `THIRD_PARTY_NOTICES.md`.
