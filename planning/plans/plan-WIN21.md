# Plan — WIN21: The Windows keyboard model

- status: ready-for-ai
- brief: planning/features-to-triage/WIN21-windows-keyboard-model.md
- spec: planning/specs/spec-WIN21.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Keyboard.KeyboardModels` with destination shortcuts.
2. Implement `KeyboardPresentation` with shortcut lookups.
3. Add unit tests in `MCPRouter.Shell.Tests/KeyboardPresentationTests.cs`.
4. Verify all tests pass via `dotnet test`.
