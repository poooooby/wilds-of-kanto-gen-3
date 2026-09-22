#!/usr/bin/env python3
"""Convert PokeWilds overworld sprites (https://github.com/SheerSt/pokewilds) into the
vertical 16x96 sheets the built-in Poke Followers / GSC style expects, to fill the dex
gaps that style has beyond dex 251.

The source tree is a LOCAL, NOT bundled/committed checkout (same "read at import time
only, never copy code" policy as tools/import_gen9_sprites.py and the Kanto Reforged /
PMDCollab interop noted in THIRD_PARTY_NOTICES.md):

    <src>/<species_slug>/overworld.png         96x16, 6 frames, 16x16 each, read right to
                                                left in the fixed order documented below
    <src>/<species_slug>/overworld-shiny.png   optional; used only when it genuinely
                                                differs from overworld.png pixel-for-pixel
                                                (many entries are byte-identical dupes)

Frame order (verified by visually cropping bulbasaur/overworld.png): reading the source
left to right, the 6 tiles are walk_left, idle_left, walk_up, idle_up, walk_down,
idle_down. Our runtime convention (tools/generate_runtime_sprite_sheets.py's
FRAME_SPECS, also used by the water runtime sheets) stacks vertically, top to bottom, as
idle_down, idle_up, idle_left, walk_down, walk_up, walk_left. So the source tile index
for each output row is SOURCE_ORDER = [5, 3, 1, 4, 2, 0]. Both source and target tiles
are 16x16, so this is a straight crop + paste per tile -- no rescale, no resampling, and
the source's more accurate GBC colors are preserved exactly.

Species -> dex matching uses lib/species_display_scale.lua's per-dex name comments
(covers dex 1..1025 locally, no external checkout needed) plus a small SLUG_FIXUPS table
for the handful of folder names that don't slugify-match automatically (punctuation /
default-form qualifiers in the source name). Base species only -- regional/alternate
forms are out of scope for this pass and are reported as unmatched, not converted.

Any dex that already has a file in assets/enhanced_overworld/poke_followers/ is skipped:
that folder stays authoritative for dex 1-251, and skipping makes this tool idempotent.

Usage:
  python3 tools/generate_pokewilds_overworld.py --src "/path/to/pokewilds overworld/pokemon"
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPECIES_DISPLAY_SCALE = ROOT / "lib" / "species_display_scale.lua"
POKE_FOLLOWERS_DIR = ROOT / "assets" / "enhanced_overworld" / "poke_followers"
OUT_DIR = ROOT / "assets" / "enhanced_overworld" / "Pokewilds"

CARD = 16
SRC_W, SRC_H = 96, 16
SHEET_W, SHEET_H = 16, 96
FRAMES = 6

# Output row i (top to bottom: idle_down, idle_up, idle_left, walk_down, walk_up,
# walk_left) comes from source tile SOURCE_ORDER[i] (left to right: walk_left,
# idle_left, walk_up, idle_up, walk_down, idle_down).
SOURCE_ORDER = [5, 3, 1, 4, 2, 0]

# Folder names (as they appear under --src) that don't slugify-match a
# species_display_scale.lua name automatically -- punctuation or an
# un-parenthesized default-form qualifier in that file's name. Base species only;
# everything else that fails to match is a form and is reported, not guessed at.
SLUG_FIXUPS: dict[str, int] = {
    "darmanitan": 555,     # "Darmanitan Standard"
    "farfetch_d": 83,      # "Farfetchd" (apostrophe stripped, no underscore)
    "gourgeist": 711,      # "Gourgeist Average"
    "kommo-o": 784,        # "Kommo O" (folder keeps the literal hyphen)
    "mimikyu": 778,        # "Mimikyu Disguised"
    "minior": 774,         # "Minior Red Meteor"
    "mrmime": 122,         # "Mr Mime"
    "mrrime": 866,         # "Mr Rime"
    "porygonz": 474,       # "Porygon Z"
    "pumpkaboo": 710,      # "Pumpkaboo Average"
    "sirfetch_d": 865,     # "Sirfetchd"
}

NAME_RE = re.compile(r"\[(\d+)\]\s*=\s*[\d.]+,\s*--\s*([^(]+?)\s*(?:\([^)]*\))?\s*$", re.M)


def slugify(name: str) -> str:
    s = name.strip().lower().replace("'", "").replace(".", "").replace(":", "")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s


def load_dex_slugs() -> dict[str, int]:
    """slug -> dex, from lib/species_display_scale.lua's per-dex name comments."""
    text = SPECIES_DISPLAY_SCALE.read_text(encoding="utf-8")
    out: dict[str, int] = {}
    for dex_s, name in NAME_RE.findall(text):
        out.setdefault(slugify(name), int(dex_s))
    return out


def resolve_dex(slug: str, slug_to_dex: dict[str, int]) -> int | None:
    if slug in SLUG_FIXUPS:
        return SLUG_FIXUPS[slug]
    return slug_to_dex.get(slug)


def reordered_sheet(src: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    for row, src_idx in enumerate(SOURCE_ORDER):
        x0 = src_idx * CARD
        tile = src.crop((x0, 0, x0 + CARD, CARD))
        out.paste(tile, (0, row * CARD))
    return out


def _selftest_reorder() -> None:
    """Regression guard for SOURCE_ORDER: a synthetic 96x16 source with one
    solid color per 16x16 tile (tile i = color i) must land at output row
    SOURCE_ORDER[row] after reordered_sheet(). Runs on every invocation --
    there is no Python test runner wired up in this repo (tests/*.lua only)."""
    src = Image.new("RGBA", (SRC_W, SRC_H), (0, 0, 0, 0))
    for i in range(FRAMES):
        tile = Image.new("RGBA", (CARD, CARD), (i * 40, 255 - i * 40, i, 255))
        src.paste(tile, (i * CARD, 0))
    out = reordered_sheet(src)
    for row, src_idx in enumerate(SOURCE_ORDER):
        expected = (src_idx * 40, 255 - src_idx * 40, src_idx, 255)
        actual = out.getpixel((0, row * CARD))
        assert actual == expected, (
            f"SOURCE_ORDER regression: output row {row} is {actual}, expected "
            f"source tile {src_idx}'s color {expected}"
        )


def main(argv=None) -> int:
    _selftest_reorder()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, type=Path,
                    help="Local path to the PokeWilds 'pokemon' folder (one subdir per species slug)")
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    ap.add_argument("--force", action="store_true",
                     help="Regenerate even if the output file already exists")
    args = ap.parse_args(argv)

    if not args.src.is_dir():
        sys.exit(f"ERROR: --src not found: {args.src}")

    slug_to_dex = load_dex_slugs()

    converted: list[tuple[str, int]] = []
    shiny_written: list[str] = []
    shiny_skipped: list[str] = []
    already_covered: list[tuple[str, int]] = []
    orientation_bad: list[str] = []
    unmatched: list[str] = []
    dex_used: dict[int, str] = {}
    collisions: list[tuple[str, str, int]] = []

    species_dirs = sorted(p for p in args.src.iterdir() if p.is_dir())
    for sp_dir in species_dirs:
        ow = sp_dir / "overworld.png"
        if not ow.is_file():
            continue
        slug = sp_dir.name
        dex = resolve_dex(slug, slug_to_dex)
        if dex is None:
            unmatched.append(slug)
            continue
        if dex in dex_used:
            collisions.append((slug, dex_used[dex], dex))
            continue

        primary_normal = POKE_FOLLOWERS_DIR / f"follower_{dex:03d}_normal.png"
        if primary_normal.is_file():
            already_covered.append((slug, dex))
            continue

        with Image.open(ow) as im:
            im = im.convert("RGBA")
            if im.size != (SRC_W, SRC_H):
                orientation_bad.append(f"{slug} ({im.width}x{im.height}, expected {SRC_W}x{SRC_H})")
                continue
            normal_sheet = reordered_sheet(im)

        args.out.mkdir(parents=True, exist_ok=True)
        out_normal = args.out / f"follower_{dex:03d}_normal.png"
        if args.force or not out_normal.is_file():
            normal_sheet.save(out_normal)
        dex_used[dex] = slug
        converted.append((slug, dex))

        sw = sp_dir / "overworld-shiny.png"
        out_shiny = args.out / f"follower_{dex:03d}_shiny.png"
        if sw.is_file():
            with Image.open(sw) as ims:
                ims = ims.convert("RGBA")
                if ims.size != (SRC_W, SRC_H):
                    shiny_skipped.append(f"{slug} (bad shiny size {ims.width}x{ims.height})")
                elif list(ims.getdata()) == list(im.getdata()):
                    shiny_skipped.append(f"{slug} (shiny identical to normal)")
                else:
                    shiny_sheet = reordered_sheet(ims)
                    if args.force or not out_shiny.is_file():
                        shiny_sheet.save(out_shiny)
                    shiny_written.append(slug)
        else:
            shiny_skipped.append(f"{slug} (no shiny art)")

    print(f"=== Converted: {len(converted)} species -> {args.out} ===")
    print(f"    shiny written: {len(shiny_written)}, shiny skipped (falls back to normal): {len(shiny_skipped)}")
    print(f"\n=== Already covered by poke_followers/ (skipped, dex 1-251 stays authoritative): {len(already_covered)} ===")
    print(f"\n=== Skipped -- bad orientation (expected {SRC_W}x{SRC_H}): {len(orientation_bad)} ===")
    for s in orientation_bad:
        print(f"  {s}")
    if collisions:
        print(f"\n=== REFUSING duplicate dex targets: {len(collisions)} ===")
        for slug, kept, dex in collisions:
            print(f"  dex {dex}: kept '{kept}', skipped '{slug}'")
    print(f"\n=== Unmatched slugs (likely forms; not converted): {len(unmatched)} ===")
    for s in sorted(unmatched):
        print(f"  {s}")

    new_beyond_251 = sorted(d for _, d in converted if d > 251)
    print(f"\nNew species beyond dex 251 (net gain over poke_followers/GSC today): {len(new_beyond_251)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
