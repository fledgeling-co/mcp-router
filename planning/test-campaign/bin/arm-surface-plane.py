#!/usr/bin/env python3
"""The arm for `plane` — plant a misfiled member on a surface of each plane, and watch it redden.

2026-11-02: the two former declared-silence plants below now redden because a new member needs
a typed production-source binding. The historical explanation records the old limitation. A
separate paired control proves that a genuinely declared dotted UI label passes the new rule
while the old name-shape rule refuses it. Source bindings add no case actuations.

WHAT THIS IS FOR
----------------
DEF-131: until 2026-09-03 `bin/control-census.py` decided which field a declared member belonged
in from the SHAPE OF ITS NAME, and the shape it recognised was a PascalCase `Foo.Bar`. The defect
was measured by plant and the measurement is the reason a better regex was not the fix: moving
SURF-045 and SURF-046 back from `operations` to `controls` reddened with four findings, and moving
SURF-047 back reddened with NONE, because `MakeAppx pack` and `winget validate` are
indistinguishable from a button somebody labelled that.

So this file runs the SAME plants against BOTH censuses — the one this branch replaced, read out
of git, and the one it installed — and requires the pair to differ in the specific way the fix
claims. A plant the new rule catches and the old rule missed is the whole of the evidence; a plant
both catch would prove nothing about this change, and a plant neither catches would mean the
change did not happen.

Every plant is made on a COPY of `planning/test-campaign/` under a scratch root, never on the
registry itself, and the copy is discarded. The census resolves its own paths from
`Path(__file__).resolve().parents[3]`, so a copy laid out as `<scratch>/planning/test-campaign/`
reads the planted registry and nothing else.

THE THREE READINGS, and the middle one is the one people skip
--------------------------------------------------------------
    BASELINE   the registry as committed, both censuses: exit 0, no findings. An arm that has
               never been seen silent is an arm that might be shouting at everything.
    EFFECT     each plant, run alone: the new census reports exactly the expected finding.
    SILENCE    the plant reverted, re-run: exit 0 again. This is what separates a rule from a
               file that has started failing for its own reasons.

TWO PLANTS ARE EXPECTED TO STAY SILENT, and they are declared rather than omitted, because an
arm that only ever plants what its subject catches is a demonstration and not a measurement.

  * A surface declared `plane: mixed` carries both halves over one subject, so neither field is
    wrong on it and nothing here can decide the question for those rows. The census prints them by
    name as UNDEFENDED. This arm plants into one anyway and requires the silence.
  * A PascalCase `Foo.Bar` declared under `controls` on a GLASS surface was refused by the census
    this branch replaced and is not refused by this one — coverage given up when the shape rule
    was deleted, filed as DEF-420. This arm plants it and requires the silence HERE and the red on
    the previous census, so the loss stays measured in both directions.

If a later change starts reporting either, this arm fails and says so, and the census's header,
DEF-131's resolution and DEF-420 have to be rewritten before the expectation is edited.

THE WRITER IS EXERCISED TOO, and it is the other half of the schema change. `bin/design-controls.py`
writes `plane: "glass"` beside the control list `--set-controls` writes, and refuses a surface the
registry already calls something else. It cannot be run end to end here — it drives a browser
through `obscura`, which is a macOS binary — so its registry write is imported and called directly
against a synthetic harvest: one glass surface, which it must write, and one headless surface,
which it must refuse and leave untouched.

EXITS
-----
    0  every reading matched, including the declared silence
    1  a reading did not match — printed as expected-vs-observed, per plant
    2  the arm could not run at all (git could not produce the previous census)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning" / "test-campaign"

# The commit whose census this branch replaced. Read from git rather than kept as a vendored copy:
# a copy would be a second thing to keep in step, and the point of the comparison is that the file
# on the other side is the one that was actually shipped.
#
# PINNED TO A SHA, AND IT HAS TO BE. This read `HEAD:` until Wave C integration, which is correct
# for exactly as long as the new census is UNCOMMITTED - the state the arm was written and watched
# in. The moment the commit that earns it lands, `HEAD:` resolves to the NEW census and the arm
# compares the file against itself: all six EFFECT plants read red on both sides, the three that
# were the whole point (DEF-131's exhibit among them) stop being differences, and the arm exits 1
# reporting the collapse rather than a defect. An instrument that measures its subject only until
# its subject ships is the failure this campaign is built against, and it was found by running the
# arm on the merged tree rather than by reading it.
#
# 42aef112 is the merge base of Wave C - the last commit holding `_OPERATION_SHAPE`, the string
# rule DEF-131 deleted. Moving this pin means declaring a new "before", which is a decision with a
# consequence for what the DECLARED SILENCE arms mean, so it is written here rather than tracked.
PREVIOUS = "42aef112:planning/test-campaign/bin/control-census.py"


def plant_glass_declares_operations(inv: dict) -> None:
    """A call a lane makes, filed on a board of buttons."""
    surface(inv, "SURF-002")["operations"] = ["LogonTaskSupervisor.Register"]


def plant_headless_declares_control(inv: dict) -> None:
    """An ordinary control name on a plane with no glass — invisible to any string rule."""
    surface(inv, "SURF-045")["controls"] = ["Reset history"]


def plant_def131_exhibit(inv: dict) -> None:
    """DEF-131's own measurement: SURF-047's four operations moved back under `controls`."""
    s = surface(inv, "SURF-047")
    s["controls"] = s.pop("operations")
    s["controlsSource"] = s.pop("operationsSource")


def plant_undetermined_with_members(inv: dict) -> None:
    """A surface that declares 3 controls while saying nobody has worked out its plane."""
    surface(inv, "SURF-003")["plane"] = "undetermined"


def plant_no_plane(inv: dict) -> None:
    """The default that does not exist: a surface declaring members and no plane at all."""
    surface(inv, "SURF-001").pop("plane")


def plant_mixed_without_note(inv: dict) -> None:
    """`mixed` switches the check off for a row, so it costs a written statement."""
    surface(inv, "SURF-046").pop("planeNote")


def plant_mixed_declares_control(inv: dict) -> None:
    """A DECLARED SILENCE. Both fields are legitimate on a mixed row; nothing can decide."""
    surface(inv, "SURF-046")["controls"] = ["Reset history"]


def plant_api_name_on_glass(inv: dict) -> None:
    """THE COVERAGE THIS CHANGE GAVE UP, planted so the loss is measured and not merely admitted.

    The rule this branch deleted refused a PascalCase `Foo.Bar` under `controls` anywhere. On a
    surface now declared `glass` the plane says the member is a control and the shape rule said
    it is not, and keeping both would be exactly the two-rules-disagreeing state DEF-131's `next`
    ruled out. So the shape rule went, and this plant is silent where it used to be red. DEF-420.
    """
    s = surface(inv, "SURF-002")
    s["controls"] = s["controls"] + ["LogonTaskSupervisor.Register"]


# (name, plant, expected finding(s) from THIS branch's census, expected exit from the previous
# census, a string that must NOT appear when the expected finding list is empty)
PLANTS = [
    ("glass surface declares an operation", plant_glass_declares_operations,
     ["SURF-002 is declared `plane`: glass and declares 1 member(s) under `operations`"], 0, ""),
    ("headless surface declares a control", plant_headless_declares_control,
     ["SURF-045 is declared `plane`: headless and declares 1 member(s) under `controls`"], 0, ""),
    ("DEF-131's exhibit — SURF-047's four operations moved back under `controls`",
     plant_def131_exhibit,
     ["SURF-047 is declared `plane`: headless and declares 4 member(s) under `controls`"], 0, ""),
    ("undetermined plane with members declared", plant_undetermined_with_members,
     ["SURF-003 is declared `plane`: undetermined and declares 3 member(s) under `controls`"],
     0, ""),
    ("no plane at all", plant_no_plane,
     ["SURF-001 declares `plane`: None, which is not one of"], 0, ""),
    ("mixed with no planeNote", plant_mixed_without_note,
     ["SURF-046 is declared `plane`: mixed and carries no `planeNote`"], 0, ""),
    ("mixed surface adds a control without a typed UI binding",
     plant_mixed_declares_control,
     ['["SURF-046","control","Reset history"]: new member has no typed source binding'], 0, ""),
    ("API-call name under controls has no typed UI binding — DEF-420",
     plant_api_name_on_glass,
     ['["SURF-002","control","LogonTaskSupervisor.Register"]: new member has no typed source binding'], 1, ""),
]


def surface(inv: dict, sid: str) -> dict:
    return next(s for s in inv["surface"] if s["id"] == sid)


def run(census: Path) -> tuple[int, str]:
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    r = subprocess.run([sys.executable, str(census)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=env, timeout=300)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def stage(scratch: Path) -> tuple[Path, Path, Path]:
    """A scratch copy of the campaign, plus the previous census beside the current one."""
    camp = scratch / "planning" / "test-campaign"
    (camp / "bin").mkdir(parents=True)
    for name in ("inventory.json", "cases.json", "member-source-baseline.json", "member-source-bindings.json"):
        shutil.copy2(CAMPAIGN / name, camp / name)
    sys.path.insert(0, str(CAMPAIGN / 'bin'))
    from member_source_provenance import audit_files
    source_report = audit_files(ROOT, CAMPAIGN)
    if source_report['findings']:
        raise ValueError('cannot stage invalid source bindings: ' + str(source_report['findings']))
    shutil.copy2(CAMPAIGN / 'bin/member_source_provenance.py', camp / 'bin/member_source_provenance.py')
    bindings = json.loads((CAMPAIGN / 'member-source-bindings.json').read_text())['bindings']
    for binding in bindings.values():
        target = scratch / binding['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / binding['path'], target)
    new = camp / "bin" / "control-census.py"
    shutil.copy2(CAMPAIGN / "bin" / "control-census.py", new)
    old = camp / "bin" / "control-census-previous.py"
    r = subprocess.run(["git", "-C", str(ROOT), "show", PREVIOUS],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0 or not r.stdout.strip():
        print(f"cannot read {PREVIOUS} from git — no comparison is possible and this arm prints "
              f"no verdict rather than half of one:\n{r.stderr.strip()}", file=sys.stderr)
        raise SystemExit(2)
    old.write_text(r.stdout, encoding="utf-8")
    return camp, new, old


def check_writer(committed: dict) -> list[str]:
    """`design-controls.py`'s registry write, exercised without a browser.

    Imported by path rather than reimplemented: a copy of the rule under test in the file that
    tests it measures the copy. `--set-controls` is what puts `plane` on a Mac surface, so the
    two readings that matter are that it writes glass where it harvested glass and that it
    REFUSES a surface the registry already calls something else instead of flipping it.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "design_controls", CAMPAIGN / "bin" / "design-controls.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    failures: list[str] = []
    harvest = {"controls": ["Reset history"], "messageOnly": [],
               "source": "design/mocks/prototype.html"}

    inv = json.loads(json.dumps(committed))
    written, refusals = mod.write_controls(inv, {"SURF-002": harvest})
    row = surface(inv, "SURF-002")
    ok = (written, refusals, row.get("plane"), row.get("controls")) == \
        (1, [], "glass", ["Reset history"])
    print(f"WRITER    glass surface, harvested controls  ·  wrote {written}, refused "
          f"{len(refusals)}, plane now {row.get('plane')!r}")
    if not ok:
        failures.append(f"WRITER glass: expected (1, [], 'glass', ['Reset history']), got "
                        f"{(written, refusals, row.get('plane'), row.get('controls'))}")

    inv = json.loads(json.dumps(committed))
    before = json.dumps(surface(inv, "SURF-045"), sort_keys=True)
    written, refusals = mod.write_controls(inv, {"SURF-045": harvest})
    after = json.dumps(surface(inv, "SURF-045"), sort_keys=True)
    ok = written == 0 and len(refusals) == 1 and "SURF-045" in refusals[0] and before == after
    print(f"WRITER    headless surface, harvested controls  ·  wrote {written}, refused "
          f"{len(refusals)}, row byte-identical: {before == after}")
    if not ok:
        failures.append(f"WRITER headless: expected one refusal naming SURF-045 and the row left "
                        f"untouched, got written={written} refusals={refusals} "
                        f"unchanged={before == after}")
    return failures


def check_typed_pair(camp: Path, new: Path, old: Path, committed: dict) -> list[str]:
    """Distinguish typed declaration matching from the retired name-shape regex."""
    bindings_file = camp / 'member-source-bindings.json'
    original_bindings = bindings_file.read_text()
    registry = camp / 'inventory.json'
    _code, before = run(new)
    import re
    before_count = re.search(r'Controls:\s+(\d+) of (\d+)', before)
    source = camp.parents[1] / 'app/Sources/ArmedDottedControl.swift'
    source.write_text('import SwiftUI\nstruct ArmedDottedControl: View { var body: some View { Button("Foo.Bar") {} } }\n')
    inv = json.loads(json.dumps(committed))
    surface(inv, 'SURF-002')['controls'].append('Foo.Bar')
    registry.write_text(json.dumps(inv))
    bindings = json.loads(original_bindings)
    member = json.dumps(['SURF-002', 'control', 'Foo.Bar'], separators=(',', ':'))
    bindings['bindings'][member] = {'adapter': 'swift-control-label', 'path': 'app/Sources/ArmedDottedControl.swift',
                                   'declaration': 'ArmedDottedControl', 'platform': 'macos', 'configuration': 'debug'}
    bindings_file.write_text(json.dumps(bindings))
    try:
        new_code, new_out = run(new)
        old_code, _old_out = run(old)
        after_count = re.search(r'Controls:\s+(\d+) of (\d+)', new_out)
        unchanged_actuation = bool(before_count and after_count and before_count[1] == after_count[1]
                                  and int(after_count[2]) == int(before_count[2]) + 1)
        print('TYPED PAIR genuine dotted UI label: new=%d old=%d unchanged actuation=%s'
              % (new_code, old_code, unchanged_actuation))
        failures = [] if new_code == 0 and old_code == 1 and unchanged_actuation else [
            'typed dotted-label pair failed or source evidence changed an actuation count: ' + new_out]
    finally:
        registry.write_text(json.dumps(committed))
        bindings_file.write_text(original_bindings)
        source.unlink()
    code, out = run(new)
    if code:
        failures.append('typed-pair restoration was not silent: ' + out)
    return failures


def main() -> int:
    committed = json.loads((CAMPAIGN / "inventory.json").read_text(encoding="utf-8-sig"))
    failures: list[str] = []

    with tempfile.TemporaryDirectory(prefix="arm-surface-plane-") as tmp:
        camp, new, old = stage(Path(tmp))
        registry = camp / "inventory.json"

        def write(inv: dict) -> None:
            registry.write_text(json.dumps(inv, indent=2, ensure_ascii=False) + "\n",
                                encoding="utf-8")

        # ── BASELINE ────────────────────────────────────────────────────────────────────────
        for label, census in (("this branch's census", new), ("the census it replaced", old)):
            code, out = run(census)
            ok = code == 0
            print(f"BASELINE  {label:<26} exit {code}  {'clean' if ok else 'FINDINGS'}")
            if not ok:
                failures.append(f"BASELINE {label}: expected exit 0 over the committed registry, "
                                f"got {code}:\n{out}")

        # ── EFFECT, one plant at a time ─────────────────────────────────────────────────────
        for name, apply, expected, prev_exit, absent in PLANTS:
            inv = json.loads(json.dumps(committed))
            apply(inv)
            write(inv)
            new_code, new_out = run(new)
            old_code, old_out = run(old)
            hits = [e for e in expected if e in new_out]
            if expected:
                good = new_code == 1 and len(hits) == len(expected)
                print(f"EFFECT    {name}\n            new census exit {new_code} "
                      f"({len(hits)}/{len(expected)} expected finding(s))  ·  previous census "
                      f"exit {old_code} {'SILENT — the defect' if old_code == 0 else 'red'}")
                if not good:
                    failures.append(f"EFFECT {name}: expected exit 1 carrying "
                                    f"{[e for e in expected if e not in new_out]}, got exit "
                                    f"{new_code}:\n{new_out}")
            else:
                good = new_code == 0 and absent not in new_out
                print(f"DECLARED SILENCE  {name}\n            new census exit {new_code} · "
                      f"previous census exit {old_code} "
                      f"{'RED — this is coverage given up' if old_code else 'silent too'}")
                if not good:
                    failures.append(f"DECLARED SILENCE {name}: this arm requires exit 0 and no "
                                    f"finding naming it, because a limit of this design is "
                                    f"written down against it. Got exit {new_code}. If the "
                                    f"census now catches this, the header, DEF-131's resolution "
                                    f"and DEF-420 are stale and must be rewritten before this "
                                    f"line is changed:\n{new_out}")
            if old_code != prev_exit:
                failures.append(f"PREVIOUS CENSUS {name}: expected exit {prev_exit} from "
                                f"{PREVIOUS} and got {old_code}. The comparison this arm rests "
                                f"on is what moved, not the plant:\n{old_out}")

            # ── SILENCE, after every single plant ───────────────────────────────────────────
            write(committed)
            code, out = run(new)
            if code != 0:
                failures.append(f"SILENCE after {name}: the plant was reverted and the census "
                                f"still exits {code}. The arm is reporting something other than "
                                f"the plant:\n{out}")

        failures += check_typed_pair(camp, new, old, committed)
        failures += check_writer(committed)

        print(f"\nSILENCE   plant reverted after each of {len(PLANTS)} plant(s): "
              f"{'clean each time' if not any(f.startswith('SILENCE') for f in failures) else 'NOT CLEAN'}")

    if failures:
        print(f"\n{len(failures)} reading(s) did not match:", file=sys.stderr)
        for f in failures:
            print(f"  · {f}", file=sys.stderr)
        return 1
    print(f"\narm-surface-plane: {len(PLANTS)} plant(s), each seen against both censuses, each "
          f"reverted and re-run clean, the typed dotted-label pair and the writer's two readings. "
          f"Plane and typed-source checks remain separate from observed actuation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
