# The campaign's surface list is hand-maintained, and has gone stale twice over

- origin: the orchestrator, from the G14 surface-enumeration finding · 2026-08-27
- audience: Whoever needs the campaign's coverage figure to stay true as the product grows
- platforms: n/a
- proposed-by-ai: false

## What and why

Three shipped surfaces are missing from the campaign because its surface list is written by hand
and nothing reconciles it against the product. This is the recurrence, not the instance: fixing
the three leaves the mechanism that lost them in place, and the next destination to ship will be
lost the same way.

The completeness gate asks which enumerated surface has no case. Every enumerated surface has
one, so it reports clean. A surface that was never enumerated is invisible to a check keyed on
enumeration — the same shape M32 closed for mock elements by making the census total, where an
element outside every rule could not be reported by a gate that reports by rule.

The requirement list has the same illness at a smaller scale: the input file holds twenty
requirements and the inventory holds twenty-five, so five were added directly to one side with
nothing reconciling the two.

The remedy is that the campaign's denominator should be **derived from the product**, or
reconciled against it and refuse when they disagree. The product already states its destinations
in one place, and the sheet inventory states its sheets.

## Acceptance sketch

- The campaign's surface set is derived from, or checked against, the product's own declaration
  of its destinations and sheets.
- A destination the product ships and the campaign does not enumerate fails a gate, naming it.
- The failure distinguishes "shipped and unenumerated" from "enumerated and uncovered", because
  the remedies differ.
- The same reconciliation covers the requirement list's two sources, or records why it cannot.
- The check is armed: adding a destination to the product with no campaign surface is shown
  turning the gate red, and removing it again turns it green.
- The three currently-missing surfaces are named by the gate on its first run.

## Assumptions made writing this

- Assuming derivation is preferable to a second hand-maintained list that also drifts, but that a
  reconciliation which refuses on disagreement is an acceptable answer if derivation cannot see
  sheets as well as destinations.
- Assuming this is one item rather than two, because the surface list and the requirement list
  fail by the same mechanism and a fix that reads the product can serve both.
