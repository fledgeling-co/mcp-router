# Plan — WIN10: The Windows Inbox board and review sheet

- status: ready-for-ai
- brief: planning/features-to-triage/WIN10-windows-inbox-board-and-review-sheet.md
- spec: planning/specs/spec-WIN10.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Inbox.InboxModels` with decision states, capability lines, and item records.
2. Implement `InboxPresentation` with device provenance and conditional capability formatting.
3. Implement `InboxBoardModel` with state filtering and approve/decline operations.
4. Implement `InboxBoard.xaml` and `InboxBoard.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Mount `"inbox"` destination in `ShellWindow.xaml.cs`.
6. Add unit tests in `MCPRouter.Shell.Tests/InboxPresentationTests.cs` and `InboxBoardModelTests.cs`.
7. Verify all tests pass via `dotnet test`.
