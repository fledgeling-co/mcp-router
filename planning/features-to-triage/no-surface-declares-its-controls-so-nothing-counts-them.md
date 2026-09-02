---
status: to-triage
merged-as: 88918d4
settled: |
  NOT marked `completed`, and the refusal is the finding rather than an oversight.
  `planning/shipped-brief-gate.py` R6 declines a terminal word on a brief whose subject the
  registry still says no against - DEF-008 is open and DEF-011 is partially-fixed - and `reckon`
  reads a declared word AHEAD of the evidence, so the word would take those failing rows off the
  total. The census this brief asked for exists and is quoted below; the defects it was filed
  beside do not close because a denominator now counts them.
  2026-09-02, wa3. The Mac half was already done when this was read again: G28 declared controls
  on every Mac board and built `planning/test-campaign/bin/control-census.py`, which prints the
  census this brief asked `campaign.py check` for. It is not `campaign.py check` because
  `vendor/test-campaign/` pins 0.9.2 and the census landed upstream in 0.11.0, so on the pinned
  instrument declaring controls produces no visible line at all - that reasoning is in the file's
  own header and the pin was left alone.

  What was NOT done and is now: PROVENANCE on the Windows side. Fourteen Windows surface rows
  (SURF-029, SURF-031..SURF-043) carried a control list with nothing saying where it came from,
  which is the half of this brief that decides whether a control the build never drew can appear
  as missing. Each now carries a `controlsSource` naming the XAML it was read out of, and a
  `controlsSourceNote` saying plainly that a static read sees only literals and the number is a
  FLOOR. `bin/win-surface-reconcile.py` R4 enforces both and was watched to fail three ways.

  Numbers as the checker printed them, `bin/control-census.py`, before on `main` and after here:
  38 of 180 actuated across 29 surfaces -> 56 of 199 across 32, with the 13 strays (cases actuating
  a control no surface declared) gone. Evidence in `planning/evidence/WA3/run/`.

  Still open: the acceptance sketch's last two lines. A control whose promised effect is a message
  is recorded as such on the Mac boards and on none of the Windows ones - every Windows row reads
  0 message-only, which is a gap rather than a measurement. And 39 controls remain UNDISPOSED.
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
