using System.Text.Json.Serialization;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Insights;

/// <summary>
/// The body <c>GET /insights</c> answers with (<c>src/insights.ts</c>). Every member the board draws is
/// here, and the board draws nothing the router did not send.
///
/// <para>An absent reading is null on the wire, never zero. <see cref="Resident"/> is null when no child
/// process has been measured, <see cref="InsightsHarnessCalls.Calls"/> is null when a harness's calls cannot
/// be attributed, and the run-scoped members of <see cref="InsightsAnalystWire"/> are null until a run exists.</para>
/// </summary>
public sealed record InsightsEnvelope
{
    [JsonPropertyName("generatedAt")]
    public required string GeneratedAt { get; init; }

    public required int WindowHours { get; init; }

    public required string WindowStart { get; init; }

    public string? LogHorizon { get; init; }
    public string? ObservedSince { get; init; }
    public bool? WindowComplete { get; init; }
    public InsightsRetentionWire? Retention { get; init; }

    public required InsightsChildren Children { get; init; }

    public required InsightsCalls Calls { get; init; }

    public InsightsResident? Resident { get; init; }

    public required IReadOnlyList<InsightsHarnessCalls> CallsByHarness { get; init; }

    /// <summary>Calls the router counted that no harness row claims. Kept so the rows and the total reconcile.</summary>
    public required int OtherCalls { get; init; }

    /// <summary>Null only when the router has no analyst, in which case <c>POST /insights/analyse</c> answers 503.</summary>
    public InsightsAnalystWire? Analyst { get; init; }
}

public sealed record InsightsChildren
{
    public required int Alive { get; init; }

    public required int Declared { get; init; }
}

public sealed record InsightsCalls
{
    public required int Total { get; init; }

    public required int Failed { get; init; }

    /// <summary>Usage-log lines the router could not parse. They are counted here and in no other figure.</summary>
    public required int UnreadableLines { get; init; }
}

public sealed record InsightsResident
{
    public required double Megabytes { get; init; }

    public required int Children { get; init; }
}

public sealed record InsightsHarnessCalls
{
    public required string Harness { get; init; }

    [JsonPropertyName("displayName")]
    public required string DisplayName { get; init; }

    public int? Calls { get; init; }

    public string? Reason { get; init; }
}

/// <summary>
/// The session analyst as the router reports it. <c>scheduled</c> is false on the wire and says so: the
/// cadence is stored and reported, and nothing fires it. <see cref="NextRunAt"/> is therefore a computed
/// time, not a promise, and the board does not draw it.
/// </summary>
public sealed record InsightsAnalystWire
{
    public required InsightsLaneChoice Primary { get; init; }

    public InsightsLaneChoice? Fallback { get; init; }

    [JsonConverter(typeof(InsightsCadenceWire))]
    public required string Cadence { get; init; }

    public required string CadenceLabel { get; init; }

    public required bool Scheduled { get; init; }

    public string? NextRunAt { get; init; }

    /// <summary>The rung that judged the last run, or null when nothing judged it or no run exists.</summary>
    public InsightsLaneChoice? Lane { get; init; }

    public string? RanAt { get; init; }

    public int? LinesRead { get; init; }

    public int? Discarded { get; init; }

    public int? Findings { get; init; }

    public bool? UsedFallback { get; init; }

    public int? RejectedFindings { get; init; }

    public bool? CandidatesUnavailable { get; init; }

    public required IReadOnlyList<InsightsStoreWire> Stores { get; init; }
}

public sealed record InsightsLaneChoice
{
    [JsonConverter(typeof(InsightsLaneWire))]
    public required string Lane { get; init; }

    public required string Model { get; init; }

    public required string Label { get; init; }
}

/// <summary>One session store the last run looked at. A store that was not read carries the reason.</summary>
public sealed record InsightsStoreWire
{
    public required string Harness { get; init; }

    public required string Path { get; init; }

    public required bool Read { get; init; }

    public required int Lines { get; init; }

    public required int Discarded { get; init; }

    public string? Reason { get; init; }
}

/// <summary>The lane words the router's <c>ANALYST_LANES</c> closes. An unlisted word fails the decode.</summary>
public sealed class InsightsLaneWire : ClosedSetWire
{
    public InsightsLaneWire() : base("claude", "cursor", "grok", "codex", "gemini") { }
}

/// <summary>The cadence words the router's <c>ANALYST_CADENCES</c> closes. An unlisted word fails the decode.</summary>
public sealed class InsightsCadenceWire : ClosedSetWire
{
    public InsightsCadenceWire() : base("manual", "sixHourly", "twelveHourly", "daily") { }
}


public sealed record InsightsRetentionWire
{
    public required int Days { get; init; }
    public required int CapMegabytes { get; init; }
    public required InsightsCappedWire Capped { get; init; }
}

public sealed record InsightsCappedWire
{
    public required int Generations { get; init; }
    public required int Records { get; init; }
    public string? From { get; init; }
    public string? To { get; init; }
}
