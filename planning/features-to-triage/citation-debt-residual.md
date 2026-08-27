---
status: to-triage
found-by: the remaining-backlog fleet, 2026-08-27, checking `make lint` whole rather than gate by gate
---

# Six files still hold more bare citations than their baseline

- origin: the remaining-backlog fleet · 2026-08-27
- audience: whoever needs a red gate to mean something again
- platforms: n/a
- proposed-by-ai: false

## What and why

`make lint` is red on `main` and has been all session. Measured at `0d59545`, before any of this
session's work: the same three members were already failing, so this is inherited debt rather than a
regression. It was not noticed for most of the session because the fleet ran individual gates and
never ran `lint` whole — which is the reporting version of the defect itself.

A permanently red gate stops telling anyone anything. This repository has recorded that failure
twice already in its own words, and every runner from here on inherits a red `lint` in which a new
failure is indistinguishable from the standing one.

See the LEDGER row for G35 for this item's measured figures.

## Acceptance sketch

- The gate's count falls, and the fall is visible run to run.
- The baseline is not raised to absorb the debt. Where a figure genuinely cannot fall, the reason is
  recorded as an exception with its own words rather than folded into the floor.
- Anything left is stated with its number rather than implied to be finished.
- What this session's own fleet added is fixed first, on the same reasoning G20 recorded: a rule its
  author does not keep will not be kept by anyone else.

## Assumptions made writing this

- Assuming the debt is paid down rather than absorbed, since every gate here states that its counts
  may only fall.
- Assuming reaching zero in one pass is not required, and that saying where it stopped is part of the
  deliverable rather than a failure of it.
