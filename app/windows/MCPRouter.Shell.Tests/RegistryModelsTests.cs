using System.Text.Json;
using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>The wire shapes /registry/search serves, parsed from fixtures in exactly the shape
/// the router serves them (src/control.ts lifts the indexes' stamps and flattens repository, and
/// adds the installed flag per row).</summary>
public sealed class RegistryModelsTests
{
    private const string SmitheryShape = """
        {
          "results": [
            {
              "id": "smithery:@vercel/flaky-hunter",
              "name": "@vercel/flaky-hunter",
              "displayName": "flaky-hunter",
              "description": "Reruns a suite until a test fails twice, then bisects it.",
              "source": "smithery",
              "updatedAt": "2025-11-19T07:26:28.312Z",
              "useCount": 9880,
              "verified": true,
              "iconUrl": "https://example.com/icon.png",
              "install": {
                "type": "http",
                "url": "https://server.smithery.ai/@vercel/flaky-hunter/mcp",
                "requires": [{ "name": "Authorization", "description": "Bearer <key>", "isSecret": true }]
              },
              "installed": false
            }
          ],
          "sources": { "official": 1, "smithery": 1, "merged": 1 },
          "warnings": []
        }
        """;

    private const string OfficialShape = """
        {
          "results": [
            {
              "id": "io.github/owner/context-budget",
              "name": "io.github/owner/context-budget",
              "displayName": "context-budget",
              "description": "Diffs a delivered feature against the spec that asked for it.",
              "source": "official",
              "repository": "https://github.com/owner/context-budget",
              "version": "1.4.0",
              "updatedAt": "2025-09-14T15:20:36.371442Z"
            }
          ],
          "sources": { "official": 1, "smithery": 0, "merged": 1 },
          "warnings": ["GitHub allows 60 requests an hour without a token, so star counts are partial. Set GITHUB_TOKEN to raise it."]
        }
        """;

    private static RegistrySearchResponse Parse(string json) =>
        JsonSerializer.Deserialize<RegistrySearchResponse>(json, RegistryClient.JsonSchema.Options)!;

    [Fact]
    public void SmitheryRowCarriesUsageAndInstall()
    {
        var response = Parse(SmitheryShape);
        var row = Assert.Single(response.Results);
        Assert.Equal(9880, row.UseCount);
        Assert.True(row.Verified);
        Assert.Equal("2025-11-19T07:26:28.312Z", row.UpdatedAt);
        Assert.Equal("http", row.Install!.Type);
        Assert.False(row.Installed ?? false);
    }

    [Fact]
    public void OfficialRowCarriesNoUsageFigureAndNoInstallBlock()
    {
        var response = Parse(OfficialShape);
        var row = Assert.Single(response.Results);
        // The official index publishes no usage figure, so the row carries none - null, never
        // a zero - and no install block either.
        Assert.Null(row.UseCount);
        Assert.Null(row.Install);
        // The router lifts the official registry's _meta stamp to a top-level updatedAt, and
        // flattens repository to its url string.
        Assert.Equal("2025-09-14T15:20:36.371442Z", row.UpdatedAt);
        Assert.Equal("https://github.com/owner/context-budget", row.Repository);
    }

    [Fact]
    public void RouterWarningSurvivesTheRoundTrip()
    {
        var response = Parse(OfficialShape);
        var warning = Assert.Single(response.Warnings);
        Assert.StartsWith("GitHub allows 60 requests an hour", warning);
    }

    [Fact]
    public void EmptyResponseParsesToEmptyLists()
    {
        var response = Parse("""{"results":[],"sources":{"official":0,"smithery":0,"merged":0},"warnings":[]}""");
        Assert.Empty(response.Results);
        Assert.Equal(0, response.Sources.Merged);
    }

    [Fact]
    public void AsInstalledTouchesOnlyTheFlag()
    {
        var row = Parse(SmitheryShape).Results[0].AsInstalled();
        Assert.True(row.Installed);
        Assert.Equal(9880, row.UseCount);
        Assert.Equal("flaky-hunter", row.DisplayName);
    }
}
