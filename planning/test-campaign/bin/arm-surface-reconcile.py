"""Add a destination the campaign has never heard of, watch the gate name it, put it back.

WHY THIS EXISTS SEPARATELY FROM THE PRESENCE CONTROL
-----------------------------------------------------
`surface-reconcile.py` runs a presence control on every invocation: it plants a defect of each
class into an in-memory copy of the world and requires the classifier to report it. That proves the
CLASSIFIER bites. It does not prove the CHAIN that feeds it bites — a classifier can be perfect
while the oracle reads a stale binary, or a file that is not the one the app ships, or reads
nothing and returns an empty list that flows through every loop as a clean verdict. `arm-pipeline.py`
draws exactly this distinction for the glass suite, and for the same reason.

So this one mutates the product's own source. `Destination.swift` grows a tenth case with no
campaign surface anywhere, and the gate is required to name it — through a real `swiftc` run
against the real file, which is the whole path the gate uses.

WHAT GREEN MEANS HERE
---------------------
The assertion is a DELTA rather than "red, then green". It was written that way because the gate
was legitimately red when this file landed — three shipped addresses had no campaign surface, and
G15-G17 were the items adding them — so neither end of red-then-green was available to assert.
G25 bound the three and the baseline is green now (measured 2026-08-27: `BASELINE exit=0 named=[]`,
`MUTATED exit=1 named=['destination:probeboard']`), and the delta form is KEPT rather than
tightened to red-then-green, because it is the stronger check either way: the mutated verdict must
be the baseline PLUS the planted address and nothing else, and the restored verdict must be
byte-identical to the baseline. A gate that went red for a second reason under the mutation, or
that failed to return to exactly where it was, fails here.

WHAT IT PUTS BACK
-----------------
One file, restored from the exact bytes read before the mutation, verified by SHA-256 rather than
by having run the reverse edit. The record is written to evidence/runs/arm-surface-reconcile.json.

    /usr/bin/python3 planning/test-campaign/bin/arm-surface-reconcile.py
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "planning" / "test-campaign"
GATE = D / "bin" / "surface-reconcile.py"
SRC = ROOT / "app" / "Sources" / "MCPRouterKit" / "Shell" / "Destination.swift"
OUT = D / "evidence" / "runs" / "arm-surface-reconcile.json"

PLANTED = "destination:probeboard"

# Every exhaustive `switch` over `Destination` inside its own file, plus the declaration. The
# compiler requires all of them: that is the property the oracle rests on, and an anchor set that
# missed one would fail to build and report as a caught defect rather than a broken arm.
MUTATIONS = [
    ("    case cleanup\n    case insights\n",
     "    case cleanup\n    case insights\n    case probeboard\n"),
    ('        case .insights: "Insights"\n',
     '        case .insights: "Insights"\n        case .probeboard: "Probe"\n'),
    ("        case .discover, .inbox, .evals, .cleanup, .insights: .library\n",
     "        case .discover, .inbox, .evals, .cleanup, .insights, .probeboard: .library\n"),
    ("        case .insights: 9\n",
     "        case .insights: 9\n        case .probeboard: nil\n"),
    ("        case .activity, .skills, .discover, .evals, .harnesses, .insights: nil\n",
     "        case .activity, .skills, .discover, .evals, .harnesses, .insights, .probeboard: nil\n"),
    ('        case .insights: "insights"\n',
     '        case .insights: "insights"\n        case .probeboard: "insights"\n'),
]


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def gate():
    p = subprocess.run([sys.executable, str(GATE)], cwd=ROOT, capture_output=True, text=True,
                       timeout=900)
    out = p.stdout + p.stderr
    named = sorted(line.split()[1] for line in out.splitlines() if line.strip().startswith("FAIL "))
    return p.returncode, named, out


def main() -> int:
    original = SRC.read_text()
    before = sha(original)
    record = {"source": str(SRC.relative_to(ROOT)), "planted": PLANTED, "sha256Before": before}
    print(f"{SRC.relative_to(ROOT)}  sha256 before  {before}")

    base_rc, base_named, base_out = gate()
    record["baseline"] = {"exit": base_rc, "named": base_named}
    print(f"\nBASELINE       exit={base_rc}  named={base_named}")
    if PLANTED in base_named:
        print(f"REFUSED — {PLANTED} is already reported before anything was planted.")
        return 1

    try:
        text = original
        for old, new in MUTATIONS:
            if text.count(old) != 1:
                print(f"REFUSED — anchor appears {text.count(old)} times, need 1:\n  {old!r}")
                return 1
            text = text.replace(old, new, 1)
        SRC.write_text(text)
        print(f"\nplanted a tenth destination in {SRC.name} with no campaign surface")

        mut_rc, mut_named, mut_out = gate()
        record["mutated"] = {"exit": mut_rc, "named": mut_named}
        print(f"MUTATED        exit={mut_rc}  named={mut_named}")

        added = [n for n in mut_named if n not in base_named]
        removed = [n for n in base_named if n not in mut_named]
        record["delta"] = {"added": added, "removed": removed}
        armed = (mut_rc == 1 and added == [PLANTED] and not removed)
        record["armed"] = armed
        if armed:
            print(f"  ARMED — the gate went red naming exactly {PLANTED}, and nothing else moved")
        else:
            print(f"  NOT ARMED — added={added} removed={removed} exit={mut_rc}")
            print(mut_out[-2500:])
    finally:
        SRC.write_text(original)

    after = sha(SRC.read_text())
    record["sha256After"] = after
    record["restoredIdentical"] = after == before
    print(f"\n{SRC.relative_to(ROOT)}  sha256 after   {after}")
    print(f"  restored byte-identical: {after == before}")

    rest_rc, rest_named, _ = gate()
    record["restored"] = {"exit": rest_rc, "named": rest_named}
    same = (rest_rc == base_rc and rest_named == base_named)
    record["verdictRestored"] = same
    print(f"RESTORED       exit={rest_rc}  named={rest_named}")
    print(f"  verdict identical to baseline: {same}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(record, indent=1) + "\n")
    print(f"\nwrote {OUT.relative_to(ROOT)}")

    ok = record.get("armed") and record["restoredIdentical"] and same
    print("\nARM PASSED" if ok else "\nARM FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
