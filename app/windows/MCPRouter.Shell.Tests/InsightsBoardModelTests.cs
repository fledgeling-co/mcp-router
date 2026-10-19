using System.Globalization;
using MCPRouter.Shell.Model.Insights;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Insights board's states and figures, decided in the model where a test can reach them. Every
/// envelope here is the one the TypeScript route sent (<see cref="InsightsRouteFixture"/>), not a row
/// written by hand. The one exception is the analyst that is not served, which the route answers only
/// when the router has no analyst; the test sets that member to null directly.
/// </summary>
public sealed class InsightsBoardModelTests
{
    private static string ShownAt(string readAt) =>
        DateTimeOffset.Parse(readAt, CultureInfo.InvariantCulture)
            .ToLocalTime()
            .ToString("HH:mm:ss", CultureInfo.InvariantCulture);

    private static InsightsFigure Figure(InsightsBoardSnapshot snapshot, string key) =>
        Assert.Single(snapshot.Figures, f => f.Key == key);

    [Fact]
    public void BeforeAnyReadTheBoardIsLoadingAndDrawsNothing()
    {
        var snapshot = InsightsBoardModel.Snapshot(null, null);

        Assert.Equal(InsightsBoardState.Loading, snapshot.State);
        Assert.Empty(snapshot.Figures);
        Assert.Empty(snapshot.Harnesses);
        Assert.Null(snapshot.Analyst);
        Assert.False(snapshot.AnalyseNowEnabled);
    }

    [Fact]
    public void AReadingWithCallsIsPopulatedAndDrawsTheFourFigures()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        Assert.Equal(InsightsBoardState.Populated, snapshot.State);
        Assert.Equal(new[] { "processes", "memory", "calls", "failed" }, snapshot.Figures.Select(f => f.Key));
        Assert.Null(snapshot.Error);
    }

    [Fact]
    public void EveryFigureNamesItsDenominatorOrItsProvenance()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        foreach (var figure in snapshot.Figures)
        {
            Assert.False(string.IsNullOrWhiteSpace(figure.Provenance), figure.Key);
        }
    }

    [Fact]
    public void NoFigureIsOneTheRouterDidNotReport()
    {
        // The design's "peak 4" is not on the wire, so it is not drawn.
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        Assert.DoesNotContain(snapshot.Figures, f => f.Provenance.Contains("peak", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(snapshot.Figures, f => f.Value.Contains("peak", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void ProcessesCarryTheDeclaredCountAsTheirDenominator()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        var processes = Figure(snapshot, "processes");
        Assert.Equal("0", processes.Value);
        Assert.Equal("of 1 declared", processes.Provenance);
    }

    [Fact]
    public void AnUnmeasuredMemoryReadingIsNamedNotShownAsZero()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        var memory = Figure(snapshot, "memory");
        Assert.Equal("No measurement", memory.Value);
        Assert.Equal("no child process has been measured", memory.Provenance);
    }

    [Fact]
    public void AMeasuredMemoryReadingIsLabelledAsMeasuredAcrossItsChildren()
    {
        var envelope = InsightsRouteFixture.Populated() with
        {
            Resident = new InsightsResident { Megabytes = 214.4, Children = 2 },
        };

        var memory = Figure(InsightsBoardModel.Snapshot(envelope, null), "memory");

        Assert.Equal("214 MB", memory.Value);
        Assert.Equal("measured across 2 child processes", memory.Provenance);
    }

    [Fact]
    public void ToolCallsAreTheRoutersTotalOverItsWindow()
    {
        var calls = Figure(InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null), "calls");

        Assert.Equal("12", calls.Value);
        Assert.Equal("in the last 24 hours", calls.Provenance);
    }

    [Fact]
    public void FailedCallsAreAPercentageWithItsCounts()
    {
        var failed = Figure(InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null), "failed");

        Assert.Equal("16.67%", failed.Value);
        Assert.Equal("2 of 12 calls", failed.Provenance);
    }

    [Fact]
    public void AWindowWithNoCallsIsEmptyAndShowsNoRateRatherThanZero()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Idle(), null);

        Assert.Equal(InsightsBoardState.Empty, snapshot.State);
        Assert.Equal("0", Figure(snapshot, "calls").Value);
        Assert.Equal("—", Figure(snapshot, "failed").Value);
        Assert.Equal("no calls in the window to measure", Figure(snapshot, "failed").Provenance);
        Assert.Contains("No calls have reached this router in the last 24 hours.", snapshot.Notes);
    }

    [Fact]
    public void EachHarnessShowsItsOwnCountAndItsShareOfTheTotal()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        var claude = Assert.Single(snapshot.Harnesses, h => h.Name == "Claude Code");
        Assert.Equal("8", claude.Calls);
        Assert.Equal("66.7%", claude.Share);
        Assert.Null(claude.Explanation);
    }

    [Fact]
    public void AHarnessWhoseCallsCannotBeCountedShowsTheRoutersReasonNotAZero()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        var codex = Assert.Single(snapshot.Harnesses, h => h.Name == "Codex CLI");
        Assert.Equal("—", codex.Calls);
        Assert.Null(codex.Share);
        Assert.Contains("codex", codex.Explanation, StringComparison.Ordinal);
    }

    [Fact]
    public void CallsNotAttributedToAHarnessAreAnOtherLineThatReconciles()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        var other = Assert.Single(snapshot.Harnesses, h => h.Name == "Other calls");
        Assert.Equal("4", other.Calls);
        Assert.Equal("33.3%", other.Share);
    }

    [Fact]
    public void AHarnessWithNoCallsSaysSoRatherThanShowingABareZero()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Idle(), null);

        var claude = Assert.Single(snapshot.Harnesses, h => h.Name == "Claude Code");
        Assert.Equal("0", claude.Calls);
        Assert.Equal("No calls from this harness in the window.", claude.Explanation);
    }

    [Fact]
    public void AMissingHarnessInventoryIsSaidNotLeftBlank()
    {
        var envelope = InsightsRouteFixture.Populated() with { CallsByHarness = [], OtherCalls = 12 };

        var snapshot = InsightsBoardModel.Snapshot(envelope, null);

        Assert.Contains(
            "No harness configuration was found, so calls can't be attributed to a harness.",
            snapshot.Notes);
    }

    [Fact]
    public void UnreadableUsageLinesAreNamedAsNotCounted()
    {
        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null);

        Assert.Contains("1 usage log line couldn't be read and isn't counted.", snapshot.Notes);
        Assert.DoesNotContain(InsightsBoardModel.Snapshot(InsightsRouteFixture.Idle(), null).Notes,
            n => n.Contains("couldn't be read", StringComparison.Ordinal));
    }

    [Fact]
    public void TheAnalystCardStatesItsLastRunInCountedTerms()
    {
        var envelope = InsightsRouteFixture.Populated();

        var card = InsightsBoardModel.Snapshot(envelope, null).Analyst!;

        Assert.True(card.Available);
        Assert.Equal(
            $"Last run at {ShownAt(envelope.Analyst!.RanAt!)}: 12,400 lines read, 1 finding, judged by Claude CLI · haiku.",
            card.LastRun);
    }

    [Fact]
    public void AnUnreadStoreIsNamedWithItsReasonAndTheReadCountIsStated()
    {
        var card = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null).Analyst!;

        Assert.Contains("Read 2 of 3 session stores.", card.StoreNotes);
        Assert.Contains("Cursor wasn't read: SQLite store, not read by this reader.", card.StoreNotes);
    }

    [Fact]
    public void AnAnalystThatIsNotScheduledSaysSoAndShowsNoNextRunTime()
    {
        var envelope = InsightsRouteFixture.Populated();

        var card = InsightsBoardModel.Snapshot(envelope, null).Analyst!;

        Assert.Equal("Saved cadence: Every 6 hours. Not scheduled: the analyst runs only when you press Analyse now.", card.ScheduleNote);
        Assert.DoesNotContain(ShownAt(envelope.Analyst!.NextRunAt!), card.ScheduleNote!, StringComparison.Ordinal);
    }

    [Fact]
    public void AnAnalystThatHasNeverRunSaysSo()
    {
        var card = InsightsBoardModel.Snapshot(InsightsRouteFixture.Idle(), null).Analyst!;

        Assert.True(card.Available);
        Assert.Equal("The analyst has not run yet.", card.LastRun);
        Assert.Empty(card.StoreNotes);
    }

    [Fact]
    public void AnUnservedAnalystSaysSoAndHasNoRunToShow()
    {
        var envelope = InsightsRouteFixture.Populated() with { Analyst = null };

        var snapshot = InsightsBoardModel.Snapshot(envelope, null);

        Assert.False(snapshot.Analyst!.Available);
        Assert.Equal("The session analyst isn't available on this router.", snapshot.Analyst.Notice);
        Assert.Null(snapshot.Analyst.LastRun);
    }

    [Fact]
    public void AnalyseNowIsEnabledWhenTheRouterServesTheRoute()
    {
        Assert.True(InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null).AnalyseNowEnabled);
        Assert.True(InsightsBoardModel.Snapshot(InsightsRouteFixture.Idle(), null).AnalyseNowEnabled);
    }

    [Fact]
    public void AnalyseNowIsDisabledWhenTheRouterHasNoAnalyst()
    {
        var envelope = InsightsRouteFixture.Populated() with { Analyst = null };

        Assert.False(InsightsBoardModel.Snapshot(envelope, null).AnalyseNowEnabled);
    }

    [Fact]
    public void AnalyseNowIsDisabledOnAStaleReadBecauseTheRouterCannotBeReached()
    {
        var error = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");

        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), error);

        Assert.Equal(InsightsBoardState.Stale, snapshot.State);
        Assert.False(snapshot.AnalyseNowEnabled);
    }

    [Fact]
    public void AnalyseNowIsDisabledWhenNothingHasBeenRead()
    {
        var error = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");

        Assert.False(InsightsBoardModel.Snapshot(null, null).AnalyseNowEnabled);
        Assert.False(InsightsBoardModel.Snapshot(null, error).AnalyseNowEnabled);
    }

    [Fact]
    public void AStaleReadKeepsItsFiguresAndNamesTheReadingItShows()
    {
        var envelope = InsightsRouteFixture.Populated();
        var error = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");

        var snapshot = InsightsBoardModel.Snapshot(envelope, error);

        Assert.Equal(InsightsBoardState.Stale, snapshot.State);
        Assert.Equal(4, snapshot.Figures.Count);
        Assert.Equal(envelope.GeneratedAt, snapshot.ReadAt);
        Assert.Same(error, snapshot.Error);
        Assert.Contains(
            $"The router isn't running. Showing the reading from {ShownAt(envelope.GeneratedAt)}; the figures may no longer match the router.",
            snapshot.Notes);
    }

    [Theory]
    [InlineData(ControlApiFailure.RouterNotRunning)]
    [InlineData(ControlApiFailure.Transport)]
    public void AnUnansweredRouterIsUnreachableAndDrawsNoFigures(ControlApiFailure kind)
    {
        var error = new ControlApiException(kind, "the request did not complete");

        var snapshot = InsightsBoardModel.Snapshot(null, error);

        Assert.Equal(InsightsBoardState.Unreachable, snapshot.State);
        Assert.Same(error, snapshot.Error);
        Assert.Empty(snapshot.Figures);
    }

    [Theory]
    [InlineData(ControlApiFailure.Unauthorized, 401)]
    [InlineData(ControlApiFailure.Server, 503)]
    [InlineData(ControlApiFailure.MalformedResponse, null)]
    public void ARouterThatRefusesOrCannotBeReadIsRefusedAndDrawsNoFigures(ControlApiFailure kind, int? status)
    {
        var error = new ControlApiException(kind, "the router said no", status);

        var snapshot = InsightsBoardModel.Snapshot(null, error);

        Assert.Equal(InsightsBoardState.Refused, snapshot.State);
        Assert.Same(error, snapshot.Error);
        Assert.Empty(snapshot.Figures);
    }

    [Fact]
    public void AFailedAnalyseIsCarriedForTheCardAndLeavesTheReadingAlone()
    {
        var failure = new ControlApiException(ControlApiFailure.Server, "no analyst model answered — claude: not signed in", 502);

        var snapshot = InsightsBoardModel.Snapshot(InsightsRouteFixture.Populated(), null, failure);

        Assert.Same(failure, snapshot.AnalyseFailure);
        Assert.Equal(InsightsBoardState.Populated, snapshot.State);
        Assert.Equal("12", Figure(snapshot, "calls").Value);
    }

    [Fact]
    public void TheShippingBoardDrawsNoSampleFigures()
    {
        // The design's numbers and labels are what the board showed before it read the router. None of them may
        // reach the shipping view or its model.
        var shipped = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/InsightsBoard.xaml")
            + RepoRoot.Read("app/windows/MCPRouter.Shell/Views/InsightsBoard.xaml.cs")
            + RepoRoot.Read("app/windows/MCPRouter.Shell.Model/Insights/InsightsBoardModel.cs");

        foreach (var sample in new[] { "9,418", "214 MB", "0.13%", "Antigravity", "peak 4", "Last 7 days", "1,482" })
        {
            Assert.DoesNotContain(sample, shipped, StringComparison.Ordinal);
        }
    }
}
