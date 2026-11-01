using System.Text.Json;
using MCPRouter.Shell.Model.Skills;
using Xunit;
using static MCPRouter.Shell.Tests.SkillWritesFixture;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The <c>GET /skills</c> member the held-version board reads, decoded from the router's captured replies. The
/// options are the ones the live client's <c>ReadFromJsonAsync</c> uses, so the decode is the one the board
/// performs.
/// </summary>
public sealed class SkillWireCapturedTests
{
    private static SkillsResponse Read(string name) =>
        JsonSerializer.Deserialize<SkillsResponse>(Body(name), JsonSerializerOptions.Web)!;

    [Fact]
    public void AHeldRowCarriesTheChangelogTheRouterRead()
    {
        var trawl = Assert.Single(Read("skills").SkillList, skill => skill.Name == "trawl");

        Assert.Equal("2.3.0", trawl.Held?.PluginVersion);
        Assert.Equal(
            "# Changelog\n\n## 2.3.0\n\n- Reads the session transcripts directly.\n- Adds a date filter.\n",
            trawl.Held?.Changelog?.Text);
        Assert.Equal("CHANGELOG.md from the cached 2.3.0 copy", trawl.Held?.Changelog?.Note);
    }

    [Fact]
    public void TheRouterSaysWhenItServesPromoteFromCache()
    {
        Assert.True(Read("skills").PromotesFromCache);
        Assert.False(JsonSerializer.Deserialize<SkillsResponse>(
            "{ \"skills\": [], \"clients\": [] }", JsonSerializerOptions.Web)!.PromotesFromCache);
    }

    [Fact]
    public void AKeptVersionIsNotHeldOnTheNextRead()
    {
        // The router records a keep and stops reporting the row as held until a newer version is offered.
        var trawl = Assert.Single(Read("skillsAfterKeep").SkillList, skill => skill.Name == "trawl");

        Assert.Null(trawl.Held);
    }
}
