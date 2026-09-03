---
status: to-triage
found-by: intake, parity target for SURF-005 · 2026-08-30
reckon-sources: [SURF-034, SURF-044]
target-note: SURF-034 `Windows Discover board` carries `note: WIN7.` and SURF-044 `Windows Discover detail dialog` opens `WIN7's detail dialog`; neither row existed when the `none` was declared on 2026-08-30.
---
# The Windows Discover board — two bands, because editorial and measured are different claims

- origin: owner directive, 2026-08-30; parity target for the Mac Discover board
- audience: anyone on Windows looking for a capability they do not already have
- platforms: windows

## What and why

Discover answers "what is worth my attention that I don't already have?" The mock is unusually
explicit about why it is shaped as it is, and both reasons are guarantees rather than layout
preferences — so a Windows reimplementation that restyles them away regresses the product.

**Two bands, never one list.** The mock: "Two bands, because editorial and measured are different
claims and a single ranked list has to pretend one is the other. Trending carries a window and a
signed delta; without both it is just 'popular' in a different font." So Featured and Trending are
separate, and a trending row that cannot show its window and its signed delta must not be drawn as
trending.

**No install button on a row.** The mock again: "Rows do not carry an install button: one tap from a
gameable ranking to executing someone's code is the affordance the adversary wants. You open it, and
you install from the detail." This is a security property. Windows 11's card and list idioms invite
an inline primary action, so the pressure to add one here is real and must be resisted.

The named worst state is a rate-limited or unreachable registry, which has to draw as itself rather
than as an empty catalogue — an empty list and a failed fetch are different facts.

## Acceptance sketch

- Featured and Trending render as separate bands and are never merged into one ranked list.
- Every trending row carries both its window and a signed delta; a row lacking either is not shown as trending.
- No row carries an install action. Opening a row reaches a detail surface, and installation is only available from there.
- Browse by category reaches a filtered view.
- A rate-limited or unreachable registry draws as that, distinctly from "nothing found".
- Empty, loading and disconnected states all draw.

## Assumptions made writing this

- Assuming Discover is a board in the Windows shell's navigation, matching the design of record's sidebar, even though the console mock renders no Discover panel of its own.
- Assuming the registry search route `GET /registry/search` on the control API is the data source.
- Assuming the detail surface reached from a row is the capability document panel briefed in WIN16 rather than a separate Discover-only view.
