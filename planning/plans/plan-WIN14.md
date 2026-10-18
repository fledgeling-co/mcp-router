# Plan — WIN14: The Windows Harnesses board

- status: ready-for-ai
- brief: planning/features-to-triage/WIN14-windows-harnesses-board.md
- spec: planning/specs/spec-WIN14.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Harnesses.HarnessModels` with harness states and duplicate structures.
2. Implement `HarnessPresentation` with formatting for double-running warnings.
3. Implement `HarnessesBoardModel` with Windows harness discovery.
4. Implement `HarnessesBoard.xaml` and `HarnessesBoard.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Mount `"harnesses"` destination in `ShellWindow.xaml.cs`.
6. Add unit tests in `MCPRouter.Shell.Tests/HarnessPresentationTests.cs` and `HarnessesBoardModelTests.cs`.
7. Verify all tests pass via `dotnet test`.
