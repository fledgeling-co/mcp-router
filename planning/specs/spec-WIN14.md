# Specification — WIN14: The Windows Harnesses board

- status: ready-for-ai
- origin: planning/features-to-triage/WIN14-windows-harnesses-board.md
- surface: Windows Harnesses board (SURF-025 parity target)
- platforms: windows

## 1. Objective and Core Commitments

1. Discover AI harnesses installed on this Windows PC (%USERPROFILE%\.claude.json, Cursor, VS Code, etc.).
2. Detect double-running: A harness configured to route through the router while simultaneously running duplicate direct stdio servers.
3. Present config paths, routing state, duplicate counts, and bridge mechanisms.
4. "Open config" action reveals the configuration in Explorer.

## 2. Architecture & Data Model

- `HarnessModels`: `DetectedHarness`, `HarnessReading`, `HarnessTransport`, `HarnessDuplicate`.
- `HarnessPresentation`: State labels and double-running warnings.
- `HarnessesBoardModel`: Discovers local harnesses and flags duplicates.
- `HarnessesBoard`: WinUI 3 XAML view rendering harness status cards.

## 3. Test Coverage

- `HarnessPresentationTests`: Tests state labels and warning plurals.
- `HarnessesBoardModelTests`: Tests local harness discovery and duplicate detection.
