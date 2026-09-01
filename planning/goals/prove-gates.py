#!/usr/bin/env python3
"""Prove every completion gate can go BOTH ways before it is armed.

A gate is only evidence if it can fail on the real defect and pass on the real
fix. This repository has recorded both halves failing: a sweep that reported
"28 scripts, 0 failures" while two of them were already broken (the instrument
measured the wrong thing), and a first draft of `winlive` in this very session
that matched "automationprobe" against a dump whose window is named
"Automation probe" -- red for the wrong reason, and it would have stayed red
after the work landed.

So each arm below mutates the gate's real input to the state that SHOULD flip
it, runs the gate, and restores. Two properties, both learned here the hard way:

  * The restore is READ BACK and compared byte-for-byte. ORCHESTRATOR records a
    restore write that hit an intermittent EPERM on this volume, leaving the
    branch silently short a line while `git status` reported the file clean.
  * A PRESENCE CONTROL runs first. If the arm's own mutation did not change the
    file, the arm proves nothing and must report that rather than a green tick.

    python planning/goals/prove-gates.py
"""
import io
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GATE = ROOT / "planning" / "goals" / "completion-gates.py"


def run(name):
    r = subprocess.run([sys.executable, str(GATE), name], cwd=ROOT,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env={"PYTHONIOENCODING": "utf-8",
                                              "PATH": __import__("os").environ.get("PATH", ""),
                                              "SYSTEMROOT": __import__("os").environ.get("SYSTEMROOT", "")})
    return r.returncode, (r.stdout or "") + (r.stderr or "")


class Arm:
    """Mutate a file, run the gate, restore, verify the restore."""

    def __init__(self, path):
        self.path = Path(path)
        self.original = self.path.read_bytes()

    def mutate(self, fn):
        text = self.original.decode("utf-8-sig")
        new = fn(json.loads(text))
        self.path.write_text(json.dumps(new, ensure_ascii=False, indent=2), encoding="utf-8")
        if self.path.read_bytes() == self.original:
            raise SystemExit("PRESENCE CONTROL FAILED: the arm's mutation of %s changed nothing, "
                             "so whatever the gate says next proves nothing." % self.path.name)

    def restore(self):
        self.path.write_bytes(self.original)
        back = self.path.read_bytes()
        if back != self.original:
            raise SystemExit("RESTORE FAILED on %s -- the tree is now dirty in a way git may "
                             "report as clean. Fix by hand before continuing." % self.path)


results = []


def record(gate, arm, expect, rc, out):
    ok = (rc != 0) if expect == "red" else (rc == 0)
    results.append((gate, arm, expect, rc, ok))
    first = next((l for l in out.splitlines() if l.strip()), "")
    print("  %-12s %-34s expect %-3s  exit %d  %s" % (gate, arm, expect, rc, "OK" if ok else "*** WRONG ***"))
    if not ok:
        print("        %s" % first[:150])


print("Proving the completion gates can go both ways.\n")

# ---------------------------------------------------------------- waves
print("waves -- zero scheduled product+evidence work, on a reckoning newer than HEAD")
rc, out = run("waves")
record("waves", "as-is (67 items remain)", "red", rc, out)

led = ROOT / "planning" / "reckoning" / "2026-09-01" / "ledger.json"
a = Arm(led)
try:
    a.mutate(lambda d: {**d,
                        "summary": {**d["summary"],
                                    "work_by_kind": {"product-work": 0, "evidence-work": 0,
                                                     "decision-work": 128}},
                        "schedule": {**d["schedule"], "waves": []}})
    rc, out = run("waves")
    record("waves", "all scheduled work cleared", "green", rc, out)

    # The freshness half. A cleared ledger that predates HEAD must STILL be red,
    # because that is the exact shape of the 2026-09-01 false green: an artifact
    # saying zero because it was written before the work existed.
    import os
    st = led.stat()
    head = int(subprocess.run(["git", "log", "-1", "--format=%ct"], cwd=ROOT,
                              capture_output=True, text=True).stdout.strip() or "0")
    os.utime(led, (head - 3600, head - 3600))
    rc, out = run("waves")
    record("waves", "cleared but STALE (predates HEAD)", "red", rc, out)
finally:
    a.restore()

# ---------------------------------------------------------------- wincoverage
print("\nwincoverage -- every drawn Windows surface named by a campaign surface, and cased")
rc, out = run("wincoverage")
record("wincoverage", "as-is (0 of 16 named)", "red", rc, out)

surf = ROOT / "planning" / "test-campaign" / "surfaces.in.json"
cases = ROOT / "planning" / "test-campaign" / "cases.json"
WIN = ["WIN3", "WIN4", "WIN5", "WIN6", "WIN7", "WIN8", "WIN9", "WIN10",
       "WIN11", "WIN12", "WIN13", "WIN14", "WIN15", "WIN16", "WIN21", "WIN22"]
sa, ca = Arm(surf), Arm(cases)
try:
    def add_surfaces(d):
        rows = d if isinstance(d, list) else d.get("surfaces", [])
        for i, w in enumerate(WIN):
            rows.append({"id": "SURF-9%02d" % i, "title": "Windows %s board" % w, "item": w})
        return d

    def add_cases(d):
        rows = d if isinstance(d, list) else d.get("cases", [])
        for i, w in enumerate(WIN):
            rows.append({"id": "CASE-9%03d" % i, "surface": "SURF-9%02d" % i, "status": "pass"})
        return d

    sa.mutate(add_surfaces)
    rc, out = run("wincoverage")
    record("wincoverage", "16 surfaces added, no cases", "red", rc, out)

    ca.mutate(add_cases)
    rc, out = run("wincoverage")
    record("wincoverage", "16 surfaces + 16 cases", "green", rc, out)
finally:
    ca.restore()
    sa.restore()

# ---------------------------------------------------------------- winlive
print("\nwinlive -- a UIA verdict against the REAL shell, not WIN20's own probe")
rc, out = run("winlive")
record("winlive", "as-is (probe, self-disclaimed)", "red", rc, out)

rep = ROOT / "planning" / "evidence" / "WIN20" / "run" / "assert-report.json"
ra = Arm(rep)
try:
    ra.mutate(lambda d: {**d, "subject": "MCPRouter.Shell", "subjectIsNotTheProduct": ""})
    rc, out = run("winlive")
    record("winlive", "repointed at the real shell", "green", rc, out)

    ra.mutate(lambda d: {**d, "subject": "MCPRouter.Shell", "subjectIsNotTheProduct": "",
                         "failed": [{"id": "x", "why": "a board did not draw"}]})
    rc, out = run("winlive")
    record("winlive", "real shell, one assertion failing", "red", rc, out)

    ra.mutate(lambda d: {**d, "subject": "MCPRouter.Shell", "subjectIsNotTheProduct": "",
                         "failed": [], "passed": []})
    rc, out = run("winlive")
    record("winlive", "real shell, asserted NOTHING", "red", rc, out)
finally:
    ra.restore()

# ---------------------------------------------------------------- branches
print("\nbranches -- no unmerged ai/* branch")
rc, out = run("branches")
record("branches", "as-is (ai/p4 unmerged)", "red", rc, out)
print("        green arm: not simulated -- it would require merging or deleting a real branch.")
print("        The gate reads `git branch --no-merged main --list ai/*` and is empty-set green;")
print("        the previous fleet's version of it went green for real on 2026-09-01.")

# ---------------------------------------------------------------- liveness
print("\nliveness -- something moved recently, and auto-passes once waves is satisfied")
rc, out = run("liveness")
record("liveness", "as-is (1324 min idle)", "red", rc, out)
import os
os.environ["FINISH_LIVENESS_BUDGET_MIN"] = "999999"
r = subprocess.run([sys.executable, str(GATE), "liveness"], cwd=ROOT, capture_output=True,
                   text=True, encoding="utf-8", errors="replace",
                   env={**os.environ, "PYTHONIOENCODING": "utf-8"})
record("liveness", "budget widened past the idle time", "green", r.returncode, r.stdout or "")

# ---------------------------------------------------------------- verdict
print("\n" + "-" * 72)
bad = [r for r in results if not r[4]]
print("%d arm(s), %d correct, %d WRONG" % (len(results), len(results) - len(bad), len(bad)))
if bad:
    for g, a_, e, rc, _ in bad:
        print("  WRONG: %s / %s expected %s, got exit %d" % (g, a_, e, rc))
    sys.exit(1)
print("every arm flipped the gate the way it should. The gates are evidence.")
sys.exit(0)
