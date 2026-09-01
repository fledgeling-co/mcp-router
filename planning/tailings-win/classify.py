#!/usr/bin/env python3
"""Bulk-classify the tailings rows whose evidence is shared by construction.

Rows of one probe family with one root cause share one pointer. Classifying them
one at a time would restate the same evidence 25 times; classifying them without
a pointer would be the failure this skill exists to find. So each family below
names the tool result or repo fact behind it, and anything not covered by a
family stays unclassified and shows up in `check`.
"""
import io
import json
import sys
from pathlib import Path

# Each entry: (class, evidence). The evidence must point at a tool result in the
# audited session, or at repo state now — never at this pass's own narration.
FAMILIES = {
    "T15": ("undone",
            "signals.py T15 x6: /test-campaign, /tailings, /reckon, /intake, /ship-feature and "
            "/clarify were named in the human turn at :6 and :1285, never invoked, and never "
            "mentioned as unavailable. All six resolve in this repo's manifest — this session "
            "loaded ship-fleet:ship-fleet and better-goal by qualified name, so skill invocation "
            "was working. Not degraded: the instruments were present."),
    "T1": ("undone",
           "signals.py T1 x2: ship-fleet/gemini.md and better-goal/gemini.md were present beside "
           "skills this session loaded and never read. signals.py models for this session are "
           "gemini-3.7-flash and gemini-3.7-flash-high (c4a) and glm-5.3/glm-5.3-flash/grok-4.6 "
           "via perch-router (f62), so the overlay applied and its overrides were not taken."),
    "T9": ("degraded",
           "signals.py T9: 13 reviewer lanes chosen without lane_pick.py — the transcript at :218 "
           "shows `claude -p` invoked directly for the WIN3 verdict. That is in-family review "
           "presented as verification, and the session did not record it as such."),
    "T5": ("unbacked",
           "signals.py T5 x3: worklist-check.sh, preflight.sh and watch.sh had output redirected "
           "and were never re-run unsuppressed. Nothing contradicts their exit codes; nothing "
           "supports them either. Note watch.sh was in fact broken on this machine the whole time "
           "(GNU-vs-BSD `stat -f %m`, fixed 2026-09-02), so its suppressed run hid a real failure."),
    "T11": ("contradicted",
            "signals.py T11: the gate printed a non-zero class that the report which followed "
            "omitted. Reproduced 2026-09-02 — scripts/windows/verify.ps1 prints `passed 39 failed 0 "
            "not-run 5` and names the 5, including `uia live lane` and `shell self-test`, then says "
            "`A green run here is NOT a green repository`. A report quoting only exit 0 drops the "
            "class the lane exists to keep visible."),
    "T3": ("unbacked",
           "signals.py T3: a failing command precedes a clean claim that does not name it. The "
           "surrounding gates were re-measured 2026-09-02 and are green now (verify.ps1 exit 0, "
           "brief-target-gate exit 0), so the claims are not contradicted by present repo state — "
           "but the session never named the failure, so they could not be checked when made."),
    "R2": ("contradicted",
           "crossref.py R2: the session cites src/skills.ts; it exists nowhere in the repo or its "
           "history across the 55-commit window 2026-08-31T07:07Z..14:40Z."),
}

# Rows needing their own pointer.
SPECIFIC = {
    "A014": ("substantiated",
             "The six windows-parity-fleet gates were re-run 2026-09-02 against the same tree: "
             "branches exit 0 (`no unmerged ai/win* branches`), coverage exit 0 (`all 24 rows "
             "reachable`), lane exit 0 (`passed 39 failed 0 not-run 5`). The claim is about those "
             "gates and those gates did pass. What they do not measure is a separate finding."),
    "A015": ("contradicted",
             "verify.ps1 exit 0 is real and was reproduced 2026-09-02. But the lane's own output "
             "ends `passed 39 failed 0 not-run 5` and prints `A green run here is NOT a green "
             "repository`, listing `uia live lane (run-probe-lane.ps1) - needs WinSta0` and `shell "
             "self-test (captures) - needs an interactive session` among the not-run. Both WERE "
             "runnable from a session — the UIA lane was run 2026-09-01T21:41Z and returned 90/0/2. "
             "So `Complete Windows Parity Fleet Delivered & Verified` rests on a lane that "
             "explicitly disclaims being a repository verdict, with the two Windows-specific "
             "measurements not run."),
}



# ---------------------------------------------------------------------------
# Remedies. `check` blocks a row in a class that owes one and carries none, and
# it is right to: a class without a remedy is a label, and the point of the
# partition is that each class implies a different next action.
REMEDY = {
    "undone": "Run it now. This session is doing exactly that: test-campaign over the Windows "
              "lane, reckon against the current tree, intake for every finding, then ship-fleet.",
    "degraded": "Re-route through defer's lane_pick.py so the reviewer is out-of-family, and "
                "record any in-family review as degraded rather than as verification.",
    "unbacked": "Re-run the named check, or strike the claim. For the status/figure rows the "
                "re-run is this session's own: the campaign gains a Windows lane, and every WIN "
                "item gets a live UIA verdict, so the assertions stop resting on an unspawned "
                "verifier.",
    "contradicted": "Correct the durable artifact. ORCHESTRATOR.md's per-item narratives and the "
                    "18 merge subjects carrying `verified` are amended to state what actually "
                    "produced the verdict, and the not-run classes the lane prints are restored "
                    "to the reports that dropped them.",
    "laundered": "Revert the edit and re-run the gate.",
    "inert": "File a defect brief naming the observable that should have changed.",
}

# Sites opened in this pass, recorded so `check` can see the budget spend. Each
# is a file this pass actually read or a command it actually ran, not a probe.
SITES = {
    "f62": ["A044", "A046", "A043", "A054"],
    "c4a": ["A014", "A015", "A016"],
}

# The two set by hand already; do not overwrite.
KEEP = {"A044", "A046"}


def main():
    total = {"set": 0, "kept": 0, "left": 0}
    for d in ("planning/tailings-win/f62", "planning/tailings-win/c4a"):
        p = Path(d) / "worklist.json"
        doc = json.loads(io.open(p, encoding="utf-8").read())
        for r in doc["rows"]:
            rid = r.get("id")
            if rid in KEEP or r.get("class"):
                total["kept"] += 1
                continue
            if rid in SPECIFIC:
                cls, ev = SPECIFIC[rid]
            elif r.get("source") in FAMILIES:
                cls, ev = FAMILIES[r["source"]]
            elif r.get("kind") in ("status", "figure"):
                # The session's own status and figure claims. Re-measured where
                # the repo can answer: every ai/win* branch IS merged, every WIN
                # merge commit DOES carry a code diff, and the test counts rise
                # monotonically in the commit subjects. What no repo state can
                # settle is whether an independent verifier produced the verdict
                # each one asserts, and A046 shows none was spawned.
                cls = "unbacked"
                ev = ("Re-measured against repo state 2026-09-02: all ai/win* branches merged, "
                      "every WIN merge carries a non-empty code diff. The figures are consistent "
                      "with the tree. What is unbacked is the verification each claim asserts — "
                      "see A046: 0 spawned agents across 404 tool calls (f62), 1 across 327 (c4a).")
            else:
                total["left"] += 1
                continue
            r["class"] = cls
            r["evidence"] = ev
            if not r.get("remedy"):
                r["remedy"] = REMEDY.get(cls, "")
            total["set"] += 1
        key = "f62" if "f62" in d else "c4a"
        for r in doc["rows"]:
            if not r.get("remedy") and r.get("class") in REMEDY:
                r["remedy"] = REMEDY[r["class"]]
            if r.get("id") in SITES[key]:
                r["site"] = True
        io.open(p, "w", encoding="utf-8").write(json.dumps(doc, ensure_ascii=False, indent=2))
    print("classified %d, kept %d already set, %d left unclassified"
          % (total["set"], total["kept"], total["left"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
