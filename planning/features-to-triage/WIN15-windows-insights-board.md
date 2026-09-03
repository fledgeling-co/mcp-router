---
status: to-triage
found-by: intake, parity target for SURF-026 · 2026-08-30
reckon-sources: [SURF-040]
target-note: SURF-040 `Windows Insights board` carries `note: WIN15.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows Insights board — counted from calls this router served, never modelled

- origin: owner directive, 2026-08-30; parity target for the Mac Insights board
- audience: anyone on Windows who wants to know what their agents actually used
- platforms: windows

## What and why

Insights shows "what your agents actually used, and what the analyst found in your own session
logs", and it carries a stated guarantee: "Every number here is counted from calls this router
served — none of it is modelled."

The design of record shows four headline figures, each with its denominator or its provenance
alongside: child processes at rest (`0`, peak 4, 11 declared); resident memory across all children
(`214 MB`, marked *measured, not modelled*); tool calls over seven days (`9,418`, with 1,482 in the
last 24 h); and failed calls (`0.13%`, expanded as `12 of 9,418 · 9 were docker-mcp`). Below that,
where calls came from, per harness. There is a period selector (`Last 7 days`) and an `Analyse now`
action.

The pattern is consistent and is the board's discipline: **no figure appears without what it is a
figure of**. A percentage carries its numerator and denominator; a memory number says it was
measured; a zero says why it is zero — the design of record explains Antigravity's zero as "its
sessions still use their own eighteen servers rather than this endpoint" rather than leaving a bare
0. A Windows implementation that renders these as bare stat tiles would lose the property that makes
the board trustworthy.

One figure needs a Windows answer rather than a port: resident memory across child processes is read
differently on Windows, and "measured, not modelled" has to stay true of however it is obtained.

## Acceptance sketch

- All four headline figures render, each with its denominator or provenance shown, not as bare numbers.
- The failure percentage shows its numerator and denominator and names the dominant contributor.
- Resident memory is genuinely measured on Windows, and the label saying so is accurate.
- A zero is explained rather than left bare, where the reason is known.
- Per-harness call attribution renders and its total agrees with the headline call count.
- The period selector changes the window and every figure updates with it.
- Empty (no calls yet, or a window with no data) and disconnected states draw, and an empty window is distinguishable from a zero.

## Assumptions made writing this

- Assuming figures come from the existing `GET /usage/summary` route rather than being computed in the client, which would risk a client-side number diverging from the router's.
- Assuming the session analyst runs in the router and the client triggers and displays it.
- Assuming the seven-day default and the available periods carry over from the design of record rather than being re-chosen.
