# Plan — WIN16: The Windows capability document panel

- status: ready-for-ai
- brief: planning/features-to-triage/WIN16-windows-capability-document-panel.md
- spec: planning/specs/spec-WIN16.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.CapabilityDocument.CapabilityDocumentModels`.
2. Implement `CapabilityDocumentPresentation` with update gate copy.
3. Implement `CapabilityDocumentViewModel` for document and delta loading.
4. Implement `CapabilityDocumentPanel.xaml` and `CapabilityDocumentPanel.xaml.cs` in `MCPRouter.Shell/Views/`.
5. Add unit tests in `MCPRouter.Shell.Tests/CapabilityDocumentPresentationTests.cs` and `CapabilityDocumentViewModelTests.cs`.
6. Verify all tests pass via `dotnet test`.
