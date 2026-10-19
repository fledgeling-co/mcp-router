using MCPRouter.Checks.Model;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The five skill checks, held to the Mac's <c>SkillChecks</c> (<c>app/Sources/MCPRouterKit/Checks/SkillChecks.swift</c>)
/// verdict for verdict and reason for reason, because DESIGN.md §6 asks for one wording per state across both devices.
/// Each test names the observation a verdict rests on, and each "not applicable" or "not observed" is pinned so that a
/// pass is never reported for a question that was not asked.
/// </summary>
public sealed class SkillChecksTests
{
    private static readonly SkillClient ClaudeCode = new(
        "claudeCode", "Claude Code", true, "/home/.claude/skills", SkillClientStatus.Read, null);

    private static readonly SkillClient Cursor = new(
        "cursor", "Cursor", true, null, SkillClientStatus.Unreadable, "this router reads Claude Code's skills directory only");

    private static readonly SkillClient ClaudeDesktop = new(
        "claudeDesktop", "Claude Desktop", false, null, SkillClientStatus.Unsupported, null);

    private static readonly IReadOnlyList<SkillClient> Clients = [ClaudeCode, Cursor, ClaudeDesktop];

    private static readonly SkillSource.PluginOrigin Plugin = new(
        "trawl", "fledgeling-plugins", "2.2.0", null, null, null, 1);

    private static readonly SkillSource.Standalone Standalone = new("/home/.claude/skills/graphify");

    private static Skill Make(
        SkillSource source,
        IReadOnlyDictionary<string, SkillPresence>? presence = null,
        HeldVersion? held = null,
        SkillProvenance? provenance = null,
        string? description = "Mines past sessions for evidence.") =>
        new(
            "trawl",
            description,
            "/home/.claude/plugins/cache/fledgeling-plugins/trawl/2.2.0/skills/trawl",
            source,
            presence ?? new Dictionary<string, SkillPresence> { ["claudeCode"] = SkillPresence.Present },
            held,
            provenance);

    [Fact]
    public void ReachableIsConfirmedWhereAnyCapableClientHasTheSkill()
    {
        var result = SkillChecks.Reachable(Make(Plugin), Clients);

        Assert.Equal(CheckId.Reachable, result.Check);
        Assert.Equal(CheckVerdict.Passed, result.Verdict);
    }

    [Fact]
    public void ReachableFailsWhenEveryReadClientLacksTheSkill()
    {
        // Only Claude Code is read here. An unreadable Cursor directory would make this Unknown, not Failed.
        var absent = Make(Plugin, new Dictionary<string, SkillPresence>
        {
            ["claudeCode"] = SkillPresence.Absent,
        });

        var result = SkillChecks.Reachable(absent, [ClaudeCode]);

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(
            "Every one of the 1 skills-capable client was read, and none has it installed.",
            result.Reason);
    }

    [Fact]
    public void ReachableIsNotObservedWhenACapableDirectoryCouldNotBeRead()
    {
        var absent = Make(Plugin, new Dictionary<string, SkillPresence>
        {
            ["claudeCode"] = SkillPresence.Absent,
        });

        var result = SkillChecks.Reachable(absent, Clients);

        Assert.Equal(CheckVerdict.Unknown, result.Verdict);
        Assert.Equal(
            "It is installed in no client the router could read, and Cursor's skills directory could not be read "
                + "— so it may be installed exactly where nobody could look.",
            result.Reason);
    }

    [Fact]
    public void AnAbsentPresenceKeyIsNotEvidenceOfAbsence()
    {
        // The Cursor directory was never read, so the presence map has no key for it. Treating a missing key as
        // "not installed there" would declare the skill loadable by nobody on the strength of a lookup that never
        // happened. The unreadable client status is what suspends the judgement.
        var noKeys = Make(Plugin, new Dictionary<string, SkillPresence>());

        var result = SkillChecks.Reachable(noKeys, [Cursor]);

        Assert.Equal(CheckVerdict.Unknown, result.Verdict);
    }

    [Fact]
    public void AStandaloneSkillIsNotVersioned()
    {
        var result = SkillChecks.Versioned(Make(Standalone));

        Assert.Equal(CheckId.Versioned, result.Check);
        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(
            "It was placed in a client's directory by hand, so it has no version anywhere on disk and no result "
                + "about it can be stamped against one.",
            result.Reason);
    }

    [Fact]
    public void APluginSkillIsVersioned()
    {
        Assert.Equal(CheckVerdict.Passed, SkillChecks.Versioned(Make(Plugin)).Verdict);
    }

    [Fact]
    public void APluginSkillWithoutProvenanceIsUnchanged()
    {
        var result = SkillChecks.OriginUnchanged(Make(Plugin));

        Assert.Equal(CheckId.OriginUnchanged, result.Check);
        Assert.Equal(CheckVerdict.Passed, result.Verdict);
    }

    [Fact]
    public void AStandaloneSkillHasNoOriginToHaveMoved()
    {
        // Not a confirmation: an unmoved origin is not something that can be true of an entity with no marketplace.
        var result = SkillChecks.OriginUnchanged(Make(Standalone));

        Assert.Equal(CheckVerdict.NotApplicable, result.Verdict);
        Assert.Equal(
            "It was placed in a client's directory by hand rather than supplied by a marketplace, so there is no "
                + "origin for it to have moved from.",
            result.Reason);
    }

    [Fact]
    public void AMovedOriginFailsWithTheRoutersTwoSources()
    {
        var moved = Make(Plugin, provenance: new SkillProvenance(
            "github:acme-tools/skills", "github:unknown-user/skills", "2026-08-01"));

        var result = SkillChecks.OriginUnchanged(moved);

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(
            "The router first saw it at github:acme-tools/skills and it now resolves to github:unknown-user/skills, "
                + "first observed 2026-08-01.",
            result.Reason);
    }

    [Fact]
    public void NoHeldVersionIsNotAsked()
    {
        var result = SkillChecks.UpdateWantsNoMore(Make(Plugin));

        Assert.Equal(CheckId.UpdateWantsNoMore, result.Check);
        Assert.Equal(CheckVerdict.NotApplicable, result.Verdict);
        Assert.Equal(
            "No newer version of its plugin is being held, so there is nothing waiting to ask for more.",
            result.Reason);
    }

    [Fact]
    public void AHeldVersionThatAsksForNothingPasses()
    {
        var held = new HeldVersion("2.3.0", [], 1);

        Assert.Equal(CheckVerdict.Passed, SkillChecks.UpdateWantsNoMore(Make(Plugin, held: held)).Verdict);
    }

    [Fact]
    public void AHeldVersionThatAsksForMoreFailsAndNamesWhatItAsks()
    {
        var held = new HeldVersion("2.3.0", ["network access"], 1);

        var result = SkillChecks.UpdateWantsNoMore(Make(Plugin, held: held));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal("Version 2.3.0 is held and asks for network access.", result.Reason);
    }

    [Fact]
    public void ADescribedSkillPasses()
    {
        var result = SkillChecks.Described(Make(Plugin));

        Assert.Equal(CheckId.Described, result.Check);
        Assert.Equal(CheckVerdict.Passed, result.Verdict);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ASkillWithoutADescriptionFails(string? description)
    {
        var result = SkillChecks.Described(Make(Plugin, description: description));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(
            "Its SKILL.md declares no description, so an agent has nothing to route on when choosing it.",
            result.Reason);
    }

    [Fact]
    public void AllFiveAreReturnedInTheOrderTheInspectorRendersThem()
    {
        var results = SkillChecks.All(Make(Plugin), Clients);

        Assert.Equal(
            new[] { CheckId.Reachable, CheckId.Versioned, CheckId.OriginUnchanged, CheckId.UpdateWantsNoMore, CheckId.Described },
            results.Select(r => r.Check));
    }

    [Fact]
    public void EverySkillCheckCarriesAStatement()
    {
        // Every statement is a fragment judged by the result beside it, and none is blank.
        foreach (var check in new[]
                 {
                     CheckId.Reachable, CheckId.Versioned, CheckId.OriginUnchanged,
                     CheckId.UpdateWantsNoMore, CheckId.Described,
                 })
        {
            Assert.False(string.IsNullOrWhiteSpace(CheckCopy.Statement(check)), check.ToString());
        }
    }
}
