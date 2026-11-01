using MCPRouter.Shell.Model;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The held-version copy, verbatim from the Mac's <c>SkillCopy.swift</c> (DESIGN.md §6: one wording per state across
/// both devices), and the update check's offers, merged as the Mac's <c>SkillUpdateOffers.swift</c> merges them.
/// </summary>
public sealed class SkillPresentationWriteTests
{
    [Fact]
    public void MissingInstalledUpdaterCapabilityIsExplicitlyUnavailable()
    {
        var response = System.Text.Json.JsonSerializer.Deserialize<SkillsResponse>("{\"skills\":[],\"clients\":[],\"promoteFromCache\":true}")!;
        Assert.Equal(SkillPresentation.InstalledPluginUpdatesUnavailable, response.InstalledPluginUpdateReason);
        Assert.True(response.PromotesFromCache);
    }

    [Fact]
    public void TheKeptCopyNamesWhatTheRouterRecordedAndClaimsNoBadgeCleared()
    {
        Assert.Equal("Kept 2.3.0. The router has recorded that you kept it.", SkillPresentation.Kept("2.3.0"));
    }

    [Fact]
    public void ThePromotedCopyNamesTheCopyKeptAndTheUndo()
    {
        Assert.Equal(
            "Copied trawl 2.3.0 to the router store. Undo restores the previous router copy. Claude Code was not changed.",
            SkillPresentation.Promoted("trawl", "2.3.0"));
    }

    [Fact]
    public void TheUndoCopyNamesTheVersionPutBackWhenTheRouterSaysIt()
    {
        Assert.Equal(
            "Restored the router copy of trawl at 2.2.0. Claude Code was not changed.",
            SkillPresentation.Undone("trawl", "2.2.0"));
    }

    [Fact]
    public void TheUndoCopyDoesNotInventAVersionTheRouterDidNotSend()
    {
        Assert.Equal("Restored the router copy of trawl. Claude Code was not changed.", SkillPresentation.Undone("trawl", null));
    }

    [Fact]
    public void TheUndoBarCopyNamesThePluginThatWasPromoted()
    {
        Assert.Equal(
            "The router copy of trawl changed. Undo restores the previous router copy.",
            SkillPresentation.PromotionCanBeUndone("trawl"));
    }

    [Fact]
    public void PromoteIsDimmedWithTheReasonOnARouterThatDoesNotServeTheCache()
    {
        Assert.Equal(
            "Promoting reads the held version from Claude's plugin cache, and this router does not serve that yet.",
            SkillPresentation.PromoteUnavailable);
    }

    [Fact]
    public void TheUpdateSectionNamesItsHeadingAndTheOffersReadingBesideTheRow()
    {
        Assert.Equal("Updates available", SkillPresentation.UpdatesHeading);
        Assert.Equal("2.3.0 is offered and 2.2.0 is installed", SkillPresentation.Offered("2.3.0", "2.2.0"));
    }

    [Fact]
    public void AnEmptyUpdateCheckSaysWhatItCovered()
    {
        Assert.Equal(
            "The update check found no newer version among the plugins Claude has installed and the entries this router holds.",
            SkillPresentation.UpdatesNone);
    }

    [Fact]
    public void TheRegistersOfferLeadsAndCarriesItsChangelog()
    {
        var changelog = new SkillChangelog("# Changelog", "CHANGELOG.md from the cached 2.3.0 copy");
        var skills = new[] { HeldSkill("trawl", "trawl", "2.2.0", "2.3.0", changelog) };
        var stored = new[] { StoredOffer("design-review@fledgeling-plugins", "2.3.1", "2.4.0") };

        var offers = SkillPresentation.UpdateOffers(skills, stored);

        Assert.Equal(2, offers.Count);
        var first = offers[0];
        Assert.Equal(StoredExtensionKind.Plugins, first.Kind);
        Assert.Equal("trawl@fledgeling-plugins", first.Name);
        Assert.Equal("update-available", first.State);
        Assert.Equal("2.2.0", first.Installed);
        Assert.Equal("2.3.0", first.Available);
        Assert.True(first.HasUpdate);
        Assert.Equal("2.3.0 is offered and 2.2.0 is installed", first.Reason);
        Assert.Equal("# Changelog", first.Changelog?.Text);
    }

    [Fact]
    public void APluginWithTwoHeldSkillsIsOfferedOnce()
    {
        var skills = new[]
        {
            HeldSkill("trawl", "trawl", "2.2.0", "2.3.0", null),
            HeldSkill("trawl-extra", "trawl", "2.2.0", "2.3.0", null),
        };

        Assert.Single(SkillPresentation.UpdateOffers(skills, []));
    }

    [Fact]
    public void AStoredOfferTheRegisterDoesNotHoldIsStillOffered()
    {
        var skills = new[] { HeldSkill("trawl", "trawl", "2.2.0", "2.3.0", null) };
        var stored = new[] { StoredOffer("design-review@fledgeling-plugins", "2.3.1", "2.4.0") };

        var offers = SkillPresentation.UpdateOffers(skills, stored);

        Assert.Equal(2, offers.Count);
        Assert.Equal("design-review@fledgeling-plugins", offers[1].Name);
        Assert.True(offers[1].HasUpdate);
    }

    [Fact]
    public void AStoredOfferTheRegisterAlreadyOffersIsNotListedTwice()
    {
        var skills = new[] { HeldSkill("trawl", "trawl", "2.2.0", "2.3.0", null) };
        var stored = new[] { StoredOffer("trawl@fledgeling-plugins", "2.2.0", "2.3.0") };

        Assert.Single(SkillPresentation.UpdateOffers(skills, stored));
    }

    [Fact]
    public void AStoredEntryWithNothingNewerIsNotAnOffer()
    {
        var stored = new[]
        {
            new ExtensionUpdateEntry(
                StoredExtensionKind.Plugins, "trawl@fledgeling-plugins", "current", "2.3.0", "2.3.0", false,
                "2.3.0 is installed and nothing newer is offered", null),
        };

        Assert.Empty(SkillPresentation.UpdateOffers([], stored));
    }

    private static Skill HeldSkill(
        string name, string plugin, string installed, string offered, SkillChangelog? changelog) => new(
        Name: name,
        Description: null,
        Path: $"/cache/{plugin}/{installed}/skills/{name}",
        Source: new SkillSource.PluginOrigin(plugin, "fledgeling-plugins", installed, null, null, null, 1),
        Presence: new Dictionary<string, SkillPresence>(),
        Held: new HeldVersion(offered, ["capabilities not compared with the installed version"], 1, changelog));

    private static ExtensionUpdateEntry StoredOffer(string name, string installed, string available) => new(
        StoredExtensionKind.Plugins,
        name,
        "update-available",
        installed,
        available,
        true,
        $"{available} is offered and {installed} is installed",
        null);
}
