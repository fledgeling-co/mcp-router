using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The item. A result belongs to the version it ran against: a stored run renders as the row's
/// result only while its stamp equals the live version; when the version moves the result is
/// dropped, the row reads stale, a notice names the move, and nothing anywhere re-shows the old
/// tally against the new version. "Run the stale suite" acts only on stale rows.
/// </summary>
public sealed class VersionBoundTests : IDisposable
{
    private readonly string _directory;
    private readonly CheckHistoryStore _store;
    private readonly FakeClient _client;
    private readonly ChecksBoardModel _model;

    public VersionBoundTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), $"win8-ver-{Guid.NewGuid():N}");
        _store = new CheckHistoryStore(_directory);
        _client = new FakeClient();
        _model = new ChecksBoardModel(_client, _store, () => Now);
    }

    public DateTimeOffset Now { get; set; } = new(2026, 8, 31, 12, 0, 0, TimeSpan.Zero);

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

    [Fact]
    public async Task ARunAgainstTheLiveVersionRendersAsTheRowsResult()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        await _model.LoadAsync();
        await _model.RunAllAsync();

        var row = _model.Rows.Single();

        Assert.False(row.Result.IsStale);
        Assert.Equal("6 of 6", row.Result.Word);
        Assert.Equal("1.4.2", row.Result.Run!.Stamp);
        Assert.Equal("just now", row.Ran);
        Assert.Equal("6 confirmed", row.Result.Detail);
    }

    [Fact]
    public async Task WhenTheVersionMovesTheResultIsDroppedAndTheRowReadsStale()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        await _model.LoadAsync();
        await _model.RunAllAsync();

        // The capability moves: the user edited the entry, the router's digest changed.
        _client.Servers[0] = FakeClient.Server("trawl", stamp: "1.5.0");
        await _model.LoadAsync();

        var row = _model.Rows.Single();

        Assert.True(row.Result.IsStale);
        Assert.Equal(CheckCopy.StaleWord, row.Result.Word);

        // The old tally is never re-shown against the new version — not as the word, not as the
        // detail. "6 of 6" cannot be found on this row.
        Assert.Equal(CheckCopy.StaleWord, row.Result.Word);
        Assert.Equal(CheckCopy.StaleDetail(6, "1.4.2"), row.Result.Detail);
        Assert.Equal("1.5.0", row.LiveStamp!.Value);
        Assert.Equal(CheckCopy.NoRunMark, row.Ran);
    }

    [Fact]
    public async Task TheInvalidationNoticeNamesWhatWasDroppedAndWhy()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        await _model.LoadAsync();
        await _model.RunAllAsync();
        _client.Servers[0] = FakeClient.Server("trawl", stamp: "1.5.0");
        await _model.LoadAsync();

        var notice = Assert.Single(_model.Invalidations);

        Assert.Equal("server:trawl", notice.SubjectId);
        Assert.Equal("trawl", notice.Name);
        Assert.Equal("1.4.2", notice.StoredStamp);
        Assert.Equal("1.5.0", notice.LiveStamp);
        Assert.Contains("dropped", CheckCopy.Invalidated(notice.Name, notice.StoredStamp, notice.LiveStamp), StringComparison.Ordinal);
        Assert.Contains("1.4.2", CheckCopy.Invalidated(notice.Name, notice.StoredStamp, notice.LiveStamp), StringComparison.Ordinal);
        Assert.Contains("1.5.0", CheckCopy.Invalidated(notice.Name, notice.StoredStamp, notice.LiveStamp), StringComparison.Ordinal);
    }

    [Fact]
    public async Task TheStaleSuiteActsOnlyOnStaleRows()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        _client.Servers.Add(FakeClient.Server("design-review", stamp: "2.3.1"));
        await _model.LoadAsync();
        await _model.RunAllAsync();

        // Only trawl moves.
        _client.Servers[0] = FakeClient.Server("trawl", stamp: "1.5.0");
        await _model.LoadAsync();
        _client.ReindexCalls.Clear();

        await _model.RunStaleAsync();

        var called = Assert.Single(_client.ReindexCalls);
        Assert.Equal("trawl", called);

        Assert.False(_model.Rows.Single(r => r.Name == "trawl").Result.IsStale);
        Assert.Equal("2.3.1", _model.Rows.Single(r => r.Name == "design-review").Result.Run!.Stamp);
    }

    [Fact]
    public async Task RunAllActsOnEveryRow()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        _client.Servers.Add(FakeClient.Server("obscura", stamp: "0.2.0"));
        await _model.LoadAsync();

        await _model.RunAllAsync();

        Assert.Equal(2, _client.ReindexCalls.Count);
        Assert.All(_model.Rows, r => Assert.False(r.Result.IsStale));
    }

    [Fact]
    public async Task TheDroppedRunSurvivesInHistoryLabelledWithItsVersion()
    {
        _client.Servers.Add(FakeClient.Server("trawl", stamp: "1.4.2"));
        await _model.LoadAsync();
        await _model.RunAllAsync();
        _client.Servers[0] = FakeClient.Server("trawl", stamp: "1.5.0");
        await _model.LoadAsync();

        var row = _model.Rows.Single();
        var dropped = Assert.Single(row.History);

        Assert.Equal("1.4.2", dropped.Stamp);

        // The detail's heading names the version the run belongs to, so stale evidence can be
        // inspected without ever being presented against the version that replaced it.
        var heading = CheckCopy.LastCompleteRun("trawl", dropped.Stamp);
        Assert.Contains("1.4.2", heading, StringComparison.Ordinal);
        Assert.Contains("the last complete run", heading, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ARowWithNoStoredRunReadsNotChecked()
    {
        _client.Servers.Add(FakeClient.Server("docker-mcp", stamp: "1.2.0"));
        await _model.LoadAsync();

        var row = _model.Rows.Single();

        Assert.Equal(CheckCopy.NotChecked, row.Result.Word);
        Assert.Equal(CheckCopy.NoRunMark, row.Ran);
        Assert.Empty(_model.Invalidations);
    }

    [Fact]
    public async Task ASubjectWithNoVersionCanBeNeitherStoredNorInvalidated()
    {
        _client.Servers.Add(FakeClient.Server("unhashed", stamp: null));
        await _model.LoadAsync();

        await _model.RunAllAsync();

        var row = _model.Rows.Single();
        Assert.Equal(CheckCopy.Unstampable, row.Result.Word);
        Assert.Equal(CheckCopy.UnstampableDetail, row.Result.Detail);
        Assert.Null(row.LiveStamp);
        Assert.Empty(_model.Invalidations);
        Assert.Empty(_store.History(SubjectKey.Server("unhashed")));
    }

    [Fact]
    public async Task AFailedRunStoresNothingAndLeavesTheRowsWordAlone()
    {
        _client.Servers.Add(FakeClient.Server("obscura", stamp: "0.2.0"));
        _client.ReindexError = ControlApiError.ServerError(422, "could not start", null);
        await _model.LoadAsync();

        await _model.RunAllAsync();

        var row = _model.Rows.Single();
        Assert.True(_model.RunFailures.ContainsKey(row.SubjectId));
        Assert.Null(row.Result.Run);
        Assert.Equal(CheckCopy.NotChecked, row.Result.Word);
        Assert.False(row.Result.IsStale);
        Assert.Empty(_store.History(SubjectKey.Server("obscura")));
    }

    [Fact]
    public async Task ARefusedRunCarriesTheRoutersOwnErrorShape()
    {
        _client.Servers.Add(FakeClient.Server("obscura", stamp: "0.2.0"));
        await _model.LoadAsync();

        _client.ReindexError = ControlApiError.Unauthorized();
        await _model.RunAllAsync();

        var failure = _model.RunFailures["server:obscura"];
        Assert.Equal(ControlApiError.ControlErrorKind.Unauthorized, failure.Kind);
        Assert.Equal("This app isn't authorised to talk to the router", failure.Headline);
    }

    [Fact]
    public async Task SelectingARowExposesTheExchangesThatFailed()
    {
        _client.Servers.Add(FakeClient.Server("obscura", stamp: "0.2.0", usage: new UsageRecord { Calls = 12, Errors = 2 }));
        await _model.LoadAsync();
        await _model.RunAllAsync();

        var row = _model.Rows.Single();
        var results = _model.StoredResults(row);

        var failed = results.Single(r => r.Verdict == CheckVerdict.Failed);
        Assert.Equal(CheckId.CallsSucceed, failed.Check);
        Assert.Equal(CheckCopy.CallsFailed(2, 12), failed.Reason);

        // The exchange's input side comes from the live record for a current row.
        var input = _model.Input(failed, row);
        Assert.NotNull(input);
        Assert.Contains("usage.calls = 12", input, StringComparison.Ordinal);
        Assert.Contains("usage.errors = 2", input, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AStaleRowShowsNoLiveInputsBesideItsSupersededEvidence()
    {
        _client.Servers.Add(FakeClient.Server("obscura", stamp: "0.2.0", usage: new UsageRecord { Calls = 12, Errors = 2 }));
        await _model.LoadAsync();
        await _model.RunAllAsync();
        _client.Servers[0] = FakeClient.Server("obscura", stamp: "0.3.0");
        await _model.LoadAsync();

        var row = _model.Rows.Single();

        // The run is stale; the live record is a different version's. Its inputs must not be
        // printed beside the superseded run's results.
        Assert.True(row.Result.IsStale);
        foreach (var result in _model.StoredResults(row))
        {
            Assert.Null(_model.Input(result, row));
        }
    }
}

/// <summary>The seam's fake: an in-memory router with a reindex-call tape.</summary>
internal sealed class FakeClient : IChecksControlClient
{
    public List<ServerRecord> Servers { get; } = [];
    public List<string> ReindexCalls { get; } = [];
    public ControlApiError? ReindexError { get; set; }
    public ControlApiError? ServersError { get; set; }

    public static ServerRecord Server(string name, string? stamp, UsageRecord? usage = null) => new()
    {
        Name = name,
        Transport = "stdio",
        Hash = stamp,
        Tools = 3,
        IndexedAt = "2026-08-30T10:00:00Z",
        Auth = new AuthRecord { Supported = true, Authorized = true },
        Usage = usage ?? new UsageRecord { Calls = 4, Errors = 0 },
    };

    public Task<ServersResponse> ServersAsync(CancellationToken cancellation = default)
    {
        if (ServersError is not null)
        {
            throw ServersError;
        }

        return Task.FromResult(new ServersResponse { Port = 8879, Servers = [.. Servers] });
    }

    public Task<SkillsRead> SkillsAsync(CancellationToken cancellation = default) =>
        Task.FromResult(new SkillsRead(["the router answered 404 for /skills"]));

    public Task ReindexAsync(string serverName, CancellationToken cancellation = default)
    {
        ReindexCalls.Add(serverName);
        if (ReindexError is not null)
        {
            throw ReindexError;
        }

        return Task.CompletedTask;
    }
}
