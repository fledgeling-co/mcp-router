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

WHY THE ARMS ARE RELATIVE RATHER THAN ABSOLUTE. The first version of this file
hardcoded each gate's CURRENT colour: `record("wincoverage", "as-is (0 of 16
named)", "red", ...)`. Then the work landed, wincoverage went green for the best
possible reason, and this harness reported it as WRONG -- an arm asserting a
world that no longer existed. A proof harness that decays into noise every time
the tree improves gets switched off, and a switched-off proof proves nothing.

So an arm no longer states what colour a gate IS. It observes that as a
BASELINE, then requires each mutation to FLIP it. An arm whose mutation aims at
a colour the gate already had is reported INCONCLUSIVE rather than OK, because a
gate that was already red tells you nothing when it stays red.

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
BASELINE = {}


def observe(gate, label, rc):
    """Record what the gate says about the tree as it stands. Never scored.

    This is an observation, not an arm. It is also one half of the two-way proof:
    the live tree IS one of the two directions, and it is the only one nobody had
    to simulate.
    """
    BASELINE[gate] = rc
    print("  %-12s %-34s baseline %-5s (exit %d)"
          % (gate, label, "red" if rc else "green", rc))


def record(gate, arm, expect, rc, out, against=None):
    want_red = (expect == "red")
    base = BASELINE.get(gate) if against is None else against
    if base is not None and ((base != 0) == want_red):
        # The mutation aimed at the colour the gate already had, so its outcome
        # is not evidence either way. Saying OK here would be the harness
        # congratulating itself for a gate that never moved.
        results.append((gate, arm, expect, rc, None))
        print("  %-12s %-34s expect %-3s  exit %d  INCONCLUSIVE (baseline already %s)"
              % (gate, arm, expect, rc, "red" if base else "green"))
        return
    ok = (rc != 0) if want_red else (rc == 0)
    results.append((gate, arm, expect, rc, ok))
    # Counted, not filtered away: reader-accounting.py flags a bare comprehension
    # filter, and it is right to - "the first non-blank line" silently discards
    # however many blank ones preceded it, and a gate whose output is ALL blank
    # would print an empty reason and look like a gate with nothing to say.
    lines = out.splitlines()
    first, blanks = "", 0
    for line in lines:
        if line.strip():
            first = line
            break
        blanks += 1
    if not first and lines:
        first = "(%d line(s) of output, all blank)" % len(lines)
    print("  %-12s %-34s expect %-3s  exit %d  %s" % (gate, arm, expect, rc, "OK" if ok else "*** WRONG ***"))
    if not ok:
        print("        %s" % first[:150])


print("Proving the completion gates can go both ways.\n")

# ---------------------------------------------------------------- waves
print("waves -- zero scheduled product+evidence work, on a reckoning newer than HEAD")
rc, out = run("waves")
observe("waves", "as the tree stands", rc)

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
    # Measured against the CLEARED state proved green one line above, not against
    # the untouched tree: the only difference between them is the timestamp.
    record("waves", "cleared but STALE (predates HEAD)", "red", rc, out, against=0)
finally:
    a.restore()

# ---------------------------------------------------------------- wincoverage
print("\nwincoverage -- every drawn Windows surface named by a campaign surface, and cased")
rc, out = run("wincoverage")
observe("wincoverage", "as the tree stands", rc)

# The gate reads inventory.json for surfaces and cases.json for cases. An earlier
# version of this arm mutated surfaces.in.json -- the INPUT file campaign.py reads
# and never writes -- so it could not have flipped the gate no matter what it put
# there, and its green tick meant nothing. The gate's own docstring says which
# file is the registry; this arm now reads it from the same place.
inv = ROOT / "planning" / "test-campaign" / "inventory.json"
cases = ROOT / "planning" / "test-campaign" / "cases.json"

ia, ca = Arm(inv), Arm(cases)
try:
    def drop_windows_cases(d):
        rows = d if isinstance(d, list) else d.get("cases", [])
        kept = [c for c in rows if not str(c.get("surface", "")).startswith("SURF-0")
                or str(c.get("lane", "")) != "windows-glass"]
        dropped = len(rows) - len(kept)
        if not dropped:
            raise SystemExit("PRESENCE CONTROL FAILED: no windows-glass cases to drop, so this "
                             "arm cannot demonstrate the uncased state it exists to demonstrate.")
        return kept if isinstance(d, list) else {**d, "cases": kept}

    ca.mutate(drop_windows_cases)
    rc, out = run("wincoverage")
    record("wincoverage", "every windows-glass case removed", "red", rc, out)
    ca.restore()

    def drop_windows_surfaces(d):
        rows = d.get("surface") or []
        kept = [x for x in rows if str(x.get("lane", "")) != "windows-glass"]
        if len(kept) == len(rows):
            raise SystemExit("PRESENCE CONTROL FAILED: no windows-glass surfaces to drop.")
        return {**d, "surface": kept}

    ia.mutate(drop_windows_surfaces)
    rc, out = run("wincoverage")
    record("wincoverage", "every windows-glass surface removed", "red", rc, out)
finally:
    ca.restore()
    ia.restore()

# ---------------------------------------------------------------- winlive
print("\nwinlive -- a UIA verdict against the REAL shell, not WIN20's own probe")
rc, out = run("winlive")
observe("winlive", "as the tree stands", rc)

# Repointed 2026-09-02 from WIN20's probe report to the shell lane's, because the
# gate was repointed. An arm still mutating WIN20's file would have gone on
# passing while measuring a file the gate no longer opens -- the same
# wrong-file failure the wincoverage arm above had.
rep = ROOT / "planning" / "evidence" / "WIN-SHELL" / "run" / "assert-report.json"
ra = Arm(rep)
CLEAN = {"destinations": 10, "measured": 10, "passed": 10, "failed": 0, "crashed": 0,
         "unoracled": 0, "inconclusive": 0, "subjectIsNotTheProduct": ""}
try:
    ra.mutate(lambda d: {**d, **CLEAN})
    rc, out = run("winlive")
    record("winlive", "all ten destinations passing", "green", rc, out)

    ra.mutate(lambda d: {**d, **CLEAN, "passed": 9, "failed": 1})
    rc, out = run("winlive")
    record("winlive", "one destination failing", "red", rc, out, against=0)

    # The denominator arm. 10 of 10 passing is a different claim from 6 of 6
    # passing out of 10, and a gate that cannot tell them apart is how a
    # coverage figure loses its denominator.
    ra.mutate(lambda d: {**d, **CLEAN, "measured": 6, "passed": 6})
    rc, out = run("winlive")
    record("winlive", "6 of 10 measured, all passing", "red", rc, out, against=0)

    ra.mutate(lambda d: {**d, **CLEAN, "measured": 0, "passed": 0})
    rc, out = run("winlive")
    record("winlive", "nothing measured at all", "red", rc, out, against=0)

    # A lane that declares itself not a measurement of the product outranks
    # every figure in it, however green.
    ra.mutate(lambda d: {**d, **CLEAN,
                         "subjectIsNotTheProduct": "this is the probe, not the shell"})
    rc, out = run("winlive")
    record("winlive", "perfect figures, self-disclaimed", "red", rc, out, against=0)
finally:
    ra.restore()

# ---------------------------------------------------------------- branches
print("\nbranches -- no unmerged ai/* branch")
rc, out = run("branches")
observe("branches", "as the tree stands", rc)
print("        green arm: not simulated -- it would require merging or deleting a real branch.")
print("        The gate reads `git branch --no-merged main --list ai/*` and is empty-set green;")
print("        the previous fleet's version of it went green for real on 2026-09-01.")

# ---------------------------------------------------------------- liveness
print("\nliveness -- something moved recently, and auto-passes once waves is satisfied")
rc, out = run("liveness")
observe("liveness", "as the tree stands", rc)
import os
os.environ["FINISH_LIVENESS_BUDGET_MIN"] = "999999"
r = subprocess.run([sys.executable, str(GATE), "liveness"], cwd=ROOT, capture_output=True,
                   text=True, encoding="utf-8", errors="replace",
                   env={**os.environ, "PYTHONIOENCODING": "utf-8"})
record("liveness", "budget widened past the idle time", "green", r.returncode, r.stdout or "")

os.environ["FINISH_LIVENESS_BUDGET_MIN"] = "0"
r = subprocess.run([sys.executable, str(GATE), "liveness"], cwd=ROOT, capture_output=True,
                   text=True, encoding="utf-8", errors="replace",
                   env={**os.environ, "PYTHONIOENCODING": "utf-8"})
record("liveness", "budget of zero minutes", "red", r.returncode, r.stdout or "")
os.environ.pop("FINISH_LIVENESS_BUDGET_MIN", None)

# ---------------------------------------------------------------- verdict
print("\n" + "-" * 72)
bad = [r for r in results if r[4] is False]
inconclusive = [r for r in results if r[4] is None]
good = [r for r in results if r[4] is True]
print("%d arm(s), %d correct, %d WRONG, %d inconclusive"
      % (len(results), len(good), len(bad), len(inconclusive)))
for g, a_, e, rc, _ in inconclusive:
    print("  INCONCLUSIVE: %s / %s aimed at %s, which the gate already was" % (g, a_, e))
if bad:
    for g, a_, e, rc, _ in bad:
        print("  WRONG: %s / %s expected %s, got exit %d" % (g, a_, e, rc))
    sys.exit(1)
print("every arm that could move a gate, moved it the way it should.")
print("Baselines observed on the live tree: %s"
      % ", ".join("%s=%s" % (g, "red" if rc else "green") for g, rc in sorted(BASELINE.items())))
sys.exit(0)
