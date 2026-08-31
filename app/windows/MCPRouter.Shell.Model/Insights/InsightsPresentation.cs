using System;

namespace MCPRouter.Shell.Model.Insights;

public static class InsightsPresentation
{
    public const string Title = "Insights";
    public const string BoardDescription = "What your agents actually used, and what the analyst found in your own session logs. Every number here is counted from calls this router served — none of it is modelled.";

    public static string PeriodLabel(InsightsPeriod period)
    {
        return period switch
        {
            InsightsPeriod.Last24Hours => "Last 24 hours",
            InsightsPeriod.Last7Days => "Last 7 days",
            InsightsPeriod.Last30Days => "Last 30 days",
            _ => period.ToString()
        };
    }
}
