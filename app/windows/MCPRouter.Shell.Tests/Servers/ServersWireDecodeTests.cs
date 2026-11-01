using System.Text.Json;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The wire decode is gated against the router's own recorded answers — the fixtures the Swift
/// client recorded from a live router and committed under
/// <c>app/Sources/MCPRouterKit/Control/Fixtures/</c>. A decoder that reads those reads what the
/// router actually sends, not what this client wishes it sent.
/// </summary>
public sealed class ServersWireDecodeTests
{
    private const string Fixtures = "app/Sources/MCPRouterKit/Control/Fixtures";

    private static string Fixture(string name) => RepoRoot.Read($"{Fixtures}/{name}");

    private static T Decode<T>(string json) where T : class
    {
        var decoded = JsonSerializer.Deserialize<T>(json, ServersWire.Options);
        Assert.NotNull(decoded);
        return decoded;
    }

    [Fact]
    public void TheRecordedEnvelopeDecodes()
    {
        var envelope = Decode<ServersEnvelope>(Fixture("servers.json"));

        Assert.Equal(8971, envelope.Port);
        Assert.Equal(300000, envelope.IdleMs);
        Assert.Equal(JsonDocument.Parse(Fixture("servers.json")).RootElement.GetProperty("since").GetString(), envelope.Since);
        Assert.Null(envelope.PendingAuth);
        Assert.Equal(4, envelope.Servers.Count);
        Assert.Equal("stdio", envelope.Servers[0].Transport);
        Assert.Equal("https://example.invalid/mcp", envelope.Servers[1].Url);
        Assert.Equal(new[] { "hello" }, envelope.Servers[0].Args);
        Assert.Equal(new[] { "FIXTURE_KEY" }, envelope.Servers[0].EnvKeys);
        Assert.Equal(new[] { "fixture-stdio", "fixture-http", "fixture-tools", "fixture-oauth" },
            envelope.Servers.Select(s => s.Name));
    }

    [Fact]
    public void APendingAuthEnvelopeDecodesWithItsFlow()
    {
        var envelope = Decode<ServersEnvelope>(Fixture("servers-pending-auth.json"));

        Assert.Equal(4, envelope.Servers.Count);
        Assert.NotNull(envelope.PendingAuth);
        Assert.Equal("fixture-oauth", envelope.PendingAuth!.Server);

        var oauth = envelope.Servers.Single(s => s.Name == "fixture-oauth");
        Assert.True(oauth.Auth.Supported);
        Assert.False(oauth.Auth.Authorized);
    }

    [Fact]
    public void APlacardedRowDecodesWithItsSubstitute()
    {
        var row = Decode<ServerRow>(Fixture("server-placarded.json"));

        Assert.NotNull(row.Placard);
        Assert.Equal("under review while the upstream is rebuilt", row.Placard!.Reason);
        Assert.Equal("fixture-tools", row.Placard.Substitute);
    }

    [Fact]
    public void APendingChangeRowDecodesWithItsCount()
    {
        var row = Decode<ServerRow>(Fixture("server-pending-change.json"));

        Assert.Equal("running", row.State);
        Assert.NotNull(row.PendingChange);
        Assert.Equal(3, row.PendingChange!.Count);
        var seenAt = JsonDocument.Parse(Fixture("server-pending-change.json")).RootElement
            .GetProperty("pendingChange").GetProperty("seenAt").GetString();
        Assert.Equal(seenAt, row.PendingChange.SeenAt);
    }

    [Fact]
    public void AHeldChangesDocumentDecodesIncludingTheInvisibleCodepoints()
    {
        var changes = Decode<HeldChanges>(Fixture("changes-pending.json"));

        Assert.True(changes.Pending);
        Assert.Equal(3, changes.Changes.Count);
        Assert.Equal(new[] { "changed", "added", "removed" }, changes.Changes.Select(c => c.Kind));
        Assert.Equal(new[] { "U+200B" }, changes.Changes[0].Invisible);
        Assert.Contains("operator notes", changes.Changes[0].After!.Description);
        Assert.Equal("Answer with pong.", changes.Changes[0].Before!.Description);
    }

    /// <summary>A row whose required members are missing is a router to refuse, not one to
    /// default — the Swift model's own comment on `disabled`, and the reason the member is
    /// `required` here. A defaulted `false` would draw a disabled server as live.</summary>
    [Fact]
    public void ARowMissingARequiredMemberIsRefused()
    {
        var text = Fixture("servers.json").Replace("\"disabled\":false,", "", StringComparison.Ordinal);

        Assert.Throws<JsonException>(() => Decode<ServersEnvelope>(text));
    }

    [Fact]
    public void AnUnknownLifecycleStateIsRefused()
    {
        var text = Fixture("servers.json").Replace("\"state\":\"idle\"", "\"state\":\"vibrating\"", StringComparison.Ordinal);

        Assert.Throws<JsonException>(() => Decode<ServersEnvelope>(text));
    }

    [Fact]
    public void AnUnknownTransportIsRefused()
    {
        var text = Fixture("servers.json").Replace("\"transport\":\"stdio\"", "\"transport\":\"carrier-pigeon\"", StringComparison.Ordinal);

        Assert.Throws<JsonException>(() => Decode<ServersEnvelope>(text));
    }

    /// <summary>The one recorded collapse: `cwd` absent and `cwd` null both decode to a null
    /// Cwd. The Swift model distinguishes them because the reference emits them differently;
    /// nothing on this board draws the value, so the distinction is the inspector's business
    /// (spec-WIN4, ServersWire.cs). The recorded fixture carries no `cwd` member at all.</summary>
    [Fact]
    public void AbsentAndNullCwdBothDecode()
    {
        var absent = Fixture("server-stdio.json");
        var explicitNull = absent.Replace("\"command\":", "\"cwd\":null,\"command\":", StringComparison.Ordinal);

        Assert.Null(Decode<ServerRow>(absent).Cwd);
        Assert.Null(Decode<ServerRow>(explicitNull).Cwd);
    }
}
