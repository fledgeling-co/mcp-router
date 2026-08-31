# Specification — WIN19: Windows packaging and distribution

- status: ready-for-ai
- origin: planning/features-to-triage/WIN19-windows-packaging-and-distribution.md
- platforms: windows

## 1. Objective and Packaging Model

1. Clean installation and uninstallation model on Windows 11.
2. Distribution via Windows Package Manager (`winget`) and MSIX.
3. Explicit SmartScreen disclosure for unsigned/development builds vs signed releases.
4. Uninstall preserves user configuration in `%USERPROFILE%\.claude\mcp-router` while removing application binaries.

## 2. Architecture & Data Model

- `PackagingModels`: `PackagingContract`, `DistributionChannel`.
- `PackagingPresentation`: Identity strings, channel descriptions, and SmartScreen guidance.

## 3. Test Coverage

- `PackagingPresentationTests`: Verifies channel naming and uninstall disclosure strings.
