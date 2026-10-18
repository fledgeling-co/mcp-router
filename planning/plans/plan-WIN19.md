# Plan — WIN19: Windows packaging and distribution

- status: ready-for-ai
- brief: planning/features-to-triage/WIN19-windows-packaging-and-distribution.md
- spec: planning/specs/spec-WIN19.md

## Implementation Plan

1. Implement `MCPRouter.Shell.Model.Packaging.PackagingModels`.
2. Implement `PackagingPresentation` with identity and channel metadata.
3. Add unit tests in `MCPRouter.Shell.Tests/PackagingPresentationTests.cs`.
4. Verify all tests pass via `dotnet test`.
