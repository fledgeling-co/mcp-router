# Plan — WIN12: Pairing an iPhone to the Windows client

- status: ready-for-ai
- brief: planning/features-to-triage/WIN12-windows-pairing-sheet.md
- spec: planning/specs/spec-WIN12.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Pairing.PairingModels` with pairing phases and refusal reasons.
2. Implement `PairingPresentation` with copy and firewall warning strings.
3. Implement `PairingSessionModel` with state management.
4. Implement `PairingDialog.xaml` and `PairingDialog.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Add unit tests in `MCPRouter.Shell.Tests/PairingPresentationTests.cs` and `PairingSessionModelTests.cs`.
6. Verify all tests pass via `dotnet test`.
