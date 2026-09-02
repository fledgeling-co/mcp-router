#!/usr/bin/env python3
"""Arm for `win-surface-reconcile.py`: prove each of its four rules can go red.

A reconciler that has never been watched to fail is a claim, not an instrument. Each arm below
removes exactly one registry fact -- the row, the control, the case link, the provenance -- runs
the reader, and requires the exit code to move. It restores the file in a `finally` either way, so
a failed arm cannot leave the registry mutated.

Run from anywhere:  python planning/test-campaign/bin/arm-win-surface-reconcile.py
Exits 0 when every arm reddened, 1 when any did not.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INV = ROOT / "planning" / "test-campaign" / "inventory.json"
CASES = ROOT / "planning" / "test-campaign" / "cases.json"
READER = ROOT / "planning" / "test-campaign" / "bin" / "win-surface-reconcile.py"


def run() -> tuple[int, str]:
    p = subprocess.run([sys.executable, str(READER)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


class Arm:
    def __init__(self, path: Path):
        self.path = path
        self.original = path.read_text(encoding="utf-8-sig")

    def mutate(self, fn):
        d = json.loads(self.original)
        self.path.write_text(json.dumps(fn(d), ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")

    def restore(self):
        self.path.write_text(self.original, encoding="utf-8")


results: list[tuple[str, bool, str]] = []


def record(rule: str, what: str, rc: int, out: str) -> None:
    red = rc == 1
    results.append((rule, red, what))
    lines = [x.strip() for x in out.strip().splitlines()]
    mine = [x for x in lines if x.startswith("· " + rule)]
    print("  %-3s %-52s exit=%d  %s" % (rule, what, rc, "RED" if red else "*** STAYED GREEN ***"))
    for x in mine:
        print("        %s" % x[:150])
    # Everything the filter above discarded, printed rather than dropped. An arm that shows only
    # the finding it expected cannot show a finding it did NOT expect -- a mutation that reddens
    # a DIFFERENT rule would read as a clean red here, which is the failure where an arm proves a
    # gate can fail without proving what it fails on. reader-accounting.py refuses the silent
    # comprehension; this is the record it asks for.
    rest = [x for x in lines if x and x not in mine and not x.startswith("win-surface-reconcile:")]
    for x in rest:
        print("        [not %s] %s" % (rule, x[:140]))


def surfaces(d):
    return d["surface"]


print("baseline -- the tree as it stands")
rc, out = run()
print("  exit=%d  %s" % (rc, out.strip().splitlines()[-1][:120] if out.strip() else ""))
if rc != 0:
    print("BASELINE IS NOT GREEN. Every arm below would be measuring an already-red reader, so "
          "nothing here would mean anything. Fix the findings first.")
    sys.exit(1)

inv = Arm(INV)
cases = Arm(CASES)

try:
    # R1 -- a shipped destination with no surface row to be uncovered in. This is G14's finding.
    def drop_a_destination_surface(d):
        d["surface"] = [s for s in surfaces(d)
                        if s.get("route") != "app://windows/shell#harnesses"]
        return d
    inv.mutate(drop_a_destination_surface)
    rc, out = run()
    record("R1", "the Harnesses surface row deleted", rc, out)
    inv.restore()

    # R2 -- a pane item that is not a declared control on the shell. This is G28's finding.
    def drop_a_pane_control(d):
        for s in surfaces(d):
            if s.get("route") == "app://windows/shell":
                s["controls"] = [c for c in s["controls"] if c != "Insights"]
        return d
    inv.mutate(drop_a_pane_control)
    rc, out = run()
    record("R2", "`Insights` removed from the shell's controls", rc, out)
    inv.restore()

    # R3 -- a measured Windows requirement whose measurement belongs to no surface.
    def unlink_a_case(d):
        for c in d:
            if c.get("id") == "CASE-0341":
                c.pop("surface", None)
                c.pop("actuatesSurface", None)
        return d
    cases.mutate(unlink_a_case)
    rc, out = run()
    record("R3", "CASE-0341 stripped of its surface link", rc, out)
    cases.restore()

    # R4a -- a control list with no provenance at all.
    def drop_a_source(d):
        for s in surfaces(d):
            if s.get("id") == "SURF-036":
                s.pop("controlsSource", None)
        return d
    inv.mutate(drop_a_source)
    rc, out = run()
    record("R4", "SURF-036's controlsSource removed", rc, out)
    inv.restore()

    # R4b -- a provenance that points at a file which is not there. This is the one that reads as
    # checked and is not, and it is the failure the SURF-045 row actually shipped with.
    def break_a_source_path(d):
        for s in surfaces(d):
            if s.get("id") == "SURF-031":
                s["controlsSource"] = s["controlsSource"].replace(
                    "Views/ServersBoard.xaml", "Views/ServerBoard.xaml")
        return d
    inv.mutate(break_a_source_path)
    rc, out = run()
    record("R4", "SURF-031's source path misspelt", rc, out)
    inv.restore()

    # R4c -- a control the named source does not contain, which is what a stale list looks like.
    def invent_a_control(d):
        for s in surfaces(d):
            if s.get("id") == "SURF-039":
                s["controls"] = s["controls"] + ["Rescan everything twice"]
        return d
    inv.mutate(invent_a_control)
    rc, out = run()
    record("R4", "a control invented on SURF-039", rc, out)
    inv.restore()

    # The control control: the reader must refuse to report a verdict when its own parse breaks,
    # rather than reporting a clean registry. Exit 2, not 0 and not 1.
    catalog = ROOT / "app" / "windows" / "MCPRouter.Shell.Model" / "DestinationCatalog.cs"
    original = catalog.read_text(encoding="utf-8-sig")
    try:
        catalog.write_text("// nothing here\n", encoding="utf-8")
        rc, out = run()
        ok = rc == 2
        results.append(("CTRL", ok, "DestinationCatalog.cs emptied"))
        print("  %-3s %-52s exit=%d  %s" % ("CTRL", "DestinationCatalog.cs emptied", rc,
                                            "REFUSED (2)" if ok else "*** DID NOT REFUSE ***"))
    finally:
        catalog.write_text(original, encoding="utf-8")
finally:
    inv.restore()
    cases.restore()

rc, out = run()
print("\nrestored -- exit=%d" % rc)

bad = [r for r in results if not r[1]]
print("\n%d/%d arm(s) moved the exit code." % (len(results) - len(bad), len(results)))
sys.exit(1 if bad or rc != 0 else 0)
