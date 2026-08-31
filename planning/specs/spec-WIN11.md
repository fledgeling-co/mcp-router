# Specification — WIN11: The Windows ambient surface (notification area & flyout)

- status: ready-for-ai
- origin: planning/features-to-triage/WIN11-windows-notification-area-icon-and-flyout.md
- surface: Windows ambient notification area surface (SURF-009 parity target)
- platforms: windows

## 1. Objective

Provide ambient router state without requiring the user to foreground the main application:
1. Distinguishes 4 distinct states:
   - At rest (all systems quiet)
   - Working (active tool calls in flight)
   - Something waiting (inbox items queued from phone)
   - Cannot reach router (offline/disconnected)
2. Displays actionable flyout with router state, queued count, and quick navigation to Inbox / Servers.
3. Accessible and keyboard-navigable.

## 2. Architecture & Data Model

- `AmbientModels`: `AmbientRouterState`, `AmbientStatusInfo`.
- `AmbientPresentation`: State titles, subtitles, and tray tooltips.
- `AmbientSurfaceModel`: Tracks router state, active calls, and waiting counts.
- `AmbientFlyoutView`: Compact WinUI 3 flyout view with status indicators and navigation actions.

## 3. Test Coverage

- `AmbientPresentationTests`: Verifies state titles, tooltips, and pluralized status details.
- `AmbientSurfaceModelTests`: Tests state transitions and status info generation.
