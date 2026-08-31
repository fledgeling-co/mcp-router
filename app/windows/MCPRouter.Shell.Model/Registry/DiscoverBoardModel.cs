namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// The Discover board's own state: the debounced search, the generation guard, and the one
/// write. A Windows port of the Mac's <c>DiscoverBoardModel</c>, holding the same correctness
/// mechanism and the same refusal.
///
/// <b>The generation counter is the correctness mechanism, and cancellation is only an
/// optimisation.</b> A cold search can take minutes (two index calls at 12-second timeouts plus
/// star enrichment), so the window in which a stale result can land is wide: a query typed while
/// an empty-query search is in flight must not be repainted by the older answer when it finally
/// returns. Every search captures the generation and discards its outcome - success or failure -
/// unless the counter still matches when it resumes.
///
/// <b>Install lives only in the detail dialog.</b> Nothing here is reachable from a row: a list
/// row that installs is exactly the one-click path from a ranking to executing someone's code
/// that this board is shaped to refuse (spec-WIN7 §3).
/// </summary>
public sealed class DiscoverBoardModel
{
    private readonly RegistryClient _client;
    private int _generation;

    public DiscoverBoardModel(RegistryClient client) => _client = client;

    public RegistrySearchResponse? LastResponse { get; private set; }

    /// <summary>The last outcome that was accepted, superseded results discarded before they
    /// ever reach it. Starts in the loading state: no answer yet is not an answer of none.</summary>
    public DiscoverOutcome LastOutcome { get; private set; } =
        new(null, RegistryPresentation.ListStateKind.Loading, null, null, IsStale: false);

    public async Task<DiscoverOutcome> SearchAsync(string query, CancellationToken cancellationToken = default)
    {
        var captured = ++_generation;
        var trimmed = query.Trim();
        var result = await _client.SearchAsync(trimmed, 60, cancellationToken);

        // Both guards, and in this order: a superseded result is discarded even when the task
        // was never cancelled, which is the case the counter exists for.
        if (cancellationToken.IsCancellationRequested || captured != _generation)
        {
            return LastOutcome;
        }

        if (result.Failure is null)
        {
            var response = result.Response!;
            var kind = RegistryPresentation.Resolve(response, trimmed, offline: false, failed: false);
            LastResponse = response;
            LastOutcome = new DiscoverOutcome(response, kind, null, null, IsStale: false);
            return LastOutcome;
        }

        var reason = result.Failure.Kind switch
        {
            RegistryClient.SearchFailureKind.RouterUnreachable => (DiscoverCopy.FailureReason?)null,
            RegistryClient.SearchFailureKind.Unauthorized => DiscoverCopy.FailureReason.Unauthorized,
            RegistryClient.SearchFailureKind.RouterError => DiscoverCopy.FailureReason.RouterRefused,
            RegistryClient.SearchFailureKind.MalformedResponse => DiscoverCopy.FailureReason.MalformedResponse,
            _ => DiscoverCopy.FailureReason.Transport,
        };

        // The router not answering is its own surface state (never one more error string);
        // everything else is a failure rendered from the closed reason enum.
        if (result.Failure.Kind == RegistryClient.SearchFailureKind.RouterUnreachable)
        {
            LastOutcome = new DiscoverOutcome(null, RegistryPresentation.ListStateKind.Offline, null, null, IsStale: false);
            return LastOutcome;
        }

        // A previous good reading is kept and labelled rather than discarded. Throwing it away
        // would replace a true-but-old board with an empty one, and an empty board is a stronger
        // claim than a stale one.
        if (LastResponse is { } previous)
        {
            LastOutcome = new DiscoverOutcome(previous, RegistryPresentation.ListStateKind.Failed, reason, result.Failure.Detail, IsStale: true);
            return LastOutcome;
        }

        LastOutcome = new DiscoverOutcome(null, RegistryPresentation.ListStateKind.Failed, reason, result.Failure.Detail, IsStale: false);
        return LastOutcome;
    }

    /// <summary>Declare the entry as a server. Called only from the detail dialog; the value the
    /// user typed is handed to the router with the declaration and stored nowhere here.</summary>
    public Task<RegistryClient.AddResult> AddAsync(NewServer declaration, CancellationToken cancellationToken = default) =>
        _client.AddAsync(declaration, cancellationToken);

    /// <summary>Flips one row's installed flag without refetching. No refetch on purpose: the
    /// search is non-deterministic between calls, so re-reading it at the moment the user acted
    /// would reorder the board under them and lose the row they were looking at.</summary>
    public void MarkInstalled(string entryId)
    {
        if (LastResponse is null) return;
        LastResponse = new RegistrySearchResponse
        {
            Results = LastResponse.Results
                .Select(e => e.Id == entryId ? e.AsInstalled() : e)
                .ToList(),
            Sources = LastResponse.Sources,
            Warnings = LastResponse.Warnings,
        };
    }
}

/// <summary>One accepted search outcome, as values a test and a view can both read.</summary>
public sealed record DiscoverOutcome(
    RegistrySearchResponse? Response,
    RegistryPresentation.ListStateKind Kind,
    DiscoverCopy.FailureReason? Reason,
    string? RouterDetail,
    bool IsStale);

/// <summary>The publisher filter - the one real partition the wire carries, refined by
/// provenance from the id prefix rather than by the source label alone. A row both indexes
/// supplied belongs to both of this filter's non-All scopes, because that is what "both" means.</summary>
public enum PublisherFilter
{
    All,
    Official,
    Smithery,
}

public static class PublisherFilterExtensions
{
    public static string Label(this PublisherFilter filter) => filter switch
    {
        PublisherFilter.All => DiscoverCopy.PublisherAll,
        PublisherFilter.Official => DiscoverCopy.PublisherOfficial,
        PublisherFilter.Smithery => DiscoverCopy.PublisherSmithery,
        _ => throw new ArgumentOutOfRangeException(nameof(filter), filter, "unknown publisher filter"),
    };

    /// <summary>The entries the filter is honest over. Applied before the bands, so every band
    /// draws from the same filtered view and neither band can claim a population it is not
    /// showing.</summary>
    public static IReadOnlyList<RegistryEntry> Apply(this PublisherFilter filter, IReadOnlyList<RegistryEntry> entries) =>
        filter == PublisherFilter.All
            ? entries
            : entries
                .Where(e =>
                {
                    var provenance = RegistryPresentation.ProvenanceFor(e);
                    return filter == PublisherFilter.Official
                        ? provenance.IsOfficial
                        : provenance.IsSmithery;
                })
                .ToList();
}
