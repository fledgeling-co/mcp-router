---
status: to-triage
found-by: intake, parity target for SURF-006 · 2026-08-30
registry-target: none
no-target-reason: SURF-006 registers the macOS Checks board and the registry holds no Windows equivalent, so no recorded case could witness the Windows one
---

# The Windows Checks board — a result belongs to the version it ran against

- origin: owner directive, 2026-08-30; parity target for the Mac Checks board
- audience: anyone on Windows deciding whether a capability still does what it says
- platforms: windows

## What and why

Checks carries the product's strongest honesty guarantee, stated on the surface itself: "A result
belongs to the version it ran against and is thrown away when that version moves — a green tick
carried forward is worse than no tick." The design of record demonstrates it: `trawl` moved from
1.4.2 to 1.5.0, so its previous result was **dropped** rather than shown against the new code, and
the row reads `Stale`.

The board also states a refusal: "No model-graded evaluation exists in this product." The related
mock frames checks as "watched, not scored" — an eval is a transcript you read, and a failure
freezes on the exchange that failed rather than collapsing to a badge.

The columns are Capability, Version, Result, Checks, Ran, with `Run all` and `Run the stale suite`
in the head. The invalidation notice sits above the table and names what was dropped and why.

This board is where a Windows reimplementation is most likely to regress the product without
anybody noticing, because carrying a stale green tick forward is the *easy* implementation and it
looks better. The staleness rule and the absence of model grading are acceptance items.

## Acceptance sketch

- Every result is stamped with the version it ran against, and that version is visible on the row.
- When a capability's version moves, its previous result is dropped and the row reads stale — it is never re-displayed against the new version.
- The invalidation notice names which result was dropped and why, and offers to re-run that capability.
- `Run all` and `Run the stale suite` are distinct actions and the second acts only on stale rows.
- A failing check can be opened to the exchange that failed, rather than only to a count.
- No surface anywhere shows a model-graded score.
- Empty (nothing checked yet), running, and disconnected states draw.

## Assumptions made writing this

- Assuming checks are executed by the router rather than by the Windows client, so the client shows and triggers rather than runs.
- Assuming the design of record's "Checks" and the mock's "Evals" are the same surface under two names, since their described behaviour matches; triage should settle which word the product uses, per DESIGN.md section 6 on vocabulary.
- Assuming result history is not retained across versions, following the stated rule; if the Mac app retains it for audit, that is a difference triage should reconcile.
