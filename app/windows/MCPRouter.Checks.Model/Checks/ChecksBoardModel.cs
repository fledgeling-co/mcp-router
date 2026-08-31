namespace MCPRouter.Checks.Model;

/// <summary>
/// The Checks board's state, its reads and its runs.
///
/// The rule this type is built around is the item itself: **a row's result is the stored run's,
/// and it is valid only while its stamp equals the capability's live version.** Load never
/// derives a verdict — it reconciles the store against the live versions the router serves. The
/// three ways a row can look, and the one it never can:
///
/// - `Not checked` — nothing stored.
/// - current — a stored run whose stamp is the live version; its tally and time are shown.
/// - `Stale` — a stored run whose stamp has been left behind by an edit. The tally is DROPPED
///   from the row, an invalidation notice names the move, and `Run the stale suite` acts on
///   exactly these rows.
/// - What a row never shows is the old tally against the new version. A green tick carried
///   forward is worse than no tick; there is no code path that renders one.
/// </summary>
public sealed class ChecksBoardModel
{
    /// <summary>One fetch's outcome. Reading survives a later failure so the board keeps its rows
    /// and says why they may be old — a board that has rows and then loses the router must
    /// neither throw the rows away nor hide the failure (§5's Error row).</summary>
    public enum LoadState
    {
        Loading,
        Loaded,
        Stale,
        Failed,
    }

    /// <summary>One row's result cell, as the version rule decides it.</summary>
    public record RowResult
    {
        /// <summary>How loud the result is, without any colour knowledge in the model. The view
        /// maps these to the platform's indicator hues — and every tone still carries its word,
        /// because on Windows the hue is the only channel some users do not have (§12).</summary>
        public enum RowTone
        {
            /// <summary>An ordinary reading: primary text.</summary>
            Primary,
            /// <summary>Something failed: the attention-demanding critical hue.</summary>
            Critical,
            /// <summary>Wants a human decision, or nothing was measured: the caution hue.</summary>
            Caution,
            /// <summary>A quiet absence, not a failure: secondary text.</summary>
            Secondary,
        }

        public static RowResult NotChecked { get; } = new() { Word = CheckCopy.NotChecked, Tone = RowTone.Secondary };

        public static RowResult Current(StoredRun run, int total) => new()
        {
            Word = $"{run.Results.Count(r => r.VerdictValue == CheckVerdict.Passed)} of {total}",
            Detail = CheckCopy.TallySegments([.. run.Results.Select(r => r.ToResult())]),
            Confirmed = run.Results.Count(r => r.VerdictValue == CheckVerdict.Passed),
            Total = total,
            Run = run,
            Tone = run.Results.Any(r => r.VerdictValue == CheckVerdict.Failed) ? RowTone.Critical : RowTone.Primary,
        };

        public static RowResult Stale(string storedStamp, int total) => new()
        {
            Word = CheckCopy.StaleWord,
            Detail = CheckCopy.StaleDetail(total, storedStamp),
            StoredStamp = storedStamp,
            Tone = RowTone.Caution,
        };

        public static RowResult CouldNotRun(string reason) => new()
        {
            Word = CheckCopy.CouldNotRun,
            Detail = reason,
            Tone = RowTone.Caution,
        };

        /// <summary>The word in the Result cell.</summary>
        public required string Word { get; init; }

        /// <summary>The Checks column: tally segments for a current run, the stale pointer for a
        /// dropped one, the reason for one that could not run.</summary>
        public string? Detail { get; init; }

        public RowTone Tone { get; init; } = RowTone.Secondary;

        public string? StoredStamp { get; init; }
        public StoredRun? Run { get; init; }
        public int Confirmed { get; init; }
        public int Total { get; init; }

        public bool IsStale => StoredStamp is not null;
        public bool IsCurrent => Run is not null;
        public bool WantsAttention => IsCurrent && Run!.Results.Any(r => r.VerdictValue == CheckVerdict.Failed);
    }

    /// <summary>One row: a capability the router can see, its live version, and what is stored
    /// about it.</summary>
    public record Row
    {
        public required SubjectKey Key { get; init; }
        public required string Name { get; init; }
        public required string Detail { get; init; }
        /// <summary>The live version — the stamp a run must carry to count as this version's
        /// result. Null when the capability has no version on the wire, which no stored run can
        /// ever be measured against.</summary>
        public required Stamp? LiveStamp { get; init; }
        public required RowResult Result { get; init; }
        /// <summary>The Ran column, or <see cref="CheckCopy.NoRunMark"/> where nothing is
        /// stored.</summary>
        public required string Ran { get; init; }
        public required IReadOnlyList<StoredRun> History { get; init; }

        public string SubjectId => Key.StoreKey;
    }

    /// <summary>What the invalidation notice says: which capability's result was dropped, and the
    /// move that dropped it.</summary>
    public record Invalidation(string SubjectId, string Name, string StoredStamp, string LiveStamp)
    {
        public virtual bool Equals(Invalidation? other) =>
            other is not null && SubjectId == other.SubjectId
            && StoredStamp == other.StoredStamp && LiveStamp == other.LiveStamp;

        public override int GetHashCode() => HashCode.Combine(SubjectId, StoredStamp, LiveStamp);
    }

    private readonly IChecksControlClient _client;
    private readonly CheckHistoryStore _store;
    private readonly Func<DateTimeOffset> _now;

    /// <summary>The server records as the last successful read served them, by name. The detail's
    /// input lines come from here — and only for a row whose stored stamp matches the live one,
    /// so a live observation is never printed beside a superseded run's evidence.</summary>
    public IReadOnlyDictionary<string, ServerRecord> LiveServers { get; private set; }
        = new Dictionary<string, ServerRecord>(StringComparer.Ordinal);

    public ChecksBoardModel(IChecksControlClient client, CheckHistoryStore store, Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _store = store;
        _now = now ?? (() => DateTimeOffset.Now);
    }

    public LoadState State { get; private set; } = LoadState.Loading;

    /// <summary>The rows as the last successful read reconciled them. Kept through a later
    /// failure — stale-with-reading — so the board keeps its rows and says why they may be
    /// old.</summary>
    public IReadOnlyList<Row> Rows { get; private set; } = [];

    /// <summary>The dropped results the last read found, in row order.</summary>
    public IReadOnlyList<Invalidation> Invalidations { get; private set; } = [];

    public ControlApiError? Error { get; private set; }

    /// <summary>Why the skills half is absent, when it is. The read path is real; the named
    /// absence is its outcome.</summary>
    public IReadOnlyList<string> SkillsAbsentReasons { get; private set; } = [];

    /// <summary>The history could not be read. The checks are unaffected; the board says so
    /// rather than claiming the checks never ran.</summary>
    public string? HistoryError => _store.LoadError;

    /// <summary>The run in flight, so the board can say so rather than looking inert.</summary>
    public string? RunningSubject { get; private set; }
    public int RunningIndex { get; private set; }
    public int RunningTotal { get; private set; }

    /// <summary>A refused run, reported against the row rather than as a toast.</summary>
    private readonly Dictionary<string, ControlApiError> _runFailures = new(StringComparer.Ordinal);
    public IReadOnlyDictionary<string, ControlApiError> RunFailures => _runFailures;

    // ------------------------------------------------------------------ reading

    /// <summary>
    /// One fetch of the capabilities, then reconciliation: every row's result is decided by
    /// comparing its stored run's stamp against the live version. No verdict is derived here.
    /// </summary>
    public async Task LoadAsync(CancellationToken cancellation = default)
    {
        List<ServerRecord> servers;
        try
        {
            var response = await _client.ServersAsync(cancellation).ConfigureAwait(false);
            servers = [.. response.Servers];
        }
        catch (ControlApiError error)
        {
            if (Rows.Count > 0)
            {
                State = LoadState.Stale;
            }
            else
            {
                State = LoadState.Failed;
            }

            Error = error;
            return;
        }

        List<string> skillReasons;
        try
        {
            var skills = await _client.SkillsAsync(cancellation).ConfigureAwait(false);
            skillReasons = [.. skills.AbsentReason];
        }
        catch (ControlApiError error)
        {
            // Kept, not swallowed: the board must be able to say the skills half is missing rather
            // than silently listing servers only.
            skillReasons = [error.UserFacingDescription];
        }

        Error = null;
        SkillsAbsentReasons = skillReasons;
        Reconcile(servers);
        State = LoadState.Loaded;
    }

    /// <summary>The reconciliation, cut off the network so the version rule is testable in
    /// isolation: given what the router serves now, decide every row.</summary>
    private void Reconcile(IReadOnlyList<ServerRecord> servers)
    {
        LiveServers = servers.ToDictionary(s => s.Name, StringComparer.Ordinal);
        var rows = new List<Row>(servers.Count);
        var invalidations = new List<Invalidation>();

        foreach (var server in servers)
        {
            var key = SubjectKey.Server(server.Name);
            var live = Stamp.ForServer(server);
            var history = _store.History(key);
            var latest = _store.Latest(key);
            var now = _now();

            RowResult result;
            string ran;

            if (live is null)
            {
                // No version to stamp against: checks about this subject can run and be shown,
                // but nothing could ever be stored, and the row says which rather than looking
                // merely unchecked.
                result = new RowResult { Word = CheckCopy.Unstampable, Detail = CheckCopy.UnstampableDetail };
                ran = CheckCopy.NoRunMark;
            }
            else if (latest is null)
            {
                result = RowResult.NotChecked;
                result = result with { Detail = CheckCopy.NotCheckedDetail(ServerChecks.All(server).Count) };
                ran = CheckCopy.NoRunMark;
            }
            else if (latest.StampValue.Value == live.Value)
            {
                result = RowResult.Current(latest, ServerChecks.All(server).Count);
                ran = RelativeTime.Ago(latest.RanAt, now);
            }
            else
            {
                // The version moved. The stored tally is dropped — the row reads stale and the
                // notice names the move. Nothing here re-shows the old result against the new
                // version; that code path does not exist.
                result = RowResult.Stale(latest.Stamp, ServerChecks.All(server).Count);
                ran = CheckCopy.NoRunMark;
                invalidations.Add(new Invalidation(key.StoreKey, server.Name, latest.Stamp, live.Value));
            }

            rows.Add(new Row
            {
                Key = key,
                Name = server.Name,
                Detail = server.Transport,
                LiveStamp = live,
                Result = result,
                Ran = ran,
                History = history,
            });
        }

        Rows = rows;
        Invalidations = invalidations;
    }

    // ------------------------------------------------------------------ running

    /// <summary>
    /// Re-checks one subject: genuinely re-perform the handshake, re-read, re-derive, record
    /// against the LIVE stamp as it is after the refresh — and record nothing at all when there
    /// is no stamp, which the store enforces structurally.
    /// </summary>
    public async Task RunAsync(Row row, CancellationToken cancellation = default)
    {
        RunningSubject = row.Name;
        var index = 0;
        foreach (var candidate in Rows)
        {
            if (candidate.SubjectId == row.SubjectId)
            {
                break;
            }

            index++;
        }

        RunningIndex = index + 1;
        RunningTotal = Rows.Count;
        try
        {
            await _client.ReindexAsync(row.Name, cancellation).ConfigureAwait(false);
            var response = await _client.ServersAsync(cancellation).ConfigureAwait(false);
            var refreshed = response.Servers.FirstOrDefault(s => s.Name == row.Name);
            if (refreshed is null)
            {
                _runFailures[row.SubjectId] = ControlApiError.Malformed($"the router no longer reports a server named {row.Name}");
                return;
            }

            Reconcile(response.Servers);
            _runFailures.Remove(row.SubjectId);

            var stored = Rows.First(r => r.SubjectId == row.SubjectId);
            _store.Record(stored.Key, stored.LiveStamp, ServerChecks.All(refreshed), _now());
            Reconcile(response.Servers);
        }
        catch (ControlApiError error)
        {
            // A run that could not complete is reported against the row and stores nothing:
            // "nothing was measured" is a different answer from a failure, and collapsing the two
            // is how a board starts reading clean while measuring nothing.
            _runFailures[row.SubjectId] = error;
        }
        finally
        {
            RunningSubject = null;
        }
    }

    /// <summary>Every row. Distinct from the stale suite by construction: this iterates all
    /// rows.</summary>
    public async Task RunAllAsync(CancellationToken cancellation = default)
    {
        foreach (var row in Rows.ToArray())
        {
            await RunAsync(row, cancellation).ConfigureAwait(false);
        }
    }

    /// <summary>Acts ONLY on stale rows — the action's entire reason to exist. The gate asserts
    /// that a board with current and stale rows re-runs the stale and leaves the current
    /// untouched.</summary>
    public async Task RunStaleAsync(CancellationToken cancellation = default)
    {
        foreach (var row in Rows.Where(r => r.Result.IsStale).ToArray())
        {
            await RunAsync(row, cancellation).ConfigureAwait(false);
        }
    }

    /// <summary>The per-check reading for a row, from its stored run when one exists. These are
    /// the run's own recorded results — for a stale row, evidence of the version the heading
    /// names, never of the live one.</summary>
    public IReadOnlyList<CheckResult> StoredResults(Row row) =>
        [.. (row.Result.Run ?? row.History.FirstOrDefault())?.Results.Select(r => r.ToResult()) ?? []];

    /// <summary>The input a stored result was computed from, when it can honestly be shown. The
    /// live record is the current version's; showing its field values beside a superseded run's
    /// results would be exactly the presentation the version rule forbids — so a stale row's
    /// exchanges show their recorded reasons and the null answer for inputs.</summary>
    public string? Input(CheckResult result, Row row) =>
        row.Result.IsCurrent && LiveServers.TryGetValue(row.Name, out var server)
            ? ServerChecks.Input(result.Check, server)
            : null;
}
