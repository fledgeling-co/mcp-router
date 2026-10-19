---
status: completed
found-by: intake, parity target for SURF-025 · 2026-08-30
reckon-sources: [SURF-039]
target-note: SURF-039 `Windows Harnesses board` carries `note: WIN14.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows Harnesses board — which AI tools on this PC actually route through here

- origin: owner directive, 2026-08-30; parity target for the Mac Harnesses board
- audience: anyone on Windows who has pointed a harness at the router and wants to know whether it worked
- platforms: windows

## What and why

The design of record states the board's point sharply: "Which AI tools on this Mac actually route
through here. Pointing a harness at the endpoint is the easy half; the half that saves anything is
noticing it still spawns its own copies."

That second half is the feature. The mock's worked example is Antigravity, which "runs 18 servers of
its own, ten of which this router already fronts" and "reaches the router through a per-session shim
as well, so those sessions pay both costs at once." Detecting *double-running* is what the board is
for, and it is the part most easily lost in a reimplementation that only checks whether a config
line exists.

Per harness the design of record shows the config path and version (`~/.claude.json · v2.1.204`),
routing status, entry and duplicate counts, tools reachable, processes at rest, and `Open config`,
`Verify now` and a last-verified stamp. Board actions are `Rescan` and `Reconcile all...`.

**This board is the most Windows-specific of the thirteen**, because everything it reads is a path.
`~/.claude.json` is `%USERPROFILE%\.claude.json`; Cursor, Codex and the rest each have their own
Windows locations; and the Windows harness set is not the same as the Mac's — some of the five in
the mock may not exist on Windows at all, and others may exist only on Windows. That inventory is
unmeasured today and is part of this work rather than an input to it.

## Acceptance sketch

- Harnesses installed on this PC are detected by their real Windows config locations, and the inventory is discovered rather than assumed from the Mac list.
- Each detected harness shows its config path, version, routing status, entry and duplicate counts, tools reachable, and processes at rest.
- Double-running is detected and named: a harness routing through the router *and* spawning its own copies is reported as such, with the overlap counted.
- `Show the diff...` reaches a view of what overlaps.
- `Verify now` re-checks a single harness and updates its stamp; `Rescan` re-checks all.
- `Open config` reveals the file in Explorer rather than editing it in place.
- A harness that is installed but not routed, and one that is absent entirely, read differently.
- Empty (no harnesses detected) and disconnected states draw.

## Assumptions made writing this

- Assuming the Windows harness inventory has to be established as part of this work, since no measurement of it exists in the repo.
- Assuming the board reads harness configs and does not write them, following the rule the Mac client is held to; reconciliation that writes is a separate decision.
- Assuming the on-surface phrase "on this Mac" becomes the Windows equivalent, which is a vocabulary change DESIGN.md section 6 governs.
