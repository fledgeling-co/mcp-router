#!/usr/bin/env python3
"""Record the on-glass arms, and re-rung the two REQ-017 cases the relation now covers.

TWO DIFFERENT ARMS, NAMED DIFFERENTLY, BECAUSE THEY PROVE DIFFERENT THINGS
--------------------------------------------------------------------------
`predicate` — the assertion was fed a mutated artifact and went red. This proves the
check can fail, which is the minimum a passing check owes. It does NOT prove the
build→launch→capture→assert pipeline can fail, because the artifact is a recording.

`pipeline` — the app's own source was reverted, the app rebuilt, the window relaunched
and recaptured, and the assertion then went red on evidence produced by the mutated
build. That is the stronger arm and it is recorded only where it actually ran.

Both are written verbatim into `armedBy` so a reader is never left inferring which one
a case has.

    python3 record-glass-arms.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

D = Path(__file__).resolve().parent.parent
CASES = D / "cases.json"
BIN = Path(__file__).resolve().parent

# case -> the surface whose decoy reddened it, from the decoy sweep
GLASS = {
    "CASE-0001": "SURF-001", "CASE-0003": "SURF-002", "CASE-0005": "SURF-008",
    "CASE-0011": "SURF-003", "CASE-0012": "SURF-004", "CASE-0013": "SURF-005",
    "CASE-0014": "SURF-006", "CASE-0015": "SURF-007", "CASE-0016": "SURF-011",
    "CASE-0101": "SURF-001", "CASE-0102": "SURF-002", "CASE-0103": "SURF-003",
    "CASE-0104": "SURF-004", "CASE-0105": "SURF-005", "CASE-0106": "SURF-006",
    "CASE-0107": "SURF-007", "CASE-0108": "SURF-008", "CASE-0111": "SURF-011",
}

# The two cases whose assertion changed, and what it changed to. This is a rung RAISE,
# so it has to be earned rather than asserted: the old check was "this state's copy is
# in the window", which one state can satisfy while the product is dishonest. The new
# one is a relation over three captures of the same window, and it distinguishes
# WITHHELD from ZEROED — which no single-state check can do.
REQ017 = {
    "CASE-0041": ("empty", "absent",
                  "zero is knowable, so the empty state PUBLISHES 0 tools from 0 servers "
                  "· 0 running rather than withholding. That is the control that proves "
                  "the offline absence is a decision and not a dead selector."),
    "CASE-0042": ("offline", "zeroed",
                  "an unreachable router WITHHOLDS the counts entirely and says why, "
                  "rather than rendering 0 tools from 0 servers, which a reader cannot "
                  "tell apart from a running-and-empty router."),
}


def run(args: list[str]) -> tuple[int, str]:
    p = subprocess.run([sys.executable, *args], cwd=D.parent.parent,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def main() -> int:
    cases = json.loads(CASES.read_text())
    by_id = {c["id"]: c for c in cases}

    # Re-verify rather than trust: the arm is only recorded if it reproduces here.
    disc_rc, disc = run([str(BIN / "glass-assert.py"), "--discriminate"])
    base_rc, base = run([str(BIN / "glass-assert.py")])
    if disc_rc != 0 or base_rc != 0:
        print("REFUSED — the glass suite is not currently green/leak-free; nothing recorded.")
        print(disc[-400:] if disc_rc else base[-400:])
        return 1
    checked = next((l for l in base.splitlines() if l.startswith("checked=")), "")
    pairs = next((l for l in disc.splitlines() if l.startswith("compared")), "")

    reds = {}
    for surface in sorted(set(GLASS.values())):
        rc, out = run([str(BIN / "glass-assert.py"), "--decoy", surface])
        red = {l.split()[1] for l in out.splitlines() if l.startswith("  FAIL ")}
        if rc == 0:
            print(f"REFUSED — decoy {surface} did not turn anything red.")
            return 1
        reds[surface] = red

    written = []
    for case, surface in GLASS.items():
        if case not in by_id:
            print(f"REFUSED — {case} not in cases.json")
            return 1
        if case not in reds[surface]:
            print(f"REFUSED — decoy {surface} did not redden {case}")
            return 1
        c = by_id[case]
        c["armed"] = True
        c["armedBy"] = (
            f"predicate arm. The assertion is stated explicitly in bin/glass-assert.py "
            f"and re-run there ({checked}). Removing {surface}'s own copy from its window "
            f"dump turns this case RED, so the check is known to bite. The suite's "
            f"discrimination control additionally runs every board's predicate against "
            f"every other board's dump ({pairs}) — a predicate that accepted a foreign "
            f"window would be matching shared shell chrome rather than the board it names. "
            f"This arms the PREDICATE against a recorded artifact; the build→launch→"
            f"capture→assert pipeline is armed once, end to end, on CASE-0014/CASE-0106."
        )
        note = (c.get("note") or "").strip()
        if not note:
            note = "assertion was unrecorded before this run; it is now stated in " \
                   "bin/glass-assert.py and reproduced there."
        c["note"] = f"{note} ARMED: predicate watched to fail under the {surface} decoy."
        for artifact in ("evidence/runs/glass-assert.json",):
            if artifact not in c["evidence"]:
                c["evidence"].append(artifact)
        written.append(case)

    # REQ-017: the rung raise, with each case armed by the decoy aimed at its own state.
    for case, (state, decoy, why) in REQ017.items():
        rc, out = run([str(BIN / "req017-honesty.py")])
        if rc != 0:
            print(f"REFUSED — the REQ-017 relation does not hold: {out[-300:]}")
            return 1
        drc, dout = run([str(BIN / "req017-honesty.py"), "--decoy", decoy])
        if drc == 0:
            print(f"REFUSED — REQ-017 decoy {decoy} did not go red")
            return 1
        failed = [l.strip()[8:] for l in dout.splitlines() if l.strip().startswith("FAILED")]
        c = by_id[case]
        c["oracle"] = "metamorphic"
        c["armed"] = True
        c["armedBy"] = (
            f"predicate arm, on a relation rather than a state. bin/req017-honesty.py "
            f"runs 10 checks across three AX dumps of the SAME window under three loads "
            f"(populated / empty / offline). The `--decoy {decoy}` run makes the product "
            f"behave as {('a router that lies with zeros' if decoy == 'zeroed' else 'a readable router that withholds anyway')} "
            f"and turns {len(failed)} of those checks red: {'; '.join(failed)}."
        )
        c["note"] = (
            f"{(c.get('note') or '').strip()} RE-RUNG structural → metamorphic: the old "
            f"assertion was that this state's copy appears in the window, which a single "
            f"state can satisfy while the product is dishonest. The assertion is now the "
            f"relation — {why} Measured over 3 real window dumps, 10 checks, 0 failures."
        )
        for artifact in ("evidence/runs/req017-honesty.json",):
            if artifact not in c["evidence"]:
                c["evidence"].append(artifact)
        written.append(case)

    CASES.write_text(json.dumps(cases, indent=1) + "\n")
    print(f"recorded {len(written)} cases: {len(GLASS)} glass predicate arms, "
          f"{len(REQ017)} REQ-017 re-rung + armed")
    print(f"  {checked}")
    print(f"  {pairs}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
