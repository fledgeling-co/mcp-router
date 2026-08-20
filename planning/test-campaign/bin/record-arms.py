#!/usr/bin/env python3
"""Write the arming record into cases.json without clobbering what is already there.

`campaign.py set --note` REPLACES the note, and these cases carry notes that say
what was measured. Arming adds a second fact — what was reverted and what went red
— so it is appended with its own marker rather than overwriting the measurement.

Reads the arm driver's own log rather than taking an argument, so a case can only be
marked armed here if the driver actually recorded a red for it.

    python3 record-arms.py            # from evidence/runs/arm-suites.log
"""
from __future__ import annotations

import json
from pathlib import Path

D = Path(__file__).resolve().parent.parent
CASES = D / "cases.json"
ARMS = D / "evidence" / "runs" / "arm-suites.log"
MARK = "ARMED:"


def main() -> int:
    log = json.loads(ARMS.read_text())
    cases = json.loads(CASES.read_text())
    by_id = {c["id"]: c for c in cases}

    written, refused = [], []
    for arm in log["arms"]:
        case = by_id.get(arm["case"])
        if case is None:
            refused.append(f"{arm['case']} not in cases.json")
            continue
        if not arm["armed"]:
            refused.append(f"{arm['case']} was not armed by the driver")
            continue

        m, r = arm["mutated"], arm["restored"]
        case["armed"] = True
        case["armedBy"] = (
            f"Reverted {arm['reverts']} Mutation in {', '.join(arm['files'])}; "
            f"`swift test --filter {arm['filter']}` then ran {m['tests']} test(s) and went "
            f"RED, and {r['tests']} test(s) went green again after the source was restored. "
            f"The run count is swift-testing's own, because the XCTest bundle prints "
            f"'Executed 0 tests' on every run and a red that ran nothing is not a red."
        )
        note = (case.get("note") or "").split(f" {MARK}")[0].rstrip()
        case["note"] = f"{note} {MARK} the assertion was watched to fail once, " \
                       f"under the mutation recorded in armedBy.".strip()
        if "evidence/runs/arm-suites.log" not in case["evidence"]:
            case["evidence"].append("evidence/runs/arm-suites.log")
        written.append(arm["case"])

    CASES.write_text(json.dumps(cases, indent=1) + "\n")
    print(f"armed in registry: {len(written)} of {len(log['arms'])} attempted")
    for c in written:
        print(f"  {c}")
    for r in refused:
        print(f"  REFUSED {r}")
    return 0 if not refused else 1


if __name__ == "__main__":
    raise SystemExit(main())
