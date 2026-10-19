using System.Globalization;
using MCPRouter.Shell.Model.Harnesses;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Harnesses board's states, decided in the model where a test can reach them: a board that
/// has not been read, a reading that arrived with rows, one that arrived empty, one the router never
/// answered, one it refused, and one that answered before and fails now. Every envelope here is the
/// one the TypeScript route sent (<see cref="HarnessesRouteFixture"/>), not a row written by hand.
/// </summary>
public sealed class HarnessesBoardModelTests
{
    [Fact]
    public void BeforeAnyReadTheBoardIsLoading()
    {
        var snapshot = HarnessesBoardModel.Snapshot(null, null);

        Assert.Equal(HarnessesBoardState.Loading, snapshot.State);
        Assert.Empty(snapshot.Harnesses);
    }

    [Fact]
    public void AReadingWithRowsIsPopulatedAndKeepsTheRoutersOrder()
    {
        var envelope = HarnessesRouteFixture.Envelope();

        var snapshot = HarnessesBoardModel.Snapshot(envelope, null);

        Assert.Equal(HarnessesBoardState.Populated, snapshot.State);
        Assert.Equal(envelope.Harnesses.Select(h => h.Harness), snapshot.Harnesses.Select(h => h.Harness));
        Assert.Equal(envelope.ReadAt, snapshot.ReadAt);
        Assert.Null(snapshot.Error);
    }

    [Fact]
    public void AReadingWithNoHarnessesIsAnHonestEmptyNotAnError()
    {
        var envelope = HarnessesRouteFixture.Envelope() with { Harnesses = [] };

        var snapshot = HarnessesBoardModel.Snapshot(envelope, null);

        Assert.Equal(HarnessesBoardState.Empty, snapshot.State);
        Assert.Empty(snapshot.Harnesses);
        Assert.Null(snapshot.Error);
    }

    [Theory]
    [InlineData(ControlApiFailure.RouterNotRunning, null)]
    [InlineData(ControlApiFailure.Transport, null)]
    public void AnUnansweredRouterIsUnreachable(ControlApiFailure kind, int? status)
    {
        var error = new ControlApiException(kind, "connection refused", status);

        var snapshot = HarnessesBoardModel.Snapshot(null, error);

        Assert.Equal(HarnessesBoardState.Unreachable, snapshot.State);
        Assert.Same(error, snapshot.Error);
        Assert.Empty(snapshot.Harnesses);
    }

    [Theory]
    [InlineData(ControlApiFailure.Unauthorized, 401)]
    [InlineData(ControlApiFailure.Server, 503)]
    [InlineData(ControlApiFailure.MalformedResponse, null)]
    public void ARouterThatRefusesOrCannotBeReadIsRefused(ControlApiFailure kind, int? status)
    {
        var error = new ControlApiException(kind, "the router said no", status);

        var snapshot = HarnessesBoardModel.Snapshot(null, error);

        Assert.Equal(HarnessesBoardState.Refused, snapshot.State);
        Assert.Same(error, snapshot.Error);
    }

    [Fact]
    public void AReadingThatFailsAfterAnEarlierOneIsStaleAndKeepsItsRows()
    {
        var envelope = HarnessesRouteFixture.Envelope();
        var error = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");

        var snapshot = HarnessesBoardModel.Snapshot(envelope, error);

        Assert.Equal(HarnessesBoardState.Stale, snapshot.State);
        Assert.Equal(envelope.Harnesses.Count, snapshot.Harnesses.Count);
        Assert.Equal(envelope.ReadAt, snapshot.ReadAt);
        Assert.Same(error, snapshot.Error);
    }

    [Theory]
    [InlineData("claudeDesktop", "Routed (stdio shim)")]
    [InlineData("codexCLI", "Routed (HTTP)")]
    [InlineData("claudeCode", "Double-running")]
    [InlineData("opencode", "Not routed")]
    public void EachRowIsLabelledByTheReadingTheRouterSent(string harness, string label)
    {
        Assert.Equal(label, HarnessesBoardModel.RowLabel(HarnessesRouteFixture.Row(harness)));
    }

    [Fact]
    public void AFileThatCannotBeReadIsLabelledUnreadableNotNotRouted()
    {
        // The router sends the empty report for an unreadable file: state not-wired, counts zero.
        // Labelling it "Not routed" would present a file nobody could read as a clean absence.
        var row = HarnessesRouteFixture.Row("cursor");

        Assert.Equal("not-wired", row.State);
        Assert.Equal("Unreadable", HarnessesBoardModel.RowLabel(row));
        Assert.False(HarnessesBoardModel.IsCaution(row));
    }

    [Fact]
    public void ADuplicatingHarnessIsACautionAndNamesItsDuplicates()
    {
        var row = HarnessesRouteFixture.Row("claudeCode");

        Assert.True(HarnessesBoardModel.IsCaution(row));
        Assert.Equal(
            "2 servers declared directly here that this router already fronts.",
            HarnessPresentation.DoubleRunningWarning(row.DuplicateCount));
    }

    [Fact]
    public void TheStaleNoteNamesTheReadingItStillShowsAndTheFailure()
    {
        var envelope = HarnessesRouteFixture.Envelope();
        var shownAt = DateTimeOffset.Parse(envelope.ReadAt, CultureInfo.InvariantCulture)
            .ToLocalTime()
            .ToString("HH:mm:ss", CultureInfo.InvariantCulture);

        var note = HarnessPresentation.StaleNote(envelope.ReadAt, "The router isn't running");

        Assert.Contains(shownAt, note, StringComparison.Ordinal);
        Assert.Contains("The router isn't running", note, StringComparison.Ordinal);
    }
}
