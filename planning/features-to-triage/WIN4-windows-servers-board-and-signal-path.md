---
status: to-triage
found-by: intake, parity target for SURF-002 · 2026-08-30
reckon-sources: [SURF-031]
target-note: SURF-031 `Windows Servers board and the Signal Path` carries `note: WIN4.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows Servers board, including the Signal Path — the one loud surface in the product

- origin: owner directive, 2026-08-30; parity target for the Mac Servers board
- audience: anyone on Windows who wants to see which MCP servers their agents can actually reach
- platforms: windows

## What and why

Servers is the board the product exists for. The design of record states its purpose on the surface
itself: "Every MCP server your agents can reach. A jack lights the instant something calls it, and
goes dark when the reaper closes the child. Nothing here is running because it was declared."

It carries two things. A table of declared servers with a live state each — the design of record
shows `awake`, `dormant`, `held`, `tripped` and `needs sign-in`, with awake entries counting down
their idle time. And above it the **Signal Path**: a lane of jacks reading `5 harnesses -> 1
endpoint -> 11 upstreams`, which DESIGN.md section 1 names as the signature element and "the only
loud thing in the app". Its geometry is specified in DESIGN.md under `Signal Path geometry`, and
that specification is written in macOS metrics.

This is the surface where the directive's split bites hardest. The Signal Path is not a stock
control on any platform — it is drawn — so it is the one place where "apply modern Windows 11
aesthetic" cannot mean "use the system control". It must be redrawn to the Windows floor while
staying recognisably the same instrument, and its published geometry has to be restated in
effective pixels rather than points.

Two board actions sit in the head: `Reap idle` and `Add server...`. The trailing ellipsis is
load-bearing per DESIGN.md rule 4 — it means the control opens a further view rather than committing
— and that convention is shared with Windows, so it carries over unchanged.

## Acceptance sketch

- The board lists every declared server with its live state, and a state changes without a manual refresh when the router changes it.
- All five states draw distinctly, including `tripped` and `needs sign-in`, and each is distinguishable without relying on hue alone.
- The Signal Path draws, counts harnesses, endpoints and upstreams correctly, and a jack lights on a real call and darkens when the child is reaped.
- Idle countdowns tick and are legible; a server at rest reads as at rest rather than as broken.
- `Reap idle` acts, and `Add server...` opens a further view rather than committing, matching the ellipsis convention.
- The empty state (nothing declared) and the disconnected state (router unreachable) both draw, per DESIGN.md section 5.
- The Signal Path's geometry is restated for Windows in the design authority rather than being eyeballed from the macOS numbers.

## Assumptions made writing this

- Assuming the Signal Path is kept on Windows rather than replaced by a table column, since DESIGN.md calls it the signature element and the directive asks for parity.
- Assuming the five states in the design of record are the complete set; the Swift implementation was not read from here and may carry more.
- Assuming server state arrives over the existing control API rather than needing a new route, since `GET /servers` already exists.
