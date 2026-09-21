#!/usr/bin/env python3
"""Generate lib/gen9_encounters_authored.lua from tools/data/gen9_authored_encounters.json.

The generated Essentials data (lib/gen9_encounters_data.lua) does not cover a few Gen 1 areas (Route 18, Route 24,
Victory Road, five Super Rod groups). Those tables are authored by hand in the JSON next to this script; this tool
validates every pick against the national dex data and writes them in the SAME format as the generated data, so
lib/gen9_encounters.lua merges them in without special cases.

Validation (the reason this is a tool and not a hand-edited Lua file) keeps every species in the realm of its part of
the game: each map lists a `band` (base-stat total range, allowed evolution positions, optional types) taken from the
ORIGINAL area's own species, and a species outside its band is an error. Species must also be Gen 3-9 (dex 252..1025)
and not legendary/mythical/Ultra Beast/Paradox.

A map may also carry a `classic` block: the same shapes, but Gen 2 species (dex 152..251). lib/gen9_encounters.lua uses it
only when the MAX GEN cap leaves the primary table with no slot at all (a Gen 2 cap drops every Gen 3-9 species), so those
areas stay modern-flavoured instead of falling back to the original game's table. A map may have ONLY a `classic` block
(the generated Essentials data covers it, but with nothing at or below Gen 2).

Inputs (outside the repo, like tools/generate_gen9_encounters.py):
  --national-dex  national_dex mod's data/species/generated/national.lua   (keys, dex, types, base stats)
  --evolutions    national_dex mod's data/evolutions/generated/            (evolution position; optional --
                                                                            without it the stage check is skipped)

Quantization is the generated data's own (tools/generate_gen9_encounters.py: spread_rows / to_units / order_pairs):
one slot per (species, level) with whole-256ths odds. Super Rod entries keep the group size given in the JSON.

Run: python3 tools/generate_gen9_authored.py --national-dex <.../national.lua> [--evolutions <.../evolutions/generated>]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_gen9_encounters as gen  # noqa: E402  (reuses the generated data's own quantization)

DATA_PATH = ROOT / "tools/data/gen9_authored_encounters.json"
FLAGS_PATH = ROOT / "lib/species_flags_data.lua"
OUT_PATH = ROOT / "lib/gen9_encounters_authored.lua"
UNITS = gen.UNITS
GEN3_FIRST, GEN9_LAST = 252, 1025
GEN2_FIRST, GEN2_LAST = 152, 251
KINDS = ("grass", "water", "superRod")


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_species_facts(path: Path) -> dict[str, dict]:
    """key -> { dex, types, bst } from national.lua's `register` records."""
    lines = path.read_text(encoding="utf-8").split("\n")
    out: dict[str, dict] = {}
    section = None
    rec = None
    for ln in lines:
        m = re.match(r"^  (patch|register|text) = \{", ln)
        if m:
            section, rec = m.group(1), None
            continue
        if section != "register":
            continue
        m = re.match(r"^    ([A-Z0-9_]+) = \{$", ln)
        if m:
            rec = {"dex": None, "types": [], "hp": 0, "attack": 0, "defense": 0, "speed": 0, "spa": 0, "spd": 0}
            out[m.group(1)] = rec
            continue
        if rec is None:
            continue
        m = re.match(r"^\s+dex = (\d+),", ln)
        if m and rec["dex"] is None:
            rec["dex"] = int(m.group(1))
        m = re.match(r"^\s+types = \{ (.*?) \},", ln)
        if m:
            rec["types"] = re.findall(r'"([A-Z_]+)"', m.group(1))
        m = re.match(r"^\s+baseStats = \{ (.*?) \},", ln)
        if m:
            for k, v in re.findall(r"(\w+) = (\d+)", m.group(1)):
                if k in ("hp", "attack", "defense", "speed"):
                    rec[k] = int(v)
        m = re.match(r"^\s+spAttack = (\d+),", ln)
        if m:
            rec["spa"] = int(m.group(1))
        m = re.match(r"^\s+spDefense = (\d+),", ln)
        if m:
            rec["spd"] = int(m.group(1))
    for rec in out.values():
        rec["bst"] = rec["hp"] + rec["attack"] + rec["defense"] + rec["speed"] + rec["spa"] + rec["spd"]
    return out


def parse_stages(directory: Path) -> dict[str, str]:
    """key -> single | base | mid | final (position in its evolution chain)."""
    stages: dict[str, str] = {}
    for f in sorted(directory.glob("*.lua")):
        for ln in f.read_text(encoding="utf-8").split("\n"):
            m = re.match(r"^  ([A-Z0-9_]+) = \{ chain = \{([^}]*)\}", ln)
            if not m:
                continue
            key = m.group(1)
            chain_len = len(re.findall(r'"[A-Z0-9_]+"', m.group(2)))
            st = re.search(r"stage = (\d+)", ln)
            stage_no = int(st.group(1)) if st else 1
            has_into = "evolvesInto = {" in ln
            if chain_len <= 1:
                stages[key] = "single"
            elif stage_no == 1:
                stages[key] = "base"
            elif has_into:
                stages[key] = "mid"
            else:
                stages[key] = "final"
    return stages


def restricted_dex(path: Path) -> set[int]:
    return {int(n) for n in re.findall(r"\[(\d+)\] = \"", path.read_text(encoding="utf-8"))}


def check_species(sp: str, where: str, band: dict | None, facts: dict, stages: dict | None,
                  restricted: set[int], report: list[str], dex_range: tuple[int, int] = (GEN3_FIRST, GEN9_LAST)) -> dict:
    rec = facts.get(sp)
    if rec is None or rec["dex"] is None:
        die(f"{where}: species {sp} is not in the national dex data")
    dex = rec["dex"]
    lo_dex, hi_dex = dex_range
    if not (lo_dex <= dex <= hi_dex):
        die(f"{where}: {sp} is dex {dex}; this table only allows dex {lo_dex}..{hi_dex}")
    if dex in restricted:
        die(f"{where}: {sp} (dex {dex}) is legendary/mythical/Ultra Beast/Paradox")
    if band:
        lo, hi = band["bst"]
        if not (lo <= rec["bst"] <= hi):
            die(f"{where}: {sp} has base-stat total {rec['bst']}, outside this area's {lo}-{hi}")
        want = band.get("types")
        if want and not any(t in rec["types"] for t in want):
            die(f"{where}: {sp} is {'/'.join(rec['types'])}, needs one of {', '.join(want)}")
        if stages is not None and band.get("stages"):
            stage = stages.get(sp, "single")
            if stage not in band["stages"]:
                die(f"{where}: {sp} is a '{stage}' evolution, this area allows {', '.join(band['stages'])}")
    return rec


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--national-dex", required=True, type=Path)
    ap.add_argument("--evolutions", type=Path, default=None)
    ap.add_argument("--report", type=Path, default=None)
    args = ap.parse_args()

    spec = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    facts = parse_species_facts(args.national_dex)
    stages = parse_stages(args.evolutions) if args.evolutions else None
    restricted = restricted_dex(FLAGS_PATH)
    report = []
    if stages is None:
        report.append("note: no --evolutions given, the evolution-stage check was skipped")

    def build(entry: dict, dex_range: tuple[int, int], label: str) -> dict:
        """Validate and quantize one block ({grass|water, superRod, bands...}) into the runtime shapes."""
        out: dict = {}
        for kind in ("grass", "water"):
            if kind not in entry:
                continue
            rows = entry[kind]
            where = f"{label}.{kind}"
            band = (entry.get("bands") or {}).get(kind)
            total = sum(r["pct"] for r in rows)
            if abs(total - 100) > 0.001:
                die(f"{where}: percentages add up to {total}, not 100")
            per_sec = [[]]
            dexes = {}
            for r in rows:
                if r["min"] > r["max"]:
                    die(f"{where}: {r['species']} min {r['min']} > max {r['max']}")
                rec = check_species(r["species"], where, band, facts, stages, restricted, report, dex_range)
                dexes[r["species"]] = rec["dex"]
                per_sec[0].append((r["species"], r["pct"] / 100.0, r["min"], r["max"]))
            weights = gen.spread_rows(per_sec, report)
            units = gen.to_units(weights)
            thresholds, slots, cum = [], [], 0
            for sp, lv in gen.order_pairs(units):
                cum += units[(sp, lv)]
                thresholds.append(cum)
                slots.append({"level": lv, "species": sp, "dex": dexes[sp],
                              "pct": round(units[(sp, lv)] / UNITS * 100, 2)})
            assert cum == UNITS and len(thresholds) == len(slots)
            out[kind] = {"buckets": thresholds, "slots": slots}
            worst_pair, worst_species = gen.ladder_errors(weights, units)
            report.append(f"  {kind}: {len(slots)} slots, {len(rows)} species; max error "
                          f"{worst_pair:.2f} pts per level / {worst_species:.2f} pts per species")
        if "superRod" in entry:
            band = entry.get("bandsSuperRod")
            group = entry["superRod"]
            if not (1 <= len(group) <= gen.SUPER_ROD_SLOTS):
                die(f"{label}.superRod: {len(group)} entries (1..{gen.SUPER_ROD_SLOTS} allowed)")
            rod = []
            for e in group:
                rec = check_species(e["species"], f"{label}.superRod", band, facts, stages, restricted, report, dex_range)
                rod.append({"level": e["level"], "species": e["species"], "dex": rec["dex"]})
            out["superRod"] = rod
            report.append(f"  superRod: {len(rod)} entries (the original group's size, so the bite chance is unchanged)")
        return out

    result: dict[str, dict] = {}
    for map_id, entry in spec["maps"].items():
        report.append(map_id)
        out = build(entry, (GEN3_FIRST, GEN9_LAST), map_id)
        if "classic" in entry:
            report.append("  classic (Gen 2, used only under a Gen 2 cap):")
            out["classic"] = build(entry["classic"], (GEN2_FIRST, GEN2_LAST), f"{map_id}.classic")
        result[map_id] = out

    lines = [
        "-- AUTO-GENERATED by tools/generate_gen9_authored.py from tools/data/gen9_authored_encounters.json -- do not hand-edit.",
        "-- Hand-authored Gen 3-9 tables for the Gen 1 areas the generated Essentials data does not cover (same shape as",
        "-- lib/gen9_encounters_data.lua: grass/water { buckets, slots } and superRod), plus per-map `classic` tables of Gen 2",
        "-- species that lib/gen9_encounters.lua uses only when the MAX GEN cap leaves the primary table empty. Every species is validated against the",
        "-- area's power band (base-stat total, evolution position, type) and levels are re-anchored to the original game's",
        "-- level distribution at runtime, like the generated data. lib/gen9_encounters.lua fills in only the maps/kinds the",
        "-- generated data lacks.",
        "return {",
        "  version = 2,",
        "  maps = {",
    ]
    def emit(entry: dict, indent: str) -> None:
        for kind in KINDS:
            if kind not in entry:
                continue
            lines.append(f"{indent}{kind} = {{")
            if kind == "superRod":
                for sl in entry[kind]:
                    lines.append(f'{indent}  {{ level = {sl["level"]}, species = "{sl["species"]}", dex = {sl["dex"]} }},')
            else:
                lines.append(f"{indent}  buckets = {{ " + ", ".join(str(b) for b in entry[kind]["buckets"]) + " },")
                lines.append(f"{indent}  slots = {{")
                for sl in entry[kind]["slots"]:
                    lines.append(f'{indent}    {{ level = {sl["level"]}, species = "{sl["species"]}", '
                                 f'dex = {sl["dex"]}, pct = {sl["pct"]} }},')
                lines.append(f"{indent}  }},")
            lines.append(f"{indent}}},")

    for map_id, entry in result.items():
        lines.append(f"    {map_id} = {{")
        emit(entry, "      ")
        if "classic" in entry:
            lines.append("      classic = {")
            emit(entry["classic"], "        ")
            lines.append("      },")
        lines.append("    },")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")
    text = "\n".join(report)
    if args.report:
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    print(f"\nwrote {OUT_PATH.relative_to(ROOT)}: {len(result)} maps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
