---
status: to-triage
found-by: intake, parity target for SURF-007 · 2026-08-30
registry-target: none
no-target-reason: SURF-007 registers the macOS Cleanup board and the registry holds no Windows equivalent, so no recorded case could witness the Windows one
---

# The Windows Cleanup board — states its window, and never calls anything rubbish

- origin: owner directive, 2026-08-30; parity target for the Mac Cleanup board
- audience: anyone on Windows wondering what is installed that they no longer need
- platforms: windows

## What and why

Cleanup answers "what is here that shouldn't be?" and the design of record is careful about how it
is allowed to answer: "Nothing is removed automatically and nothing is called rubbish — a server
nobody has called might be worthless, or might be the one that matters twice a year."

Three properties carry the board, and each is a stated commitment rather than a layout choice:

- **It states the window it judges over** (`Unused for 30 days`), because, in the mock's words,
  "'never used' across four days of history is not evidence of anything."
- **Every row carries the reason it might legitimately be idle.** The design of record gives the
  column the header *Why it might still matter*. A rarely-used migration skill is not a cull
  candidate, and presenting it as one "loses trust once and never gets it back."
- **It re-checks the upstream before offering to remove anything**, because a dormant capability is
  precisely the one nothing else re-examines.

It also corrects the user's likely reason for being there: under the router an unused server costs
cached schema and nothing else — no process, no memory, no start-up — so the reason to remove one is
tool-list clutter or lost trust, and not disk space. That framing is on the surface and is part of
what the board is.

Removal is destructive and irreversible from the user's point of view, so the Windows implementation
inherits DESIGN.md rule 4: destructive is never the default action.

## Acceptance sketch

- The judging window is stated on the surface and is adjustable rather than hardcoded.
- Every row shows why the capability might still legitimately be idle, alongside its kind, tool count and install date.
- Nothing is removed automatically, and no row is labelled as rubbish, junk or waste.
- Before removal is offered, the upstream is re-checked, and the result of that re-check is visible.
- Removal is confirmed, is never the default action, and says exactly what will be removed.
- A history too short for the stated window says so instead of reporting everything as never called.
- Empty (nothing unused), disconnected, and upstream-unreachable states draw.

## Assumptions made writing this

- Assuming removal goes through the control API rather than the Windows client deleting files, matching how the Mac client is constrained.
- Assuming the 30-day default carries over from the design of record rather than being re-chosen for Windows.
- Assuming "capability" spans both MCP servers and skills here, since the design of record's Kind column distinguishes them within one table.
