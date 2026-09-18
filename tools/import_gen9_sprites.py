#!/usr/bin/env python3
"""Normalize assets/gen_9/{Normal,Shiny}/<NAME[_N]>.png into the standard
{dex:03d}-{form}-{n|s}.png convention tools/generate_true_size_runtime.py's
hgss_source() already expects — written to a STAGING folder, not directly into
assets/enhanced_overworld/followsprites/. The one-time "Gen 9" sprite style has
since been merged into HGSS (species it covered that HGSS didn't were copied
straight into followsprites/ — see CHANGELOG.md), so the natural next step for
freshly-imported art is now the same: review this staging output, then copy
whichever files fill a real gap directly into followsprites/ (there is no
longer a separate gen9_sprites/ concept in the runtime pipeline).

assets/gen_9/ names species/forms directly (e.g. PIKACHU.png, ARCEUS_6.png)
instead of encoding a dex number, so two external, NOT bundled/committed data
sources are needed purely as offline import-time lookups (same "read at
import time only, never copy code/data" policy as scripts/import_pmdcollab.py
and Kanto Reforged interop — see THIRD_PARTY_NOTICES.md):

  --dbk-data <path>      local copy of tectorifter/g9-battle-sprites'
                         data/dbk_data.lua (numeric stem -> semantic form
                         key, e.g. ARCEUS_6 -> ARCEUS_BUG, plus the `female`
                         gender-dimorphic-species flag table)
  --national-dex <path>  local copy of sanjinpepic/gen1recomp-national-dex's
                         mod/data/species/generated/national.lua (semantic
                         name/form key -> numeric dex; forms carry a
                         synthetic dex >= 30000 plus form/baseSpecies fields)

This script NEVER clones or downloads at runtime — the developer supplies
local checkouts of both repos.

Usage:
  python3 tools/import_gen9_sprites.py \\
    --dbk-data /path/to/g9-battle-sprites/data/dbk_data.lua \\
    --national-dex /path/to/gen1recomp-national-dex/mod/data/species/generated/national.lua
    # dry-run by default: prints the full resolved/unresolved report, writes nothing.
    # add --apply to actually copy files into --out.

Output (only with --apply):
  assets/gen_9_staging/followsprites/{dex:03d}-{b|f}-{n|s}.png
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN9_SRC_DEFAULT = ROOT / "assets" / "gen_9"
OUT_DEFAULT = ROOT / "assets" / "gen_9_staging" / "followsprites"
SPECIES_ASSETS_LUA = ROOT / "lib" / "species_assets.lua"

# Battle-only states with no overworld presence (confirmed by maintainer):
# assets/gen_9/ intentionally has no art for these, so any stem that resolves
# to a semantic form key ending in one of these tokens is skipped, not missing.
EXCLUDED_FORM_SUFFIXES = (
    "_MEGA", "_GMAX", "_MEGA_Z", "_RAINY", "_SUNNY", "_SNOWY",
    "MEGA_X", "MEGA_Y", "_STARTER", "_ETERNAMAX",
)

# Known misspelling/encoding quirks in assets/gen_9/ (confirmed or observed).
NAME_FIXUPS = {
    "POLTHCAGEIST": "POLTCHAGEIST",
    "NIDORANfE": "NIDORAN_F",
    "NIDORANmA": "NIDORAN_M",
}

# Placeholder / non-species files to silently ignore (not reported as errors).
IGNORED_STEMS = {"000"}

_LUA_EXTRACT_REGISTER = r"""
local t = dofile(%s)
local reg = t.register
for k, v in pairs(reg) do
  if type(v) == "table" and v.id and v.dex then
    io.write(string.format("%%s\t%%d\t%%s\n", v.id, v.dex, v.form or ""))
  end
end
"""

_LUA_EXTRACT_DBK = r"""
local t = dofile(%s)
-- t.species is [formKey] = stem (formKey first, per dbk_data.lua's header
-- comment: "species: national_dex species id -> DBK sprite-sheet stem").
for formKey, stem in pairs(t.species) do
  io.write(stem .. "\t" .. formKey .. "\n")
end
io.write("--FEMALE--\n")
for stem in pairs(t.female) do
  io.write(stem .. "\n")
end
"""


def run_lua(script: str, data_path: Path) -> str:
    lua_bin = shutil.which("lua") or shutil.which("luajit")
    if not lua_bin:
        sys.exit("ERROR: 'lua' (or 'luajit') not found on PATH — required to read the "
                 "supplied Lua data files.")
    quoted = "[[" + str(data_path) + "]]"
    proc = subprocess.run(
        [lua_bin, "-e", script % quoted],
        cwd=str(data_path.parent),
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"ERROR: lua failed reading {data_path}:\n{proc.stderr}")
    return proc.stdout


def load_national_dex(path: Path) -> tuple[dict[str, int], dict[str, int]]:
    """Returns (base_name -> dex, form_key -> dex). Form keys are entries
    whose `.form` field is non-empty (synthetic dex, see module docstring)."""
    base, forms = {}, {}
    for line in run_lua(_LUA_EXTRACT_REGISTER, path).splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        name, dex_s, form = parts
        dex = int(dex_s)
        if form:
            forms[name] = dex
        else:
            base[name] = dex
    return base, forms


def load_dbk_data(path: Path) -> tuple[dict[str, list[str]], set[str]]:
    """Returns (stem -> [semantic form keys], set of base names with a
    genuine gender-dimorphic `_female` art variant per dbk_data.lua's own
    `female` table)."""
    stem_to_keys: dict[str, list[str]] = {}
    female_flagged: set[str] = set()
    in_female_section = False
    for line in run_lua(_LUA_EXTRACT_DBK, path).splitlines():
        if line == "--FEMALE--":
            in_female_section = True
            continue
        if in_female_section:
            female_flagged.add(line)
            continue
        stem, form_key = line.split("\t")
        stem_to_keys.setdefault(stem, []).append(form_key)
    for keys in stem_to_keys.values():
        keys.sort(key=len)  # prefer the shortest/simplest key when ambiguous
    return stem_to_keys, female_flagged


def build_squashed_index(name_to_dex: dict[str, int]) -> dict[str, str]:
    """gen_9 base-species filenames strip separators entirely (MRMIME,
    TAPUKOKO, IRONHANDS, HOOH, NIDORANfE) while the national-dex/hardcoded
    convention keeps them (MR_MIME, TAPU_KOKO, IRON_HANDS, HO_OH, NIDORAN_F).
    Maps a squashed (underscore/case stripped) name back to its real key."""
    out: dict[str, str] = {}
    for name in name_to_dex:
        out.setdefault(name.replace("_", "").upper(), name)
    return out


def load_hardcoded_species_assets(path: Path) -> dict[str, int]:
    """Parse lib/species_assets.lua's SPECIES_TO_ASSET_ID (flat NAME=NUMBER
    table, 1..386) via regex — no Lua needed, it's a simple literal table."""
    src = path.read_text(encoding="utf-8")
    table_src = re.search(r"local SPECIES_TO_ASSET_ID = \{(.*?)\n\}", src, re.S)
    if not table_src:
        sys.exit(f"ERROR: could not find SPECIES_TO_ASSET_ID table in {path}")
    out = {}
    for name, num in re.findall(r"(\w+)\s*=\s*(\d+)", table_src.group(1)):
        out[name] = int(num)
    return out


def is_stray_s_duplicate(stem: str, sibling_stems: set[str]) -> str | None:
    """BOMBIRDIERs / OGERPON_8s / TERAPAGOS_2s style stray trailing lowercase
    's'. Returns the normalized (s-stripped) stem, or None if this isn't such
    a case."""
    if not stem.endswith("s") or stem[-2:].isupper():
        return None
    if not re.match(r"^[A-Z0-9_]+s$", stem):
        return None
    return stem[:-1]


NUMBERED_FORM_RE = re.compile(r"^([A-Z0-9_]+?)_(\d+)$")


def resolve_stem(
    raw_stem: str,
    all_stems_in_folder: set[str],
    base_name_to_dex: dict[str, int],
    form_key_to_dex: dict[str, int],
    dbk_stem_to_keys: dict[str, list[str]],
    dbk_female_flagged: set[str],
    squashed_index: dict[str, str],
) -> tuple[int, str] | tuple[None, str]:
    """Returns (dex, form_letter) on success, or (None, reason) on failure."""
    stem = raw_stem

    # Known misspelling fixup.
    stem = NAME_FIXUPS.get(stem, stem)

    # Stray trailing lowercase 's': duplicate of a clean sibling -> caller
    # should already have filtered these out before calling; if we get here
    # with no clean sibling, strip and proceed.
    stripped = is_stray_s_duplicate(stem, all_stems_in_folder)
    if stripped is not None:
        stem = stripped

    # _female normalization.
    if stem.endswith("_female"):
        base = stem[: -len("_female")]
        if NUMBERED_FORM_RE.match(base):
            return None, f"ambiguous _female on an already-numbered form ({raw_stem}) — needs a decision, not converted"
        if base in dbk_female_flagged:
            # Genuine gender-dimorphic species: same dex as the base name,
            # '-f-' suffix, not a new numbered form.
            dex = base_name_to_dex.get(base)
            if dex is None:
                return None, f"'{base}' not found in national dex (gender-variant lookup)"
            return dex, "f"
        # Not flagged in dbk_data.lua's own female table: maintainer's rule
        # is to renumber it as form index 1 -- but only when that slot isn't
        # already a distinct real file (e.g. BASCULEGION_1.png ALSO exists
        # alongside BASCULEGION_female.png -- renaming would silently
        # collide the two into the same output file).
        candidate = base + "_1"
        if candidate in all_stems_in_folder:
            return None, (f"'{raw_stem}' would collide with the existing '{candidate}.png' "
                           f"if renamed to _1 -- needs a decision, not converted")
        stem = candidate

    m = NUMBERED_FORM_RE.match(stem)
    if not m:
        # Plain base species name. gen_9 sometimes strips separators
        # entirely (MRMIME, TAPUKOKO, HOOH) vs. the real key (MR_MIME,
        # TAPU_KOKO, HO_OH) -- fall back to the squashed-name index.
        dex = base_name_to_dex.get(stem)
        if dex is None:
            real_name = squashed_index.get(stem.replace("_", "").upper())
            if real_name:
                dex = base_name_to_dex.get(real_name)
        if dex is None:
            return None, f"'{stem}' not found in national dex (base species)"
        return dex, "b"

    # Numbered alternate form: reverse-lookup via dbk_data.lua's stems.
    keys = dbk_stem_to_keys.get(stem)
    if not keys:
        return None, f"stem '{stem}' not found in dbk_data.lua species table"
    for key in keys:
        if any(key.endswith(suf) or suf in key for suf in EXCLUDED_FORM_SUFFIXES):
            continue
        dex = form_key_to_dex.get(key)
        if dex is not None:
            return dex, "b"
    if len(keys) == 1 and any(
        keys[0].endswith(suf) or suf in keys[0] for suf in EXCLUDED_FORM_SUFFIXES
    ):
        return None, f"'{keys[0]}' is a battle-only form (excluded, no overworld art needed)"
    return None, f"stem '{stem}' -> form key(s) {keys} not found in national dex"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dbk-data", required=True, type=Path,
                     help="Local path to g9-battle-sprites' data/dbk_data.lua")
    ap.add_argument("--national-dex", required=True, type=Path,
                     help="Local path to gen1recomp-national-dex's national.lua")
    ap.add_argument("--gen9-src", type=Path, default=GEN9_SRC_DEFAULT,
                     help=f"Source folder (default: {GEN9_SRC_DEFAULT})")
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT,
                     help=f"Staging output folder (default: {OUT_DEFAULT})")
    ap.add_argument("--apply", action="store_true",
                     help="Actually copy files. Without this flag: report only, writes nothing.")
    args = ap.parse_args(argv)

    base_name_to_dex = load_hardcoded_species_assets(SPECIES_ASSETS_LUA)
    nd_base, form_key_to_dex = load_national_dex(args.national_dex)
    for name, dex in nd_base.items():
        base_name_to_dex.setdefault(name, dex)  # hardcoded 1..386 table wins on overlap
    dbk_stem_to_keys, dbk_female_flagged = load_dbk_data(args.dbk_data)
    squashed_index = build_squashed_index(base_name_to_dex)

    resolved: list[tuple[str, str, int, str]] = []   # (variant, orig_stem, dex, form_letter)
    unresolved: list[tuple[str, str, str]] = []       # (variant, orig_stem, reason)
    skipped_dupes: list[tuple[str, str, str]] = []    # (variant, orig_stem, kept_stem)

    for variant_dir, variant_suffix in (("Normal", "n"), ("Shiny", "s")):
        folder = args.gen9_src / variant_dir
        if not folder.is_dir():
            print(f"WARNING: {folder} does not exist, skipping", file=sys.stderr)
            continue
        stems = {p.stem for p in folder.glob("*.png")}
        for stem in sorted(stems):
            if stem in IGNORED_STEMS:
                continue
            s = NAME_FIXUPS.get(stem, stem)
            stripped = is_stray_s_duplicate(s, stems)
            if stripped is not None and stripped in stems:
                skipped_dupes.append((variant_suffix, stem, stripped))
                continue
            dex_or_none, reason_or_form = resolve_stem(
                stem, stems, base_name_to_dex, form_key_to_dex,
                dbk_stem_to_keys, dbk_female_flagged, squashed_index,
            )
            if dex_or_none is None:
                unresolved.append((variant_suffix, stem, reason_or_form))
            else:
                resolved.append((variant_suffix, stem, dex_or_none, reason_or_form))

    print(f"=== Resolved: {len(resolved)} ===")
    for variant, stem, dex, form in sorted(resolved, key=lambda r: (r[2], r[0])):
        print(f"  {variant} {stem:30s} -> {dex:05d}-{form}-{variant}.png")

    print(f"\n=== Skipped stray-'s' duplicates: {len(skipped_dupes)} ===")
    for variant, stem, kept in skipped_dupes:
        print(f"  {variant} {stem} (duplicate of {kept})")

    print(f"\n=== Unresolved: {len(unresolved)} ===")
    for variant, stem, reason in unresolved:
        print(f"  {variant} {stem}: {reason}")

    # Defense in depth: two different source stems must never target the
    # same output filename (would silently overwrite one with the other).
    by_target: dict[str, list[str]] = {}
    for variant_suffix, stem, dex, form in resolved:
        target = f"{dex:03d}-{form}-{variant_suffix}.png"
        by_target.setdefault(target, []).append(stem)
    collisions = {t: stems for t, stems in by_target.items() if len(stems) > 1}
    if collisions:
        print(f"\n=== REFUSING: {len(collisions)} output-filename collision(s) ===")
        for target, stems in collisions.items():
            print(f"  {target} <- {stems}")
        print("\nFix the conflicting source files/mapping before re-running. No files written.")
        return 1

    if not args.apply:
        print("\nDry run only — no files written. Re-run with --apply to convert.")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    written = 0
    for variant_suffix, stem, dex, form in resolved:
        variant_dir = "Normal" if variant_suffix == "n" else "Shiny"
        src = args.gen9_src / variant_dir / f"{stem}.png"
        dst = args.out / f"{dex:03d}-{form}-{variant_suffix}.png"
        shutil.copyfile(src, dst)
        written += 1
    print(f"\nWrote {written} files to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
