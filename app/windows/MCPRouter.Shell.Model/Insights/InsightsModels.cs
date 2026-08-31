using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Insights;

public enum InsightsPeriod
{
    Last24Hours,
    Last7Days,
    Last30Days
}

public sealed record HeadlineMetric(
    string Value,
    string Label,
    string DenominatorOrProvenance,
    string? ContextNote = null
);

public sealed record HarnessAttributionRow(
    string HarnessName,
    int CallCount,
    double Percentage,
    string? Explanation = null
);

public sealed record InsightsSummary(
    HeadlineMetric ChildProcesses,
    HeadlineMetric ResidentMemory,
    HeadlineMetric ToolCalls,
    HeadlineMetric FailedCalls,
    IReadOnlyList<HarnessAttributionRow> HarnessBreakdown
);
