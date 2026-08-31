# Plan — WIN11: The Windows ambient surface

- status: ready-for-ai
- brief: planning/features-to-triage/WIN11-windows-notification-area-icon-and-flyout.md
- spec: planning/specs/spec-WIN11.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Ambient.AmbientModels` with router states and status structures.
2. Implement `AmbientPresentation` with status text and tooltips across the 4 states.
3. Implement `AmbientSurfaceModel` for state tracking.
4. Implement `AmbientFlyoutView.xaml` and `AmbientFlyoutView.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Add unit tests in `MCPRouter.Shell.Tests/AmbientPresentationTests.cs` and `AmbientSurfaceModelTests.cs`.
6. Verify all tests pass via `dotnet test`.
