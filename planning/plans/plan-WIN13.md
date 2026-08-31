# Plan — WIN13: The Windows Settings board

- status: ready-for-ai
- brief: planning/features-to-triage/WIN13-windows-settings-board.md
- spec: planning/specs/spec-WIN13.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Settings.SettingsModels` with sections and settings state.
2. Implement `SettingsPresentation` with section titles and honest governance copy.
3. Implement `SettingsBoardModel` with state updates.
4. Implement `SettingsBoard.xaml` and `SettingsBoard.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Mount `"settings"` destination in `ShellWindow.xaml.cs`.
6. Add unit tests in `MCPRouter.Shell.Tests/SettingsPresentationTests.cs` and `SettingsBoardModelTests.cs`.
7. Verify all tests pass via `dotnet test`.
