# Plan — WIN23: Router lifecycle on Windows

- status: ready-for-ai
- brief: planning/features-to-triage/WIN23-router-lifecycle-on-windows.md
- spec: planning/specs/spec-WIN23.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Lifecycle.LifecycleModels`.
2. Implement `LifecyclePresentation` with user-session and supervision copy.
3. Add unit tests in `MCPRouter.Shell.Tests/LifecyclePresentationTests.cs`.
4. Verify all tests pass via `dotnet test`.
