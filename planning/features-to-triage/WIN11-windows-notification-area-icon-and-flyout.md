---
status: to-triage
found-by: intake, parity target for SURF-009, which has no literal Windows equivalent · 2026-08-30
reckon-sources: [SURF-041, SURF-050]
target-note: SURF-041 `Windows ambient surface - notification-area flyout` carries `note: WIN11.` and SURF-050 `Windows ambient status readout - the navigation pane footer` names SURF-041 as the surface WIN11 described; neither row existed when the `none` was declared on 2026-08-30.
---
# The always-available Windows surface that answers what the Mac menu-bar popover answers

- origin: owner directive, 2026-08-30; parity target for the Mac menu-bar popover
- audience: anyone on Windows who wants router state without switching to the app
- platforms: windows

## What and why

The Mac carries a menu-bar popover, shown in the mock as "at rest, and with something waiting" — an
ambient surface that says whether the router is healthy and whether anything is queued, reachable
without bringing the app forward. It also carries the inbox band, which is how a queued item
announces itself.

**Windows has no menu bar, so this is a design question rather than a port.** The nearest idiom is a
notification-area icon with a flyout, and that is the obvious candidate, but it differs from the
macOS original in ways that matter and should be decided rather than discovered:

- Windows 11 hides notification-area icons by default behind the overflow chevron. An ambient
  surface the user must first unhide is not ambient. Whether the app may promote itself, and whether
  it should ask, is a real question.
- The macOS popover is a rich surface. A notification-area flyout is conventionally smaller and more
  transient, so the popover's content may need to be re-cut rather than rescaled.
- Windows has a second, genuinely native channel for "something is waiting" that macOS's menu bar
  does not: toast notifications and taskbar badging. That is WIN22, and it may carry part of what
  the inbox band carries on the Mac.

Because the registry has no surface for this, the risk is that it is quietly dropped and Windows
ships without an ambient surface at all — parity lost in a way no gate would catch.

## Acceptance sketch

- An ambient surface exists that reports router state without the main window being open or focused.
- It distinguishes at rest, working, something waiting, and cannot-reach-the-router.
- Opening it reaches the queued items, and from there the review sheet, without bypassing WIN10's rule that nothing installs before approval.
- Its behaviour when Windows hides the icon in the overflow area is decided and stated, rather than left to chance.
- It is keyboard reachable and exposed to assistive technology, not mouse-only.
- The choice of idiom is recorded with what the alternatives would have been better at.

## Assumptions made writing this

- Assuming a notification-area icon with a flyout is the leading candidate, without settling it — the alternatives are a taskbar-badged window, a toast-only model, or a Windows widget.
- Assuming the inbox band's job can be split between this surface and toast notifications, rather than requiring one surface to carry both.
- Assuming an always-running background presence is acceptable on Windows; if the app is not to run at login, this surface's value changes and WIN23 becomes its precondition.
