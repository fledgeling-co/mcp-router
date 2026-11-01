using System;
using System.Globalization;

namespace MCPRouter.Shell.Model.Insights;

public static class InsightsPresentation
{
    public const string Title = "Insights";
    public const string BoardDescription = "What your agents actually used, and what the analyst found in your own session logs. Every number here is counted from calls this router served — none of it is modelled.";

    public const string NoMeasurement = "No measurement";
    public const string NoRateInWindow = "no calls in the window to measure";
    public const string NoCallsDash = "—";
    public const string NoHarnessConfig = "No harness configuration was found, so calls can't be attributed to a harness.";
    public const string ZeroHarnessExplanation = "No calls from this harness in the window.";
    public const string OtherCallsExplanation = "Not attributed to a harness above.";
    public const string AnalystUnavailable = "The session analyst isn't available on this router.";
    public const string AnalystNeverRun = "The analyst has not run yet.";

    /// <summary>The window the router answered over. The router fixes it, so the board names it rather than offering a selector.</summary>
    public static string WindowLabel(int hours) => hours == 168 ? "Last 7 days" : $"Last {hours} hours";
    public static IReadOnlyList<InsightsPeriod> Periods { get; } = new[] { InsightsPeriod.Last24Hours, InsightsPeriod.Last7Days };
    public static int PeriodHours(InsightsPeriod period) => period == InsightsPeriod.Last7Days ? 168 : 24;
    public static string PeriodQuery(InsightsPeriod period) => period == InsightsPeriod.Last7Days ? "7d" : "24h";
    public static string PeriodTitle(InsightsPeriod period) => WindowLabel(PeriodHours(period));
    public static string StampedAt(string instant) => DateTimeOffset.TryParse(instant, CultureInfo.InvariantCulture, DateTimeStyles.None, out var at)
        ? at.ToLocalTime().ToString("d MMM yyyy HH:mm", CultureInfo.InvariantCulture) : instant;

    /// <summary>The window's figures are read over, in the words the figures use.</summary>
    public static string InWindow(int hours) => hours == 168 ? "in the last 7 days" : $"in the last {hours} hours";

    /// <summary>A usage-log line count, in words that match the number.</summary>
    public static string UnreadableLines(int count) =>
        $"{count.ToString("N0", CultureInfo.InvariantCulture)} {Plural(count, "usage log line", "usage log lines")} couldn't be read and {(count == 1 ? "isn't" : "aren't")} counted.";

    /// <summary>The time a reading was taken, in this machine's clock. The router stamps it in UTC.</summary>
    public static string ShownAt(string readAt) =>
        DateTimeOffset.TryParse(readAt, CultureInfo.InvariantCulture, DateTimeStyles.None, out var at)
            ? at.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture)
            : readAt;

    /// <summary>
    /// A read failed after an earlier one answered. The earlier figures stay, and the note says what they are:
    /// the reading from that time, under a failure this read hit.
    /// </summary>
    public static string StaleNote(string readAt, string headline) =>
        $"{headline}. Showing the reading from {ShownAt(readAt)}; the figures may no longer match the router.";

    public static string Plural(int count, string singular, string plural) => count == 1 ? singular : plural;

    public static string Count(int value) => value.ToString("N0", CultureInfo.InvariantCulture);
}
