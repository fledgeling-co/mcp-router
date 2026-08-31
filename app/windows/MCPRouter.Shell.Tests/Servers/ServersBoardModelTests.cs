using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The board's readings, derived in one place — these hold the counts the Signal Path draws to
/// the envelopes they come from, so a surface cannot quietly re-derive one differently.
/// </summary>
public sealed class ServersBoardModelTests
{
    private static ServersEnvelope Envelope(params ServerRow[] servers) => new()
    {
        Port = 8971,
        IdleMs = 300000,
        Since = "2026-08-25T11:45:27.733Z",
        Servers = servers,
    };

    private static ServerRow Row(
        string name = "probe",
        string state = "idle",
        int inFlight = 0,
        bool disabled = false,
        int pendingCount = 0) => new()
    {
        Name = name,
        Transport = "stdio",
        State = state,
        InFlight = inFlight,
        CallsServed = 0,
        IdleSec = 0,
        Hash = "h",
        Tools = 0,
        ToolNames = [],
        Projects = [],
        Warm = false,
        Disabled = disabled,
        PendingChange = pendingCount > 0
            ? new PendingChange { SeenAt = "2026-08-25T11:45:33.372Z", Count = pendingCount }
            : null,
        Auth = new ServerAuth { Supported = false, Authorized = true },
        Usage = new ServerUsage { Calls = 0, Errors = 0 },
    };

    [Fact]
    public void TheTopologyLineCountsWhatTheRoutesCount()
    {
        var servers = Enumerable.Range(0, 11).Select(i => Row(name: $"s{i}")).ToArray();
        var line = ServersBoardModel.Topology(harnessCount: 5, Envelope(servers));

        // The design of record's own line — and the proof it is computed, not drawn: change one
        // input and the line follows it.
        Assert.Equal("5 harnesses → 1 endpoint → 11 upstreams", line);
        Assert.Equal("5 harnesses → 1 endpoint → 12 upstreams",
            ServersBoardModel.Topology(5, Envelope(servers.Append(Row(name: "one-more")).ToArray())));
    }

    [Fact]
    public void CountsOfOneStayGrammatical()
    {
        // Drawn live against a one-server router: "1 upstreams" was on screen before this gate
        // existed to hold it.
        Assert.Equal("0 harnesses → 1 endpoint → 1 upstream",
            ServersBoardModel.Topology(0, Envelope(Row(name: "only"))));
        Assert.Equal("1 harness → 1 endpoint → 2 upstreams",
            ServersBoardModel.Topology(1, Envelope(Row(name: "a"), Row(name: "b"))));
    }

    [Fact]
    public void TheAtRestCountIsRunningChildrenWithNothingInFlight()
    {
        var envelope = Envelope(
            Row(name: "idle-child", state: "running"),
            Row(name: "awake-child", state: "running", inFlight: 1),
            Row(name: "starting-up", state: "starting"),
            Row(name: "asleep", state: "idle"));

        Assert.Equal(1, ServersBoardModel.AtRestCount(envelope));
    }

    [Fact]
    public void TheHubDrawsThePortTheRouterAnsweredOn()
    {
        // Never the constant the client dials by default — §2's LoopbackAddress rule. The
        // recorded fixture router answered on 8971 while the prototype drew 8879.
        Assert.Equal(":8971", ServersBoardModel.Endpoint(Envelope()));
    }

    [Fact]
    public void HeldRowsSkipDisabledServers()
    {
        // Switching a server off must not leave a band demanding a decision nothing can act on
        // (the Mac's needs-attention term, D11).
        var envelope = Envelope(
            Row(name: "held", pendingCount: 2),
            Row(name: "held-but-off", disabled: true, pendingCount: 3));

        var held = ServersBoardModel.HeldRows(envelope);
        Assert.Equal(new[] { "held" }, held.Select(s => s.Name));
    }

    [Fact]
    public void TheCalloutExplainsDormancyOnlyWhenThereIsSome()
    {
        var quiet = Envelope(Row(state: "running"));
        Assert.Null(ServersBoardModel.DormantCallout(quiet));

        var loud = Envelope(Row(name: "a"), Row(name: "b"), Row(name: "c", state: "running"));
        var callout = ServersBoardModel.DormantCallout(loud);
        Assert.NotNull(callout);
        Assert.StartsWith("2 upstreams are dormant", callout);

        var one = ServersBoardModel.DormantCallout(Envelope(Row(name: "a"), Row(name: "b", state: "running")));
        Assert.NotNull(one);
        Assert.StartsWith("1 upstream is dormant", one);
        Assert.Contains("its cached tool schema", one);
    }

    [Fact]
    public void TheHarnessDotReadsTheRowsOwnState()
    {
        Assert.Equal(DotTone.Lit, ServersBoardModel.HarnessDot(Harness("wired-http")));
        Assert.Equal(DotTone.Lit, ServersBoardModel.HarnessDot(Harness("wired-shim")));
        Assert.Equal(DotTone.Caution, ServersBoardModel.HarnessDot(Harness("wired-with-duplicates")));
        Assert.Equal(DotTone.Off, ServersBoardModel.HarnessDot(Harness("not-wired")));
    }

    [Fact]
    public void AnUnreadableHarnessIsCriticalNotCleanlyUnwired()
    {
        // unreadable is the member a consumer reads first: every other member of such a row is
        // the EMPTY report, the same bytes a clean unwired harness produces. Drawing that as
        // "not wired" is the confident wrong answer the collision already cost once.
        var unreadable = Harness("not-wired") with { Unreadable = "unexpected end of file" };

        Assert.Equal(DotTone.Critical, ServersBoardModel.HarnessDot(unreadable));
        Assert.Equal("unreadable", ServersBoardModel.HarnessWord(unreadable));
    }

    [Fact]
    public void TheHarnessWordCarriesWhatTheDotCannot()
    {
        Assert.Equal("wired", ServersBoardModel.HarnessWord(Harness("wired-http")));
        Assert.Equal("wired via shim", ServersBoardModel.HarnessWord(Harness("wired-shim")));
        Assert.Equal("3 duplicates", ServersBoardModel.HarnessWord(Harness("wired-with-duplicates", duplicates: 3)));
        Assert.Equal("not wired", ServersBoardModel.HarnessWord(Harness("not-wired")));
    }

    private static HarnessRow Harness(string state, int duplicates = 0, string? unreadable = null) => new()
    {
        Harness = "claude-code",
        DisplayName = "Claude Code",
        Path = "/home/probe/.claude.json",
        Exists = true,
        Unreadable = unreadable,
        State = state,
        Route = state == "wired-http" ? "http" : state == "not-wired" ? "none" : "stdio-shim",
        Entries = 2,
        DuplicateCount = duplicates,
        HttpCapability = "none",
        Capability = "unknown",
    };
}
