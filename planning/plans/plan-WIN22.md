# Plan — WIN22: Windows toast notifications for waiting decisions

- status: ready-for-ai
- brief: planning/features-to-triage/WIN22-windows-toast-notifications-for-waiting-decisions.md
- spec: planning/specs/spec-WIN22.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Notifications.NotificationModels`.
2. Implement `NotificationPresentation` with safe payload builders.
3. Add unit tests in `MCPRouter.Shell.Tests/NotificationPresentationTests.cs`.
4. Verify all tests pass via `dotnet test`.
