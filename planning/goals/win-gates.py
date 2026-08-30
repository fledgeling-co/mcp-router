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


# Items already landed or in flight outside a dispatch script: W0's decision, W1's rescue, and
# W2, which was launched inline rather than from a staged file.
LANDED = ("WIN1", "WIN2", "WIN17", "WIN18", "WIN3", "WIN20")


def rows_all():
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


def rows():
    return rows_all()


def ledger():
    r = rows()
    # A floor, not an exact count. Rows are ADDED legitimately - WIN24 came out of WIN2's own
    # verification - and requiring an exact number would have meant editing the expected total
    # every time the work grew, which is how a guard against loss becomes a rubber stamp. What
    # must never happen is a row disappearing, so the floor only ever rises.
    floor_file = Path(__file__).resolve().parent / "win-row-floor.txt"
    try:
        floor = int(floor_file.read_text(encoding="utf-8").strip())
    except Exception:
        floor = EXPECTED
    if len(r) < floor:
        print("ledger: %d WIN rows in ORCHESTRATOR.md, floor is %d." % (len(r), floor))
        print("        A row that vanished is not a row that finished - restore it before continuing.")
        return 1
    if len(r) > floor:
        floor_file.write_text(str(len(r)), encoding="utf-8")
        print("ledger: row floor raised %d -> %d (rows were added, none lost)." % (floor, len(r)))
    open_rows = [(i, s) for i, s in r if not any(s.startswith(t) for t in TERMINAL)]
    if not open_rows:
        print("ledger: all %d WIN rows terminal (done or parked with a reason)." % len(r))
        return 0
    print("ledger: %d of %d WIN rows still open." % (len(open_rows), len(r)))
    for i, s in open_rows[:12]:
        print("    %-7s %s" % (i, s or "(blank status)"))
    if len(open_rows) > 12:
        print("    ... and %d more" % (len(open_rows) - 12))

    # A progress quantity, deliberately not a clock.
    #
    # better-goal disarms a run as `stuck` when the failing gate set AND its output repeat.
    # This gate's output is otherwise byte-identical every turn while runners legitimately
    # build for an hour, so a perfectly healthy fleet would be killed as stuck. A clock would
    # fix that by never repeating - and would then never let a genuinely dead fleet trip it
    # either, which is worse, because `stuck` is the only thing that stops an empty run.
    #
    # Transcript volume is monotonic while an agent is working and frozen the moment it stops,
    # so it moves exactly when the run deserves another turn.
    if any(s.startswith(("running", "verifying")) for _, s in open_rows):
        vol, n = _runner_volume()
        if n:
            print("        %d runner transcript(s), %d lines total." % (n, vol))
        else:
            print("        No runner transcript found for a row marked running — check the")
            print("        workflow journal for (started - returned) before waiting further.")
    print("        Next action: advance the earliest ready row, or park it with a written reason.")
    return 1


CACHE = Path(__file__).resolve().parent / ".lane-verdict.json"


def _digest(p):
    import hashlib
    h = hashlib.sha256()
    try:
        h.update(p.read_bytes())
    except OSError:
        return "unreadable"
    return h.hexdigest()[:16]


def _head():
    r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def _lane_cache_get(key):
    """A cached verdict, or None. Only a PASS is ever cached.

    A red lane is re-run every turn on purpose: a failing gate is the thing the run is
    working to change, and serving a stale red would hide the fix that just landed."""
    try:
        import json
        d = json.loads(CACHE.read_text(encoding="utf-8"))
    except Exception:
        return None
    return 0 if d.get("key") == key and d.get("rc") == 0 else None


def _lane_cache_put(key, rc):
    if rc != 0:
        return
    try:
        import json
        CACHE.write_text(json.dumps({"key": key, "rc": rc}), encoding="utf-8")
    except OSError:
        pass


def _agent_transcripts():
    base = Path.home() / ".claude" / "projects"
    out = []
    for r in base.glob("*mcp-router*"):
        if r.is_dir():
            out += list(r.glob("*/subagents/workflows/*/agent-*.jsonl"))
    return out


def _runner_volume():
    """(total lines across live agent transcripts, transcript count).

    Monotonic while any agent is working, frozen the instant they all stop."""
    total = 0
    files = _agent_transcripts()
    for t in files:
        try:
            with open(t, "rb") as fh:
                total += sum(1 for _ in fh)
        except OSError:
            continue
    return total, len(files)


def _bash():
    """Git Bash, explicitly — never the bare name.

    Measured 2026-08-30: `subprocess.run(["bash", script])` on this machine reaches
    C:\\Windows\\System32\\bash.exe, which is the WSL launcher, and WSL2 cannot start here
    because virtualisation is off in firmware. It exits non-zero with a UTF-16 message about
    HCS_E_HYPERV_NOT_INSTALLED whatever the script says, so a lane that exits 0 was reported
    as exit 1 and would have been unpassable for the whole run.

    `shutil.which("bash")` disagrees with CreateProcess here — it answers Git Bash while the
    subprocess got WSL — so consulting it is not a fix either."""
    for c in (r"C:\Program Files\Git\bin\bash.exe",
              r"C:\Program Files\Git\usr\bin\bash.exe",
              r"C:\Program Files (x86)\Git\bin\bash.exe"):
        if Path(c).is_file():
            return c
    return "bash"


def lane():
    """WIN18's Windows verification lane exists and exits 0.

    Until WIN18 lands there is no lane, and that is a red gate rather than a
    skipped one: this run's whole point is that Windows work currently cannot
    be gated at all."""
    # Discovered, not hardcoded. The first version of this gate named four paths the
    # WIN18 runner was never told about, so a correct lane could have landed at a fifth
    # and left this gate red for the rest of the run — the gate deadlocking the item it
    # exists to wait for. The canonical path is now stated in WIN18's brief; the globs
    # below are the fallback so a reasonable choice still resolves.
    cands = []
    for pat in ("scripts/windows/verify.*", "scripts/verify-windows.*",
                "scripts/windows/*lane*", "scripts/verify.win.*", "planning/goals/win-lane.*"):
        cands += sorted(str(q.relative_to(ROOT)).replace("\\", "/")
                        for q in ROOT.glob(pat) if q.is_file())
    for cand in dict.fromkeys(cands):
        p = ROOT / cand
        ext = p.suffix.lower()
        if ext == ".ps1":
            cmd = ["pwsh", "-NoProfile", "-File", str(p)]
        elif ext == ".sh":
            cmd = [_bash(), str(p)]
        elif ext == ".py":
            cmd = [sys.executable, str(p)]
        elif ext in (".cmd", ".bat"):
            cmd = ["cmd", "/c", str(p)]
        else:
            continue
        # Cheap proxy, then the real thing.
        #
        # This gate fires on every turn. Running a full Windows verification suite each
        # time would tax every turn of the run for a verdict that cannot have changed
        # while nothing moved, which is what gate-craft means by putting a slow suite
        # behind a cheap proxy. The verdict is cached against the commit and the lane's
        # own mtime, so it re-runs exactly when something it measures could differ.
        # Keyed on the lane's CONTENT, not its mtime. An earlier version used
        # int(st_mtime), whose one-second resolution made same-second edits invisible:
        # a lane rewritten to exit 2 was served the previous run's exit 0. A cache that
        # can report a red gate green is worse than no cache.
        key = "%s|%s|%s" % (cand, _head(), _digest(p))
        cached = _lane_cache_get(key)
        if cached is not None:
            print("lane: %s exited %d (cached — HEAD and lane unchanged)" % (cand, cached))
            return 0 if cached == 0 else 1

        env = dict(os.environ, PYTHONIOENCODING="utf-8")
        try:
            rc = subprocess.run(cmd, cwd=ROOT, timeout=1800, env=env).returncode
        except FileNotFoundError:
            if ext != ".ps1":
                continue
            cmd[0] = "powershell"
            rc = subprocess.run(cmd, cwd=ROOT, timeout=1800, env=env).returncode
        except subprocess.TimeoutExpired:
            print("lane: %s did not finish within 1800s — recorded as NOT-RUN, not as a pass."
                  % cand)
            return 1
        _lane_cache_put(key, rc)
        print("lane: %s exited %d" % (cand, rc))
        return 0 if rc == 0 else 1

    print("lane: no Windows verification lane exists yet (WIN18 is the item that builds it).")
    print("      Searched: scripts/windows/verify.*, scripts/verify-windows.*,")
    print("                scripts/windows/*lane*, scripts/verify.win.*, planning/goals/win-lane.*")
    print("      The canonical path is stated in WIN18's brief under 'Lane contract'.")
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
    # <project>/<session-id>/subagents/workflows/<run>/agent-*.jsonl — the session segment
    # is load-bearing. An earlier version omitted it, matched nothing, and returned None,
    # which reads as "no runners" rather than as "I did not look".
    youngest = None
    for t in _agent_transcripts():
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


def coverage():
    """Is every ledger row reachable by some wave?

    The inverse of the question the other gates ask. `ledger` asks whether each row has
    finished; nothing asked whether each row can ever START. Five rows were reachable by no
    wave at all - WIN12 lost between a ledger entry and a wave-plan range that described the
    same wave differently, and WIN19/21/22/23 in a wave that had no script - and no gate would
    ever have reported it. The ledger gate would have printed the same open count forever while
    every wave reported success, which is a fleet declaring victory over a backlog it never
    dispatched."""
    import glob
    rows = [i for i, _ in rows_all()]
    covered = set(LANDED)
    for f in glob.glob(str(ROOT / "planning" / "goals" / "w*-dispatch.js")):
        try:
            covered |= set(re.findall(r"'(WIN\d+)'", open(f, encoding="utf-8").read()))
        except OSError:
            continue
    missing = [r for r in rows if r not in covered]
    if not missing:
        print("coverage: all %d rows reachable by a wave or already landed." % len(rows))
        return 0
    print("coverage: %d row(s) reachable by NO wave — nothing would ever launch them:" % len(missing))
    for r in missing:
        print("    %s" % r)
    print("        A row no wave dispatches is not blocked, it is forgotten.")
    print("        Next action: add it to a w*-dispatch.js, or park it with a written reason.")
    return 1


CHECKS = {"ledger": ledger, "lane": lane, "branches": branches,
          "liveness": liveness, "coverage": coverage}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in CHECKS:
        sys.exit("usage: win-gates.py {%s}" % "|".join(CHECKS))
    sys.exit(CHECKS[sys.argv[1]]())
