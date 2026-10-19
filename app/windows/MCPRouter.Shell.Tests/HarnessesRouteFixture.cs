using System.Text.Json;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The body <c>GET /harnesses</c> answered with, captured from the TypeScript router.
///
/// <para>Captured on 2026-10-20 by running <c>dist/index.js serve</c> under a fake <c>HOME</c> that
/// holds one config per harness shape the reader tells apart: a direct HTTP entry beside two
/// duplicates, a stdio bridge, a Codex TOML entry, a Gemini <c>serverUrl</c>, a multi-line grok
/// table, a file that does not parse, and no opencode file at all. The fixture is therefore the
/// route's own answer, not a row written by hand. Re-capture it rather than edit it: an edited
/// fixture proves the decoder agrees with the editor.</para>
/// </summary>
internal static class HarnessesRouteFixture
{
    private const string Path = "app/windows/MCPRouter.Shell.Tests/Fixtures/harnesses.json";

    public static string Text() => RepoRoot.Read(Path);

    public static HarnessesEnvelope Envelope() =>
        JsonSerializer.Deserialize<HarnessesEnvelope>(Text(), ServersWire.Options)
        ?? throw new InvalidOperationException("the captured route body decoded to nothing");

    public static HarnessRow Row(string harness) =>
        Envelope().Harnesses.Single(h => h.Harness == harness);
}
