namespace MCPRouter.Shell.Live;

/// <summary>Which of the loaded records the board is showing. The mock's four filter words.</summary>
public enum ResultFilter
{
    All,
    Errors,
    Slow,
    Held,
}

/// <summary>One row of the per-harness tally: who called, and how much of the window is theirs.</summary>
public sealed record HarnessTally(string Client, string Label, int Calls)
{
    /// <summary>The key records the router could not attribute group under, everywhere it is
    /// called anything. The Mac board's <c>ActivityNaming.unattributed</c>, carried so both
    /// platforms say it one way (DESIGN.md §6: one name per state).</summary>
    public const string UnattributedClient = "";

    public string Key => Client;
}

/// <summary>
/// The window of call records the board holds, and everything it derives from them.
///
/// Single-threaded by contract: the consumer applies records and reads views on the UI thread,
/// marshalling off the client's delivery thread itself. Nothing here locks, because two
/// threads agreeing on a log is not a problem this class was given.
///
/// **Everything the board shows is derived from records the router actually returned.** The
/// tallies are built from the loaded window, so a harness cannot appear in the tally without a
/// record behind it, and a filter cannot show a count the window does not support - the way
/// DESIGN.md §6's "numbers the router does not observe are never displayed" actually bites on a
/// log surface.
/// </summary>
public sealed class ActivityModel
{
    /// <summary>
    /// How many records are kept. The router's own ring is 500 (<c>RING_SIZE</c> in
    /// <c>src/usage.ts</c>) and <c>GET /usage</c> slices its tail, so asking for more returns
    /// no more; matching it exactly means the backfill is the whole of what the router has and
    /// the live stream tops the list up to the same bound rather than growing without limit -
    /// an unbounded list behind a feed that never stops is a leak with a slow fuse.
    /// </summary>
    public const int Capacity = 500;

    /// <summary>The Slow filter's threshold, in the unit the router measures in.</summary>
    public const int SlowThresholdMs = 2000;

    private readonly List<CallRecord> _records = new(Capacity);
    private readonly HashSet<string> _ids = new(StringComparer.Ordinal);
    private readonly HashSet<string> _excludedHarnesses = new(StringComparer.Ordinal);

    /// <summary>Newest first - the order the backfill arrives in and the only order in which
    /// "a new call appears at the top" is true.</summary>
    public IReadOnlyList<CallRecord> Records => _records;

    public StreamPhase Phase { get; set; } = StreamPhase.Connecting;

    public ResultFilter Filter { get; set; } = ResultFilter.All;

    /// <summary>Whether the view is paused. Ingestion never pauses - see <see cref="SetPaused"/>.</summary>
    public bool Paused { get; private set; }

    /// <summary>
    /// Calls that arrived while the view was paused. This is a count of records actually
    /// ingested, never an estimate - the board's sentence about the pause is checkable against
    /// the rows it heads.
    /// </summary>
    public int RecordsWhilePaused { get; private set; }

    /// <summary>
    /// Applies one record from the live stream.
    ///
    /// Returns whether anything changed, so a caller can skip work for an event that was
    /// already on screen. A record the backfill already carried is dropped rather than
    /// prepended, and past the capacity the oldest record leaves the window: the id set keeps
    /// the de-duplication a lookup rather than a scan of five hundred records on every event.
    /// While paused the record is still ingested - the brief's "pause must not drop calls that
    /// arrive while paused" - and only the view's refresh is held back.
    /// </summary>
    public bool Prepend(CallRecord record)
    {
        if (!_ids.Add(record.Id)) return false;

        _records.Insert(0, record);
        while (_records.Count > Capacity)
        {
            var dropped = _records[^1];
            _records.RemoveAt(_records.Count - 1);
            _ids.Remove(dropped.Id);
        }

        if (Paused) RecordsWhilePaused++;
        return true;
    }

    /// <summary>
    /// Applies the backfill. The window is rebuilt de-duplicated, keeping the first
    /// <see cref="Capacity"/> records - newest first in, so the records that survived are the
    /// newest - and the id set with them.
    /// </summary>
    public void Load(IEnumerable<CallRecord> records)
    {
        _records.Clear();
        _ids.Clear();
        foreach (var record in records)
        {
            if (_ids.Add(record.Id)) _records.Add(record);
            if (_records.Count >= Capacity) break;
        }
    }

    public void SetPaused(bool paused)
    {
        if (Paused == paused) return;
        Paused = paused;
        if (!paused) RecordsWhilePaused = 0;
    }

    /// <summary>Includes or excludes one harness key from the rows. Toggling a harness off
    /// hides its rows; it never deletes anything from the window.</summary>
    public void SetHarnessIncluded(string clientKey, bool included)
    {
        if (included) _excludedHarnesses.Remove(clientKey);
        else _excludedHarnesses.Add(clientKey);
    }

    public bool IsHarnessIncluded(string clientKey) => !_excludedHarnesses.Contains(clientKey);

    /// <summary>The records the board draws: the result filter and the harness toggles, composed.</summary>
    public IReadOnlyList<CallRecord> VisibleRows() =>
        _records.Where(r => MatchesFilter(r) && IsHarnessIncluded(HarnessKey(r))).ToList();

    /// <summary>Per-harness counts under the result filter alone, most calls first.
    ///
    /// The tally is measured over the filtered set the rows are drawn from, but not over the
    /// harness toggles - a pill that deleted its own count the moment it was toggled off would
    /// hide the thing the count exists to show. A tally and the rows it heads can therefore be
    /// read against each other without arithmetic.</summary>
    public IReadOnlyList<HarnessTally> Tallies()
    {
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var record in _records)
        {
            if (!MatchesFilter(record)) continue;
            var key = HarnessKey(record);
            counts[key] = counts.GetValueOrDefault(key) + 1;
        }

        return counts
            .Select(kv => new HarnessTally(kv.Key, ActivityFormatting.HarnessName(kv.Key), kv.Value))
            .OrderByDescending(t => t.Calls)
            .ThenBy(t => t.Label, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>Whether the current filter combination matches nothing over a window that is
    /// not itself empty - the state whose copy has to say "you filtered it all out" rather
    /// than "nothing has happened".</summary>
    public bool IsFilteredToNothing() => _records.Count > 0 && VisibleRows().Count == 0;

    /// <summary>The timestamp the partial banner names, or null over an empty window.</summary>
    public string? NewestTs() => _records.Count > 0 ? _records[0].Ts : null;

    private bool MatchesFilter(CallRecord record) => Filter switch
    {
        ResultFilter.All => true,
        ResultFilter.Errors => !record.Ok,
        ResultFilter.Slow => record.Ms > SlowThresholdMs,
        ResultFilter.Held => record.ResultKind == CallResultKind.Held,
        _ => true,
    };

    /// <summary>The group a record's attribution joins. The client name is display, not
    /// identity, and an absent or empty client is one group, spelled by
    /// <see cref="ActivityFormatting.HarnessName"/> - never dropped, never guessed at.</summary>
    private static string HarnessKey(CallRecord record) => record.Client ?? HarnessTally.UnattributedClient;
}
