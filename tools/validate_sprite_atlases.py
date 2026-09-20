#!/usr/bin/env python3
"""Prove the sprite atlases are lossless and complete.

For every sprite in assets/atlas/ this re-slices its rectangle from the shard and compares the RGBA bytes to the
source PNG. It also checks that every source sprite of each family is indexed (and nothing extra is), that every
rectangle is inside its shard and that no two rectangles in a shard overlap.

    python3 tools/validate_sprite_atlases.py            # validates assets/atlas/
    python3 tools/validate_sprite_atlases.py --dir assets/atlas

Exit code 0 = OK. Used by scripts/build-mod.py --atlas and runnable by hand.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate(atlas_dir: Path) -> tuple[list[str], dict]:
    errors: list[str] = []
    stats = {"families": 0, "sprites": 0, "shards": 0}
    root_path = atlas_dir / "index.json"
    if not root_path.is_file():
        return [f"missing {root_path.relative_to(ROOT).as_posix()}"], stats
    root = load_json(root_path)
    if root.get("version") != 1:
        errors.append(f"unsupported root index version {root.get('version')!r}")

    for fam, meta in sorted(root.get("families", {}).items()):
        stats["families"] += 1
        idx_path = ROOT / meta["index"]
        if not idx_path.is_file():
            errors.append(f"{fam}: missing family index {meta['index']}")
            continue
        idx = load_json(idx_path)
        shards = idx.get("shards", [])
        stats["shards"] += len(shards)
        images = []
        for s in shards:
            p = ROOT / s["file"]
            if not p.is_file():
                errors.append(f"{fam}: missing shard {s['file']}")
                images.append(None)
                continue
            im = Image.open(p).convert("RGBA")
            if im.size != (s["w"], s["h"]):
                errors.append(f"{fam}: shard {s['file']} is {im.size}, index says {(s['w'], s['h'])}")
            images.append(im)

        rects_by_shard: dict[int, list] = {}
        # The family index is the source of truth for its directories (a prefix family has none in the root index);
        # also walk the prefixes on disk so a source directory that was never indexed is caught.
        fam_dirs = set(idx["dirs"]) | set(meta.get("dirs", []))
        for prefix in meta.get("prefixes", []):
            base = ROOT / prefix.rstrip("/")
            if base.is_dir():
                fam_dirs |= {p.parent.relative_to(ROOT).as_posix() for p in base.rglob("*.png")}
        for d in sorted(fam_dirs):
            src_names = sorted(p.name for p in (ROOT / d).glob("*.png"))
            indexed = idx["dirs"].get(d, {})
            missing = sorted(set(src_names) - set(indexed))
            extra = sorted(set(indexed) - set(src_names))
            if missing:
                errors.append(f"{fam}: {len(missing)} source sprites not indexed in {d} (first: {missing[0]})")
            if extra:
                errors.append(f"{fam}: {len(extra)} indexed sprites have no source in {d} (first: {extra[0]})")
            for name, (sh, x, y, w, h) in indexed.items():
                stats["sprites"] += 1
                atlas = images[sh] if 0 <= sh < len(images) else None
                if atlas is None:
                    errors.append(f"{fam}: {d}/{name} points at bad shard {sh}")
                    continue
                if x < 0 or y < 0 or x + w > atlas.size[0] or y + h > atlas.size[1]:
                    errors.append(f"{fam}: {d}/{name} rectangle {x},{y},{w},{h} is outside shard {sh}")
                    continue
                rects_by_shard.setdefault(sh, []).append((x, y, w, h, f"{d}/{name}"))
                src = ROOT / d / name
                if not src.is_file():
                    continue
                with Image.open(src) as sim:
                    want = sim.convert("RGBA")
                if want.size != (w, h):
                    errors.append(f"{fam}: {d}/{name} is {want.size}, index says {(w, h)}")
                    continue
                got = atlas.crop((x, y, x + w, y + h))
                if got.tobytes() != want.tobytes():
                    errors.append(f"{fam}: {d}/{name} differs from its source PNG")

        for sh, rects in rects_by_shard.items():
            rects.sort()
            for i, a in enumerate(rects):
                for b in rects[i + 1:]:
                    if b[0] >= a[0] + a[2]:
                        break  # sorted by x: nothing further right can overlap a
                    if b[1] < a[1] + a[3] and a[1] < b[1] + b[3]:
                        errors.append(f"{fam}: shard {sh}: {a[4]} overlaps {b[4]}")
    return errors, stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="assets/atlas", help="atlas directory, repo-relative (default: %(default)s)")
    args = ap.parse_args()
    errors, stats = validate(ROOT / args.dir)
    if errors:
        print(f"sprite atlas validation FAILED ({len(errors)} problems):", file=sys.stderr)
        for e in errors[:40]:
            print("  - " + e, file=sys.stderr)
        if len(errors) > 40:
            print(f"  ... and {len(errors) - 40} more", file=sys.stderr)
        return 1
    print(f"sprite atlas validation ok: {stats['families']} families, {stats['shards']} shards, "
          f"{stats['sprites']} sprites re-sliced pixel-exact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
