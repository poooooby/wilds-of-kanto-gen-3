"""Unown letter forms for the sprite build tools.

Unown is one species (dex 201) with 26 letters. The HGSS/PokeMMO follow-sprite art has one sheet per letter:
    201-b-n.png        letter A      201-b-s.png        (shiny)
    201-b-n-01.png     letter B      201-b-s-01.png
    ...
    201-b-n-25.png     letter Z      201-b-s-25.png
(-26 and -27 are "!" and "?", which Gold does not have.)

The runtime pipeline is keyed by a numeric species id, so each letter B..Z is baked as an extra "form asset" with id
FORM_BASE + n (60001..60025) through the same generators as a species. lib/unown_forms.lua is the runtime side and must
agree on FORM_BASE / FORM_COUNT. The entries are synthesized here rather than written into the followsprites mapping
(tools/generate_followsprites_mapping.ps1 owns that file and would drop them on regeneration).
"""
from __future__ import annotations

import copy
from pathlib import Path

BASE_DEX = 201
FORM_BASE = 60000
FORM_COUNT = 25
SRC_REL = "assets/enhanced_overworld/followsprites"


def is_form_id(dex: int) -> bool:
    return FORM_BASE < int(dex) <= FORM_BASE + FORM_COUNT


def source_files(dex: int) -> dict[str, str]:
    """{'normal': '201-b-n-03.png', 'shiny': '201-b-s-03.png'} for a form id, {} otherwise."""
    if not is_form_id(dex):
        return {}
    n = int(dex) - FORM_BASE
    return {"normal": f"{BASE_DEX:03d}-b-n-{n:02d}.png", "shiny": f"{BASE_DEX:03d}-b-s-{n:02d}.png"}


def mapping_entries(species: dict, root: Path) -> dict[str, dict]:
    """Synthesized followsprites-mapping entries (same shape as species['201']) for every letter whose art exists."""
    base = species.get(str(BASE_DEX))
    if not isinstance(base, dict):
        return {}
    out: dict[str, dict] = {}
    for n in range(1, FORM_COUNT + 1):
        sid = FORM_BASE + n
        files = source_files(sid)
        entry = copy.deepcopy(base)
        entry["speciesId"] = sid
        ok = True
        for variant, fname in files.items():
            block = entry.get(variant)
            if not isinstance(block, dict) or not (root / SRC_REL / fname).is_file():
                ok = False
                break
            block["file"] = fname
            block["path"] = f"{SRC_REL}/{fname}"
        if ok:
            out[str(sid)] = entry
    return out
