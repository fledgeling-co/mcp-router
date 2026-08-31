using System.Text.Json;

namespace MCPRouter.Checks.Model;

/// <summary>
/// The app's record of check runs it has performed, bounded and stamped.
///
/// Ported from the Mac's <c>CheckHistoryStore</c>, keeping its JSON shape, its bound and its
/// separation rule. It holds history and nothing else — but note what "history" means here:
/// on this board a stored run IS the row's result, valid only while its stamp matches the live
/// version (<see cref="ChecksBoardModel"/>). What this store never holds is authority: a stale
/// run cannot render as a current result, because the row reconciliation is what stands between
/// the store and the screen.
///
/// The Mac keeps invalidated runs labelled in its inspector; this board drops the run's standing
/// as a result and keeps the evidence, version-labelled, in the detail — spec-WIN8 §3.3. Capacity
/// 20 is the Mac's bound: an unbounded local file is a slow leak nobody notices until it is large,
/// and history past twenty runs answers no question this board asks.
/// </summary>
public sealed class CheckHistoryStore
{
    /// <summary>Runs kept per subject. The 21st evicts the oldest.</summary>
    public const int Capacity = 20;

    private readonly string _filePath;
    private Dictionary<string, List<StoredRun>> _runs;
    private readonly JsonSerializerOptions _options = new()
    {
        WriteIndented = true,
    };

    /// <summary>Why the history could not be read, when it could not. Kept rather than swallowed:
    /// the board must be able to say "the history could not be read" rather than "there is none",
    /// which are different claims.</summary>
    public string? LoadError { get; private set; }

    /// <summary>Injected so tests write to a temp dir rather than the real one.</summary>
    public CheckHistoryStore(string directory)
    {
        Directory.CreateDirectory(directory);
        _filePath = Path.Combine(directory, "check-history.json");
        (_runs, LoadError) = Read(_filePath);
    }

    /// <summary>The default location: this app's data directory, beside the shell's own state.</summary>
    public static string DefaultDirectory()
    {
        var baseDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(baseDirectory))
        {
            baseDirectory = Path.GetTempPath();
        }

        return Path.Combine(baseDirectory, "MCPRouter");
    }

    /// <summary>One subject's runs, newest first.</summary>
    public IReadOnlyList<StoredRun> History(SubjectKey subject) =>
        _runs.GetValueOrDefault(subject.StoreKey) ?? [];

    /// <summary>
    /// Records one run, and reports whether it was recorded.
    ///
    /// Returns false and writes nothing when there is no stamp — the structural half of "no result
    /// without a version". Storing an unstamped result would create a row that could never be
    /// known to be out of date, which is a worse answer than no row.
    /// </summary>
    public bool Record(SubjectKey subject, Stamp? stamp, IReadOnlyList<CheckResult> results, DateTimeOffset? at = null)
    {
        if (stamp is null || results.Count == 0)
        {
            return false;
        }

        var key = subject.StoreKey;
        var existing = _runs.GetValueOrDefault(key) ?? [];
        existing.Insert(
            0,
            new StoredRun(
                stamp.Value,
                at ?? DateTimeOffset.Now,
                results.Select(StoredResult.From).ToList()));
        if (existing.Count > Capacity)
        {
            existing.RemoveRange(Capacity, existing.Count - Capacity);
        }

        _runs[key] = existing;
        Write();
        return true;
    }

    /// <summary>The most recent run for a subject, or null. That is the row's candidate result —
    /// never authoritative until its stamp has been reconciled against the live version.</summary>
    public StoredRun? Latest(SubjectKey subject) =>
        _runs.GetValueOrDefault(subject.StoreKey) is { Count: > 0 } runs ? runs[0] : null;

    private static (Dictionary<string, List<StoredRun>>, string?) Read(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return (new Dictionary<string, List<StoredRun>>(StringComparer.Ordinal), null);
        }

        try
        {
            var json = File.ReadAllText(filePath);
            var runs = JsonSerializer.Deserialize<Dictionary<string, List<StoredRun>>>(json)
                       ?? new Dictionary<string, List<StoredRun>>(StringComparer.Ordinal);
            return (runs, null);
        }
        catch (Exception error)
        {
            // A corrupt or unreadable history starts empty and keeps the error. Refusing to open
            // the board because a cache file is malformed would be trading a complete surface for
            // a partial one over data nothing depends on — but the board still says the history
            // could not be read rather than claiming the checks never ran.
            return (new Dictionary<string, List<StoredRun>>(StringComparer.Ordinal), error.Message);
        }
    }

    private void Write()
    {
        try
        {
            File.WriteAllText(_filePath, JsonSerializer.Serialize(_runs, _options));
        }
        catch (Exception error)
        {
            // A failed write leaves the in-memory history intact and the board working. There is
            // nothing useful to tell the user about a cache that could not be saved, and nothing
            // they could do about it, so it is not surfaced as an error state.
            LoadError = error.Message;
        }
    }
}
