---
status: completed
found-by: intake, parity target for SURF-001 · 2026-08-30
reckon-sources: [SURF-030]
target-note: SURF-030 `Windows shell - NavigationView, caption band, title, menus` is this brief's surface and its own `note` field opens `WIN3.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows shell — navigation, title bar, and the command surface the Mac reaches through its menu bar

- origin: owner directive, 2026-08-30; parity target for the Mac shell
- audience: anyone running the router on Windows, who today has no client at all
- platforms: windows

## What and why

The Mac shell is a sidebar of nine boards, a window title that says what you are looking at rather
than the app's name, and a menu bar that DESIGN.md rule 9 requires to be the complete command
surface. Windows 11 has the first two and not the third, so the shell is where the directive's
"parity of feature, Windows in look" is hardest and has to be decided rather than translated.

The nine boards in the design of record are Discover, Skills, Servers, Activity, Harnesses, Checks,
Cleanup, Inbox and Insights; Settings is a tenth destination. The Windows idiom for that is a
navigation view with the boards as items, close enough to the Mac sidebar that the information
architecture carries over unchanged — which is the point of the directive.

The command surface is the open question. Every command being reachable from the menu bar is a real
guarantee on macOS: it is what makes the app keyboard-complete and inspectable. Dropping it on
Windows would lose a property rather than restyle one. The Windows options are a command bar, a
title-bar menu, or per-board command bars, and they differ in whether "every command is reachable
from one place" survives at all.

## Acceptance sketch

- The window opens with Mica, a custom title bar consistent with Windows 11, and the board list navigable by keyboard alone.
- The title says which board is shown, not the app's name — the Mac rule that is platform-neutral and worth keeping.
- All ten destinations are reachable and each draws at least an empty state; a board with nothing behind it yet says so rather than rendering blank.
- Light and dark both draw, following the Windows system setting, and changing the system theme while the app runs updates the window without a restart.
- The window survives per-monitor DPI change: dragged between a scaled and an unscaled display it re-lays out rather than blurring.
- Whatever replaces the menu bar is named, with a stated answer to whether every command is still reachable from one surface.
- The shell follows the design of record for layout and vocabulary, and the Windows floor from WIN2 for how it is drawn.

## Assumptions made writing this

- Assuming the nine boards plus Settings is the destination set, taken from the design of record's own board list rather than from the superseded prototype.
- Assuming the shell owns per-monitor DPI because it owns the window; the board briefs inherit it rather than each re-testing it.
- Assuming theme follows the system rather than offering an in-app override, matching Windows 11 convention. The Mac app's behaviour here was not checked and may differ, which triage should reconcile.
