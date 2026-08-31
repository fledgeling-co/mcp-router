using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Insights;

public sealed class InsightsBoardModel
{
    public InsightsPeriod SelectedPeriod { get; set; } = InsightsPeriod.Last7Days;

    public InsightsSummary GetSummary()
    {
        return new InsightsSummary(
            ChildProcesses: new HeadlineMetric("0", "Child processes at rest", "peak 4 · 11 declared"),
            ResidentMemory: new HeadlineMetric("214 MB", "Resident memory", "measured, not modelled across all children"),
            ToolCalls: new HeadlineMetric("9,418", "Tool calls served", "1,482 in the last 24 h"),
            FailedCalls: new HeadlineMetric("0.13%", "Failed calls", "12 of 9,418 · 9 were docker-mcp"),
            HarnessBreakdown: new List<HarnessAttributionRow>
            {
                new("Claude Desktop", 6820, 72.4),
                new("Cursor", 1950, 20.7),
                new("Codex", 648, 6.9),
                new("Antigravity", 0, 0.0, "Sessions use direct servers rather than this endpoint")
            }
        );
    }
}
