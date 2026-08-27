---
status: completed
shipped-by: 519aebc
---

# The Insights board has never been opened on glass

- origin: the orchestrator, from the G14 surface-enumeration finding · 2026-08-27
- audience: Anyone relying on the campaign's coverage number to know what has been exercised
- platforms: mac
- proposed-by-ai: false

## What and why

The Insights board shipped with M22 and no test case has ever opened it. Like Harnesses, it is
absent from the campaign's surface list, so it cannot be reported as uncovered.

It carries a specific hazard the other boards do not, and that is the reason this is its own
brief rather than a line in the Harnesses one. Insights is the board whose cells are **counts and
measurements** — the surface where a figure the product does not actually observe would be
hardest to spot, because a plausible number reads as a real one. The design of record forbids
displaying a figure the router does not observe, and nothing has ever checked that on this board
against a live router. M32's census work found one such cell here already: `Resident, all
children` and `214 MB` drawn inside a frame whose own instrument reported one unclassified
element where twelve were drawn.

So the on-glass work here is not only "does it render" but "does each figure it draws trace to
something observed".

## Acceptance sketch

- The board is enumerated as a campaign surface with a route and a lane that can observe it.
- Selecting it from the sidebar reaches it, and the window title becomes its destination name.
- Its populated, empty and failure states each render and are each photographed.
- Every figure the board draws is either traced to something the router observes, or recorded as
  a derivation with that stated.
- A figure that cannot be traced fails the case rather than passing because it looks reasonable.
- The campaign's own gate counts the board in its denominator afterwards.

## Assumptions made writing this

- Assuming the observe-or-do-not-draw rule applies to this board's cells as written, rather than
  having an exemption nobody has recorded.
- Assuming tracing a figure to its source is in scope here rather than deferred to a separate
  honesty audit, because a rendered number nobody traced is the defect this board invites.
