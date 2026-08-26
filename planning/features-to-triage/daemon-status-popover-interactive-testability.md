# Background Status Item and Popover Accessible Testability

- origin: test-campaign unmeasured cases and reckoning findings · 2026-08-25
- audience: Automated test harnesses and developers verifying background status presentation
- platforms: mac
- proposed-by-ai: false

## What and why
Automated test harnesses can inspect and actuate the menu bar status item, inbox arrival badge, and quick-access popover without requiring foreground window focus or manual screen interaction. The test campaign currently leaves background status interactions unmeasured because background menu extras refuse synthetic press events without stealing user focus. Providing standard accessible actions on the status item enables full verification of notification counts and attention states.

## Acceptance sketch
- The menu bar status item exposes standard accessibility actions that allow programmatic triggering of the popover.
- The popover contents and inbox badge counts can be inspected while the host application remains in the background.
- Dismissing the popover returns the status item to its idle appearance without leaving lingering window handles.
- Automated tests can verify attention indicators and unread counts without raising the main application window.

## Assumptions made writing this
- Assuming accessibility element actions should be exposed natively rather than requiring simulated global mouse clicks.
- Assuming test automation drives existing system accessibility APIs rather than building a custom sidecar test protocol.
