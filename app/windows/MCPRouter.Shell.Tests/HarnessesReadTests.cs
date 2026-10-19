using System.Net;
using System.Text;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Harnesses board's read, exercised through the shipping client over an injected handler.
///
/// <para>Two facts here are the protocol rather than the board's copy. The router gates
/// <c>GET /harnesses</c> behind the control token, so the read must carry it. And the wire's
/// <c>state</c> and <c>route</c> words are a closed set, so an unlisted word fails the decode rather
/// than being drawn as a neighbour of a word this build knows.</para>
/// </summary>
public sealed class HarnessesReadTests
{
    private const string Token = "test-token-harness-not-a-secret-just-a-marker";

    private sealed class RecordingHandler(HttpStatusCode status, string body) : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequest = request;
            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    private static ControlApiClient Client(RecordingHandler handler) =>
        new(tokenProvider: () => Token, handler: handler);

    [Fact]
    public async Task TheCapturedBodyDecodesEveryMemberTheBoardReads()
    {
        var envelope = HarnessesRouteFixture.Envelope();

        Assert.Equal("global", envelope.Scope);
        Assert.Equal(7, envelope.Harnesses.Count);

        var claude = HarnessesRouteFixture.Row("claudeCode");
        Assert.Equal("Claude Code", claude.DisplayName);
        Assert.Equal("wired-with-duplicates", claude.State);
        Assert.Equal("http", claude.Route);
        Assert.Equal(2, claude.Entries);
        Assert.Equal(2, claude.DuplicateCount);
        Assert.Equal("measured", claude.Capability);
        Assert.Null(claude.Unreadable);

        var desktop = HarnessesRouteFixture.Row("claudeDesktop");
        Assert.Equal("stdio-shim", desktop.Route);
        Assert.Equal("mcp-remote", desktop.Bridge);
        Assert.Equal("documented", desktop.Capability);

        var cursor = HarnessesRouteFixture.Row("cursor");
        Assert.True(cursor.Exists);
        Assert.NotNull(cursor.Unreadable);
        Assert.Equal("not-wired", cursor.State);

        var opencode = HarnessesRouteFixture.Row("opencode");
        Assert.False(opencode.Exists);
        Assert.Null(opencode.Unreadable);
        Assert.Equal("unknown", opencode.Capability);
    }

    [Fact]
    public async Task AStateWordTheRouterDoesNotSendFailsTheDecode()
    {
        var broken = HarnessesRouteFixture.Text()
            .Replace("\"state\":\"wired-http\"", "\"state\":\"wired-tcp\"", StringComparison.Ordinal);
        using var client = Client(new RecordingHandler(HttpStatusCode.OK, broken));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetHarnessesAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, failure.Kind);
    }

    [Fact]
    public async Task ARouteWordTheRouterDoesNotSendFailsTheDecode()
    {
        var broken = HarnessesRouteFixture.Text()
            .Replace("\"route\":\"stdio-shim\"", "\"route\":\"stdio-tcp\"", StringComparison.Ordinal);
        using var client = Client(new RecordingHandler(HttpStatusCode.OK, broken));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetHarnessesAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, failure.Kind);
    }

    [Fact]
    public async Task TheReadCarriesTheControlTokenBecauseTheRouteGatesIt()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, HarnessesRouteFixture.Text());
        using var client = Client(handler);

        await client.GetHarnessesAsync();

        Assert.Equal($"Bearer {Token}", handler.LastRequest!.Headers.Authorization?.ToString());
    }

    [Fact]
    public async Task ARefusedReadIsUnauthorisedAndKeepsTheRoutersOwnWording()
    {
        var refusal = RepoRoot.Read("app/Sources/MCPRouterKit/Control/Fixtures/unauthorized.json");
        using var client = Client(new RecordingHandler(HttpStatusCode.Unauthorized, refusal));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetHarnessesAsync());

        Assert.Equal(ControlApiFailure.Unauthorized, failure.Kind);
        Assert.Equal(401, failure.Status);
        Assert.DoesNotContain(Token, failure.Message, StringComparison.Ordinal);
    }
}
