using System.Text.Json;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The skills wire shapes decode as the Mac's M4 models decode them - including the two cases M4
/// proved red-green: a source with an unknown kind fails decoding rather than being guessed at,
/// and a missing list key decodes as empty rather than as a failure.
/// </summary>
public sealed class SkillModelsTests
{
    private static SkillsResponse Decode(string json) =>
        JsonSerializer.Deserialize<SkillsResponse>(json) ?? throw new Xunit.Sdk.XunitException("decoded to null");

    [Fact]
    public void DecodesTheFullWireShape()
    {
        const string json = """
        {
          "skills": [
            {
              "name": "trawl",
              "description": "Mines sessions.",
              "path": "~/.claude/plugins/cache/fledgeling-plugins/trawl/2.2.0/skills/trawl",
              "source": {
                "kind": "plugin",
                "plugin": "trawl",
                "marketplace": "fledgeling-plugins",
                "pluginVersion": "2.2.0",
                "installedAt": "2026-08-02",
                "lastUpdated": "2026-08-17",
                "commit": "4c1e08a",
                "siblingSkillCount": 3
              },
              "presence": { "claudeCode": "present", "cursor": "absent", "grok": "unreadable" },
              "held": { "pluginVersion": "2.3.0", "addedCapabilities": ["network access"], "affectedSkillCount": 3 },
              "provenance": {
                "firstSeenSource": "github:acme-tools/skills",
                "currentSource": "github:unknown-user/skills",
                "firstSeenAt": "2026-08-01"
              }
            },
            {
              "name": "graphify",
              "description": null,
              "path": "~/.claude/skills/graphify",
              "source": { "kind": "standalone", "path": "~/.claude/skills/graphify" },
              "presence": { "claudeCode": "present" },
              "held": null,
              "provenance": null
            }
          ],
          "clients": [
            { "id": "claudeCode", "displayName": "Claude Code", "supportsSkills": true, "root": "~/.claude/skills", "status": "read", "reason": null },
            { "id": "grok", "displayName": "Grok", "supportsSkills": true, "root": "~/.grok/installed-plugins", "status": "unreadable", "reason": "permission denied" },
            { "id": "windsurf", "displayName": "Windsurf", "supportsSkills": false, "root": null, "status": "unsupported", "reason": null }
          ]
        }
        """;

        var response = Decode(json);

        var trawl = Assert.Single(response.SkillList, s => s.Name == "trawl");
        var origin = Assert.IsType<SkillSource.PluginOrigin>(trawl.Source);
        Assert.Equal("2.2.0", origin.PluginVersion);
        Assert.Equal("fledgeling-plugins", origin.Marketplace);
        Assert.Equal(3, origin.SiblingSkillCount);
        Assert.Equal(SkillPresence.Present, trawl.Presence["claudeCode"]);
        Assert.Equal(SkillPresence.Absent, trawl.Presence["cursor"]);
        Assert.Equal(SkillPresence.Unreadable, trawl.Presence["grok"]);
        Assert.Equal("2.3.0", trawl.Held?.PluginVersion);
        Assert.Equal(["network access"], trawl.Held?.AddedCapabilities);
        Assert.True(trawl.Held?.WantsMore);
        Assert.Equal("github:acme-tools/skills", trawl.Provenance?.FirstSeenSource);
        Assert.True(trawl.NeedsAttention);

        var graphify = Assert.Single(response.SkillList, s => s.Name == "graphify");
        var standalone = Assert.IsType<SkillSource.Standalone>(graphify.Source);
        Assert.Equal("~/.claude/skills/graphify", standalone.Path);
        Assert.True(standalone.IsStandalone);
        Assert.Null(graphify.Held);
        Assert.False(graphify.NeedsAttention);

        Assert.Equal(3, response.ClientList.Count);
        // Slot clients are the skills-capable ones - including a directory nobody could read.
        // An unreadable client still has a slot; what it asserts is "unknown", not "absent".
        Assert.Equal(2, response.SlotClients.Count);
        Assert.Single(response.UnsupportedClients);
        Assert.Equal(SkillClientStatus.Unreadable, response.ClientList[1].Status);
        Assert.Equal("permission denied", response.ClientList[1].Reason);
    }

    [Fact]
    public void AnUnknownSourceKindFailsDecodingRatherThanBeingGuessedAt()
    {
        const string json = """
        { "skills": [ { "name": "x", "path": "p", "source": { "kind": "registry" } } ], "clients": [] }
        """;

        Assert.ThrowsAny<JsonException>(() => Decode(json));
    }

    [Fact]
    public void AnUnknownPresenceValueFailsDecoding()
    {
        const string json = """
        { "skills": [ { "name": "x", "path": "p", "source": { "kind": "standalone", "path": "p" },
            "presence": { "claudeCode": "maybe" } } ], "clients": [] }
        """;

        Assert.ThrowsAny<JsonException>(() => Decode(json));
    }

    [Fact]
    public void MissingListKeysDecodeAsEmpty()
    {
        const string json = "{ }";

        var response = Decode(json);

        Assert.Empty(response.SkillList);
        Assert.Empty(response.ClientList);
    }

    [Fact]
    public void MarketplacesDecodeTheirOwnKindDiscriminator()
    {
        const string json = """
        {
          "marketplaces": [
            { "name": "fledgeling-plugins", "source": { "kind": "github", "repo": "fledgeling-co/fledgeling-plugins" },
              "auto_update": true, "installed_plugin_count": 4, "supplied_skill_count": 24 },
            { "name": "Local directory", "source": { "kind": "directory", "path": "~/.claude/skills" },
              "auto_update": false, "installed_plugin_count": 0, "supplied_skill_count": 5 }
          ]
        }
        """;

        var response = JsonSerializer.Deserialize<MarketplacesResponse>(json)
                       ?? throw new Xunit.Sdk.XunitException("decoded to null");

        Assert.Equal(2, response.MarketplaceList.Count);
        var github = Assert.IsType<MarketplaceSource.GitHub>(response.MarketplaceList[0].Source);
        Assert.Equal("github: fledgeling-co/fledgeling-plugins", github.Label);
        Assert.False(github.IsLocalDirectory);

        var directory = Assert.IsType<MarketplaceSource.Directory>(response.MarketplaceList[1].Source);
        Assert.True(directory.IsLocalDirectory);
        Assert.Equal("directory: ~/.claude/skills", directory.Label);
    }
}
