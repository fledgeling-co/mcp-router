# Specification — WIN10: The Windows Inbox board and review sheet

- status: ready-for-ai
- origin: planning/features-to-triage/WIN10-windows-inbox-board-and-review-sheet.md
- surface: Windows Inbox board (SURF-008 parity target)
- platforms: windows

## 1. Objective and Core Safety Property

"The phone queues, it never installs."
1. Items queued from an iPhone appear in the Inbox in an undecided state.
2. Nothing is downloaded, executed, or configured into any harness prior to explicit user approval on the desktop.
3. Review cards state "What it would be able to do" in plain, conditional language.
4. User can Approve and install, or Decline ("Not for me").
5. State grouping: Undecided, Approved, Not for me.

## 2. Architecture & Data Model

- `InboxModels`: `InboxItem`, `InboxCapabilityLine`, `DecisionState`, `InboxOriginKind`.
- `InboxPresentation`: Formats subtitles, tab labels, empty state messages, and capability descriptions.
- `InboxBoardModel`: Tracks queue items, counts by decision state, and transitions items between states.
- `InboxBoard`: WinUI 3 XAML view displaying header with device info, filter tabs, and capability review cards.

## 3. Test Coverage

- Unit tests in `InboxPresentationTests` testing device subtitle formatting, tab labels, and copy alignment.
- Unit tests in `InboxBoardModelTests` testing queue population, approvals, and declines.
