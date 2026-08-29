#!/usr/bin/env python3
"""Gates for the Windows parity fleet's better-goal run.

One subcommand, one question, judged on exit code alone. Each prints why it
failed, because the guard's block text becomes the run's next instruction and
"a gate went red" is not an instruction.

    python3 planning/goals/win-gates.py ledger|lane|branches|liveness

Deliberately NOT a wrapper over `make`: every verification target in this
repository's Makefile shells out to `xcodebuild`, and `make`, `swift`,
`swiftlint` and `xcodebuild` are all absent on Windows. A gate that shells to a
binary which is not installed reports the machine, not the work.
"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ORCH = ROOT / "ORCHESTRATOR.md"
TERMINAL = ("done", "parked", "waived")
EXPECTED = 23


def rows():
    """Every WIN ledger row as (id, status). The table is | ID | Title | Cat | Deps | Mock | Lane | Status | ..."""
    out = []
    for line in ORCH.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| **WIN"):
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        if len(cells) < 7:
            continue
        out.append((cells[0].strip("*"), cells[6].lower()))
    return out


def ledger():
    r = rows()
    if len(r) != EXPECTED:
        print("ledger: found %d WIN rows in ORCHESTRATOR.md, expected %d." % (len(r), EXPECTED))
        print("        A row that vanished is not a row that finished — restore it before continuing.")
        return 1
    open_rows = [(i, s) for i, s in r if not any(s.startswith(t) for t in TERMINAL)]
    if not open_rows:
        print("ledger: all %d WIN rows terminal (done or parked with a reason)." % len(r))
        return 0
    print("ledger: %d of %d WIN rows still open." % (len(open_rows), len(r)))
    for i, s in open_rows[:12]:
        print("    %-7s %s" % (i, s or "(blank status)"))
    if len(open_rows) > 12:
        print("    ... and %d more" % (len(open_rows) - 12))
    print("        Next action: advance the earliest ready row, or park it with a written reason.")
    return 1


def lane():
    """WIN18's Windows verification lane exists and exits 0.

    Until WIN18 lands there is no lane, and that is a red gate rather than a
    skipped one: this run's whole point is that Windows work currently cannot
    be gated at all."""
    for cand in ("scripts/windows/verify.ps1", "scripts/windows/verify.sh",
                 "scripts/verify-windows.ps1", "planning/goals/win-lane.ps1"):
        p = ROOT / cand
        if p.exists():
            cmd = (["pwsh", "-NoProfile", "-File", str(p)] if p.suffix == ".ps1"
                   else ["bash", str(p)])
            try:
                rc = subprocess.run(cmd, cwd=ROOT, timeout=1800).returncode
            except FileNotFoundError:
                cmd[0] = "powershell"
                rc = subprocess.run(cmd, cwd=ROOT, timeout=1800).returncode
            print("lane: %s exited %d" % (cand, rc))
            return 0 if rc == 0 else 1
    print("lane: no Windows verification lane exists yet (WIN18 is the item that builds it).")
    print("      Looked for scripts/windows/verify.ps1|.sh, scripts/verify-windows.ps1.")
    print("      Until it exists, NO Windows item can be gated — `make lint` and `make test`")
    print("      shell to xcodebuild and cannot run on this machine.")
    print("      Next action: land WIN18.")
    return 1


def branches():
    r = subprocess.run(["git", "branch", "--list", "ai/win*", "--no-merged", "main"],
                       cwd=ROOT, capture_output=True, text=True)
    left = [b.strip().lstrip("* ") for b in r.stdout.splitlines() if b.strip()]
    if not left:
        print("branches: no unmerged ai/win* branches.")
        return 0
    print("branches: %d unmerged ai/win* branch(es):" % len(left))
    for b in left:
        print("    %s" % b)
    print("        Next action: verify then merge one (merges are serialized — one at a time).")
    return 1


def _runner_idle_minutes():
    """Youngest write across any live workflow agent transcript, in minutes.

    Returns None when no transcript exists. A runner mid-build writes its
    transcript continuously while touching no branch for an hour, so the git tip
    alone answers a different question from the one this gate asks."""
    base = Path.home() / ".claude" / "projects"
    roots = [p for p in base.glob("*mcp-router*") if p.is_dir()]
    youngest = None
    for r in roots:
        # <project>/<session-id>/subagents/workflows/<run>/agent-*.jsonl — the session
        # segment is load-bearing. Without it this glob matches nothing and the witness
        # returns None, which reads as "no runners" rather than as "I did not look".
        for t in r.glob("*/subagents/workflows/*/agent-*.jsonl"):
            try:
                age = (time.time() - t.stat().st_mtime) / 60.0
            except OSError:
                continue
            if youngest is None or age < youngest:
                youngest = age
    return youngest


def liveness():
    """Whether anything is actually moving. Independent of whether the work is done.

    Two independent witnesses, because either alone gives a wrong answer: the git
    tip goes cold while runners legitimately build for an hour, and a transcript
    keeps moving after the work has stopped mattering."""
    budget = float(os.environ.get("WIN_LIVENESS_MINUTES", "90"))

    idle = _runner_idle_minutes()
    if idle is not None and idle <= 15:
        print("liveness: a fleet runner wrote %.0f min ago — the run is moving." % idle)
        return 0

    r = subprocess.run(["git", "log", "-1", "--format=%ct %h %s"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("liveness: git log failed — cannot tell whether this run is alive.")
        return 1
    ts, rest = r.stdout.strip().split(" ", 1)
    age = (time.time() - int(ts)) / 60.0
    if age <= budget:
        print("liveness: tip moved %.0f min ago — %s" % (age, rest))
        return 0

    print("liveness: no commit for %.0f min (budget %.0f). Last: %s" % (age, budget, rest))
    if idle is None:
        print("        No workflow agent transcript found either, so nothing witnesses a runner.")
    else:
        print("        Youngest runner transcript is %.0f min old, so the runners are cold too." % idle)
    print("        A cold tip alone is not proof of death — but cold on both witnesses is.")
    print("        Next action: derive (started - returned) from the workflow journal, then")
    print("        resume with workflow-resume rather than relaunching, which cold-starts.")
    return 1


CHECKS = {"ledger": ledger, "lane": lane, "branches": branches, "liveness": liveness}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in CHECKS:
        sys.exit("usage: win-gates.py {%s}" % "|".join(CHECKS))
    sys.exit(CHECKS[sys.argv[1]]())
