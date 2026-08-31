# Specification — WIN15: The Windows Insights board

- status: ready-for-ai
- origin: planning/features-to-triage/WIN15-windows-insights-board.md
- surface: Windows Insights board (SURF-026 parity target)
- platforms: windows

## 1. Objective and Core Guarantees

"Every number here is counted from calls this router served — none of it is modelled."
1. Four headline metrics:
   - Processes at rest (with peak and declared counts).
   - Resident memory ("measured, not modelled across all children").
   - Tool calls served (with 24h count).
   - Failed calls percentage (with numerator/denominator and dominant contributor named).
2. Per-harness call attribution where totals agree with the headline total.
3. Explains zeroes rather than leaving bare 0s.
4. Period selection (24 hours, 7 days, 30 days).

## 2. Architecture & Data Model

- `InsightsModels`: `HeadlineMetric`, `HarnessAttributionRow`, `InsightsSummary`, `InsightsPeriod`.
- `InsightsPresentation`: Period labels and guarantee strings.
- `InsightsBoardModel`: Metric calculation and harness attribution.
- `InsightsBoard`: WinUI 3 XAML view displaying headline tiles and breakdown table.

## 3. Test Coverage

- `InsightsPresentationTests`: Period label tests.
- `InsightsBoardModelTests`: Metric denominator presence and zero explanation tests.
