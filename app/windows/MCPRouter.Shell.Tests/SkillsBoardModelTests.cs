using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Skills board's load-state machine, on the fixture board the design of record draws. The
/// counts here are the ones the head and tabs display, so they are held exactly - including the
/// one the brief overrides the mock on: Update all counts 3, not 4, because the held-for-review
/// row is never silently in the set.
/// </summary>
public sealed class SkillsBoardModelTests
{
    private static SkillsControlError ServerError { get; } =
        new SkillsControlError.Server(500, "boom", null);

    [Fact]
    public void TheFixtureBoardCountsWhatTheMockDraws()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board,
            null,
            FixtureSkillsControlClient.Marketplaces,
            null);

        Assert.Equal(SkillsBoardState.Populated, snapshot.State);
        Assert.Equal(7, snapshot.InstalledCount);
        Assert.Equal(3, snapshot.MarketplacesCount);
        // The Updates tab lists every fetched version: three promote-ons, one held.
        Assert.Equal(4, snapshot.Updated.Count);
        // ...and Update all counts only the ones asking for nothing more. The mock's head draws
        // 4; the brief's security clause wins (spec-WIN6 §3.1).
        Assert.Equal(3, snapshot.UpdateAllCount);
    }

    [Fact]
    public void TheHeldForReviewSetIsExactlyTheRowsWantingMore()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board, null,
            FixtureSkillsControlClient.Marketplaces, null);

        var held = Assert.Single(snapshot.HeldForReview);
        Assert.Equal("design-review", held.Name);
        Assert.Equal(["network access"], held.Held?.AddedCapabilities);
    }

    [Fact]
    public void NoSkillsIsTheEmptyStateNotAnError()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            new SkillsResponse([], [FixtureSkillsControlClient.Board.ClientList[0]]),
            null,
            new MarketplacesResponse([]),
            null);

        Assert.Equal(SkillsBoardState.Empty, snapshot.State);
        Assert.Empty(snapshot.HeldForReview);
    }

    [Fact]
    public void TheRouterNotRunningIsTheOfflineState()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            null, new SkillsControlError.RouterNotRunning(), null, null);

        Assert.Equal(SkillsBoardState.Offline, snapshot.State);
        Assert.Equal("The router isn't running", snapshot.Error?.Headline);
    }

    [Fact]
    public void AnyOtherFailureIsTheFailedStateWithItsCopy()
    {
        foreach (var error in new SkillsControlError[]
                 {
                     new SkillsControlError.MalformedResponse("this router has no /skills endpoint"),
                     new SkillsControlError.Unauthorized(),
                     ServerError,
                     new SkillsControlError.Transport("reset"),
                 })
        {
            var snapshot = SkillsBoardSnapshot.FromResults(null, error, null, null);

            Assert.Equal(SkillsBoardState.Failed, snapshot.State);
            Assert.Same(error, snapshot.Error);
        }
    }

    [Fact]
    public void AnUnreadableClientRaisesThePartialNote()
    {
        var board = FixtureSkillsControlClient.Board;
        var withUnreadable = new SkillsResponse(
            board.SkillList.ToArray(),
            board.ClientList.Append(
                new SkillClient("grok", "Grok", true, "~/.grok/installed-plugins",
                    SkillClientStatus.Unreadable, "permission denied")).ToArray());

        var snapshot = SkillsBoardSnapshot.FromResults(
            withUnreadable, null, FixtureSkillsControlClient.Marketplaces, null);

        Assert.NotNull(snapshot.PartialNote);
        Assert.Contains("Grok", snapshot.PartialNote);
        Assert.Contains("permission denied", snapshot.PartialNote);
    }

    [Fact]
    public void TheFixtureBoardAsShippedHasNoPartialNote()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board, null,
            FixtureSkillsControlClient.Marketplaces, null);

        Assert.Null(snapshot.PartialNote);
    }

    [Fact]
    public void AFailedMarketplaceReadKeepsTheSkillsAndSaysWhatDidNotArrive()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board,
            null,
            null,
            new SkillsControlError.MalformedResponse("this router has no /marketplaces endpoint"));

        Assert.Equal(SkillsBoardState.Populated, snapshot.State);
        Assert.Null(snapshot.Marketplaces);
        Assert.NotNull(snapshot.MarketplaceListNote);
        Assert.Contains("didn't load", snapshot.MarketplaceListNote);
    }

    [Fact]
    public void ALoadedMarketplaceListCarriesNoNote()
    {
        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board, null,
            FixtureSkillsControlClient.Marketplaces, null);

        Assert.Null(snapshot.MarketplaceListNote);
    }

    [Fact]
    public void AResponseWithNeitherResultNorErrorIsALieAndThrows()
    {
        Assert.Throws<InvalidOperationException>(() =>
            SkillsBoardSnapshot.FromResults(null, null, null, null));
    }
}
