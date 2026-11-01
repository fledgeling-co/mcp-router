using System;
using System.Collections.Generic;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Insights;

public enum InsightsPeriod { Last24Hours, Last7Days }

/// <summary>What the Insights board is holding at a moment.</summary>
public enum InsightsBoardState
{
    /// <summary>No read has finished yet.</summary>
    Loading,

    /// <summary>The router answered, and the window holds at least one call.</summary>
    Populated,

    /// <summary>The router answered, and the window holds no calls. A finding, not a failure: the figures say so rather than showing a rate.</summary>
    Empty,

    /// <summary>An earlier read answered and the latest did not. The earlier figures stay, and say so.</summary>
    Stale,

    /// <summary>The router was never reached: nothing is listening, or the request did not complete.</summary>
    Unreachable,

    /// <summary>The router answered and refused, or answered with something this build cannot read.</summary>
    Refused,
}

/// <summary>One headline figure. <see cref="Provenance"/> is its denominator, or what makes it a measurement.</summary>
/// <param name="Key">Stable identity for the figure: <c>processes</c>, <c>memory</c>, <c>calls</c> or <c>failed</c>.</param>
public sealed record InsightsFigure(string Key, string Value, string Label, string Provenance);

/// <summary>
/// One row of the harness breakdown. <see cref="Calls"/> reads "—" where the router could not count, and
/// <see cref="Explanation"/> then carries the router's reason rather than a zero.
/// </summary>
public sealed record InsightsHarnessLine(string Name, string Calls, string? Share, string? Explanation);

/// <summary>
/// The analyst card, decided from the analyst member. <see cref="Available"/> is false when the router has no
/// analyst, and then <see cref="Notice"/> says so and nothing else is claimed.
/// </summary>
public sealed record InsightsAnalystCard
{
    public required bool Available { get; init; }

    public string? LastRun { get; init; }

    public IReadOnlyList<string> StoreNotes { get; init; } = Array.Empty<string>();

    public string? ScheduleNote { get; init; }

    public string? Notice { get; init; }
}

/// <summary>Everything the Insights board draws, at a moment, as values a test can compare.</summary>
public sealed record InsightsBoardSnapshot
{
    public required InsightsBoardState State { get; init; }

    /// <summary>The window the router answered over, named by the router's own hours. Null before any answer.</summary>
    public string? WindowLabel { get; init; }

    public IReadOnlyList<InsightsFigure> Figures { get; init; } = Array.Empty<InsightsFigure>();

    public IReadOnlyList<InsightsHarnessLine> Harnesses { get; init; } = Array.Empty<InsightsHarnessLine>();

    /// <summary>Statements that qualify the figures above: a stale reading, an unreadable line, an empty window.</summary>
    public IReadOnlyList<string> Notes { get; init; } = Array.Empty<string>();

    /// <summary>When the figures were read. Null when no read has answered.</summary>
    public string? ReadAt { get; init; }

    /// <summary>The failure of the latest read, when it failed. Carries the wording the board shows.</summary>
    public ControlApiException? Error { get; init; }

    /// <summary>Null until a read has answered, because the board does not know the analyst's state before then.</summary>
    public InsightsAnalystCard? Analyst { get; init; }

    /// <summary>True exactly when the router served <c>POST /insights/analyse</c> at the latest answered read.</summary>
    public bool AnalyseNowEnabled { get; init; }

    /// <summary>The failure of the last analyse, when it failed. The reading is left as it was.</summary>
    public ControlApiException? AnalyseFailure { get; init; }
}
