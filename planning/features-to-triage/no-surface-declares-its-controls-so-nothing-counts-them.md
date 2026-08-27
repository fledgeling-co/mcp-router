---
status: to-triage
found-by: `campaign.py check` on `main`, 2026-08-27
---

# No surface declares its controls, so the actuation census has no denominator

- origin: session investigation of campaign coverage axes · 2026-08-27
- audience: whoever needs to know a control does something, not merely that it draws
- platforms: n/a
- proposed-by-ai: false

## What and why

`campaign.py check` prints `Controls: NOT DECLARED` on every run: no surface in the registry lists
the controls it carries, so nothing counts how many of them a passing case has actually driven. A
control renders, carries its accessible name, passes a contrast gate and accepts a click whether or
not its handler does anything, so a census without a denominator cannot separate a working board
from a drawn one.

The campaign has the harder half of this already. It runs on glass, it captures real windows, and
several boards are measured against the design of record. What it does not have is the list to
measure against: `SURF-002` (Servers), `SURF-003` (Activity), `SURF-007` (Cleanup) and the rest
carry no `controls` array, so a case cannot record `actuates`, and `check` has nothing to report but
the absence.

Two findings already on the board are this gap seen from the side. `DEF-011` says Cleanup's per-row
actions are specified by the design and drawn by nothing. `SURF-003`'s witness verdict says the
design specifies a *"Reset history…"* button that the build draws nowhere, confirmed independently
by a control differential reporting `designControls=1 buildControls=0`. Both were found by comparing
against the design of record rather than by any census, which is the expensive route to a question a
declared control list answers cheaply.

The design of record is the natural source for the list, which is what makes this tractable: the
mock already enumerates each board's controls, and `mockup-fidelity` and the differential phase
already read it.

## Acceptance sketch

- Each Mac board surface declares the controls it carries, sourced from the design of record rather
  than from the build, so a control the build never drew is still in the denominator.
- A case that drives a control records which one, and only a passing case at `outcome` or above
  moves the count.
- `campaign.py check` reports a control census with both numbers rather than `NOT DECLARED`.
- A control whose only promised effect is a message is recorded as such, rather than being counted
  as an unactuated one.
- Driving a control reads the state it was supposed to change through a channel other than the one
  that struck it.

## Assumptions made writing this

- Assuming the control list comes from the design of record rather than from the running build,
  since a list read off the build cannot contain a control the build is missing.
- Assuming this stays on the Mac boards rather than extending to the iOS surfaces in the same pass,
  since the iOS lane's accessibility identifiers are already a recorded defect (`DEF-008`).
- Assuming the planes and journeys axes stay with `campaign-journey-plane-ledger-model`, which
  already covers both; this brief is only the third of the three `NOT DECLARED` lines.
