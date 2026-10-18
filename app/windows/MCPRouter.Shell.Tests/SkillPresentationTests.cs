using MCPRouter.Shell.Model;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Skills board's decisions, held to the Mac's shipped rules - and above all the brief's
/// security clause: a version asking for more than the installed one is HELD, never counted in
/// "Update all", and the board says what it asks for.
/// </summary>
public sealed class SkillPresentationTests
{
    private static Skill PluginSkill(
        string name = "trawl",
        string marketplace = "fledgeling-plugins",
        string pluginVersion = "1.4.2",
        HeldVersion? held = null,
        SkillProvenance? provenance = null,
        Dictionary<string, SkillPresence>? presence = null,
        int siblings = 1) =>
        new(
            name,
            "A test skill.",
            $"~/.claude/plugins/cache/{marketplace}/{name}/{pluginVersion}/skills/{name}",
            new SkillSource.PluginOrigin(
                name, marketplace, pluginVersion,
                "2026-08-02", "2026-08-17", "4c1e08a", siblings),
            presence ?? new Dictionary<string, SkillPresence> { ["claudeCode"] = SkillPresence.Present },
            held,
            provenance);

    private static readonly SkillClient ClaudeCode =
        new("claudeCode", "Claude Code", true, "~/.claude/skills", SkillClientStatus.Read, null);
    private static readonly SkillClient Cursor =
        new("cursor", "Cursor", true, "~/.cursor/skills", SkillClientStatus.Read, null);
    private static readonly SkillClient Unreadable =
        new("grok", "Grok", true, "~/.grok/installed-plugins", SkillClientStatus.Unreadable, "permission denied");
    private static readonly SkillClient Unsupported =
        new("windsurf", "Windsurf", false, null, SkillClientStatus.Unsupported, null);

    // ------------------------------------------------------------------ the version cell

    [Fact]
    public void AStandaloneSkillHasNoVersionToRender()
    {
        var skill = new Skill(
            "graphify", null, "~/.claude/skills/graphify",
            new SkillSource.Standalone("~/.claude/skills/graphify"),
            new Dictionary<string, SkillPresence>());

        var cell = SkillPresentation.Version(skill);

        Assert.Equal("unversioned", cell.Text);
        // The body face, not the instrument face: "unversioned" is a statement about the skill,
        // not a reading off it (DESIGN.md §2 reserves monospace for instrument data).
        Assert.False(cell.IsInstrument);
        Assert.False(cell.IsHeld);
    }

    [Fact]
    public void AHeldVersionReadsAsAnArrowBetweenTheTwoVersions()
    {
        var skill = PluginSkill(held: new HeldVersion("2.4.0", ["network access"], 1), pluginVersion: "2.3.1");

        var cell = SkillPresentation.Version(skill);

        Assert.Equal("2.3.1 → 2.4.0", cell.Text);
        Assert.True(cell.IsInstrument);
        Assert.True(cell.IsHeld);
    }

    [Fact]
    public void APromotableVersionReadsAsTheNewNumberAlone()
    {
        var skill = PluginSkill(held: new HeldVersion("1.5.0", [], 1), pluginVersion: "1.4.2");

        var cell = SkillPresentation.Version(skill);

        Assert.Equal("1.4.2", cell.Text);
        Assert.False(cell.IsHeld);
    }

    // ------------------------------------------------------------------ slots

    [Fact]
    public void SlotsDistinguishPresentAbsentAndUnknown()
    {
        var skill = PluginSkill(presence: new Dictionary<string, SkillPresence>
        {
            ["claudeCode"] = SkillPresence.Present,
            ["cursor"] = SkillPresence.Absent,
            ["grok"] = SkillPresence.Unreadable,
        });

        Assert.Equal(SkillPresentation.SlotState.On, SkillPresentation.Slot(skill, ClaudeCode));
        Assert.Equal(SkillPresentation.SlotState.Off, SkillPresentation.Slot(skill, Cursor));
        // An unknown is never an off: an empty slot would assert the skill is absent somewhere
        // nobody managed to look.
        Assert.Equal(SkillPresentation.SlotState.Unknown, SkillPresentation.Slot(skill, Unreadable));
    }

    [Fact]
    public void SlotLabelsComeFromTheShippedMapping()
    {
        Assert.Equal("CC", SkillPresentation.SlotLabel(ClaudeCode));
        Assert.Equal("CR", SkillPresentation.SlotLabel(Cursor));
        Assert.Equal("CX", SkillPresentation.SlotLabel(
            new SkillClient("codex", "Codex", true, null, SkillClientStatus.Read, null)));
        Assert.Equal("GR", SkillPresentation.SlotLabel(Unreadable));
        Assert.Equal("WI", SkillPresentation.SlotLabel(Unsupported));
    }

    [Fact]
    public void SlotNamesSpeakTheVocabularyNotTheLetter()
    {
        var skill = PluginSkill(presence: new Dictionary<string, SkillPresence>
        {
            ["claudeCode"] = SkillPresence.Present,
            ["cursor"] = SkillPresence.Absent,
            ["grok"] = SkillPresence.Unreadable,
        });

        Assert.Equal("Claude Code: installed", SkillPresentation.SlotAutomationName(skill, ClaudeCode));
        Assert.Equal("Cursor: not installed", SkillPresentation.SlotAutomationName(skill, Cursor));
        Assert.Equal(
            "Grok: could not be read, so this is unknown",
            SkillPresentation.SlotAutomationName(skill, Unreadable));
    }

    // ------------------------------------------------------------------ the security clause

    [Fact]
    public void UpdateAllCountsOnlyVersionsThatAskForNothingMore()
    {
        var skills = new List<Skill>
        {
            // promotes on its own - in the set
            PluginSkill("a", held: new HeldVersion("1.5.0", [], 1)),
            // asks for more - HELD, never in the set, whatever else is true of it
            PluginSkill("b", held: new HeldVersion("2.4.0", ["network access"], 1)),
            // asks for nothing at all but exists - in the set
            PluginSkill("c", held: new HeldVersion("0.2.0", [], 1)),
            // no newer version fetched - not in the set
            PluginSkill("d"),
        };

        var updatable = SkillPresentation.Updatable(skills);

        Assert.Equal(["a", "c"], updatable.Select(s => s.Name));
    }

    [Fact]
    public void TheUpdatesTabListsEveryFetchedVersionButSaysWhichAreHeld()
    {
        var held = PluginSkill("b", held: new HeldVersion("2.4.0", ["network access"], 1));
        var promotable = PluginSkill("a", held: new HeldVersion("1.5.0", [], 1));

        Assert.Equal("Wants network access", SkillPresentation.WhatChanged(held));
        Assert.Equal("Held for review", SkillPresentation.Disposition(held));
        Assert.Equal("No capability change", SkillPresentation.WhatChanged(promotable));
        Assert.Equal("Promotes on its own", SkillPresentation.Disposition(promotable));
    }

    [Fact]
    public void TheHeldBannerSpeaksTheBriefsOwnSentence()
    {
        var skill = PluginSkill(
            "design-review",
            held: new HeldVersion("2.4.0", ["network access"], 1),
            pluginVersion: "2.3.1");

        // The design of record's line, which the brief quotes verbatim.
        Assert.Equal(
            "design-review 2.4.0 is held for review",
            SkillPresentation.HeldBannerTitle(skill));
        var body = SkillPresentation.HeldBannerBody(skill);
        Assert.Equal(
            "The new version asks for network access the installed one never had. "
            + "It is downloaded, not live.",
            body);
    }

    [Fact]
    public void TheHeldBannerListsEveryCapabilityItAsksFor()
    {
        var skill = PluginSkill(
            "multi",
            held: new HeldVersion("1.1.0", ["network access", "shell execution"], 1),
            pluginVersion: "1.0.0");

        Assert.Contains("network access and shell execution", SkillPresentation.HeldBannerBody(skill));
    }

    [Fact]
    public void APromotableVersionDrawsNoHeldBanner()
    {
        var skill = PluginSkill(held: new HeldVersion("1.5.0", [], 1));

        Assert.Equal("", SkillPresentation.HeldBannerTitle(skill));
        Assert.Equal("", SkillPresentation.HeldBannerBody(skill));
    }

    [Fact]
    public void TheHeldBannerSaysWhatTheNewVersionAsksFor()
    {
        var skill = PluginSkill(
            "design-review",
            held: new HeldVersion("2.4.0", ["network access"], 1),
            pluginVersion: "2.3.1");

        Assert.Equal(
            "design-review 2.4.0 wants more than 2.3.1",
            SkillPresentation.HeldTitle(skill));
        var body = SkillPresentation.HeldBody(skill);
        Assert.Contains("kept aside rather than installed", body);
        Assert.Contains("still running 2.3.1", body);
    }

    // ------------------------------------------------------------------ header, source, provenance

    [Fact]
    public void TheSubtitleCountsSkillsAndMarketplacesAndNamesHeld()
    {
        var skills = new List<Skill>
        {
            PluginSkill("a", marketplace: "one"),
            PluginSkill("b", marketplace: "two", held: new HeldVersion("2.0.0", ["x"], 1)),
            new Skill("c", null, "p", new SkillSource.Standalone("p"),
                new Dictionary<string, SkillPresence>()),
        };

        Assert.Equal("3 skills from 2 marketplaces · 1 held for review", SkillPresentation.Subtitle(skills));
    }

    [Fact]
    public void TheSubtitleAtZeroIsASentenceNotAnAbsence()
    {
        Assert.Equal("0 skills from 0 marketplaces", SkillPresentation.Subtitle([]));
    }

    [Fact]
    public void TheSourceLineNamesThePluginWhenItSuppliesSiblings()
    {
        Assert.Equal(
            "trawl · fledgeling-plugins",
            SkillPresentation.SourceLine(PluginSkill(siblings: 3)));
        Assert.Equal("fledgeling-plugins", SkillPresentation.SourceLine(PluginSkill(siblings: 1)));
    }

    [Fact]
    public void AProvenanceWarningReplacesTheSourceLine()
    {
        var skill = PluginSkill(provenance: new SkillProvenance(
            "github:acme-tools/skills", "github:unknown-user/skills", "2026-08-01"));

        Assert.Equal(
            "Owner changed - was github:acme-tools/skills",
            SkillPresentation.ProvenanceLine(skill));
    }

    // ------------------------------------------------------------------ partial and the inspector

    [Fact]
    public void ThePartialNoteNamesClientConsequencePathAndReason()
    {
        var response = new SkillsResponse(
            [],
            [ClaudeCode, Unreadable, Unsupported]);

        var note = SkillPresentation.PartialNote(response);

        Assert.NotNull(note);
        Assert.Contains("Grok could not be read", note);
        Assert.Contains("missing from this list", note);
        Assert.Contains("~/.grok/installed-plugins - permission denied", note);
    }

    [Fact]
    public void NoPartialNoteWhenEveryClientWasRead()
    {
        var response = new SkillsResponse([], [ClaudeCode, Unsupported]);
        Assert.Null(SkillPresentation.PartialNote(response));
    }

    [Fact]
    public void TheInspectorAccountsForEveryClient()
    {
        var skill = PluginSkill(presence: new Dictionary<string, SkillPresence>
        {
            ["claudeCode"] = SkillPresence.Present,
            ["cursor"] = SkillPresence.Absent,
            ["grok"] = SkillPresence.Unreadable,
        });
        var response = new SkillsResponse([skill], [ClaudeCode, Cursor, Unreadable, Unsupported]);

        var sentences = SkillPresentation.ClientSentences(skill, response);

        Assert.Equal(4, sentences.Count);
        Assert.Equal("Claude Code", sentences[0]);
        Assert.Equal("Not in Cursor", sentences[1]);
        Assert.Equal("Grok could not be read, so this is unknown", sentences[2]);
        Assert.Equal("Windsurf has no skills mechanism", sentences[3]);
    }

    // ------------------------------------------------------------------ auto-update

    [Fact]
    public void AutoUpdateLivesOnTheMarketplaceAndHasAFourthAnswer()
    {
        var marketplaces = new List<Marketplace>
        {
            new("on-mkt", new MarketplaceSource.GitHub("a/b"), true, 1, 1),
            new("off-mkt", new MarketplaceSource.GitHub("c/d"), false, 1, 1),
            new("local", new MarketplaceSource.Directory("~/.claude/skills"), false, 0, 5),
        };

        var on = PluginSkill("a", marketplace: "on-mkt");
        var off = PluginSkill("b", marketplace: "off-mkt");
        var local = PluginSkill("c", marketplace: "local");
        var standalone = new Skill("d", null, "p", new SkillSource.Standalone("p"),
            new Dictionary<string, SkillPresence>());
        var missingRecord = PluginSkill("e", marketplace: "not-loaded");

        Assert.Equal("On", SkillPresentation.AutoUpdateCell(on, marketplaces));
        Assert.Equal("Off", SkillPresentation.AutoUpdateCell(off, marketplaces));
        // A local directory has nothing to fetch, so auto-update means nothing for it.
        Assert.Equal("n/a", SkillPresentation.AutoUpdateCell(local, marketplaces));
        Assert.Equal("n/a", SkillPresentation.AutoUpdateCell(standalone, marketplaces));
        // A marketplace record that did not load is NOT a setting anybody read.
        Assert.Equal("Not shown", SkillPresentation.AutoUpdateCell(missingRecord, marketplaces));
        Assert.IsType<SkillPresentation.AutoUpdateItem.Unread>(
            SkillPresentation.AutoUpdate(missingRecord, marketplaces));
    }

    [Fact]
    public void TheLocalMarketplaceGetsItsOwnAutoUpdateReason()
    {
        var local = new Marketplace(
            "local", new MarketplaceSource.Directory("~/.claude/skills"), false, 0, 5);

        var reason = SkillPresentation.AutoUpdateReason(local);

        Assert.Contains("nothing to fetch", reason);
        Assert.DoesNotContain("open in your other apps", reason);
    }

    [Fact]
    public void TheSupplyLineNeverSaysZeroPlugins()
    {
        Assert.Equal("Supplies nothing", SkillPresentation.SupplyLine(
            new Marketplace("x", new MarketplaceSource.GitHub("a/b"), false, 0, 0)));
        Assert.Equal("5 skills", SkillPresentation.SupplyLine(
            new Marketplace("x", new MarketplaceSource.GitHub("a/b"), false, 0, 5)));
        Assert.Equal("24 skills from 18 plugins", SkillPresentation.SupplyLine(
            new Marketplace("x", new MarketplaceSource.GitHub("a/b"), false, 18, 24)));
    }

    [Fact]
    public void TheRemoveReasonCountsWhatWouldGo()
    {
        var marketplace = new Marketplace("x", new MarketplaceSource.GitHub("a/b"), false, 4, 24);
        Assert.Equal("24 installed skills come from this marketplace. Remove them first.",
            SkillPresentation.RemoveReason(marketplace));

        var empty = new Marketplace("y", new MarketplaceSource.GitHub("a/b"), false, 0, 0);
        Assert.Equal(SkillPresentation.WritesNotYetAvailable, SkillPresentation.RemoveReason(empty));
    }

    [Fact]
    public void TheListFormMatchesTheMac()
    {
        Assert.Equal("", SkillPresentation.List([]));
        Assert.Equal("a", SkillPresentation.List(["a"]));
        Assert.Equal("a and b", SkillPresentation.List(["a", "b"]));
        Assert.Equal("a, b and c", SkillPresentation.List(["a", "b", "c"]));
    }
}
