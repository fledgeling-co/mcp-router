---
status: to-triage
found-by: intake, parity target for SURF-011 · 2026-08-30
registry-target: none
no-target-reason: SURF-011 registers the macOS Settings board and the registry holds no Windows equivalent, so no recorded case could witness the Windows one
---

# The Windows Settings board — seven panes, in Windows 11 settings idiom

- origin: owner directive, 2026-08-30; parity target for the Mac Settings board
- audience: anyone on Windows configuring the router
- platforms: windows

## What and why

The design of record carries seven settings panes: Router, Harnesses, Session analyst, Updates,
Security, Menu bar, and Advanced. Six of those transfer directly. The seventh does not: **Menu bar**
is named for an affordance Windows does not have, so it becomes the settings for whatever WIN11
decides the ambient surface is, and is renamed accordingly.

Settings is also where the largest idiom gap sits. DESIGN.md rule 6 pins the macOS control
vocabulary precisely — pop-up buttons versus pull-downs, checkbox for an independent setting, radio
for an exclusive set, switch for an emphasized group toggle. Windows 11 settings use a different
default: toggle switches for most binary settings, where macOS would use a checkbox. Following the
Mac rule literally on Windows would produce a surface that reads as foreign, and following Windows
convention means departing from a rule DESIGN.md calls a defect to violate. This is exactly what
WIN2 exists to resolve, and Settings is the surface that most needs the answer.

Two settings carry more weight than the rest and should be treated as behaviour rather than
preference: anything under Security, and the update policy under Updates, which governs the
held-for-review guarantee that WIN6 depends on.

## Acceptance sketch

- All seven panes exist and are reachable, with the menu-bar pane renamed to match whatever WIN11 built.
- Every setting persists across a restart of the app.
- Controls follow the Windows floor from WIN2 rather than the macOS control vocabulary, and the mapping is recorded.
- Security settings are not weakened by default relative to the Mac app; any difference is deliberate and recorded.
- The update policy governing held-for-review is settable and its effect on WIN6 is visible.
- Where a setting cannot apply on Windows, the pane says so rather than showing a dead control.
- Disconnected state draws — settings that require the router say what is unavailable.

## Assumptions made writing this

- Assuming settings live in the app's own navigation as a tenth destination rather than a separate window, matching Windows 11 convention where most apps have in-app settings.
- Assuming settings are stored per user rather than per machine, matching Windows convention for a user-facing app.
- Assuming no setting written by this surface reaches a harness config file directly, following the constraint the Mac client is held to.
