using System;
using System.Collections.Generic;
using MCPRouter.Shell.Model.Cleanup;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class CleanupPresentationTests
{
    [Fact]
    public void EvaluateServer_WithIndexError_ReturnsCandidateWithFailedToIndexReason()
    {
        var server = new CleanupServerItem(
            Id: "broken-srv",
            Name: "broken-srv",
            IndexError: "connection refused on port 9000",
            NeverUsed: false,
            Tools: 0,
            IndexedAt: null,
            FirstSeenAt: "2026-08-01"
        );

        var result = CleanupPresentation.EvaluateServer(server);

        Assert.Equal(CandidacyState.Candidate, result.State);
        Assert.Contains("connection refused on port 9000", result.Reason);
    }

    [Fact]
    public void EvaluateServer_WhenNeverUsed_ReturnsCandidateWithNeverCalledReason()
    {
        var server = new CleanupServerItem(
            Id: "idle-srv",
            Name: "idle-srv",
            IndexError: null,
            NeverUsed: true,
            Tools: 4,
            IndexedAt: DateTimeOffset.UtcNow,
            FirstSeenAt: "2026-07-15"
        );

        var result = CleanupPresentation.EvaluateServer(server);

        Assert.Equal(CandidacyState.Candidate, result.State);
        Assert.Equal(CleanupPresentation.NeverCalled, result.Reason);
    }

    [Fact]
    public void EvaluateServer_WhenIndexedWithZeroTools_ReturnsOffersNothing()
    {
        var server = new CleanupServerItem(
            Id: "empty-srv",
            Name: "empty-srv",
            IndexError: null,
            NeverUsed: false,
            Tools: 0,
            IndexedAt: DateTimeOffset.UtcNow,
            FirstSeenAt: "2026-08-10"
        );

        var result = CleanupPresentation.EvaluateServer(server);

        Assert.Equal(CandidacyState.Candidate, result.State);
        Assert.Equal(CleanupPresentation.OffersNothing, result.Reason);
    }

    [Fact]
    public void EvaluateServer_WhenActiveAndHealthy_ReturnsNotACandidate()
    {
        var server = new CleanupServerItem(
            Id: "active-srv",
            Name: "active-srv",
            IndexError: null,
            NeverUsed: false,
            Tools: 5,
            IndexedAt: DateTimeOffset.UtcNow,
            FirstSeenAt: "2026-06-01",
            LifetimeCalls: 45
        );

        var result = CleanupPresentation.EvaluateServer(server);

        Assert.Equal(CandidacyState.NotACandidate, result.State);
    }

    [Fact]
    public void EvaluateSkill_WhenUnreadableClient_ReturnsHeldOut()
    {
        var skill = new CleanupSkillItem("sk1", "sk1", "github", "1.0", new Dictionary<string, bool>(), "2026-08-01");
        var clients = new List<CleanupSkillClient>
        {
            new("c1", "Claude Desktop", true, true, false)
        };

        var result = CleanupPresentation.EvaluateSkill(skill, clients);

        Assert.Equal(CandidacyState.HeldOut, result.State);
        Assert.Contains("Claude Desktop's skills directory could not be read", result.Reason);
    }

    [Fact]
    public void EvaluateSkill_WhenNotInstalledAnywhere_ReturnsCandidate()
    {
        var skill = new CleanupSkillItem("sk1", "sk1", "github", "1.0", new Dictionary<string, bool>(), "2026-08-01");
        var clients = new List<CleanupSkillClient>
        {
            new("c1", "Claude Desktop", true, false, false),
            new("c2", "Cursor", true, false, false)
        };

        var result = CleanupPresentation.EvaluateSkill(skill, clients);

        Assert.Equal(CandidacyState.Candidate, result.State);
        Assert.Equal(CleanupPresentation.InstalledNowhere, result.Reason);
    }

    [Fact]
    public void EvaluateSkill_WhenInstalledInClient_ReturnsNotACandidate()
    {
        var skill = new CleanupSkillItem("sk1", "sk1", "github", "1.0", new Dictionary<string, bool> { ["c1"] = true }, "2026-08-01");
        var clients = new List<CleanupSkillClient>
        {
            new("c1", "Claude Desktop", true, false, true),
            new("c2", "Cursor", true, false, false)
        };

        var result = CleanupPresentation.EvaluateSkill(skill, clients);

        Assert.Equal(CandidacyState.NotACandidate, result.State);
    }

    [Fact]
    public void PresentationCopy_MatchesDesignRules()
    {
        Assert.Contains("Nothing is removed automatically and nothing is called rubbish", CleanupPresentation.BoardDescription);
        Assert.Contains("neither is disk space", CleanupPresentation.CardExplainer);
        Assert.Equal("Cleanup", CleanupPresentation.Title);
    }
}
