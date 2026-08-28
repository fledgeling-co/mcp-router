---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# Put the router into a chosen state and read what the boards say

- origin: reckon 1.7.0, `REQ-004`, `REQ-005` and `REQ-007` standing on the project's own word · 2026-08-29
- audience: whoever relies on the honesty guardrails and currently has only the project's account of them
- platforms: mac
- proposed-by-ai: true

## What and why

Three of the product's honesty promises carry evidence `reported`: that the Servers board reflects live
states without inventing a figure the tracker does not hold, that live counts go **absent** rather than
last-known when the tracker is stale or the router is not running, and that numbers the router does not
observe are never displayed. Each is a claim the project makes about itself; nothing independent has
watched any of them happen.

These three are one capability, not three checks. All of them are statements about what a board draws
when the world is in a state nobody would encounter by launching the app normally: the tracker stale,
the router down, a figure unavailable. Buying them means being able to **put the router into a chosen
state and photograph the boards from outside** — after which all three become observations rather than
assertions, and the same instrument covers whatever guardrail is added next.

The absence direction is the hard half and the one worth paying for. A board that shows a stale figure
as current looks identical to one that is right, so this is a promise that can only be proved by
arranging the failing condition on purpose.

## Acceptance sketch

- The router can be driven into a stated condition — running, stopped, tracker stale, figure
  unavailable — from outside the app, on demand and repeatably.
- What each board displays in each of those conditions is recorded as an observation, not as a report.
- A count that ought to go absent is proved absent, and a run where it stayed visible fails.
- A fabricated figure appearing anywhere on a board fails a check rather than being noticed by a reader.
- The three requirements move off the project's own word, and the requirement-observed denominator says
  so.

## Assumptions made writing this

- Assuming one instrument that controls the router's state buys all three, rather than three separate
  checks against whatever state the app happens to boot into.
- Assuming absence is asserted as absence — that the check watches for nothing being drawn — rather
  than for a placeholder, since a placeholder is a figure of its own.
- Assuming the instrument is worth building for the guardrails not yet written as much as for these
  three.
