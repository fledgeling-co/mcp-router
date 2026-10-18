# Plan — WIN15: The Windows Insights board

- status: ready-for-ai
- brief: planning/features-to-triage/WIN15-windows-insights-board.md
- spec: planning/specs/spec-WIN15.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Insights.InsightsModels` with metrics and breakdown rows.
2. Implement `InsightsPresentation` with copy rules.
3. Implement `InsightsBoardModel` with headline metrics and harness data.
4. Implement `InsightsBoard.xaml` and `InsightsBoard.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Mount `"insights"` destination in `ShellWindow.xaml.cs`.
6. Add unit tests in `MCPRouter.Shell.Tests/InsightsPresentationTests.cs` and `InsightsBoardModelTests.cs`.
7. Verify all tests pass via `dotnet test`.
