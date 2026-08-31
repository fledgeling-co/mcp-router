using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The store: bounded, stamped, honest about unreadability. The structural half of "no result
/// without a version" lives here — nothing is recorded for a subject with no stamp.
/// </summary>
public sealed class CheckHistoryStoreTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"win8-store-{Guid.NewGuid():N}");

    public void Dispose()
    {
        try
        {
            Directory.Delete(_directory, recursive: true);
        }
        catch (DirectoryNotFoundException)
        {
        }
    }

    private static IReadOnlyList<CheckResult> Results() =>
    [
        new CheckResult(CheckId.Indexes, CheckVerdict.Passed, null),
        new CheckResult(CheckId.CallsSucceed, CheckVerdict.Failed, CheckCopy.CallsFailed(2, 9)),
    ];

    [Fact]
    public void ARunIsRecordedNewestFirstAndReadBack()
    {
        var store = new CheckHistoryStore(_directory);
        var key = SubjectKey.Server("trawl");

        store.Record(key, new Stamp("1.4.2"), Results(), new DateTimeOffset(2026, 8, 30, 9, 0, 0, TimeSpan.Zero));
        store.Record(key, new Stamp("1.5.0"), Results(), new DateTimeOffset(2026, 8, 31, 9, 0, 0, TimeSpan.Zero));

        var history = store.History(key);
        Assert.Equal(2, history.Count);
        Assert.Equal("1.5.0", history[0].Stamp);
        Assert.Equal("1.4.2", history[1].Stamp);
        Assert.Equal(CheckId.Indexes, history[0].Results[0].CheckId);
        Assert.Equal(CheckVerdict.Passed, history[0].Results[0].VerdictValue);
        Assert.Equal(CheckCopy.CallsFailed(2, 9), history[1].Results[1].Reason);
    }

    [Fact]
    public void NothingIsRecordedWithoutAStamp()
    {
        var store = new CheckHistoryStore(_directory);
        var key = SubjectKey.Server("standalone");

        Assert.False(store.Record(key, null, Results()));
        Assert.Empty(store.History(key));
    }

    [Fact]
    public void TheTwentyFirstRunEvictsTheOldest()
    {
        var store = new CheckHistoryStore(_directory);
        var key = SubjectKey.Server("trawl");

        for (var i = 0; i < CheckHistoryStore.Capacity + 1; i++)
        {
            store.Record(key, new Stamp($"1.{i}.0"), Results(), new DateTimeOffset(2026, 8, 30, 0, i, 0, TimeSpan.Zero));
        }

        var history = store.History(key);
        Assert.Equal(CheckHistoryStore.Capacity, history.Count);
        Assert.Equal("1.20.0", history[0].Stamp);
        Assert.Equal("1.1.0", history[^1].Stamp);
    }

    [Fact]
    public async Task ACorruptFileStartsEmptyAndKeepsTheError()
    {
        Directory.CreateDirectory(_directory);
        await File.WriteAllTextAsync(Path.Combine(_directory, "check-history.json"), "{ not json ]");

        var store = new CheckHistoryStore(_directory);

        Assert.Empty(store.History(SubjectKey.Server("trawl")));
        Assert.False(string.IsNullOrWhiteSpace(store.LoadError));
    }

    [Fact]
    public void AHistoryFileSurvivesAReopen()
    {
        var store = new CheckHistoryStore(_directory);
        store.Record(SubjectKey.Server("trawl"), new Stamp("1.4.2"), Results(), DateTimeOffset.Now);

        var reopened = new CheckHistoryStore(_directory);

        var run = Assert.Single(reopened.History(SubjectKey.Server("trawl")));
        Assert.Equal("1.4.2", run.Stamp);
        Assert.Null(reopened.LoadError);
    }

    [Fact]
    public void TwoSubjectsOfDifferentKindsCannotCollide()
    {
        // The key carries the kind, so the day a skill subject arrives its ids live in their own
        // namespace.
        var store = new CheckHistoryStore(_directory);
        store.Record(SubjectKey.Server("trawl"), new Stamp("1.4.2"), Results());

        Assert.Equal(CheckSubjectKind.Server, SubjectKey.Server("trawl").Kind);
        Assert.NotEqual("skill:trawl", SubjectKey.Server("trawl").StoreKey, comparer: StringComparer.Ordinal);
    }
}
