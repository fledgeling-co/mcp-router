using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Insights;

/// <summary>
/// The Insights board's states, figures and analyst card, derived in one place so the view cannot reach a
/// state the model did not decide. Holds no I/O: every value is a function of the last reading that answered
/// and the failure of the latest read.
///
/// <para>Each figure is the router's count or a ratio of two of its counts, and carries the denominator it
/// is a figure of. Nothing is modelled: where the router sent no number, the board draws no number.</para>
/// </summary>
public static class InsightsBoardModel
{
    public static InsightsBoardSnapshot Snapshot(
        InsightsEnvelope? lastAnswered,
        ControlApiException? latestError,
        ControlApiException? analyseFailure = null,
        int askedHours = 24)
    {
        if (lastAnswered is null)
        {
            if (latestError is null)
            {
                return new InsightsBoardSnapshot { State = InsightsBoardState.Loading };
            }

            return new InsightsBoardSnapshot
            {
                State = IsUnreached(latestError) ? InsightsBoardState.Unreachable : InsightsBoardState.Refused,
                Error = latestError,
                AnalyseFailure = analyseFailure,
            };
        }

        var window = InsightsPresentation.WindowLabel(lastAnswered.WindowHours);
        var analyst = AnalystCard(lastAnswered.Analyst, lastAnswered.CallsByHarness);

        if (latestError is not null)
        {
            return new InsightsBoardSnapshot
            {
                State = InsightsBoardState.Stale,
                WindowLabel = window,
                Figures = Figures(lastAnswered),
                Harnesses = HarnessLines(lastAnswered),
                Notes = new[] { InsightsPresentation.StaleNote(lastAnswered.GeneratedAt, latestError.Headline) }
                    .Concat(WindowNotes(lastAnswered, askedHours))
                    .ToList(),
                ReadAt = lastAnswered.GeneratedAt,
                Error = latestError,
                Analyst = analyst,
                AnalyseNowEnabled = false,
                AnalyseFailure = analyseFailure,
            };
        }

        return new InsightsBoardSnapshot
        {
            State = lastAnswered.Calls.Total == 0 ? InsightsBoardState.Empty : InsightsBoardState.Populated,
            WindowLabel = window,
            Figures = Figures(lastAnswered),
            Harnesses = HarnessLines(lastAnswered),
            Notes = WindowNotes(lastAnswered, askedHours),
            ReadAt = lastAnswered.GeneratedAt,
            Analyst = analyst,
            AnalyseNowEnabled = lastAnswered.Analyst is not null,
            AnalyseFailure = analyseFailure,
        };
    }

    private static IReadOnlyList<InsightsFigure> Figures(InsightsEnvelope envelope)
    {
        var calls = envelope.Calls;
        var processes = new InsightsFigure(
            "processes",
            InsightsPresentation.Count(envelope.Children.Alive),
            "Child processes running",
            $"of {InsightsPresentation.Count(envelope.Children.Declared)} declared");

        var memory = envelope.Resident is { } resident
            ? new InsightsFigure(
                "memory",
                $"{resident.Megabytes.ToString("N0", CultureInfo.InvariantCulture)} MB",
                "Resident memory",
                $"measured across {resident.Children} child {InsightsPresentation.Plural(resident.Children, "process", "processes")}")
            : new InsightsFigure("memory", InsightsPresentation.NoMeasurement, "Resident memory", "no child process has been measured");

        var toolCalls = new InsightsFigure(
            "calls",
            InsightsPresentation.Count(calls.Total),
            "Tool calls served",
            InsightsPresentation.InWindow(envelope.WindowHours));

        var failed = calls.Total == 0
            ? new InsightsFigure("failed", InsightsPresentation.NoCallsDash, "Failed calls", InsightsPresentation.NoRateInWindow)
            : new InsightsFigure(
                "failed",
                Percent((double)calls.Failed / calls.Total * 100, 2),
                "Failed calls",
                $"{InsightsPresentation.Count(calls.Failed)} of {InsightsPresentation.Count(calls.Total)} calls");

        return new[] { processes, memory, toolCalls, failed };
    }

    private static IReadOnlyList<InsightsHarnessLine> HarnessLines(InsightsEnvelope envelope)
    {
        var total = envelope.Calls.Total;
        var lines = new List<InsightsHarnessLine>();

        foreach (var harness in envelope.CallsByHarness)
        {
            if (harness.Calls is { } calls)
            {
                lines.Add(new InsightsHarnessLine(
                    harness.DisplayName,
                    InsightsPresentation.Count(calls),
                    Share(calls, total),
                    calls == 0 ? InsightsPresentation.ZeroHarnessExplanation : null));
            }
            else
            {
                lines.Add(new InsightsHarnessLine(harness.DisplayName, InsightsPresentation.NoCallsDash, null, harness.Reason));
            }
        }

        if (envelope.OtherCalls > 0)
        {
            lines.Add(new InsightsHarnessLine(
                "Other calls",
                InsightsPresentation.Count(envelope.OtherCalls),
                Share(envelope.OtherCalls, total),
                InsightsPresentation.OtherCallsExplanation));
        }

        return lines;
    }

    /// <summary>A share of the router's total, or null where there is no total to be a share of.</summary>
    private static string? Share(int calls, int total) =>
        total == 0 ? null : Percent(calls * 100.0 / total, 1);

    private static string Percent(double value, int decimals) =>
        value.ToString($"F{decimals}", CultureInfo.InvariantCulture) + "%";

    private static IReadOnlyList<string> WindowNotes(InsightsEnvelope envelope, int askedHours)
    {
        var notes = new List<string>();
        if (envelope.WindowComplete == false && envelope.ObservedSince is { } since)
            notes.Add($"The router has counted calls only since {InsightsPresentation.StampedAt(since)}, so this {InsightsPresentation.WindowLabel(envelope.WindowHours).ToLowerInvariant()} is not a whole one.");
        if (envelope.WindowHours != askedHours)
            notes.Add($"This router answered the {InsightsPresentation.WindowLabel(envelope.WindowHours).ToLowerInvariant()}, not the {InsightsPresentation.WindowLabel(askedHours).ToLowerInvariant()}, so these figures are for the shorter window.");
        if (envelope.Retention is { Capped.Records: > 0 } retention)
            notes.Add($"The {retention.CapMegabytes} MB history cap removed {InsightsPresentation.Count(retention.Capped.Records)} records from {InsightsPresentation.StampedAt(retention.Capped.From ?? "unknown time")} to {InsightsPresentation.StampedAt(retention.Capped.To ?? "unknown time")}, so the figures for that span are short.");

        if (envelope.Calls.Total == 0)
        {
            notes.Add($"No calls have reached this router {InsightsPresentation.InWindow(envelope.WindowHours)}.");
        }

        if (envelope.Calls.UnreadableLines > 0)
        {
            notes.Add(InsightsPresentation.UnreadableLines(envelope.Calls.UnreadableLines));
        }

        if (envelope.CallsByHarness.Count == 0)
        {
            notes.Add(InsightsPresentation.NoHarnessConfig);
        }

        return notes;
    }

    private static InsightsAnalystCard AnalystCard(
        InsightsAnalystWire? analyst,
        IReadOnlyList<InsightsHarnessCalls> harnesses)
    {
        if (analyst is null)
        {
            return new InsightsAnalystCard { Available = false, Notice = InsightsPresentation.AnalystUnavailable };
        }

        return new InsightsAnalystCard
        {
            Available = true,
            LastRun = LastRunLine(analyst),
            StoreNotes = StoreLines(analyst.Stores, harnesses),
            ScheduleNote = analyst.Scheduled
                ? $"Scheduled: {analyst.CadenceLabel}."
                : $"Saved cadence: {analyst.CadenceLabel}. Not scheduled: the analyst runs only when you press Analyse now.",
        };
    }

    private static string LastRunLine(InsightsAnalystWire analyst)
    {
        if (analyst.RanAt is null)
        {
            return InsightsPresentation.AnalystNeverRun;
        }

        var lines = analyst.LinesRead is { } read ? InsightsPresentation.Count(read) : InsightsPresentation.NoCallsDash;
        var findings = analyst.Findings is { } count
            ? $"{InsightsPresentation.Count(count)} {InsightsPresentation.Plural(count, "finding", "findings")}"
            : InsightsPresentation.NoCallsDash;
        var judge = analyst.Lane?.Label ?? "no lane";
        var fallback = analyst.UsedFallback == true ? " The fallback judged it, not the primary." : "";

        return $"Last run at {InsightsPresentation.ShownAt(analyst.RanAt)}: {lines} lines read, {findings}, judged by {judge}.{fallback}";
    }

    private static IReadOnlyList<string> StoreLines(
        IReadOnlyList<InsightsStoreWire> stores,
        IReadOnlyList<InsightsHarnessCalls> harnesses)
    {
        if (stores.Count == 0)
        {
            return Array.Empty<string>();
        }

        var notes = new List<string> { $"Read {stores.Count(s => s.Read)} of {stores.Count} session stores." };
        foreach (var store in stores.Where(s => !s.Read))
        {
            var name = harnesses.FirstOrDefault(h => h.Harness == store.Harness)?.DisplayName ?? store.Harness;
            notes.Add($"{name} wasn't read: {store.Reason?.TrimEnd('.') ?? "the router gave no reason"}.");
        }

        return notes;
    }

    /// <summary>
    /// A failure to reach the router, as opposed to one the router sent back. Both a refused connection and a
    /// request that did not complete mean the router was not reached at all.
    /// </summary>
    private static bool IsUnreached(ControlApiException error) =>
        error.Kind is ControlApiFailure.RouterNotRunning or ControlApiFailure.Transport;
}
