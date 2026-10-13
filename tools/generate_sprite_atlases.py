#!/usr/bin/env python3
"""Bake the per-species runtime sprite sheets into shard atlases plus JSON indexes (a release-ZIP build output).

The game normally asks the engine for one small PNG per sprite (about 15,000 files). This tool packs each
sprite FAMILY (a directory of `<dex>-<variant>.png` sheets: normal and shiny together) into a few shard PNGs and
writes an index that maps every original relative path to its rectangle. lib/sprite_atlas.lua serves those
paths from the shards at runtime, so nothing that asks for `assets/wilds_generated/.../025-normal.png` changes.

    python3 tools/generate_sprite_atlases.py                      # prototype families (classic + hgss)
    python3 tools/generate_sprite_atlases.py --families all       # every family, incl. the PMD portraits
    python3 tools/generate_sprite_atlases.py --families classic,hgss --max-shard-px 1500000

Output (default `assets/atlas/`, gitignored, rebuilt by scripts/build-mod.py --atlas):
    index.json               { version, families: { <name>: { index, dirs: [...] } } }
    <family>.json            { version, family, shards: [{file,w,h}], dirs: { <dir>: { <name>: [shard,x,y,w,h] } } }
    <family>_<n>.png         shard atlases (RGBA, lossless; shard numbers are 0-based)

Every sprite is copied pixel for pixel (RGBA, transparent pixels keep their RGB), so slicing it back out gives
exactly the source image. tools/validate_sprite_atlases.py proves that for every sprite.

Colour numbers (default; `--rgba` = the old full-colour shards): a sheet uses few colours and its shiny is the
same drawing in other colours, so a sprite's normal and shiny sheets (same size) are stored ONCE as a greyscale
image of colour NUMBERS, each number one (normal colour, shiny colour) pair -- exact, also where a shiny splits one
colour in two, and transparent pixels keep their RGB. Each sheet's colours are one row of `<family>_pal.png`
(RGBA, column = number); lib/sprite_atlas.lua turns the numbers back into the exact sheet when it is sliced. Pairs:
`<key>-normal.png` / `<key>-shiny.png` and `<key>_normal.png` / `<key>_shiny.png` in one directory, and the
portraits' `<dex>/normal/<emotion>.png` / `<dex>/shiny/<emotion>.png`. A sprite needing more than 256 pairs is
tried alone, then kept full colour in a `rgba` shard. Family index version 2:
    shards: [{file,w,h,mode = "index" | "rgba"}], palette: {file,w,h},
    dirs: { <dir>: { <name>: [shard,x,y,w,h, palette row (index shards only)] } }

Layout: each shard is ONE COLUMN, the sprites stacked top to bottom (width = the widest sprite in the shard).
That is deliberate. PNG compresses row by row with a 32 KB deflate window, and a row that mixes several sprites
breaks both the per-row filter choice and the window's reach across a sprite's frames: measured on the real
sheets, a wide shelf-packed atlas came out 33-67% LARGER than the per-file PNGs, a single column comes out 4-16%
SMALLER. Shards stay under 32,768 px tall so they are also legal GPU textures if anyone ever uploads one.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import re
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GEN = "assets/wilds_generated"

# family -> list of directory globs (repo-relative). Only top-level PNGs of each directory are packed;
# manifests and other files stay as ordinary files.
FAMILIES: dict[str, list[str]] = {
    "classic": [f"{GEN}/followsprites_runtime"],
    "hgss": [f"{GEN}/true_size/hgss"],
    "true_followers": [f"{GEN}/true_size/followers"],
    "true_pokedex": [f"{GEN}/true_size/pokedex"],
    "true_swimming": [f"{GEN}/true_size/swimming"],
    "true_levitate": [f"{GEN}/true_size/levitate"],
    "water_swimming": [f"{GEN}/water_runtime/swimming"],
    "water_levitates": [f"{GEN}/water_runtime/levitates"],
    "silhouette_swimming": [f"{GEN}/swimming_silhouette_runtime"],
    "silhouette_levitates": [f"{GEN}/levitates_silhouette_runtime"],
    "poke_followers": ["assets/enhanced_overworld/poke_followers", "assets/enhanced_overworld/Pokewilds"],
    "pika": [f"{GEN}/pika_follower_runtime", f"{GEN}/true_size/pika_*"],
    # PMDCollab dialogue portraits: <dex>/<normal|shiny>/<emotion>.png, all 40x40 (2,050 directories).
    "portraits": ["assets/pmdcollab/portraits/*/*"],
}
# Per-family overrides. `max_px` / `max_h` size the shards (a dialogue touches one species at a time, so portrait
# shards stay small to keep the first decode a few ms). `prefixes` lets the runtime match every directory under a
# prefix without listing thousands of directories in the root index that is parsed at every launch.
FAMILY_OPTIONS: dict[str, dict] = {
    "portraits": {"max_px": 400_000, "max_h": 10_000, "prefixes": ["assets/pmdcollab/portraits/"]},
}
PROTOTYPE = ("classic", "hgss")
INDEX_VERSION = 1
MAX_SHARD_H = 32768  # tallest shard (also the GPU texture limit that is safe everywhere)


def natural_key(text: str):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", text)]


def family_dirs(patterns: list[str]) -> list[str]:
    out: list[str] = []
    for pat in patterns:
        for hit in sorted(glob.glob(str(ROOT / pat))):
            p = Path(hit)
            if p.is_dir():
                out.append(p.relative_to(ROOT).as_posix())
    return sorted(dict.fromkeys(out), key=natural_key)


def collect(dirs: list[str]):
    """[(dir, name, w, h)] in natural order (by dir, then dex/variant name)."""
    items = []
    for d in dirs:
        for f in sorted((ROOT / d).glob("*.png"), key=lambda p: natural_key(p.name)):
            with Image.open(f) as im:
                w, h = im.size
            items.append((d, f.name, w, h))
    return items


def split_shards(items, max_px: int, max_h: int = MAX_SHARD_H):
    """Consecutive runs of sprites (so neighbouring dex ids share a shard), each at most `max_h` tall and about
    `max_px` pixels (shard width is its widest sprite)."""
    shards, cur, height, width = [], [], 0, 0
    for it in items:
        w, h = it[2], it[3]
        new_w = max(width, w)
        if cur and (height + h > max_h or new_w * (height + h) > max_px):
            shards.append(cur)
            cur, height, width, new_w = [], 0, 0, w
        cur.append(it)
        height += h
        width = new_w
    if cur:
        shards.append(cur)
    return shards


def pack_shard(group):
    """One column: sprites stacked in order, left aligned. Returns (width, height, [(dir, name, x, y, w, h)])."""
    width = max(w for _, _, w, _ in group)
    placed, y = [], 0
    for d, name, w, h in group:
        placed.append((d, name, 0, y, w, h))
        y += h
    return width, y, placed


def build_family(name: str, dirs: list[str], out_dir: Path, max_px: int) -> dict:
    items = collect(dirs)
    if not items:
        return {"name": name, "sprites": 0, "shards": 0, "px": 0, "src_px": 0, "dirs": dirs, "index": None}
    opts = FAMILY_OPTIONS.get(name, {})
    shards = split_shards(items, opts.get("max_px", max_px), min(opts.get("max_h", MAX_SHARD_H), MAX_SHARD_H))
    index = {"version": INDEX_VERSION, "family": name, "shards": [], "dirs": {d: {} for d in dirs}}
    atlas_px = 0
    src_px = sum(w * h for _, _, w, h in items)
    for n, group in enumerate(shards):
        width, height, placed = pack_shard(group)
        atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        for d, fname, x, y, w, h in placed:
            with Image.open(ROOT / d / fname) as im:
                atlas.paste(im.convert("RGBA"), (x, y))
            index["dirs"][d][fname] = [n, x, y, w, h]
        rel = f"assets/atlas/{name}_{n}.png"
        atlas.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": rel, "w": width, "h": height})
        atlas_px += width * height
    (out_dir / f"{name}.json").write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    return {"name": name, "sprites": len(items), "shards": len(shards), "px": atlas_px, "src_px": src_px,
            "dirs": dirs, "index": f"assets/atlas/{name}.json"}


MAX_COLOURS = 256
# a sprite's normal / shiny partner: the variant token in its name, or the portraits' variant directory
PAIR_PATTERNS = (re.compile(r"^(.*)-(normal|shiny)(\.png)$"), re.compile(r"^(.*)_(normal|shiny)(\.png)$"),
                 re.compile(r"^(.*/)(normal|shiny)(/[^/]+)$"))


def pair_key(d: str, name: str) -> str:
    rel = f"{d}/{name}"
    for pat in PAIR_PATTERNS:
        m = pat.match(rel)
        if m:
            return m.group(1) + "*" + m.group(3)
    return rel


def colour_groups(items):
    """Sprites that share one colour-number image: a normal + shiny pair of the same size, else each alone.
    Returns [([(dir, name)], w, h)] in the items' order (the normal first)."""
    by_key: dict[str, list] = {}
    order = []
    for d, name, w, h in items:
        key = pair_key(d, name)
        if key not in by_key:
            by_key[key] = []
            order.append(key)
        by_key[key].append((d, name, w, h))
    groups = []
    for key in order:
        members = sorted(by_key[key], key=lambda m: "shiny" in f"{m[0]}/{m[1]}")  # normal first
        if len(members) == 2 and members[0][2:] == members[1][2:]:
            groups.append(([(d, n) for d, n, _, _ in members], members[0][2], members[0][3]))
        else:
            groups.extend(([(d, n)], w, h) for d, n, w, h in members)
    return groups


def number_group(members):
    """(index bytes, [colour row per member]) or None when it needs > 256 numbers (members: 1 or 2 (dir, name))."""
    cols = []
    for d, n in members:
        with Image.open(ROOT / d / n) as im:
            cols.append(np.frombuffer(im.convert("RGBA").tobytes(), dtype="<u4"))
    # one 64-bit key per pixel = its colour in each member (normal low, shiny high)
    key = cols[0].astype(np.uint64)
    if len(cols) > 1:
        key |= cols[1].astype(np.uint64) << np.uint64(32)
    pairs, inverse, counts = np.unique(key, return_inverse=True, return_counts=True)
    if len(pairs) > MAX_COLOURS:
        return None
    order = np.lexsort((pairs, -counts))  # most common first, ties by colour (deterministic)
    number = np.empty(len(pairs), dtype=np.uint8)
    number[order] = np.arange(len(pairs), dtype=np.uint8)
    data = number[inverse.reshape(-1)].tobytes()
    ranked = pairs[order]
    rows = [((ranked >> np.uint64(32 * m)) & np.uint64(0xFFFFFFFF)).astype("<u4").tobytes()
            for m in range(len(members))]
    return data, rows


def build_family_indexed(name: str, dirs: list[str], out_dir: Path, max_px: int) -> dict:
    items = collect(dirs)
    if not items:
        return {"name": name, "sprites": 0, "shards": 0, "px": 0, "src_px": 0, "dirs": dirs, "index": None}
    opts = FAMILY_OPTIONS.get(name, {})
    max_px, max_h = opts.get("max_px", max_px), min(opts.get("max_h", MAX_SHARD_H), MAX_SHARD_H)
    groups = colour_groups(items)
    # numbering reads every PNG: spread it over all cores (results come back in order)
    with ProcessPoolExecutor() as pool:
        results = list(pool.map(number_group, [m for m, _, _ in groups], chunksize=16))
    numbered, full = [], []  # [(members, w, h, data, rows)], [(dir, name, w, h)]
    for (members, w, h), got in zip(groups, results):
        if got is None and len(members) > 1:
            for m in members:  # the pair together needs too many: try each alone
                alone = number_group([m])
                if alone:
                    numbered.append(([m], w, h, *alone))
                else:
                    full.append((m[0], m[1], w, h))
        elif got is None:
            full.append((members[0][0], members[0][1], w, h))
        else:
            numbered.append((members, w, h, *got))

    index = {"version": 2, "family": name, "shards": [], "dirs": {d: {} for d in dirs}}
    palette_rows: list[bytes] = []
    atlas_px = 0
    src_px = sum(w * h for _, _, w, h in items)
    n = 0
    # colour-number shards: one rectangle per group, shared by its members
    for group in split_shards([(None, g, g[1], g[2]) for g in numbered], max_px, max_h):
        width = max(item[2] for item in group)
        height = sum(item[3] for item in group)
        shard = Image.new("L", (width, height), 0)
        y = 0
        for item in group:
            members, w, h, data, rows = item[1]
            shard.paste(Image.frombytes("L", (w, h), data), (0, y))
            for (d, fname), row in zip(members, rows):
                index["dirs"][d][fname] = [n, 0, y, w, h, len(palette_rows)]
                palette_rows.append(row)
            y += h
        shard.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": f"assets/atlas/{name}_{n}.png", "w": width, "h": height, "mode": "index"})
        atlas_px += width * height
        n += 1
    # full-colour shards for anything that would not number
    for group in split_shards(full, max_px, max_h):
        width, height, placed = pack_shard(group)
        atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        for d, fname, x, y, w, h in placed:
            with Image.open(ROOT / d / fname) as im:
                atlas.paste(im.convert("RGBA"), (x, y))
            index["dirs"][d][fname] = [n, x, y, w, h]
        atlas.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": f"assets/atlas/{name}_{n}.png", "w": width, "h": height, "mode": "rgba"})
        atlas_px += width * height
        n += 1
    if palette_rows:
        pw = max(len(r) for r in palette_rows) // 4
        pal = Image.new("RGBA", (pw, len(palette_rows)), (0, 0, 0, 0))
        for r, row in enumerate(palette_rows):
            pal.paste(Image.frombytes("RGBA", (len(row) // 4, 1), row), (0, r))
        pal.save(out_dir / f"{name}_pal.png", "PNG", optimize=True)
        index["palette"] = {"file": f"assets/atlas/{name}_pal.png", "w": pw, "h": len(palette_rows)}
    (out_dir / f"{name}.json").write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    return {"name": name, "sprites": len(items), "shards": n, "px": atlas_px, "src_px": src_px,
            "dirs": dirs, "index": f"assets/atlas/{name}.json", "full": len(full)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--families", default=",".join(PROTOTYPE),
                    help="comma list of family names, or 'all' (default: %(default)s)")
    ap.add_argument("--out", default="assets/atlas", help="output directory, repo-relative (default: %(default)s)")
    ap.add_argument("--max-shard-px", type=int, default=1_500_000, help="approximate pixels per shard")
    ap.add_argument("--rgba", action="store_true",
                    help="full-colour shards (family index version 1) instead of colour numbers")
    args = ap.parse_args()

    names = list(FAMILIES) if args.families == "all" else [n.strip() for n in args.families.split(",") if n.strip()]
    unknown = [n for n in names if n not in FAMILIES]
    if unknown:
        print(f"unknown families: {unknown}; known: {sorted(FAMILIES)}", file=sys.stderr)
        return 2

    out_dir = ROOT / args.out
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    reports = []
    for name in names:
        dirs = family_dirs(FAMILIES[name])
        build = build_family if args.rgba else build_family_indexed
        rep = build(name, dirs, out_dir, args.max_shard_px)
        reports.append(rep)
        size = sum(f.stat().st_size for f in out_dir.glob(f"{name}_*.png"))
        extra = f", {rep['full']} full colour" if rep.get("full") else ""
        print(f"{name:<22} {rep['sprites']:>5} sprites -> {rep['shards']:>3} shards, {size / 1e6:6.2f} MB{extra}")

    families = {}
    for r in reports:
        if not r["index"]:
            continue
        prefixes = FAMILY_OPTIONS.get(r["name"], {}).get("prefixes")
        meta = {"index": r["index"], "dirs": [] if prefixes else r["dirs"]}
        if prefixes:
            meta["prefixes"] = prefixes
        families[r["name"]] = meta
    root_index = {"version": INDEX_VERSION, "families": families}
    (out_dir / "index.json").write_text(json.dumps(root_index, separators=(",", ":")), encoding="utf-8")
    total_files = len(list(out_dir.iterdir()))
    total_bytes = sum(f.stat().st_size for f in out_dir.iterdir())
    shown = out_dir.relative_to(ROOT).as_posix() if out_dir.is_relative_to(ROOT) else out_dir.as_posix()
    print(f"wrote {shown}/ ({total_files} files, {total_bytes / 1e6:.1f} MB) "
          f"covering {sum(r['sprites'] for r in reports)} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
