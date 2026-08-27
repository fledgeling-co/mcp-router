#!/usr/bin/env python3
"""The control census, printed from this repository's pinned registry (G28).

WHY THIS EXISTS BESIDE `campaign.py check` RATHER THAN INSTEAD OF IT
-------------------------------------------------------------------
`campaign.py check` has counted actuated controls since **test-campaign 0.11.0**, and it is where
the census belongs. `vendor/test-campaign/` pins **0.9.2**, which has no census at all — not
`NOT DECLARED`, no line. So on the version this repository re-runs its gates from, declaring
`controls` and `actuates` correctly produces exactly no visible change, and the number the brief
asks for is readable only on a machine that happens to hold a newer plugin. Measured 2026-08-27:

    vendor 0.9.2   `check` prints no Controls line, before or after G28's registry edit
    cache  0.14.1  `Controls:   6 of 141 declared control(s) actuated by a passing effect-rung
                   case, across 14 surface(s) that declare any`

Re-vendoring the instrument to read one new line is a change to every gate this campaign quotes,
and `vendor/README.md` is explicit that the pin is the fixed point. So the pin stays and this
prints the same census from the same registry, by the same rules, until the pin moves past 0.11.0
— at which point this file should be deleted and `campaign.py check` read instead.

WHAT IT ADDS THAT THE INSTRUMENT DOES NOT HAVE AT ALL
-----------------------------------------------------
The message-only class. A control whose whole promised effect is something appearing on screen — a
sheet, a panel, a notification — is not the same measurement problem as one that promises a state
change, and upstream's census has no notion of the difference: it counts both as unactuated. That
reads as 135 dead controls where the truth is 81 controls whose only promise is a panel and 54 that
promise a change to the router's own state. Both numbers are printed, because the second is the one
worth chasing and the first is the one a reader would otherwise assume it was.

Which controls are message-only is recorded per surface in `inventory.json` under
`controlsMessageOnly`, derived by `bin/design-controls.py` from the design of record's own handler
tables, not asserted here.

THE RULES, WHICH ARE UPSTREAM'S AND NOT THIS FILE'S
---------------------------------------------------
  * A surface's denominator is its `controls` array. Absent means the surface declares none, which
    is reported as such rather than counted as clean.
  * Only `actuates` names that are IN the surface's declared list count. A name outside it is a
    finding, not a count: it means the case and the registry disagree about what the surface
    carries, and the census has nothing to count it against.
  * Only a PASSING case at an effect rung moves the count. `outcome`, `metamorphic`,
    `effect-witness`, `raster-visual` and `interactive-glass` are the effect rungs; a
    presence-rung or structural-rung pass that clicked a control and asserted the control is still
    there has measured the click and not the effect.

EXITS
-----
    0  the census ran and is printed. An inert surface is REPORTED and does not hold the gate:
       eleven of fourteen are inert today, and a gate that lands permanently red is a gate somebody
       switches off within a week (`registry-drop-gate.py`'s own finding, same week).
    1  a case actuates a control its surface never declared — the two halves disagree, and unlike
       an inert surface that is fixable in the registry right now
    2  no surface declares any controls, so there is no denominator. This is the state G28 was
       written to end, and it is an exit rather than a quiet zero for the reason the campaign
       repeats: a census over an undeclared population reads exactly like a clean one.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning" / "test-campaign"

# Upstream's, copied rather than inferred: campaign.py's EFFECT_RUNGS at 0.14.1.
EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness", "raster-visual", "interactive-glass"}
# Upstream's `state_of` resolves a status to pass/fail/skip/…; the only resolution this needs is
# whether the case passed, and a status carrying a reason after a colon keeps its head word.
def passed(status: str) -> bool:
    return (status or "").strip().lower().split(":")[0].strip() == "pass"


def main() -> int:
    inventory = json.loads((CAMPAIGN / "inventory.json").read_text())
    cases = json.loads((CAMPAIGN / "cases.json").read_text())

    declared: dict[str, list[str]] = {}
    message_only: dict[str, set[str]] = {}
    titles: dict[str, str] = {}
    for s in inventory.get("surface", []):
        if s.get("controls"):
            declared[s["id"]] = [str(x) for x in s["controls"]]
            message_only[s["id"]] = {str(x) for x in (s.get("controlsMessageOnly") or [])}
            titles[s["id"]] = s.get("title", "")

    if not declared:
        print("Controls:   NOT DECLARED — no surface lists its controls, so nothing here counts "
              "them. A control renders, carries its accessible name, passes a contrast gate and "
              "accepts a click whether or not its handler does anything.", file=sys.stderr)
        return 2

    actuated: dict[str, set[str]] = {sid: set() for sid in declared}
    claimed: dict[str, set[str]] = {sid: set() for sid in declared}
    strays: list[str] = []
    for c in cases:
        names = c.get("actuates") or []
        if not names:
            continue
        sid = c.get("surface")
        if sid not in declared:
            strays.append(f"{c['id']} actuates {len(names)} control(s) on "
                          f"{sid or 'no surface'}, which declares none")
            continue
        known = set(declared[sid])
        outside = [n for n in names if n not in known]
        if outside:
            strays.append(f"{c['id']} actuates {'; '.join(outside)} — not among {sid}'s "
                          f"declared controls")
        claimed[sid] |= set(names) & known
        if passed(c.get("status", "open")) and c.get("oracle") in EFFECT_RUNGS:
            actuated[sid] |= set(names) & known

    total = sum(len(v) for v in declared.values())
    hit = sum(len(actuated[sid]) for sid in declared)
    msg_total = sum(len(message_only[sid]) for sid in declared)
    unhit_msg = sum(len(message_only[sid] - actuated[sid]) for sid in declared)
    unhit_state = (total - hit) - unhit_msg

    print(f"Controls:   {hit} of {total} declared control(s) actuated by a passing effect-rung "
          f"case, across {len(declared)} surface(s) that declare any")
    print(f"            {msg_total} of the {total} are message-only — the design's whole promised "
          f"effect is a sheet, a panel or a notification appearing.")
    print(f"            Of the {total - hit} not actuated, {unhit_msg} are message-only and "
          f"{unhit_state} promise a state change nothing has driven.")
    print()
    for sid in sorted(declared):
        n, a = len(declared[sid]), len(actuated[sid])
        m = len(message_only[sid])
        near = claimed[sid] - actuated[sid]
        tail = (f" · {len(near)} driven only by a case below `outcome` or not passing"
                if near else "")
        print(f"  {sid}  {a:>2} of {n:>2} actuated · {m} message-only{tail}   {titles[sid]}")
        if a:
            print(f"        actuated: {'; '.join(sorted(actuated[sid]))}")

    inert = [sid for sid in sorted(declared) if not actuated[sid]]
    if inert:
        print(f"\n  {len(inert)} surface(s) declare controls that no passing effect-rung case "
              f"actuates: {', '.join(inert)}")
        print("  Reported, not blocked. The denominator is the finding; a gate that lands "
              "permanently red gets switched off.")

    if strays:
        print(f"\n  {len(strays)} case(s) actuating a control their surface never declared — the "
              f"registry and the case disagree about what the surface carries:", file=sys.stderr)
        for s in strays:
            print(f"    · {s}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
