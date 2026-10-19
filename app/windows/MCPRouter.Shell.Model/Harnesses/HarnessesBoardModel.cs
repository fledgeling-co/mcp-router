using System;
using System.Collections.Generic;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Harnesses;

/// <summary>What the Harnesses board is holding at a moment.</summary>
public enum HarnessesBoardState
{
    /// <summary>No read has finished yet.</summary>
    Loading,

    /// <summary>The router answered, and at least one harness is declared on this machine.</summary>
    Populated,

    /// <summary>The router answered, and no harness is declared on this machine. A finding, not a failure.</summary>
    Empty,

    /// <summary>An earlier read answered and the latest did not. The earlier rows stay, and say so.</summary>
    Stale,

    /// <summary>The router was never reached: nothing is listening, or the request did not complete.</summary>
    Unreachable,

    /// <summary>The router answered and refused, or answered with something this build cannot read.</summary>
    Refused,
}

/// <summary>Everything the Harnesses board draws, at a moment, as values a test can compare.</summary>
public sealed record HarnessesBoardSnapshot
{
    public required HarnessesBoardState State { get; init; }

    /// <summary>The router's own harness order, which is the order the rows are drawn in.</summary>
    public IReadOnlyList<HarnessRow> Harnesses { get; init; } = Array.Empty<HarnessRow>();

    /// <summary>When the rows were read. Null when no read has answered.</summary>
    public string? ReadAt { get; init; }

    /// <summary>The failure of the latest read, when it failed. Carries the wording the board shows.</summary>
    public ControlApiException? Error { get; init; }
}

/// <summary>
/// The Harnesses board's states and row readings, derived in one place so the view cannot reach a
/// state the model did not decide. Holds no I/O: every value is a function of the last reading that
/// answered and the failure of the latest read.
/// </summary>
public static class HarnessesBoardModel
{
    public static HarnessesBoardSnapshot Snapshot(HarnessesEnvelope? lastAnswered, ControlApiException? latestError)
    {
        if (lastAnswered is null)
        {
            if (latestError is null)
            {
                return new HarnessesBoardSnapshot { State = HarnessesBoardState.Loading };
            }

            return new HarnessesBoardSnapshot
            {
                State = IsUnreached(latestError) ? HarnessesBoardState.Unreachable : HarnessesBoardState.Refused,
                Error = latestError,
            };
        }

        if (latestError is not null)
        {
            return new HarnessesBoardSnapshot
            {
                State = HarnessesBoardState.Stale,
                Harnesses = lastAnswered.Harnesses,
                ReadAt = lastAnswered.ReadAt,
                Error = latestError,
            };
        }

        return new HarnessesBoardSnapshot
        {
            State = lastAnswered.Harnesses.Count == 0 ? HarnessesBoardState.Empty : HarnessesBoardState.Populated,
            Harnesses = lastAnswered.Harnesses,
            ReadAt = lastAnswered.ReadAt,
        };
    }

    /// <summary>
    /// The row's own word, beside its name. An unreadable file says so: its wire state is the empty
    /// report's <c>not-wired</c>, and a row that borrowed "Not routed" would present a file nobody
    /// could read as a clean absence.
    /// </summary>
    public static string RowLabel(HarnessRow harness) =>
        harness.Unreadable is not null
            ? "Unreadable"
            : HarnessPresentation.StateLabel(HarnessPresentation.ReadingOf(harness.State));

    /// <summary>
    /// Whether the row is a thing a person should look at: it runs servers this router already
    /// fronts. An unreadable row is not a caution here; it is its own note.
    /// </summary>
    public static bool IsCaution(HarnessRow harness) =>
        harness.Unreadable is null
        && HarnessPresentation.ReadingOf(harness.State) == HarnessReading.RoutedWithDirectServers;

    /// <summary>
    /// A failure to reach the router, as opposed to one the router sent back. Both a refused
    /// connection and a request that did not complete mean the router was not reached at all.
    /// </summary>
    private static bool IsUnreached(ControlApiException error) =>
        error.Kind is ControlApiFailure.RouterNotRunning or ControlApiFailure.Transport;
}
