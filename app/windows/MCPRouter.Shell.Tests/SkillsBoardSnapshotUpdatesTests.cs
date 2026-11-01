using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The update check's read on the board snapshot. Its failure is independent, as the marketplace read's is: a
/// refused check keeps the register's own offers standing and says why the store's are missing.
/// </summary>
public sealed class SkillsBoardSnapshotUpdatesTests
{
    [Fact]
    public void TheStoresOfferArrivesBesideTheRegistersOffers()
    {
        var updates = new ExtensionUpdatesResponse(
            [
                new ExtensionUpdateEntry(
                    StoredExtensionKind.Plugins, "acceptance-e2e@diolog-plugins", "update-available",
                    "2.1.0", "2.2.0", true, "2.2.0 is offered and 2.1.0 is installed", null),
            ],
            []);

        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board, null,
            FixtureSkillsControlClient.Marketplaces, null,
            updates, null);

        // The fixture's four held rows, then the one offer only the store holds.
        Assert.Equal(5, snapshot.Offers.Count);
        Assert.Equal("acceptance-e2e@diolog-plugins", snapshot.Offers[^1].Name);
        Assert.Null(snapshot.UpdatesError);
    }

    [Fact]
    public void AFailedUpdateCheckKeepsTheRegistersOffersAndSaysWhy()
    {
        var refusal = new SkillsControlError.Server(500, "the update check could not read the store", null);

        var snapshot = SkillsBoardSnapshot.FromResults(
            FixtureSkillsControlClient.Board, null,
            FixtureSkillsControlClient.Marketplaces, null,
            null, refusal);

        Assert.Equal(SkillsBoardState.Populated, snapshot.State);
        Assert.Equal(refusal, snapshot.UpdatesError);
        Assert.Equal(4, snapshot.Offers.Count);
    }
}
