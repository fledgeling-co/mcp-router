#!/usr/bin/env python3
"""Gates for the `finish-all-waves` better-goal run.

One subcommand, one question, judged on exit code alone. Each prints WHY it
failed, because the guard's block text becomes the run's next instruction and
"a gate went red" is not an instruction.

    python planning/goals/completion-gates.py waves|wincoverage|winlive|branches|liveness

WHY THESE EXIST AT ALL. The run armed on 2026-09-01 reported `met` at turn 1,
eight minutes after arming, on four gates none of which could express its own
stop condition:

  * `reckon check` exits 0 when the ledger's PARTITION is total. It printed
    `unbuilt 2 - unjoined 110 - broken 56 - unmeasured 17 - undecided 18` and
    exited 0. It is a structural gate and was read as a completion gate.
  * `brief-target-gate.py` is a ratchet against a floor. At `0 above, 0 below`
    it passes by construction and can only ever detect regression.
  * `strict-check.py` is the same shape.
  * `test -s <the brief the same session had just written>`.

So the four gates were: one structural check, two regression ratchets, and a
tautology. None of them is wrong; none of them answers "is the work done".
Every gate below is written to go RED while work remains and GREEN only when it
does not, and each one is proved able to fail before it is armed.
"""
import io
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
RECKONING = ROOT / "planning" / "reckoning"
CAMPAIGN = ROOT / "planning" / "test-campaign"
EVIDENCE = ROOT / "planning" / "evidence"

# The 24 WIN items that landed 2026-08-31..2026-09-01. "Every screen, for real"
# is the owner's decision of 2026-09-02, so every one of these needs a Windows
# surface in the campaign registry and a live UIA verdict against the REAL
# shell. WIN1 (a framework decision), WIN17/WIN23 (router, no surface) and
# WIN18/WIN20 (harness) carry no drawn surface and are listed separately so the
# gate does not demand a board that was never meant to exist.
WIN_SURFACED = [
    "WIN3", "WIN4", "WIN5", "WIN6", "WIN7", "WIN8", "WIN9", "WIN10",
    "WIN11", "WIN12", "WIN13", "WIN14", "WIN15", "WIN16", "WIN21", "WIN22",
]
WIN_UNSURFACED = ["WIN1", "WIN2", "WIN17", "WIN18", "WIN19", "WIN20", "WIN23", "WIN24"]


def _read_json(p):
    return json.load(io.open(p, encoding="utf-8"))


def _read_json_bom(p):
    """PowerShell's ConvertTo-Json writes UTF-8 WITH a BOM, which json.load
    rejects outright. Every artifact the Windows lane produces needs this."""
    return json.load(io.open(p, encoding="utf-8-sig"))


def _rows(x):
    """The registry files are sometimes a bare list and sometimes wrapped."""
    if isinstance(x, dict):
        for k in ("surfaces", "cases", "requirements", "defects", "items", "rows", "data"):
            if k in x and isinstance(x[k], list):
                return x[k]
        return []
    return x if isinstance(x, list) else []


def _git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def _head_epoch():
    r = _git("log", "-1", "--format=%ct")
    try:
        return int(r.stdout.strip())
    except Exception:
        return 0


def latest_reckoning():
    """Newest reckoning ledger by its own directory mtime."""
    if not RECKONING.is_dir():
        return None
    # reader-accounting.py is right to flag a bare comprehension filter here: a
    # reckoning directory with no ledger.json is a real thing (a run that died
    # part-way writes reckoning.md and no ledger), and silently skipping it is
    # how a gate reports on a corpus smaller than the one it was handed. So the
    # drop is COUNTED and printed rather than declared away.
    cands, dropped = [], []
    for d in sorted(RECKONING.iterdir()):
        if (d / "ledger.json").is_file():
            cands.append(d / "ledger.json")
        elif d.is_dir():
            dropped.append(d.name)
    if dropped:
        print("waves: read %d reckoning dir(s), dropped %d with no ledger.json: %s"
              % (len(cands) + len(dropped), len(dropped), ", ".join(dropped)))
    if not cands:
        return None
    return max(cands, key=lambda q: q.stat().st_mtime)


# --------------------------------------------------------------------------
def waves():
    """Zero scheduled wave work remains, measured on a reckoning NEWER than HEAD.

    Two halves, and the freshness half is the one that matters. A completion
    gate reading a stale artifact is exactly the failure that produced this
    file: the ledger says zero because it was written before the work existed,
    not because the work is done. So a ledger older than the last commit is a
    RED gate whose instruction is "re-reckon", never a pass.

    The owner's scope decision (2026-09-02, `Everything that was built`) is
    product-work + evidence-work. decision-work (110 unjoined briefs + 18
    undecided) is OUT, and is asserted to still be counted rather than silently
    dropped -- a reckoning that lost the class would otherwise read as progress.
    """
    p = latest_reckoning()
    if p is None:
        print("waves: no reckoning ledger under planning/reckoning/.")
        print("       NEXT: run the reckon skill and write planning/reckoning/<date>/ledger.json.")
        return 1

    head = _head_epoch()
    age = int(p.stat().st_mtime) - head
    if age < 0:
        print("waves: the newest reckoning (%s) predates HEAD by %d min."
              % (p.relative_to(ROOT), -age // 60))
        print("       It cannot speak for the current tree. This is NOT a pass and NOT a failure")
        print("       of the product -- it is a stale instrument.")
        print("       NEXT: re-run reckon against the current tree, then re-read this gate.")
        return 1

    try:
        d = _read_json(p)
    except Exception as e:
        print("waves: could not read %s: %s" % (p.relative_to(ROOT), e))
        return 1

    by_kind = (d.get("summary") or {}).get("work_by_kind") or {}
    prod = int(by_kind.get("product-work", 0))
    evid = int(by_kind.get("evidence-work", 0))
    deci = int(by_kind.get("decision-work", 0))
    waves_ = (d.get("schedule") or {}).get("waves") or []
    members = sum(len(w.get("members") or []) for w in waves_)

    print("waves: %s (%d min newer than HEAD)" % (p.relative_to(ROOT), age // 60))
    print("       product-work %d - evidence-work %d - decision-work %d (out of scope, still counted)"
          % (prod, evid, deci))
    print("       %d wave(s), %d scheduled member(s)" % (len(waves_), members))

    if prod == 0 and evid == 0 and members == 0:
        print("waves: no scheduled work remains.")
        return 0

    over = []
    for w in waves_:
        for m in (w.get("members") or [])[:6]:
            over.append(str(m))
    print("       NEXT: ship the scheduled members through ship-fleet. Leading: %s"
          % ", ".join(over[:6]))
    return 1


# --------------------------------------------------------------------------
def win_items_owing_a_surface():
    """Which WIN items owe a campaign surface — MEASURED, not asserted.

    The first version of this gate hardcoded sixteen ids, and two of them were
    wrong: WIN21 is a shell-wide keyboard behaviour with no board of its own,
    and WIN22 has no drawn surface at all because it is inert. A hardcoded list
    is also a number this session can quietly tune until the gate goes green,
    which is the move the whole harness exists to prevent.

    So the expectation is derived: a WIN item owes a surface exactly when its
    own merge added a .xaml under MCPRouter.Shell. That cannot be edited into
    passing without editing git history, and it grows on its own when a later
    item ships a view.

    An item with NO view is not thereby excused — WIN19, WIN22 and WIN23 were
    measured inert on 2026-09-02 and are carried as defects, which is a
    different remedy from a missing surface and belongs in a different class.
    """
    out = []
    r = _git("log", "--format=%H %s", "main")
    for line in r.stdout.splitlines():
        sha, _, subj = line.partition(" ")
        m = re.match(r"WIN(\d+):", subj)
        if not m:
            continue
        item = "WIN" + m.group(1)
        if item in out:
            continue
        d = _git("diff", "--name-only", sha + "^", sha)
        for path in d.stdout.splitlines():
            if path.endswith(".xaml") and "MCPRouter.Shell" in path:
                out.append(item)
                break
    return sorted(out, key=lambda s: int(s[3:]))


def wincoverage():
    """Every drawn Windows surface is NAMED in the campaign registry and has a case.

    At arm time this was red for the strongest possible reason: the registry
    held 20 surfaces, all Mac/iOS/router, and zero Windows anything -- against
    220 C# and 38 XAML files that shipped in two days. reckon calls that class
    `never-named`, and its whole point is that an unnamed surface is invisible
    to a coverage percentage rather than counted against it.
    """
    # The REGISTRY is inventory.json. surfaces.in.json is an input file that
    # campaign.py reads and does not write, so a gate reading it reports the
    # plan rather than the state — this gate did, and stayed red after 16
    # surfaces had been registered.
    # inventory.json keys its entities in the SINGULAR - `surface`, `case`,
    # `requirement` - and cases are kept in cases.json beside it. The first
    # reader here asked for `surfaces`, fell through to the input file, and
    # reported 20 surfaces and 0 cases over a registry that held 44. A gate
    # reading the wrong file reports the plan and calls it the state.
    try:
        inv = _read_json(CAMPAIGN / "inventory.json")
        surfaces = inv.get("surface") or inv.get("surfaces") or []
        cases = inv.get("case") or inv.get("cases") or []
        if not cases:
            cases = _rows(_read_json(CAMPAIGN / "cases.json"))
    except Exception as e:
        print("wincoverage: could not read the campaign registry: %s" % e)
        return 1
    if not surfaces:
        print("wincoverage: the registry reports ZERO surfaces. That is the instrument")
        print("             failing, not the product passing.")
        return 1

    expected = win_items_owing_a_surface()
    if not expected:
        print("wincoverage: measured ZERO WIN items shipping a .xaml under MCPRouter.Shell.")
        print("             That is the instrument failing, not the product passing.")
        return 1

    def blob(r):
        return json.dumps(r, ensure_ascii=False).lower()

    # Matching on the item id and not on the word "windows" is deliberate:
    # `cases.json` already contains the English word twice, in prose about
    # dialogs, and a substring gate on it would have reported coverage that
    # does not exist.
    surf_by_item = {}
    for s in surfaces:
        b = blob(s)
        for item in expected:
            if re.search(r"\b%s\b" % item.lower(), b):
                surf_by_item.setdefault(item, []).append(s.get("id"))

    case_by_surface = {}
    for c in cases:
        b = blob(c)
        for s in surfaces:
            sid = str(s.get("id") or "")
            if sid and sid.lower() in b:
                case_by_surface[sid] = case_by_surface.get(sid, 0) + 1

    missing_surface = [i for i in expected if i not in surf_by_item]
    uncased = []
    for item, sids in surf_by_item.items():
        if not any(case_by_surface.get(str(sid), 0) for sid in sids):
            uncased.append(item)

    print("wincoverage: %d of %d WIN item(s) that shipped a view are named by a campaign surface"
          % (len(surf_by_item), len(expected)))
    print("             expected (measured from git, not asserted): %s" % ", ".join(expected))
    print("             registry holds %d surface(s), %d case(s)" % (len(surfaces), len(cases)))
    if missing_surface:
        print("             UNNAMED (reckon's `never-named` class -- invisible to coverage, not counted against it):")
        print("               %s" % ", ".join(missing_surface))
    if uncased:
        print("             NAMED BUT UNCASED (a surface with no case is a row, not a measurement):")
        print("               %s" % ", ".join(sorted(uncased)))
    if missing_surface or uncased:
        print("             NEXT: run the test-campaign skill over the Windows lane -- enumerate the")
        print("             surfaces, write cases against the UIA plane, and register them.")
        return 1
    print("wincoverage: every drawn Windows surface is named and cased.")
    return 0


# --------------------------------------------------------------------------
def winlive():
    """The UIA live lane has a verdict against the REAL shell, not only the probe.

    HISTORY, because this gate has been repointed once and that is the kind of
    edit that deserves its reason written down. It used to read WIN20's report
    under planning/evidence/WIN20/run/. That lane is real work and its numbers
    are true -- 90 assertions passed, 0 failed, 2 honestly unoracled, the tree
    read out of process with the target never holding the foreground -- but its
    subject is SURF-029, WIN20's OWN probe window, and it says so itself in a
    field called `subjectIsNotTheProduct` whose value was "WIN3 has not landed a
    drawable Windows shell". A plane proved on its own probe measures the plane.

    WIN3 landed, and scripts/windows/uia/shell-lane.ps1 now drives the shipped
    MCPRouter.Shell binary through that same plane. So this gate reads the
    product's lane. That repointing did NOT turn it green: the shell lane
    reports four failing destinations, one of which terminates the process. A
    gate moved onto a truer subject and made redder by the move is the opposite
    of the edit this repository has learned to distrust.
    """
    rundir = EVIDENCE / "WIN-SHELL" / "run"
    report = rundir / "assert-report.json"
    if not report.is_file():
        print("winlive: no assert-report.json under planning/evidence/WIN-SHELL/run/.")
        print("         That is NOT-RUN, which is red. The probe lane's report is not a")
        print("         substitute: it measures WinUI's automation plane, not this product.")
        print("         NEXT: powershell -File scripts/windows/uia/run-shell-lane.ps1")
        return 1

    try:
        d = _read_json_bom(report)
    except Exception as e:
        print("winlive: assert-report.json unreadable: %s" % e)
        return 1

    subject = str(d.get("subject") or "?")
    total = int(d.get("destinations") or 0)
    measured = int(d.get("measured") or 0)
    passed = int(d.get("passed") or 0)
    failed = int(d.get("failed") or 0)
    crashed = int(d.get("crashed") or 0)
    unoracled = int(d.get("unoracled") or 0)
    inconclusive = int(d.get("inconclusive") or 0)
    captured = str(d.get("capturedAtUtc") or "?")

    print("winlive: subject %s" % subject)
    print("         captured %s" % captured)
    print("         destinations %d -- measured %d, passed %d, FAILED %d (%d by crash), "
          "unoracled %d, inconclusive %d"
          % (total, measured, passed, failed, crashed, unoracled, inconclusive))

    # A lane's own disclosure that it is not measuring the product outranks every
    # figure in it. Kept here so that if this lane ever grows one, it blocks.
    disclaimer = str(d.get("subjectIsNotTheProduct") or "").strip()
    if disclaimer:
        print("         The lane DECLARES ITSELF not a measurement of the product:")
        print("           %s" % disclaimer[:200])
        return 1

    if measured == 0:
        print("         0 destinations measured. A lane that asserted nothing is NOT-RUN,")
        print("         which is red, not green -- a filter selecting nothing cannot pass.")
        return 1

    # Unmeasured destinations are not failures and they are not passes either.
    # Reporting `passed` against `measured` while `total` is larger is how a
    # denominator goes missing, so the shortfall is named on its own line.
    if measured < total:
        print("         %d of %d destination(s) were never measured. They are neither passing"
              % (total - measured, total))
        print("         nor failing, and they are not covered by the figures above.")
        return 1

    if failed:
        print("         %d destination(s) FAILED against the real shell -- see DEF-077 (Skills"
              % failed)
        print("         terminates the process) and DEF-078 (three boards select and never mount).")
        return 1

    print("winlive: every destination in the shipped shell was actuated through the automation")
    print("         plane and read back a distinct, correctly-titled tree.")
    return 0


# --------------------------------------------------------------------------
def branches():
    """No unmerged ai/* branch. Slow clock -- pair with `liveness`.

    Deliberately every ai/* branch, not only ai/win*: the previous fleet's gate
    scoped itself to the Windows prefix and went green while ai/p4 sat unmerged.
    """
    r = _git("branch", "--no-merged", "main", "--list", "ai/*")
    left = [l.strip().lstrip("* ") for l in r.stdout.splitlines() if l.strip()]
    if not left:
        print("branches: no unmerged ai/* branch.")
        return 0
    print("branches: %d unmerged: %s" % (len(left), ", ".join(left)))
    print("          NEXT: verify each, then merge it. Merges are serialized by the orchestrator.")
    return 1


# --------------------------------------------------------------------------
def liveness():
    """Something moved recently -- a FAST-clock gate, per ORCHESTRATOR's own post-mortem.

    That post-mortem is the reason this gate exists and the reason for its one
    unusual property. `branches` and `waves` can only change when a merge lands;
    a merge waits on a fresh-context verdict; a verdict takes roughly forty
    minutes. The Stop hook samples every four to six minutes, so between two
    merges the correct output of both gates is byte-identical and the `stuck`
    detector fires on healthy progress. It did, at iteration 25.

    THE UNUSUAL PROPERTY: this gate auto-passes once `waves` is satisfied.
    A progress watchdog that stays red when there is nothing left to progress
    would block a finished run forever, which is the same false-negative in the
    opposite direction.
    """
    p = latest_reckoning()
    if p is not None:
        try:
            k = (_read_json(p).get("summary") or {}).get("work_by_kind") or {}
            if int(k.get("product-work", 0)) == 0 and int(k.get("evidence-work", 0)) == 0:
                print("liveness: no scheduled work remains, so there is nothing to be live about. Pass.")
                return 0
        except Exception:
            pass

    budget = int(os.environ.get("FINISH_LIVENESS_BUDGET_MIN", "90"))
    now = time.time()
    marks = []

    head = _head_epoch()
    if head:
        marks.append(("last commit", (now - head) / 60.0))

    delivered = ROOT / "planning" / "goals" / "delivered.tsv"
    if delivered.is_file():
        marks.append(("delivered.tsv", (now - delivered.stat().st_mtime) / 60.0))

    wt = ROOT / ".worktrees"
    if wt.is_dir():
        newest = 0
        for q in wt.glob("*/.git"):
            newest = max(newest, q.stat().st_mtime)
        if newest:
            marks.append(("worktree activity", (now - newest) / 60.0))

    if not marks:
        print("liveness: nothing to measure. Treated as NOT-RUN, which is red, not green.")
        return 1

    freshest = min(marks, key=lambda m: m[1])
    for name, mins in sorted(marks, key=lambda m: m[1]):
        print("liveness: %-18s %6.0f min ago" % (name, mins))
    if freshest[1] <= budget:
        print("liveness: freshest signal is %s at %.0f min (budget %d). Alive."
              % (freshest[0], freshest[1], budget))
        return 0
    print("liveness: nothing has moved for %.0f min (budget %d) while scheduled work remains."
          % (freshest[1], budget))
    print("          NEXT: this is not a status check. Dispatch the next wave member, merge a")
    print("          ready branch, or record the runner as dead and relaunch it.")
    return 1


CHECKS = {"waves": waves, "wincoverage": wincoverage, "winlive": winlive,
          "branches": branches, "liveness": liveness}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in CHECKS:
        sys.exit("usage: completion-gates.py {%s}" % "|".join(CHECKS))
    sys.exit(CHECKS[sys.argv[1]]())
