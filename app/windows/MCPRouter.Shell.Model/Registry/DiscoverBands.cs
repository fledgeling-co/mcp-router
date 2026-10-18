namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// The two bands Discover ships, and the window that filters one of them.
///
/// Two, because the brief demands it and the data supports exactly this pair: Recently changed is
/// the editorial claim ("Added … is the only thing 'new' means here", as the design of record
/// puts it under its own featured hero) and Most used is the measured claim. The mock's third
/// band — Trending — needs two observations of the same quantity over time, and nothing in this
/// product keeps one; spec-WIN7 §2 records the ruling that no row is therefore drawn as trending,
/// and <see cref="DiscoverCopy.TrendingNote" /> is the sentence the board states instead.
///
/// The obvious replacement — ranking on <c>pushedAt</c> as "actively worked on" — is refused for
/// the Mac's recorded reason: that field exists for at most ten entries per search, never for
/// Smithery-hosted ones, and which ten is decided by fetch budget rather than by any property of
/// the entries. A band is a ranking claim about a population; ranking on a field whose membership
/// is an artifact of a budget makes a claim the data cannot support.
/// </summary>
public enum DiscoverBand
{
    MostUsed,
    RecentlyChanged,
}

/// <summary>The window offered on Recently changed. <see cref="AnyTime" /> is the default, and
/// that is a data decision: entries whose newest stamps fall outside every window would render an
/// empty band on first open — a designed-in empty state, which is a different thing from an empty
/// state a search happened to produce.</summary>
public enum RecencyWindow
{
    AnyTime,
    Ninety,
    Thirty,
    Seven,
}

public static class DiscoverBands
{
    public static int? Days(this RecencyWindow window) => window switch
    {
        RecencyWindow.AnyTime => null,
        RecencyWindow.Ninety => 90,
        RecencyWindow.Thirty => 30,
        RecencyWindow.Seven => 7,
        _ => throw new ArgumentOutOfRangeException(nameof(window), window, "unknown window"),
    };

    public static string Label(this RecencyWindow window) => window switch
    {
        RecencyWindow.AnyTime => DiscoverCopy.WindowAnyTime,
        RecencyWindow.Ninety => DiscoverCopy.WindowNinety,
        RecencyWindow.Thirty => DiscoverCopy.WindowThirty,
        RecencyWindow.Seven => DiscoverCopy.WindowSeven,
        _ => throw new ArgumentOutOfRangeException(nameof(window), window, "unknown window"),
    };

    /// <summary>Only Recently changed responds to the window. UseCount is a cumulative all-time
    /// total, and slicing it by a window would assert a per-window figure that was never
    /// measured — the same defect as a trend band, in a quieter costume. A test asserts the Most
    /// used membership is identical across all four windows; that assertion is the guard.</summary>
    public static bool RespondsToWindow(DiscoverBand band) => band == DiscoverBand.RecentlyChanged;

    /// <summary>The entries in a band, ordered.
    ///
    /// An entry lacking a band's field is absent from that band, never ranked at zero: a missing
    /// UseCount means Smithery does not index the entry — the official registry publishes no
    /// popularity figure at all — and placing it last as a zero would assert a measurement of
    /// nobody using it. Ties break on id ascending so the order is total and stable, and rows
    /// never swap places on a re-render that changed nothing.</summary>
    public static IReadOnlyList<RegistryEntry> Members(
        DiscoverBand band,
        IReadOnlyList<RegistryEntry> entries,
        RecencyWindow window,
        DateTimeOffset? now = null)
    {
        return band switch
        {
            DiscoverBand.MostUsed => entries
                .Where(e => e.UseCount.HasValue)
                .OrderByDescending(e => e.UseCount ?? 0)
                .ThenBy(e => e.Id, StringComparer.Ordinal)
                .ToList(),

            DiscoverBand.RecentlyChanged => entries
                .Select(e => (Entry: e, Date: RegistryText.TryParseTimestamp(e.UpdatedAt)))
                .Where(pair =>
                {
                    if (pair.Date is null) return false; // unparseable drops, never sorts to an end
                    var cutoff = window.Days();
                    if (cutoff is null) return true;
                    var at = now ?? DateTimeOffset.UtcNow;
                    return pair.Date.Value >= at.AddDays(-cutoff.Value);
                })
                .OrderByDescending(pair => pair.Date!.Value)
                .ThenBy(pair => pair.Entry.Id, StringComparer.Ordinal)
                .Select(pair => pair.Entry)
                .ToList(),

            _ => throw new ArgumentOutOfRangeException(nameof(band), band, "unknown band"),
        };
    }

    /// <summary>Whether a band is empty while the results as a whole are not — its own state with
    /// its own copy, never the whole-board empty.</summary>
    public static RegistryPresentation.BandEmptyKind EmptyWithinResults(
        DiscoverBand band,
        IReadOnlyList<RegistryEntry> entries,
        RecencyWindow window,
        DateTimeOffset? now = null)
    {
        if (entries.Count == 0) return RegistryPresentation.BandEmptyKind.None;
        return Members(band, entries, window, now).Count == 0
            ? band == DiscoverBand.MostUsed
                ? RegistryPresentation.BandEmptyKind.MostUsed
                : window == RecencyWindow.AnyTime
                    ? RegistryPresentation.BandEmptyKind.RecentlyChangedAnyTime
                    : RegistryPresentation.BandEmptyKind.RecentlyChangedWindowed
            : RegistryPresentation.BandEmptyKind.None;
    }
}
