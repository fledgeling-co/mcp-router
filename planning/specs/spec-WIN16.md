# Specification — WIN16: The Windows capability document panel and update gate

- status: ready-for-ai
- origin: planning/features-to-triage/WIN16-windows-capability-document-panel.md
- surface: Windows capability document panel (SURF-028 parity target)
- platforms: windows

## 1. Objective and The Update Gate

1. Three tabs over one package: Capabilities, Changelog, and Flags worth knowing.
2. The Update Gate ("Capability diff before content diff"):
   - When an update introduces new capabilities, it lands as a shadow copy and stops for review.
   - The capability delta is presented first in plain conditional language before any code or content diff.
   - User can Approve and promote, or Keep current version.
3. Reached from Discover, Skills, and Inbox as a single shared panel.

## 2. Architecture & Data Model

- `CapabilityDocumentModels`: `CapabilityDocument`, `CapabilityDiffItem`, `CapabilityDocumentTab`.
- `CapabilityDocumentPresentation`: Gate headlines, explanations, and action labels.
- `CapabilityDocumentViewModel`: Loads package details and capability diffs.
- `CapabilityDocumentPanel`: WinUI 3 XAML view displaying update gate banner and tabs.

## 3. Test Coverage

- `CapabilityDocumentPresentationTests`: Tab names and gate copy tests.
- `CapabilityDocumentViewModelTests`: Document loading and capability delta presence tests.
