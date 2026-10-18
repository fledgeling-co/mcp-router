using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The board's load states and the §5 rows they carry: the first read failing is the
/// disconnected state with the ported headline; a failure after a reading keeps the reading and
/// says why; a partial read says what arrived and what did not, with the reason.
/// </summary>
public sealed class ChecksBoardModelTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"win8-model-{Guid.NewGuid():N}");

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

    private ChecksBoardModel NewModel(FakeClient client) =>
        new(client, new CheckHistoryStore(_directory));

    [Fact]
    public async Task ALoadedBoardCarriesOneRowPerCapability()
    {
        var client = new FakeClient();
        client.Servers.Add(FakeClient.Server("trawl", "1.4.2"));
        client.Servers.Add(FakeClient.Server("obscura", "0.2.0"));
        var model = NewModel(client);

        await model.LoadAsync();

        Assert.Equal(ChecksBoardModel.LoadState.Loaded, model.State);
        Assert.Equal(2, model.Rows.Count);
        Assert.Equal("trawl", model.Rows[0].Name);
        Assert.Equal("stdio", model.Rows[0].Detail);
        Assert.Null(model.Error);
    }

    [Fact]
    public async Task AFailingFirstReadIsTheDisconnectedStateWithThePortedHeadline()
    {
        var client = new FakeClient { ServersError = ControlApiError.RouterNotRunning() };
        var model = NewModel(client);

        await model.LoadAsync();

        Assert.Equal(ChecksBoardModel.LoadState.Failed, model.State);
        Assert.NotNull(model.Error);
        Assert.Equal(CheckCopy.RouterNotRunningHeadline, model.Error!.Headline);
        Assert.Equal(CheckCopy.RouterNotRunningAdvice, model.Error.Advice);
        Assert.Empty(model.Rows);
    }

    [Fact]
    public async Task AFailureAfterAReadingKeepsTheReadingAndSaysWhy()
    {
        var client = new FakeClient();
        client.Servers.Add(FakeClient.Server("trawl", "1.4.2"));
        var model = NewModel(client);
        await model.LoadAsync();

        client.ServersError = ControlApiError.RouterNotRunning();
        await model.LoadAsync();

        // Stale-with-reading: the rows survive and the error is beside them, not instead of them.
        Assert.Equal(ChecksBoardModel.LoadState.Stale, model.State);
        Assert.Equal(CheckCopy.RouterNotRunningHeadline, model.Error!.Headline);
        Assert.Single(model.Rows);
    }

    [Fact]
    public async Task TheSkillsAbsenceIsNamedWithItsReason()
    {
        var client = new FakeClient();
        client.Servers.Add(FakeClient.Server("trawl", "1.4.2"));
        var model = NewModel(client);

        await model.LoadAsync();

        var reason = Assert.Single(model.SkillsAbsentReasons);
        Assert.Contains("404", reason, StringComparison.Ordinal);
        // And the server half draws regardless.
        Assert.Single(model.Rows);
    }

    [Fact]
    public async Task ALiveServerRecordIsKeptForTheDetailButOnlyCurrentRowsShowInputs()
    {
        var client = new FakeClient();
        client.Servers.Add(FakeClient.Server("trawl", "1.4.2"));
        var model = NewModel(client);
        await model.LoadAsync();

        Assert.True(model.LiveServers.ContainsKey("trawl"));
        var row = model.Rows.Single();
        Assert.Empty(_ = model.StoredResults(row));
    }

    [Fact]
    public void ABrandNewBoardIsLoading()
    {
        var model = NewModel(new FakeClient());
        Assert.Equal(ChecksBoardModel.LoadState.Loading, model.State);
        Assert.Empty(model.Rows);
    }

    [Fact]
    public async Task NothingIsStaleOnTheVeryFirstReconciliation()
    {
        var client = new FakeClient();
        client.Servers.Add(FakeClient.Server("fresh", "9.9.9"));
        var model = NewModel(client);

        await model.LoadAsync();

        Assert.Empty(model.Invalidations);
        Assert.Equal(CheckCopy.NotChecked, model.Rows.Single().Result.Word);
    }
}
