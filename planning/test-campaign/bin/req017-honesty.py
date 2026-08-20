#!/usr/bin/env python3
"""REQ-017 on glass: the servers board withholds live counts it cannot know.

WHAT THIS ADDS OVER THE STRUCTURAL CHECK IT REPLACES
----------------------------------------------------
CASE-0041 and CASE-0042 asserted that the empty and offline states render their
copy. That is a `structural` claim: it proves a label exists in the window, and a
label existing is compatible with the product being dishonest. The guardrail
REQ-017 actually states is a RELATION between loads:

    live counts are published exactly when the control port can be read,
    and WITHHELD — not zeroed, not left stale — when it cannot.

Zeroing is the failure mode that matters, because `0 tools from 0 servers · 0
running` under an unreachable router is indistinguishable, to a reader, from a
router that is running and genuinely empty. One state's copy cannot catch that.
Three states can, and the empty state is what makes the predicate provably live:
the counts line IS there under zero servers, so its absence when offline is a
decision rather than a selector that stopped matching.

    populated   counts published, non-zero          (router readable)
    empty       counts published, all zero          (router readable, zero knowable)
    offline     counts ABSENT, and not zeroed       (router unreadable)

All three are AX dumps of one real window from one build, captured on glass by
`bin/capture-mac-glass.sh` against pid-owned CGWindowIDs.

    python3 req017-honesty.py                # the three real dumps
    python3 req017-honesty.py --decoy zeroed # arm it: offline lies with zeros
    python3 req017-honesty.py --decoy absent # arm it: empty withholds instead
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

AX = Path(__file__).resolve().parent.parent / "evidence" / "ax"
OUT = Path(__file__).resolve().parent.parent / "evidence" / "runs" / "req017-honesty.json"

# "2 tools from 4 servers · 1 running" — the one line that publishes live counts.
COUNTS = re.compile(r"(\d+)\s+tools?\s+from\s+(\d+)\s+servers?\s*·\s*(\d+)\s+running")
# "Running 1" inside the filter radio group — the same counts, second channel.
SEGMENT = re.compile(r"AXRadioButton.*?\bRunning\s+(\d+)\b")

STATES = {
    "populated": "SURF-002.window.txt",
    "empty": "SURF-002.empty.window.txt",
    "offline": "SURF-002.offline.window.txt",
}


def read(state: str, decoy: str | None) -> str:
    text = (AX / STATES[state]).read_text()
    if decoy == "zeroed" and state == "offline":
        # The defect this guards: offline rendered as a knowable zero.
        return text.replace(
            "The router isn't running\t\t\t1",
            "0 tools from 0 servers · 0 running\t\t\t1", 1)
    if decoy == "absent" and state == "empty":
        # The mirror defect: a readable router with zero servers withholding anyway,
        # which would make the offline absence unremarkable rather than deliberate.
        return COUNTS.sub("Servers", text)
    return text


def main() -> int:
    decoy = None
    if "--decoy" in sys.argv:
        decoy = sys.argv[sys.argv.index("--decoy") + 1]

    found, failures, checks = {}, [], 0
    for state in STATES:
        text = read(state, decoy)
        m = COUNTS.search(text)
        seg = SEGMENT.search(text)
        found[state] = {
            "countsLine": m.group(0) if m else None,
            "tools": int(m.group(1)) if m else None,
            "servers": int(m.group(2)) if m else None,
            "running": int(m.group(3)) if m else None,
            "filterSegmentRunning": int(seg.group(1)) if seg else None,
            "dump": STATES[state],
        }

    def check(label: str, ok: bool) -> None:
        nonlocal checks
        checks += 1
        if not ok:
            failures.append(label)

    p, e, o = found["populated"], found["empty"], found["offline"]

    # 1 · a readable router publishes counts, and they are real
    check("populated publishes a counts line", p["countsLine"] is not None)
    check("populated counts are non-zero", (p["servers"] or 0) > 0 and (p["tools"] or 0) > 0)
    check("populated publishes the filter segment count", p["filterSegmentRunning"] is not None)

    # 2 · zero is knowable, so it is published rather than withheld. This is the
    #     control that proves the absence in 3 is a decision, not a dead selector.
    check("empty publishes a counts line", e["countsLine"] is not None)
    check("empty counts are all zero",
          (e["tools"], e["servers"], e["running"]) == (0, 0, 0))

    # 3 · an unreadable router withholds, and specifically does not zero
    check("offline publishes NO counts line", o["countsLine"] is None)
    check("offline does not zero the counts", o["tools"] is None)
    check("offline withholds the filter segment count too",
          o["filterSegmentRunning"] is None)

    # 4 · the relation itself: exactly the readable loads publish
    publishing = {s for s, v in found.items() if v["countsLine"] is not None}
    check("exactly the readable loads publish counts",
          publishing == {"populated", "empty"})

    # 5 · offline says why instead, so withholding is explained rather than blank
    check("offline names the reason in the window",
          "The router isn't running" in read("offline", decoy))

    ok = not failures
    print(f"REQ-017 honesty relation over {len(STATES)} real window dumps")
    for state, v in found.items():
        print(f"  {state:<10} counts={v['countsLine'] or 'ABSENT':<36} "
              f"segment={v['filterSegmentRunning']}")
    print(f"\nchecked={checks} failures={len(failures)}"
          + (f"  decoy={decoy}" if decoy else ""))
    for f in failures:
        print(f"  FAILED  {f}")
    print("\nPASS — counts are published exactly when the router is readable, "
          "and withheld rather than zeroed when it is not."
          if ok else "\nFAIL — the honesty relation does not hold.")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(
        {"checked": checks, "failures": failures, "states": found,
         "decoy": decoy, "pass": ok}, indent=1) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
