#!/usr/bin/env python3
"""Generate lib/gen9_encounters_data.lua: the modern Kanto encounter overlay data.

Inputs (all stay OUTSIDE the repo; only the generated Lua is committed):
  --encounters   Pokemon Essentials PBS-style encounters.txt (Spanish Kanto-layout fangame table)
  --national-dex national_dex mod's data/species/generated/national.lua (species keys + dex)
  --engine       optional Gen1Recomp checkout; when given, the run also reports which generated
                 buckets are inert because the vanilla Gen 1 table has no such bucket

Only the modern blocks are used (Land / Cave / Water / SuperRod); the parallel *Classic pools are
ignored. Location -> engine map ids come from tools/data/gen9_location_map.json.

Quantization matches the engine's own tables:
  * grass/cave/water -> one slot per (species, level) with a custom cumulative `buckets` ladder
    (Encounter.roll and EncounterPick honor a per-bucket `buckets` of any length ending in 256). Each
    source row's percentage is spread evenly over every level in its min-max range, in whole 256ths.
  * Super Rod -> at most 4 entries picked uniformly (OverworldController rollFishingGroup rolls a
    2-bit index), so duplicates encode weight and the group size sets the bite odds.

This is an independent implementation of that quantization; no Kanto Reforged code or data is used.

Run: python3 tools/generate_gen9_encounters.py --encounters <encounters.txt> \
        --national-dex <.../national.lua> [--engine <gen1recomp checkout>]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCATION_MAP = ROOT / "tools/data/gen9_location_map.json"
OUT_PATH = ROOT / "lib/gen9_encounters_data.lua"

# The engine rolls rng(0,255), so a slot's odds are whole 256ths: bucket thresholds are integers
# ending in 256 and every table's slot widths sum to exactly this.
UNITS = 256
SUPER_ROD_SLOTS = 4
PLACEHOLDER_WATER_LEVELS = (50, 51)

# Essentials lists a species' regional forms as _1, _2, ... in generation order.
REGIONAL_ORDER = ["ALOLA", "GALAR", "HISUI", "PALDEA"]

# Non-regional (or otherwise not derivable) form tokens, confirmed against
# Gen 9 Pack/PBS/pokemon_forms_Gen_9_Pack.txt in ReferenceGen1-3.
FORM_OVERRIDES = {
    ("BASCULIN", 2): "BASCULIN_WHITE_STRIPED",
    ("BASCULIN", 3): "BASCULIN_WHITE_STRIPED",
    ("TATSUGIRI", 1): "TATSUGIRI_DROOPY",
    ("TATSUGIRI", 2): "TATSUGIRI_STRETCHY",
    ("SQUAWKABILLY", 1): "SQUAWKABILLY_BLUE_PLUMAGE",
    ("TOXTRICITY", 1): "TOXTRICITY_LOW_KEY",
    ("DARMANITAN", 2): "DARMANITAN_GALAR_STANDARD",
    ("WOOPER", 1): "WOOPER_PALDEA",
}
TOKEN_OVERRIDES = {"NIDORANFE": "NIDORAN_F", "NIDORANMA": "NIDORAN_M"}

BLOCK_KIND = {"Land": "grass", "Cave": "grass", "Water": "water", "SuperRod": "superRod"}


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


# --------------------------------------------------------------------- encounters.txt

def parse_encounters(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8-sig")
    sections: list[dict] = []
    cur = None
    blk = None
    for raw in text.split("\n"):
        line = raw.rstrip("\r")
        m = re.match(r"^\[(\d+)\]\s*#\s*(.*)$", line)
        if m:
            cur = {"id": m.group(1), "name": m.group(2).strip(), "blocks": {}}
            sections.append(cur)
            blk = None
            continue
        if not line.strip() or line.startswith("#"):
            continue
        row = re.match(r"^\s+(\d+),([A-Za-z0-9_]+),(\d+),(\d+)\s*$", line)
        if row and cur is not None and blk is not None:
            cur["blocks"][blk].append(
                (int(row.group(1)), row.group(2), int(row.group(3)), int(row.group(4))))
            continue
        head = re.match(r"^(\w+)(?:,(\d+))?\s*$", line)
        if head and cur is not None and not line[0].isspace():
            blk = head.group(1)
            cur["blocks"].setdefault(blk, [])
            continue
        die(f"unparseable line in {path.name}: {line!r}")
    return sections


# --------------------------------------------------------------------- national_dex

def parse_national_dex(path: Path) -> dict[str, dict]:
    """key -> {dex, form, base}.

    `register` records carry an explicit `dex`. ROM species live in `patch` (no dex field); the
    patch records are emitted in dex order (BULBASAUR=1 ... MEW=151), so position is the dex. The
    NDEX_nnnn text ids in that file are NOT dex numbers (e.g. PARASECT is NDEX_0015), so they are
    deliberately not used.
    """
    lines = path.read_text(encoding="utf-8").split("\n")
    out: dict[str, dict] = {}
    section = None
    rec = None
    patch_pos = 0
    for ln in lines:
        m = re.match(r"^  (patch|register|text) = \{", ln)
        if m:
            section = m.group(1)
            rec = None
            continue
        if section not in ("patch", "register"):
            continue
        m = re.match(r"^    ([A-Z0-9_]+) = \{$", ln)
        if m:
            rec = {"dex": None, "form": None, "base": None}
            if section == "patch":
                patch_pos += 1
                rec["dex"] = patch_pos
            out[m.group(1)] = rec
            continue
        if rec is None:
            continue
        m = re.match(r"^\s+dex = (\d+),", ln)
        if m and rec["dex"] is None:
            rec["dex"] = int(m.group(1))
        m = re.match(r'^\s+form = "([A-Z0-9_]+)",', ln)
        if m:
            rec["form"] = m.group(1)
        m = re.match(r'^\s+baseSpecies = "([A-Z0-9_]+)",', ln)
        if m:
            rec["base"] = m.group(1)
    missing = [k for k, v in out.items() if v["dex"] is None]
    if missing:
        die(f"national_dex records with no dex: {missing[:5]}")
    return out


class SpeciesResolver:
    def __init__(self, nat: dict[str, dict]):
        self.nat = nat
        self.stripped = {}
        for k in nat:
            self.stripped.setdefault(k.replace("_", ""), k)
        self.form_table: dict[str, str] = {}

    def base(self, token: str) -> str | None:
        t = token.upper()
        if t in TOKEN_OVERRIDES:
            t = TOKEN_OVERRIDES[t]
        if t in self.nat:
            return t
        return self.stripped.get(t.replace("_", ""))

    def resolve(self, token: str) -> str:
        m = re.match(r"^(.+)_(\d+)$", token)
        if not m:
            key = self.base(token)
            if key is None:
                die(f"unresolvable species token {token!r}")
            return key
        base_tok, n = m.group(1).upper(), int(m.group(2))
        override = FORM_OVERRIDES.get((base_tok, n))
        if override:
            key = override
        else:
            base_key = self.base(base_tok)
            if base_key is None:
                die(f"unresolvable form base {token!r}")
            cands = [k for k, v in self.nat.items()
                     if v["base"] == base_key and v["form"] in REGIONAL_ORDER]
            cands.sort(key=lambda k: REGIONAL_ORDER.index(self.nat[k]["form"]))
            if n > len(cands):
                die(f"form token {token!r}: only {len(cands)} regional form(s) of {base_key}: {cands}")
            key = cands[n - 1]
        if key not in self.nat:
            die(f"form token {token!r} resolved to {key!r}, which national_dex does not define")
        self.form_table[token] = key
        return key


# --------------------------------------------------------------------- engine (optional)

def load_vanilla(engine: Path) -> dict:
    enc = engine / "red/data/generated/encounters.lua"
    fld = engine / "red/data/generated/field.lua"
    buckets: dict[str, set] = {}
    cur = None
    for ln in enc.read_text(encoding="utf-8").split("\n"):
        m = re.match(r"^  ([A-Z0-9_]+) = \{$", ln)
        if m:
            cur = m.group(1)
            buckets[cur] = set()
            continue
        m = re.match(r"^    (grass|water) = \{$", ln)
        if m and cur:
            buckets[cur].add(m.group(1))
    rod: set[str] = set()
    txt = fld.read_text(encoding="utf-8")
    i = txt.index("  superRod = {")
    depth = 0
    end = i
    for end in range(i, len(txt)):
        if txt[end] == "{":
            depth += 1
        elif txt[end] == "}":
            depth -= 1
            if depth == 0:
                break
    rod.update(re.findall(r"\n    ([A-Z0-9_]+) = \{", txt[i:end + 1]))
    return {"buckets": buckets, "superRod": rod}


# --------------------------------------------------------------------- quantization

def normalize(rows: list[tuple[str, float, float, float]]) -> list[tuple[str, float, float]]:
    """rows: (species, weight, midLevel, _) -> merged per species as (species, weight, level)."""
    acc: "OrderedDict[str, list]" = OrderedDict()
    for sp, w, mid, _ in rows:
        a = acc.setdefault(sp, [0.0, 0.0])
        a[0] += w
        a[1] += w * mid
    total = sum(v[0] for v in acc.values()) or 1.0
    return [(sp, v[0] / total, v[1] / v[0]) for sp, v in acc.items()]


def round_half_up(x: float) -> int:
    return int(x + 0.5)


def evenly_spaced(lo: int, hi: int, k: int) -> list[int]:
    """k levels spread evenly across lo..hi inclusive (k >= 1)."""
    if k <= 1 or lo == hi:
        return [(lo + hi) // 2]
    out = []
    for i in range(k):
        lv = int(round(lo + i * (hi - lo) / (k - 1)))
        if lv not in out:
            out.append(lv)
    return out


def spread_rows(per_sec_rows: list[list[tuple[str, float, int, int]]], report: list[str]):
    """per_sec_rows: one list per merged section of (species, fraction, lo, hi).

    Each row's share is spread EVENLY over every integer level in lo..hi (Essentials semantics: a
    row's min,max is a uniform level in the range), so "20% Roggenrola 15-17" becomes 15/16/17 at
    ~6.7% each. Duplicate rows and merged sections accumulate onto the same (species, level) key.
    Sections carry equal weight. Returns OrderedDict[(species, level)] -> weight (sums to 1).
    """
    n_sec = len(per_sec_rows)
    out: "OrderedDict[tuple[str, int], float]" = OrderedDict()
    for rows in per_sec_rows:
        for sp, frac, lo, hi in rows:
            row_units = frac / n_sec * UNITS
            levels = list(range(lo, hi + 1))
            if row_units / len(levels) < 1.0:
                # A per-level slice would be under one 256th: coarsen to evenly spaced levels.
                k = max(1, min(len(levels), int(row_units)))
                levels = evenly_spaced(lo, hi, k)
                report.append(f"    coarsened {sp} {lo}-{hi} to {len(levels)} level(s) "
                              f"({row_units:.1f}/256 for the whole row)")
            share = frac / n_sec / len(levels)
            for lv in levels:
                out[(sp, lv)] = out.get((sp, lv), 0.0) + share
    return out


def to_units(weights: "OrderedDict[tuple[str, int], float]") -> dict[tuple[str, int], int]:
    """Integer widths (out of UNITS) summing to exactly UNITS, every (species, level) >= 1 unit.

    Two-stage largest-remainder rounding: species totals first (so a species' overall odds stay
    within ~half a unit of its source percentage), then each species' units are split across its
    levels in proportion to their weights.
    """
    if len(weights) > UNITS:
        die(f"{len(weights)} (species, level) pairs cannot fit in {UNITS} slots")
    by_sp: "OrderedDict[str, OrderedDict[int, float]]" = OrderedDict()
    for (sp, lv), w in weights.items():
        by_sp.setdefault(sp, OrderedDict())[lv] = w
    total = sum(weights.values())
    exact = {sp: sum(lv.values()) / total * UNITS for sp, lv in by_sp.items()}
    floor_of = {sp: len(lv) for sp, lv in by_sp.items()}
    alloc = {sp: max(floor_of[sp], int(exact[sp])) for sp in by_sp}
    diff = UNITS - sum(alloc.values())
    while diff > 0:
        sp = max(by_sp, key=lambda s: exact[s] - alloc[s])
        alloc[sp] += 1
        diff -= 1
    while diff < 0:
        sp = max((s for s in by_sp if alloc[s] > floor_of[s]), key=lambda s: alloc[s] - exact[s])
        alloc[sp] -= 1
        diff += 1
    units: dict[tuple[str, int], int] = {}
    for sp, levels in by_sp.items():
        tot = sum(levels.values())
        e = {lv: w / tot * alloc[sp] for lv, w in levels.items()}
        u = {lv: max(1, int(e[lv])) for lv in levels}
        d = alloc[sp] - sum(u.values())
        while d > 0:
            lv = max(levels, key=lambda l: e[l] - u[l])
            u[lv] += 1
            d -= 1
        while d < 0:
            lv = max((l for l in levels if u[l] > 1), key=lambda l: u[l] - e[l])
            u[lv] -= 1
            d += 1
        for lv in levels:
            units[(sp, lv)] = u[lv]
    return units


def order_pairs(units: dict[tuple[str, int], int]) -> list[tuple[str, int]]:
    """Heaviest species first, levels ascending within a species (odds don't depend on order)."""
    by_species: dict[str, int] = {}
    for (sp, _lv), u in units.items():
        by_species[sp] = by_species.get(sp, 0) + u
    return sorted(units, key=lambda k: (-by_species[k[0]], k[0], k[1]))


def ladder_errors(weights, units) -> tuple[float, float]:
    """(worst per-(species,level) error, worst per-species error) in percentage points."""
    total = sum(weights.values())
    worst_pair = max(abs(weights[k] / total * 100 - units[k] / UNITS * 100) for k in units)
    tgt: dict[str, float] = {}
    got: dict[str, float] = {}
    for (sp, _lv), w in weights.items():
        tgt[sp] = tgt.get(sp, 0.0) + w / total * 100
    for (sp, _lv), u in units.items():
        got[sp] = got.get(sp, 0.0) + u / UNITS * 100
    return worst_pair, max(abs(tgt[s] - got[s]) for s in tgt)


def allocate_rod(rows: list[tuple[str, float, float]]):
    rows = sorted(rows, key=lambda r: -r[1])
    dropped = [r[0] for r in rows[SUPER_ROD_SLOTS:]]
    rows = rows[:SUPER_ROD_SLOTS]
    total = sum(r[1] for r in rows) or 1.0
    exact = [r[1] / total * SUPER_ROD_SLOTS for r in rows]
    counts = [int(e) for e in exact]
    rem = SUPER_ROD_SLOTS - sum(counts)
    for i in sorted(range(len(rows)), key=lambda i: -(exact[i] - counts[i]))[:rem]:
        counts[i] += 1
    for i in range(len(counts)):           # every kept species keeps one entry
        if counts[i] == 0:
            j = max(range(len(counts)), key=lambda k: counts[k])
            counts[j] -= 1
            counts[i] += 1
    entries = []
    for (sp, _w, lv), c in zip(rows, counts):
        entries.extend([(sp, round_half_up(lv))] * c)
    return entries, dropped


# --------------------------------------------------------------------- build

def section_has_kind(sec: dict, kind: str) -> bool:
    return any(k == kind and sec["blocks"].get(b) for b, k in BLOCK_KIND.items())


def section_kind_rows(sec: dict, kind: str, report: list[str]):
    """Rows for one engine kind from one section, with the Water placeholder-level fix."""
    rows = []
    for blk, k in BLOCK_KIND.items():
        if k == kind and sec["blocks"].get(blk):
            rows = sec["blocks"][blk]
    if not rows:
        return []
    out = []
    sub = None
    if kind == "water" and all((lo, hi) == PLACEHOLDER_WATER_LEVELS for _, _, lo, hi in rows):
        pools = sec["blocks"].get("SuperRod") or sec["blocks"].get("Land") or sec["blocks"].get("Cave") or []
        if pools:
            sub = (min(lo for _, _, lo, _ in pools), max(hi for _, _, _, hi in pools))
            report.append(f"    water levels {PLACEHOLDER_WATER_LEVELS} are a placeholder in [{sec['id']}] "
                          f"{sec['name']}; substituted {sub[0]}-{sub[1]}")
    for pct, tok, lo, hi in rows:
        if sub:
            lo, hi = sub
        out.append((pct, tok, lo, hi))
    return out


def build(args) -> None:
    sections = parse_encounters(Path(args.encounters))
    by_id = {s["id"]: s for s in sections}
    nat = parse_national_dex(Path(args.national_dex))
    resolver = SpeciesResolver(nat)
    locmap = json.loads(LOCATION_MAP.read_text(encoding="utf-8"))
    vanilla = load_vanilla(Path(args.engine)) if args.engine else None

    report: list[str] = []
    result: "OrderedDict[str, dict]" = OrderedDict()
    used_sections: set[str] = set()

    for engine_id, sec_ids in sorted(locmap["maps"].items()):
        if vanilla and engine_id not in vanilla["buckets"] and engine_id not in vanilla["superRod"]:
            die(f"location map: {engine_id} is not an engine encounter/fishing map")
        secs = []
        for sid in sec_ids:
            if sid not in by_id:
                die(f"location map: section [{sid}] not found for {engine_id}")
            secs.append(by_id[sid])
            used_sections.add(sid)
        report.append(f"{engine_id}  <-  " + ", ".join(f"[{s['id']}] {s['name']}" for s in secs))
        entry: dict = {}
        for kind in ("grass", "water", "superRod"):
            if vanilla:
                if kind == "superRod":
                    inert = engine_id not in vanilla["superRod"]
                else:
                    inert = kind not in vanilla["buckets"].get(engine_id, set())
                if inert:
                    have = any(section_has_kind(sec, kind) for sec in secs)
                    if have:
                        report.append(f"  {kind}: skipped (vanilla has no {kind} bucket/group here)")
                    continue
            per_sec_rows = []
            for sec in secs:
                rows = section_kind_rows(sec, kind, report)
                if not rows:
                    continue
                total = float(sum(p for p, _, _, _ in rows)) or 1.0
                per_sec_rows.append([(resolver.resolve(tok), p / total, lo, hi)
                                     for p, tok, lo, hi in rows])
            if not per_sec_rows:
                continue
            if kind == "superRod":
                merged = normalize([(sp, frac, (lo + hi) / 2.0, None)
                                    for rows in per_sec_rows for sp, frac, lo, hi in rows])
                slots, dropped = allocate_rod(merged)
                entry[kind] = [{"level": lv, "species": sp, "dex": nat[sp]["dex"]} for sp, lv in slots]
                report.append(f"  {kind}: {len(slots)} entries")
                if dropped:
                    report.append(f"    dropped (no entry room): {', '.join(dropped)}")
                continue
            weights = spread_rows(per_sec_rows, report)
            units = to_units(weights)
            thresholds: list[int] = []
            slots = []
            cum = 0
            for sp, lv in order_pairs(units):
                cum += units[(sp, lv)]
                thresholds.append(cum)
                slots.append({"level": lv, "species": sp, "dex": nat[sp]["dex"],
                              "pct": round(units[(sp, lv)] / UNITS * 100, 2)})
            assert cum == UNITS and len(thresholds) == len(slots)
            entry[kind] = {"buckets": thresholds, "slots": slots}
            worst_pair, worst_species = ladder_errors(weights, units)
            report.append(f"  {kind}: {len(slots)} slots, {len({sp for sp, _ in units})} species; "
                          f"max error {worst_pair:.2f} pts per level / {worst_species:.2f} pts per species")
        if entry:
            result[engine_id] = entry

    ignored = [s for s in sections if s["id"] not in used_sections]
    report.append("")
    report.append(f"Sections not used ({len(ignored)}): " +
                  "; ".join(f"[{s['id']}] {s['name']}" for s in ignored))
    report.append("")
    report.append("Form tokens resolved:")
    for tok, key in sorted(resolver.form_table.items()):
        report.append(f"  {tok:20} -> {key}")

    lines = [
        "-- AUTO-GENERATED by tools/generate_gen9_encounters.py -- do not hand-edit.",
        "-- Modern Kanto encounter overlay: engine map id -> grass / water / superRod.",
        "-- grass & water: { buckets = cumulative thresholds out of 256 (ending 256), slots = one",
        "--   per (species, level), same length as buckets }. A slot's odds are its threshold minus",
        "--   the previous one; `pct` is that as a percentage (informational). Each source row's",
        "--   percentage is spread evenly over every level in its min-max range.",
        "-- superRod: <= 4 entries picked uniformly by the engine (duplicates encode weight).",
        "-- `dex` is the national_dex record's dex (1..1025, or 30001+ for forms), only used by",
        "-- tests/diagnostics; runtime gating is per species key.",
        "return {",
        "  version = 2,",
        "  maps = {",
    ]
    for engine_id, entry in result.items():
        lines.append(f"    {engine_id} = {{")
        for kind in ("grass", "water", "superRod"):
            if kind not in entry:
                continue
            lines.append(f"      {kind} = {{")
            if kind == "superRod":
                for sl in entry[kind]:
                    lines.append(f'        {{ level = {sl["level"]}, species = "{sl["species"]}", '
                                 f'dex = {sl["dex"]} }},')
            else:
                bk = entry[kind]["buckets"]
                lines.append("        buckets = { " + ", ".join(str(b) for b in bk) + " },")
                lines.append("        slots = {")
                for sl in entry[kind]["slots"]:
                    lines.append(f'          {{ level = {sl["level"]}, species = "{sl["species"]}", '
                                 f'dex = {sl["dex"]}, pct = {sl["pct"]} }},')
                lines.append("        },")
            lines.append("      },")
        lines.append("    },")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")
    text = "\n".join(report)
    if args.report:
        Path(args.report).write_text(text + "\n", encoding="utf-8")
    print(text)
    print(f"\nwrote {OUT_PATH.relative_to(ROOT)}: {len(result)} maps")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--encounters", required=True)
    ap.add_argument("--national-dex", required=True)
    ap.add_argument("--engine", default=None)
    ap.add_argument("--report", default=None, help="also write the review report to this path")
    build(ap.parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
