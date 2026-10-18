---
status: to-triage
found-by: intake, parity target for SURF-003 · 2026-08-30
reckon-sources: [SURF-032]
target-note: SURF-032 `Windows Activity board - the live call log` is the surface this brief specifies, registered on lane `windows-glass` at `app://windows/shell#activity` after the `none` was declared on 2026-08-30. The row carries no `WIN5` back-reference, so this citation rests on subject identity between the brief's title and the surface's, not on the registry naming the brief.
---
# The Windows Activity board — every tool call every harness made, as it happens

- origin: owner directive, 2026-08-30; parity target for the Mac Activity board
- audience: anyone on Windows debugging which of their agents did something
- platforms: windows

## What and why

The design of record states the board's job plainly: "Every tool call every harness made, as it
happens. This is the only place that can answer 'which of my agents did that'." That question is the
whole value, and it is unanswerable on Windows today because there is no client.

The surface is a live log with five columns — Time, Harness, Tool, Duration, Result — a `Pause`
control, an `Export...` action, a result filter (`All`, `Errors`, `Slow (> 2 s)`, `Held`) and a
per-harness tally down the side (`Claude Code · 948`, `Cursor · 311`, and so on). Results seen in the
design of record include `ok`, `timeout` and a held state.

Two properties matter more than the layout. It is **live**, so the Windows implementation needs a
streaming source rather than a poll — `GET /usage/stream` exists on the control API and is the
obvious candidate. And it is **dense**: DESIGN.md section 1 chose a light ground precisely because
an activity log is one of the densest reading surfaces here, so this board is a direct test of
whether the Windows palette preserves that reasoning. Tool names are the kind of thing a user pastes
into a terminal, which under DESIGN.md section 2 reserves monospace for them.

## Acceptance sketch

- Calls appear as they happen without a manual refresh, and `Pause` freezes the view without dropping the calls that arrive while paused.
- All four filters narrow the list, and the per-harness tallies agree with the rows shown.
- Durations render in the design of record's units, and a slow call is distinguishable from a fast one at a glance.
- `ok`, `timeout` and held results are each distinct without relying on hue alone.
- `Export...` opens a further view rather than writing a file immediately, per the ellipsis convention.
- The board stays responsive with a long history behind it; a session with thousands of calls scrolls rather than stalls.
- Empty (no calls yet) and disconnected (router unreachable) states both draw.

## Assumptions made writing this

- Assuming the live source is `GET /usage/stream` rather than polling `GET /usage`, since a streaming route already exists and polling would miss calls between polls.
- Assuming the harness list is discovered rather than hardcoded, since which harnesses exist is a property of the machine and the Windows set will differ from the Mac's.
- Assuming history retention matches the Mac app's; that value was not read from here and triage should pin it.
