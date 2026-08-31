# Plan — WIN9: The Windows Cleanup board

- status: ready-for-ai
- brief: planning/features-to-triage/WIN9-windows-cleanup-board.md
- spec: planning/specs/spec-WIN9.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Cleanup.CleanupModels` with candidacy results and data records.
2. Implement `CleanupPresentation` with server/skill candidacy evaluation and exact design-of-record copy.
3. Implement `CleanupBoardModel` for table data management and multi-select handling.
4. Implement `CleanupBoard.xaml` and `CleanupBoard.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Mount `"cleanup"` destination in `ShellWindow.xaml.cs`.
6. Add unit tests in `MCPRouter.Shell.Tests/CleanupPresentationTests.cs` and `CleanupBoardModelTests.cs`.
7. Verify all tests pass via `dotnet test`.
