using System.Text.Json;
using System.Text.Json.Nodes;
using MCPRouter.Shell.Model.Insights;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The bodies <c>GET /insights</c> answered with, captured from the TypeScript router.
///
/// <para>Captured on 2026-10-20 by running <c>dist/index.js serve</c> under a fake <c>HOME</c>, once
/// with a usage log and an analyst state holding one run (<c>insights-populated.json</c>), and once
/// with neither (<c>insights-idle.json</c>). The populated log holds twelve calls in the window, two
/// of them failed, one line that does not parse, and one call with no client name; the analyst state
/// was written in the shape the router reads back, with one run and no judge. Nothing ran a judge.
/// Re-capture rather than edit: an edited fixture proves the decoder agrees with the editor.</para>
///
/// <para>The POST answer is not captured, because <c>POST /insights/analyse</c> would spawn a judge CLI.
/// The router answers it with the same <c>analystEnvelope</c> it builds the <c>analyst</c> member from
/// (<c>src/control.ts</c>), so the populated body's <c>analyst</c> member stands in for it.</para>
/// </summary>
internal static class InsightsRouteFixture
{
    private const string PopulatedPath = "app/windows/MCPRouter.Shell.Tests/Fixtures/insights-populated.json";
    private const string IdlePath = "app/windows/MCPRouter.Shell.Tests/Fixtures/insights-idle.json";

    public static string PopulatedText() => RepoRoot.Read(PopulatedPath);

    public static string IdleText() => RepoRoot.Read(IdlePath);

    public static InsightsEnvelope Populated() => Decode<InsightsEnvelope>(PopulatedText());

    public static InsightsEnvelope Idle() => Decode<InsightsEnvelope>(IdleText());

    /// <summary>The populated body's <c>analyst</c> member, as the text a POST answer would carry.</summary>
    public static string AnalystText() =>
        JsonNode.Parse(PopulatedText())!["analyst"]!.ToJsonString();

    private static T Decode<T>(string text) =>
        JsonSerializer.Deserialize<T>(text, ServersWire.Options)
        ?? throw new InvalidOperationException("the captured route body decoded to nothing");
}
