using System;
using System.Collections.Generic;
using MCPRouter.Shell.Model.Cleanup;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DEF-302's headless half. Every row here is derived from a <see cref="ServersEnvelope"/> — the
/// same shape the router answers — because the defect these replace was a model that could produce
/// rows with no router in the picture at all.
/// </summary>
public sealed class CleanupBoardModelTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 3, 12, 0, 0, TimeSpan.Zero);

    private static ServerRow Server(string name, int calls, string? lastUsed, string? firstSeen = "2026-06-01T00:00:00Z", int tools = 3) =>
        new()
        {
            Name = name,
            Transport = "stdio",
            State = "idle",
            InFlight = 0,
            CallsServed = calls,
            IdleSec = 0,
            Tools = tools,
            ToolNames = new List<string>(),
            Projects = new List<string>(),
            Warm = false,
            Disabled = false,
            Auth = new ServerAuth { Supported = false, Authorized = false },
            Usage = new ServerUsage { Calls = calls, Errors = 0, FirstSeen = firstSeen, LastUsed = lastUsed },
        };

    private static ServersEnvelope Envelope(params ServerRow[] servers) =>
        new() { Port = 8879, IdleMs = 0, Since = "2026-06-01T00:00:00Z", Servers = servers };

    [Fact]
    public void ANewModelIsLoadingAndProposesNothing()
    {
        var model = new CleanupBoardModel();

        // The state that makes "nothing to propose" impossible to draw over a router nobody asked.
        Assert.True(model.IsLoading);
        Assert.Equal(0, model.TotalCandidates);
        Assert.Null(model.ErrorMessage);
    }

    [Fact]
    public void AdoptSortsServersIntoNeverCalledAndQuiet()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(
            Server("never", calls: 0, lastUsed: null),
            Server("quiet", calls: 12, lastUsed: "2026-07-01T00:00:00Z"),
            Server("busy", calls: 900, lastUsed: "2026-09-02T00:00:00Z")), Now);

        Assert.Equal(new[] { "never" }, Names(model.NeverCalledRows));
        Assert.Equal(new[] { "quiet" }, Names(model.QuietRows));
        Assert.Equal(2, model.TotalCandidates);
        Assert.False(model.IsLoading);
    }

    [Fact]
    public void AServerJustInsideTheWindowIsNotACandidate()
    {
        var model = new CleanupBoardModel();
        // 29 days quiet against a 30-day window.
        model.Adopt(Envelope(Server("recent", calls: 4, lastUsed: "2026-08-05T12:00:00Z")), Now);

        Assert.Empty(model.QuietRows);
        Assert.Empty(model.NeverCalledRows);
    }

    [Fact]
    public void AServerWhoseLastUseIsUnreadableIsNotProposed()
    {
        var model = new CleanupBoardModel();
        // Called, but the router sent no lastUsed. Unknown is not "long ago": proposing removal
        // off a field that failed to parse is the guess this board must not make.
        model.Adopt(Envelope(Server("unknown-last-use", calls: 5, lastUsed: null)), Now);

        Assert.Empty(model.QuietRows);
        Assert.Empty(model.NeverCalledRows);
        Assert.Null(CleanupBoardModel.DaysSince("not a date", Now));
    }

    [Fact]
    public void SelectionSurvivesARefresh()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(Server("a", 0, null), Server("b", 0, null)), Now);
        model.SetSelection("a", true);
        Assert.Equal(1, model.SelectedCount);

        // The board polls every five seconds. A selection cleared by the refresh leaves the Remove
        // button permanently disabled, which looks exactly like the inert control DEF-302 names.
        model.Adopt(Envelope(Server("a", 0, null), Server("b", 0, null)), Now);

        Assert.Equal(1, model.SelectedCount);
        Assert.Equal("a", model.GetSelectedRows()[0].Id);
    }

    [Fact]
    public void ASelectionTheRouterStoppedListingIsDropped()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(Server("a", 0, null), Server("b", 0, null)), Now);
        model.SetSelection("a", true);
        model.SetSelection("b", true);

        // `a` leaves the router's list - removed here, by the CLI, or by another copy of the app.
        model.Adopt(Envelope(Server("b", 0, null)), Now);
        Assert.Equal(1, model.SelectedCount);
        Assert.Equal("b", model.GetSelectedRows()[0].Id);

        // And it comes back. THIS is the half that matters: a tick held over a name the router had
        // stopped listing would re-arm itself the moment something with that name reappeared, and
        // the operator would be one press away from removing a server they never selected.
        model.Adopt(Envelope(Server("a", 0, null), Server("b", 0, null)), Now);
        Assert.Equal(1, model.SelectedCount);
        Assert.Equal("b", model.GetSelectedRows()[0].Id);
    }

    [Fact]
    public void FailDropsEveryRowAndSaysWhy()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(Server("a", 0, null)), Now);
        Assert.Equal(1, model.TotalCandidates);

        model.Fail("the router did not answer");

        Assert.Equal(0, model.TotalCandidates);
        Assert.Equal("the router did not answer", model.ErrorMessage);
        Assert.False(model.IsLoading);
    }

    [Fact]
    public void MarkAllAsKeepClearsTheSelectionAcrossRefreshes()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(Server("a", 0, null)), Now);
        model.SetSelection("a", true);

        model.MarkAllAsKeep();
        Assert.Equal(0, model.SelectedCount);

        model.Adopt(Envelope(Server("a", 0, null)), Now);
        Assert.Equal(0, model.SelectedCount);
    }

    [Fact]
    public void NoSkillRowIsEverProduced()
    {
        var model = new CleanupBoardModel();
        model.Adopt(Envelope(Server("a", 0, null), Server("b", 3, "2026-01-01T00:00:00Z")), Now);

        Assert.All(model.NeverCalledRows, r => Assert.Equal(CleanupKind.Server, r.Kind));
        Assert.All(model.QuietRows, r => Assert.Equal(CleanupKind.Server, r.Kind));
    }

    [Fact]
    public void TheBoardPromisesNoUndo()
    {
        // DEF-400: the action row used to read "Removing is undoable for 30 days." while the
        // router's DELETE drops the entry and reloads.
        Assert.DoesNotContain("is undoable", CleanupPresentation.RemoveIrreversibleNote, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("not undoable", CleanupPresentation.RemoveIrreversibleNote, StringComparison.Ordinal);
    }

    [Fact]
    public void TheDialogNamesWhatItWouldRemove()
    {
        Assert.Equal("Remove alpha?", CleanupPresentation.RemoveDialogTitle(new[] { "alpha" }));
        Assert.Equal("Remove 2 servers?", CleanupPresentation.RemoveDialogTitle(new[] { "alpha", "beta" }));
        Assert.Equal("Keep it", CleanupPresentation.RemoveCancelLabel(1));
        Assert.Equal("Keep them", CleanupPresentation.RemoveCancelLabel(2));
        Assert.Contains("alpha", CleanupPresentation.RemoveDialogBody(new[] { "alpha" }), StringComparison.Ordinal);
    }

    private static string[] Names(IReadOnlyList<CleanupRow> rows)
    {
        var names = new string[rows.Count];
        for (int i = 0; i < rows.Count; i++) names[i] = rows[i].Name;
        return names;
    }
}
