using System.Text.Json;
using System.Text.Json.Nodes;
using MCPRouter.Shell.Model.Insights;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The bodies <c>GET /insights</c> answered with, captured from the TypeScript router.
///
/// <para>Captured on 2026-10-20 by running <c>dist/index.js serve</c> under a fake <c>HOME</c> and a fake
/// <c>MCP_ROUTER_HOME</c>, with <c>?window=24h</c> and <c>?window=7d</c>. The populated home holds a
/// usage log with twelve calls in the last 24 hours (two failed, one line that does not parse, four with no
/// client name), two older generations holding nineteen more calls over the last seven days, an analyst
/// state holding one run and no judge, and the router counting from three days ago. That makes the 24-hour
/// window whole and the seven-day window incomplete. The idle home has no usage and counts from the moment it
/// starts, so its 24-hour window is incomplete too. Nothing ran a judge.
/// Re-capture rather than edit: an edited fixture proves the decoder agrees with the editor.</para>
///
/// <para>The POST answer is not captured, because <c>POST /insights/analyse</c> would spawn a judge CLI.
/// The router answers it with the same <c>analystEnvelope</c> it builds the <c>analyst</c> member from
/// (<c>src/control.ts</c>), so the populated body's <c>analyst</c> member stands in for it.</para>
/// </summary>
internal static class InsightsRouteFixture
{
    private const string PopulatedPath = "app/windows/MCPRouter.Shell.Tests/Fixtures/insights-populated.json";
    private const string PopulatedWeekPath = "app/windows/MCPRouter.Shell.Tests/Fixtures/insights-populated-7d.json";
    private const string IdlePath = "app/windows/MCPRouter.Shell.Tests/Fixtures/insights-idle.json";

    public static string PopulatedText() => RepoRoot.Read(PopulatedPath);

    public static string PopulatedWeekText() => RepoRoot.Read(PopulatedWeekPath);

    public static string IdleText() => RepoRoot.Read(IdlePath);

    public static InsightsEnvelope Populated() => Decode<InsightsEnvelope>(PopulatedText());

    public static InsightsEnvelope PopulatedWeek() => Decode<InsightsEnvelope>(PopulatedWeekText());

    public static InsightsEnvelope Idle() => Decode<InsightsEnvelope>(IdleText());

    /// <summary>The populated body's <c>analyst</c> member, as the text a POST answer would carry.</summary>
    public static string AnalystText() =>
        JsonNode.Parse(PopulatedText())!["analyst"]!.ToJsonString();

    private static T Decode<T>(string text) =>
        JsonSerializer.Deserialize<T>(text, ServersWire.Options)
        ?? throw new InvalidOperationException("the captured route body decoded to nothing");
}
