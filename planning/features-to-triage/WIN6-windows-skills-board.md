---
status: to-triage
found-by: intake, parity target for SURF-004 · 2026-08-30
reckon-sources: [SURF-033]
target-note: SURF-033 `Windows Skills board` carries `note: WIN6.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows Skills board — one skill, every harness, and the slots that say where it is live

- origin: owner directive, 2026-08-30; parity target for the Mac Skills board
- audience: anyone on Windows managing skills across more than one AI harness
- platforms: windows

## What and why

The design of record calls Skills "the half of this that is not MCP", and names the problem it
solves: "One skill can be live in two harnesses and absent from three; the slots say which, and
installing into another is one press."

It is the largest board in the design of record by content. The table carries Skill, Marketplace,
Version, Installed into, and Auto-update, where *Installed into* is a row of per-harness slots
(`CC · CU · GR · CX`) rather than a single value — that compression is the board's whole idea and is
the part most easily lost in a reimplementation. The head carries counts (`Installed · 38`,
`Marketplaces · 3`, `Updates · 4`) and the actions `Run doctor`, `Add marketplace...` and
`Update all · 4`.

It also carries the **held-for-review** state, which is a product guarantee rather than a
decoration. The design of record shows `design-review 2.4.0 is held for review — the new version
asks for network access the installed one never had. It is downloaded, not live.` A skill that asks
for more than the installed version does not update silently; it waits. Getting that wrong on
Windows would not be a visual defect, it would be a security regression, so the held state is an
acceptance item rather than a styling detail.

## Acceptance sketch

- The table lists installed skills with their marketplace, version and auto-update setting.
- The per-harness slots show where each skill is live and where it is absent, and installing into another harness is one action.
- A held update draws as held, says what additional permission the new version asks for, and does not become live until the user acts.
- `See what changed...` opens the capability diff rather than committing an update.
- `Update all` acts on the updatable set and does not silently include held items.
- `Run doctor` and `Add marketplace...` both reach their surfaces.
- Empty (no skills installed), disconnected, and no-marketplaces states draw.

## Assumptions made writing this

- Assuming the harness slot set is discovered per machine rather than fixed at four, since the Windows harness set will differ from the Mac's.
- Assuming the capability diff opened by `See what changed...` is the panel briefed in WIN16 rather than a separate view.
- Assuming skill installation goes through the router's control API rather than the Windows client writing harness config files directly, which the repo's lint rules forbid on the Mac side.
