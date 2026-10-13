#!/usr/bin/env python3
"""Cut a GitHub release of Wilds of Kanto Revival from this checkout (replaces the old tag-triggered CI workflow,
same steps, in the same order).

    python3 scripts/release.py --notes-file notes.md              # vX.Y.Z from manifest.json
    python3 scripts/release.py --notes-file notes.md --dry-run    # every check and the build, no tag / publish
    python3 scripts/release.py --generate-notes                   # GitHub's auto notes instead of a file

The version is manifest.json's. A plain X.Y.Z is published as a normal release and marked Latest (the Mod
Manager offers it as an update). X.Y.Z-beta.N / X.Y.Z-rc.N is published as a PRE-RELEASE and never marked
Latest, so it is not an automatic update.

Steps (all must pass; nothing is tagged or published before the last one):
  1. preflight: tracked files clean, on main, HEAD pushed to origin/main, tag not used yet, gh available
  2. tools/validate_release_version.py <tag> (tag / manifest / main.lua / mod.card / CHANGELOG agree)
  3. tools/validate_option_labels.py, scripts/validate-manager-ascii.py
  4. the two harness tests (from .deps/gen1recomp, run scripts/bootstrap.sh once) and every tests/*_unit_test.lua
     with luajit
  5. tools/generate_runtime_sprite_sheets.py and the runtime-sheet check (manifest, 001-normal.png, >= 151 sheets)
  6. scripts/build-mod.py (bakes and validates the sprite atlases), then the ZIP root check and
     tools/validate_release_zip_hygiene.py
  7. tag vVERSION at HEAD, push the tag, gh release create on poooooby/wilds-of-kanto-gen-3 with
     dist/wilds-of-kanto-vVERSION.zip ("Wilds of Kanto Revival VERSION")

The build rewrites assets/wilds_generated/followsprites_runtime/manifest.json (statuses "cached"); tracked files the
build changed are restored afterwards so the checkout stays clean.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "poooooby/wilds-of-kanto-gen-3"  # always explicit: gh's default for this fork is the upstream repo
BRANCH = "main"
HARNESS = ROOT / ".deps" / "gen1recomp"
HARNESS_TESTS = ("tests/overworld_wild_spawns_test.lua", "tests/voxel_aggressive_compat_test.lua")
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-(?:beta|rc)\.\d+)?$")


def step(msg: str) -> None:
    print(f"\n==> {msg}", flush=True)


def fail(msg: str) -> None:
    print(f"\nRELEASE STOPPED: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], cwd: Path = ROOT, env: dict | None = None, quiet: bool = False) -> str:
    res = subprocess.run(cmd, cwd=str(cwd), env={**os.environ, **(env or {})},
                         capture_output=quiet, text=True)
    if res.returncode != 0:
        if quiet:
            sys.stderr.write((res.stdout or "") + (res.stderr or ""))
        fail(f"{' '.join(cmd)} exited {res.returncode}")
    return res.stdout if quiet else ""


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=str(ROOT), capture_output=True, text=True).stdout.strip()


def dirty_tracked() -> set[str]:
    return {line[3:] for line in git("status", "--porcelain", "--untracked-files=no").splitlines() if line}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    notes = ap.add_mutually_exclusive_group(required=True)
    notes.add_argument("--notes-file", type=Path, help="release notes (Markdown)")
    notes.add_argument("--generate-notes", action="store_true", help="GitHub's generated notes (the old CI default)")
    ap.add_argument("--dry-run", action="store_true", help="run every check and the build, but do not tag or publish")
    ap.add_argument("--allow-dirty", action="store_true",
                    help="with --dry-run: skip the clean / pushed / unused-tag preflight (try uncommitted work)")
    args = ap.parse_args()
    if args.allow_dirty and not args.dry_run:
        ap.error("--allow-dirty only works with --dry-run")

    version = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))["version"]
    if not VERSION_RE.match(version):
        fail(f"manifest version {version!r} is not X.Y.Z, X.Y.Z-beta.N or X.Y.Z-rc.N")
    tag = f"v{version}"
    prerelease = "-" in version
    zip_name = f"wilds-of-kanto-v{version}.zip"
    print(f"Wilds of Kanto Revival {version}: tag {tag}, "
          f"{'PRE-RELEASE (not an automatic update)' if prerelease else 'release, marked Latest'}"
          f"{' [dry run]' if args.dry_run else ''}")

    step("1. preflight")
    if args.notes_file and not args.notes_file.is_file():
        fail(f"notes file not found: {args.notes_file}")
    if shutil.which("gh") is None:
        fail("the GitHub CLI (gh) is not installed")
    if shutil.which("luajit") is None:
        fail("luajit is not on PATH (the tests run with it)")
    if not (HARNESS / "mods" / "wilds_of_kanto_gen3").exists():
        fail("the test harness is missing: run scripts/bootstrap.sh once")
    if args.allow_dirty:
        print("  --allow-dirty: clean / pushed / tag checks skipped (dry run)")
    else:
        if dirty_tracked():
            fail("tracked files have uncommitted changes:\n  " + "\n  ".join(sorted(dirty_tracked())))
        if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
            fail(f"not on {BRANCH}")
        subprocess.run(["git", "fetch", "-q", "origin", BRANCH, "--tags"], cwd=str(ROOT))
        if git("rev-parse", "HEAD") != git("rev-parse", f"origin/{BRANCH}"):
            fail(f"HEAD is not what origin/{BRANCH} has: push first")
        if git("tag", "--list", tag):
            fail(f"tag {tag} already exists")
        print(f"  clean, on {BRANCH} at {git('rev-parse', '--short', 'HEAD')} (pushed), {tag} unused")

    step("2. tag / manifest / main.lua / mod.card / CHANGELOG versions")
    run([sys.executable, "tools/validate_release_version.py", tag])

    step("3. option labels, manager ASCII metadata")
    run([sys.executable, "tools/validate_option_labels.py"])
    run([sys.executable, "scripts/validate-manager-ascii.py"])

    step("4. tests (luajit)")
    for t in HARNESS_TESTS:
        print(f"  harness {t}")
        run(["luajit", f"mods/wilds_of_kanto_gen3/{t}"], cwd=HARNESS, quiet=True)
    units = sorted(ROOT.glob("tests/*_unit_test.lua"))
    for t in units:
        run(["luajit", t.relative_to(ROOT).as_posix()], quiet=True)
    print(f"  {len(HARNESS_TESTS)} harness + {len(units)} unit tests passed")

    clean_before = dirty_tracked()
    try:
        step("5. runtime sprite sheets")
        run([sys.executable, "tools/generate_runtime_sprite_sheets.py"], quiet=True)
        runtime = ROOT / "assets" / "wilds_generated" / "followsprites_runtime"
        if not (runtime / "manifest.json").is_file() or not (runtime / "001-normal.png").is_file():
            fail("runtime sheets missing after generate_runtime_sprite_sheets.py")
        count = len(list(runtime.glob("*.png")))
        if count < 151:
            fail(f"only {count} runtime sheets")
        print(f"  runtime sheets: {count}")

        step("6. build + ZIP checks")
        run([sys.executable, "scripts/build-mod.py"])
        zip_path = ROOT / "dist" / zip_name
        if not zip_path.is_file():
            fail(f"build did not write dist/{zip_name}")
        with zipfile.ZipFile(zip_path) as zf:
            names = zf.namelist()
        for req in ("manifest.json", "main.lua", "mod.card", "options.lua", "LICENSE"):
            if req not in names:
                fail(f"ZIP missing {req} at archive root")
        if any(n.endswith("POKEMON 1.png") for n in names):
            fail("commercial POKEMON 1.png in ZIP")
        print(f"  ZIP root check ok ({len(names)} files, {zip_path.stat().st_size / 1e6:.1f} MB)")
        run([sys.executable, "tools/validate_release_zip_hygiene.py", f"dist/{zip_name}"])
    finally:
        # the build's own rewrites of tracked files (the runtime manifest's "cached" statuses)
        changed = sorted(dirty_tracked() - clean_before)
        if changed:
            subprocess.run(["git", "checkout", "--", *changed], cwd=str(ROOT))
            print(f"  restored {len(changed)} tracked file(s) the build rewrote: {', '.join(changed)}")

    if args.dry_run:
        print(f"\nDRY RUN OK: dist/{zip_name} is ready; nothing was tagged or published.")
        return 0

    step(f"7. tag {tag} and publish")
    run(["git", "tag", tag])
    run(["git", "push", "origin", tag])
    cmd = ["gh", "release", "create", tag, f"dist/{zip_name}", "--repo", REPO, "--verify-tag",
           "--title", f"Wilds of Kanto Revival {version}"]
    cmd += ["--notes-file", str(args.notes_file)] if args.notes_file else ["--generate-notes"]
    cmd += ["--prerelease", "--latest=false"] if prerelease else ["--latest"]
    run(cmd)
    print(f"\nPublished {tag}{' as a pre-release' if prerelease else ''}: "
          f"https://github.com/{REPO}/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
