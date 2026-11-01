#!/usr/bin/env python3
"""A design render this repository calls a design render is one the instrument refuses to attach.

## The defect this exists for

`DEF-054`. `attach-shots.py --apply` would file a render of the DESIGN OF RECORD as a surface's
build capture. The instrument already ships the guard: it drops any image with a directory part
named **exactly** `mock` before matching, `attach-shots.py:101` at `5934c38f` in the pinned
`vendor/test-campaign` 0.9.2 and byte-identical at `:101` in the machine's 0.17.0, and
`capture-lineage.py:150` at `5934c38f` applies the same rule to the same population.

This repository put its hi-dpi renders at `evidence/shots/mock-hidpi/`. That is not the name the
guard matches, so both tools walked the directory and offered its eleven files to a surface on the
strength of the filename. Measured on this tree at `5934c38f` with the pinned 0.9.2:
`attach-shots.py --apply --filename-only` attached **SURF-009** to
`evidence/shots/mock-hidpi/SURF-009.full.png` — SURF-009 being the one surface with a rendered
design of record and no build capture at all (`DEF-051`), so nothing outranked the render. The
other ten were saved by an accident of sort order that does not hold across platforms: `sorted()`
over `Path` objects case-folds on Windows, where `mock-hidpi/` sorts BEFORE `SURF-00N.build.png`
and loses the last-write-wins race; on the macOS tree where `DEF-054` was measured it sorts after
and wins eleven times.

So the fix was not upstream. It was the directory name, and it is in this repository: the renders
moved to `evidence/shots/mock/hidpi/`, inside the guard the instrument already ships. Re-measured
after the move: zero surfaces attach to a design render, and SURF-009 goes back to having no
capture, which is the true state `DEF-051` records rather than a hole papered over with a picture
of the design.

## What this gate holds, which is not the directory name

Renaming a directory is not a property. The property is that **the population this repository
calls a design render and the population the instrument refuses to attach are the same set**.
Those are two independent declarations that drifted apart once and had no reason not to drift
again: `planning/test-campaign/bin/capture-manifest.py` decides what is a design render (it is
excluded from the capture manifest for being one), and `attach-shots.py` decides what is a
candidate for a surface's `shot`. Nothing joined them.

R1  The vendored rule is the one modelled here. The gate reads `attach-shots.py` and
    `capture-lineage.py` out of `vendor/test-campaign/`, checks each file's SHA-256 against the
    digest recorded below, and checks the exclusion line is present verbatim. A pinned tree that
    moved is NOT COMPARED and exits 2 — a comparison that did not happen is not a comparison that
    agreed. The digests are of files this fleet may not edit, so this arm cannot be turned green
    from inside the repository; and because it is pinned to a digest rather than to `HEAD:`, it
    does not become a self-comparison the moment it is committed (`DEF-443`).

R2  Every `.png` under `evidence/shots/` that `capture-manifest.py` excludes as a render of the
    design is also excluded by the vendored rule. This is the arm that was red at `5934c38f`: the
    repository called eleven files design renders and the instrument called them candidates.

R3  Every `.png` the manifest carries with a `target` — a photograph of the build, pointed at a
    recorded address — is NOT excluded by the vendored rule. The opposite error: a build capture
    filed under `mock/` is dropped from the wall silently, and a surface with no picture and a
    surface whose picture was thrown away read identically.

R2 and R3 are the two directions of one equality, and neither alone would have caught this: the
directory could have been renamed to something excluded and something published moved in with it.

## What it does not do

It has no opinion on whether a render is a good render, on the matcher's choice among build
captures (`SURF-002` and `SURF-007` each have several and the last one sorted wins — that is not
this defect), or on `attach-shots`'s report printing surface ids rather than file paths, which is
the half of `DEF-054` that is genuinely upstream and is recorded in that row's `resolution`.

It reads `MOCK_DIRS` out of `capture-manifest.py` by import rather than by copying the set, so the
repository has one declaration of what a design render is and this gate is not a second one.

Exit codes: 0 the two populations agree · 1 they do not · 2 the gate could not read its input, or
the pinned instrument moved · 3 `--selftest` failed.

  python3 planning/mock-exclusion-gate.py
  python3 planning/mock-exclusion-gate.py --selftest
"""
from __future__ import annotations

import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "planning/test-campaign/evidence/shots"
MANIFEST = SHOTS / "captures.json"
VENDOR = ROOT / "vendor/test-campaign/skills/test-campaign/scripts"

# The instrument, pinned. `vendor/README.md` pins the tree by checksum so the gates re-run from a
# clone; these two digests pin the two files whose one line this gate models, so a re-vendor that
# changes the rule stops this gate rather than letting it keep asserting yesterday's rule.
PINNED = {
    "attach-shots.py": (
        "c6fc7f6504a24433e4f944de2af70e01d7132c1514c9b7bf9056bd23373e956f",
        '"mock" not in {part.lower() for part in p.relative_to(shots_dir).parts[:-1]}',
    ),
    "capture-lineage.py": (
        "3121b4d173c193fd9bb3bf50c69eab56d86a280bfefddcc2100d5975bf4be37f",
        '"mock" not in {q.lower() for q in p.relative_to(shots_dir).parts[:-1]}',
    ),
}

# The rule those two lines apply, written once. A path is excluded when any directory part of it,
# lowercased, is exactly `mock`. `parts[:-1]` is the directories; the filename is not a part.
EXCLUDED_PART = "mock"


def excluded_by_instrument(rel_parts: tuple[str, ...]) -> bool:
    """`rel_parts` is the path relative to the shots dir, filename included."""
    return EXCLUDED_PART in {p.lower() for p in rel_parts[:-1]}


def load_capture_manifest_module():
    """`MOCK_DIRS` is read from the script that owns it, not copied into this file."""
    src = ROOT / "planning/test-campaign/bin/capture-manifest.py"
    if not src.exists():
        return None
    spec = importlib.util.spec_from_file_location("_capture_manifest_for_gate", src)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        # The script exits when run as a program; the constants are bound before that.
        pass
    return mod


def r1_instrument_pin() -> tuple[list[str], list[str]]:
    findings, notes = [], []
    for name, (digest, line) in sorted(PINNED.items()):
        p = VENDOR / name
        if not p.exists():
            findings.append(f"R1 {name}: not present under vendor/test-campaign — NOT COMPARED")
            continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != digest:
            findings.append(
                f"R1 {name}: the pinned instrument moved. recorded {digest[:16]}…, "
                f"on disk {got[:16]}…. This gate models one line of that file; re-read it, "
                f"confirm the exclusion rule is still `{EXCLUDED_PART}` as a whole directory "
                f"part, and re-pin. Do not raise the digest without reading the line.")
            continue
        text = p.read_text(encoding="utf-8")
        if line not in text:
            findings.append(f"R1 {name}: digest matches but the exclusion line is absent — "
                            f"the pin and the rule disagree, which is a bug in this gate.")
            continue
        n = text.index(line)
        notes.append(f"R1 {name}: pinned at {digest[:16]}…, exclusion line at "
                     f"line {text[:n].count(chr(10)) + 1}, verbatim.")
    return findings, notes


def sweep(shots: Path, mock_dirs: set[str], manifest_rows: list[dict]) -> tuple[list[str], dict]:
    """R2 and R3 over one shots tree."""
    findings: list[str] = []
    by_path = {str(r.get("path", "")).replace("\\", "/"): r for r in manifest_rows}
    n_design = n_build = 0
    # Every path this sweep walks past is counted by the reason it walked past it. A coverage
    # claim rests on the denominator, and a reader that discards silently cannot state one --
    # `planning/reader-accounting.py`'s rule, and `input_accounting.Tally`'s shape.
    skipped: list[tuple[str, str]] = []

    for p in sorted(shots.rglob("*")):
        if p.suffix.lower() != ".png":
            skipped.append(("not a .png", p.relative_to(shots).as_posix()))
            continue
        rel = p.relative_to(shots)
        parts = rel.parts
        dirs = {q.lower() for q in parts[:-1]}
        repo_says_design = bool(mock_dirs & dirs)
        instrument_excludes = excluded_by_instrument(parts)

        if repo_says_design:
            n_design += 1
            if not instrument_excludes:
                findings.append(
                    f"R2 {rel.as_posix()}: this repository calls it a render of the DESIGN "
                    f"(`capture-manifest.py` MOCK_DIRS {sorted(mock_dirs)} matched "
                    f"{sorted(dirs & mock_dirs)}), and the instrument does not exclude it — no "
                    f"directory part is exactly `{EXCLUDED_PART}`. `attach-shots.py --apply` will "
                    f"offer this file to a surface on its filename. Move it under a `"
                    f"{EXCLUDED_PART}/` parent.")
            skipped.append(("a design render, counted by R2 and not a subject of R3",
                            rel.as_posix()))
            continue

        row = by_path.get((Path("evidence/shots") / rel).as_posix())
        if row is None:
            skipped.append(("a .png the manifest names no row for", rel.as_posix()))
        elif not row.get("target"):
            skipped.append(("a manifest row with no `target` — not a build capture, so R3 has "
                            "no subject", rel.as_posix()))
        if row is not None and row.get("target"):
            n_build += 1
            if instrument_excludes:
                findings.append(
                    f"R3 {rel.as_posix()}: the manifest gives this a `target`, so it is a "
                    f"photograph of the build pointed at a recorded address — and it sits under a "
                    f"`{EXCLUDED_PART}/` parent, where the instrument drops it before matching. "
                    f"It can never become any surface's shot, and nothing says so.")

    return findings, {"design": n_design, "build": n_build, "skipped": skipped}


def selftest() -> int:
    """Three planted trees. The clean one passes; each defect reddens its own rule."""
    ok = True
    with tempfile.TemporaryDirectory() as td:
        base = Path(td)

        def plant(rel: str) -> None:
            f = base / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(b"\x89PNG\r\n\x1a\n")

        # clean: a design render inside `mock/`, a build capture outside it
        plant("clean/mock/hidpi/SURF-001.full.png")
        plant("clean/SURF-001.build.png")
        rows = [{"path": "evidence/shots/SURF-001.build.png", "target": "app://mac/servers"}]
        f, counts = sweep(base / "clean", {"mock"}, rows)
        if f:
            print("SELFTEST FAIL — the clean tree produced findings:")
            for x in f:
                print(f"   {x}")
            ok = False
        elif (counts["design"], counts["build"]) != (1, 1):
            print(f"SELFTEST FAIL — clean tree counted {counts}, expected 1 design and 1 build")
            ok = False
        else:
            print("selftest R0 clean tree: no findings, 1 design render, 1 build capture ✓")

        # R2: the defect as it stood. A design render outside the instrument's exclusion.
        plant("r2/mock-hidpi/SURF-009.full.png")
        f, _ = sweep(base / "r2", {"mock", "mock-hidpi"}, [])
        if len(f) == 1 and f[0].startswith("R2 ") and "mock-hidpi" in f[0]:
            print("selftest R2: a design render at `mock-hidpi/` is refused ✓")
        else:
            print(f"SELFTEST FAIL — R2 did not fire on the planted defect: {f}")
            ok = False

        # R3: the opposite error. A build capture buried under `mock/`.
        plant("r3/mock/SURF-002.build.png")
        rows = [{"path": "evidence/shots/mock/SURF-002.build.png", "target": "app://mac/servers"}]
        f, _ = sweep(base / "r3", set(), rows)
        if len(f) == 1 and f[0].startswith("R3 "):
            print("selftest R3: a build capture under `mock/` is refused ✓")
        else:
            print(f"SELFTEST FAIL — R3 did not fire on the planted defect: {f}")
            ok = False

    return 0 if ok else 3


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()

    import json

    if not SHOTS.is_dir():
        print(f"{SHOTS} is not a directory — the gate could not read its input.")
        return 2
    try:
        rows = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"{MANIFEST}: {e} — the gate could not read its input.")
        return 2

    mod = load_capture_manifest_module()
    mock_dirs = getattr(mod, "MOCK_DIRS", None) if mod else None
    if not isinstance(mock_dirs, set) or not mock_dirs:
        print("planning/test-campaign/bin/capture-manifest.py exposes no MOCK_DIRS set — this "
              "gate reads the repository's own declaration of what a design render is and will "
              "not substitute a copy of it.")
        return 2

    pin_findings, pin_notes = r1_instrument_pin()
    for n in pin_notes:
        print(n)
    if pin_findings:
        for x in pin_findings:
            print(f"  {x}")
        print("\nNOT COMPARED. The rule this gate models lives in a file it cannot read as pinned.")
        return 2

    findings, counts = sweep(SHOTS, {d.lower() for d in mock_dirs}, rows)
    print(f"R2/R3 sweep: {counts['design']} design render(s) under "
          f"{sorted(mock_dirs)}/, {counts['build']} build capture(s) with a recorded target, "
          f"over {SHOTS.relative_to(ROOT).as_posix()}.")
    by_reason: dict[str, int] = {}
    for reason, _name in counts["skipped"]:
        by_reason[reason] = by_reason.get(reason, 0) + 1
    for reason, n in sorted(by_reason.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  walked past {n:>3}  {reason}")

    # The zero is printed rather than implied. This is an absence sweep, and an absence sweep
    # that says nothing when it finds nothing is indistinguishable from one that did not run.
    r2 = sum(1 for x in findings if x.startswith("R2 "))
    r3 = sum(1 for x in findings if x.startswith("R3 "))
    print(f"R2 a design render the instrument would still walk: {r2} · "
          f"R3 a build capture buried where it would be dropped: {r3}")

    if findings:
        print(f"\n{len(findings)} finding(s):")
        for x in findings:
            print(f"  {x}")
        return 1

    if len(findings) == 0:
        print("The set this repository calls a design render and the set the instrument "
              "refuses to attach are the same set — no instance of either absence over the "
              f"{counts['design'] + counts['build']} .png(s) the two rules had a subject in.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
