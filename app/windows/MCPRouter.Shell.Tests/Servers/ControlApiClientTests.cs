using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The client's contract with the wire, exercised for real through an injected handler: the
/// requests it builds and the failures it raises are the product here — the gate the router
/// answers behind is part of the protocol, and the one wording per failure state is §6's rule.
///
/// <para>The token in these tests is a test constant. The assertion that matters is that it
/// never survives into an exception's text.</para>
/// </summary>
public sealed class ControlApiClientTests
{
    private const string Token = "test-token-ABC-not-a-secret-just-a-marker";

    /// <summary>A real HttpMessageHandler with a scripted answer — the seam the client's
    /// constructor names, so the class under test is the shipping class.</summary>
    private sealed class ScriptedHandler(Func<HttpRequestMessage, string?, HttpResponseMessage> respond)
        : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        public string? LastContent { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequest = request;
            LastContent = request.Content is null
                ? null
                : request.Content.ReadAsStringAsync(cancellationToken).GetAwaiter().GetResult();
            return Task.FromResult(respond(request, LastContent));
        }
    }

    private static HttpResponseMessage Text(HttpStatusCode status, string body) => new(status)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json"),
    };

    private static string Fixture(string name) =>
        RepoRoot.Read($"app/Sources/MCPRouterKit/Control/Fixtures/{name}");

    private static ControlApiClient Client(ScriptedHandler handler) =>
        new(tokenProvider: () => Token, handler: handler);

    // ------------------------------------------------------------------ reads

    [Fact]
    public async Task AReadCarriesNoTokenAndDecodesTheRecordedEnvelope()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.OK, Fixture("servers.json")));
        using var client = Client(handler);

        var envelope = await client.GetServersAsync();

        Assert.Null(handler.LastRequest!.Headers.Authorization);
        Assert.Equal(new Uri("http://127.0.0.1:8879/servers"), handler.LastRequest.RequestUri);
        Assert.Equal(8971, envelope.Port);
        Assert.Equal(4, envelope.Servers.Count);
    }

    [Fact]
    public async Task TheChangesPathEscapesTheServerName()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.OK, Fixture("changes-pending.json")));
        using var client = Client(handler);

        await client.GetChangesAsync("a b/c");

        Assert.Contains("servers/a%20b%2Fc/changes", handler.LastRequest!.RequestUri!.PathAndQuery);
    }

    // ------------------------------------------------------------------ writes

    [Fact]
    public async Task AWriteCarriesTheBearerTokenAndTheJsonContentType()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.Created, Fixture("added.json")));
        using var client = Client(handler);

        await client.AddServerAsync(new NewServerBody { Name = "probe-server", Command = "probe" });

        Assert.Equal($"Bearer {Token}", handler.LastRequest!.Headers.Authorization!.ToString());
        Assert.Equal("application/json", handler.LastRequest.Content!.Headers.ContentType!.MediaType);
        Assert.Contains("\"name\":\"probe-server\"", handler.LastContent);
    }

    [Fact]
    public async Task AWriteWithNoTokenStillSendsAndLetsTheRouterAnswer()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.Created, Fixture("added.json")));
        using var client = new ControlApiClient(tokenProvider: () => "", handler: handler);

        await client.AddServerAsync(new NewServerBody { Name = "probe-server" });

        Assert.Null(handler.LastRequest!.Headers.Authorization);
    }

    [Fact]
    public async Task ForceIsAQueryFlagAndOnlyThen()
    {
        HttpResponseMessage Answer(HttpRequestMessage request, string? _) =>
            Text(HttpStatusCode.Created, Fixture("added.json"));

        var plain = new ScriptedHandler(Answer);
        using (var client = Client(plain))
        {
            await client.AddServerAsync(new NewServerBody { Name = "probe" });
            Assert.Equal("", plain.LastRequest!.RequestUri!.Query);
        }

        var forced = new ScriptedHandler(Answer);
        using (var client = Client(forced))
        {
            await client.AddServerAsync(new NewServerBody { Name = "probe" }, force: true);
            Assert.Equal("?force=1", forced.LastRequest!.RequestUri!.Query);
        }
    }

    // ------------------------------------------------------------------ the failures

    [Fact]
    public async Task ARefusedAddCarriesTheRoutersOwnHint()
    {
        // The hint is the sentence that turns "Add it anyway" on — dropped, the user is told
        // what failed and not what to do, which is exactly what the copy rules forbid.
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.UnprocessableEntity, Fixture("add-refused.json")));
        using var client = Client(handler);

        var refused = await Assert.ThrowsAsync<ControlApiException>(() => client.AddServerAsync(new NewServerBody { Name = "probe" }));

        Assert.Equal(ControlApiFailure.Server, refused.Kind);
        Assert.Equal(422, refused.Status);
        Assert.Equal("retry with ?force=1 to add it anyway", refused.Hint);
        Assert.Contains(refused.Hint!, refused.Advice);
    }

    [Fact]
    public async Task A401IsUnauthorizedAndTheTokenNeverReachesTheException()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.Unauthorized, Fixture("unauthorized.json")));
        using var client = Client(handler);

        var unauthorized = await Assert.ThrowsAsync<ControlApiException>(() => client.GetServersAsync());

        Assert.Equal(ControlApiFailure.Unauthorized, unauthorized.Kind);
        Assert.Equal("This app isn't authorised to talk to the router", unauthorized.Headline);
        Assert.Equal("Re-pair…", unauthorized.ActionLabel);
        Assert.DoesNotContain(Token, unauthorized.ToString());
    }

    [Fact]
    public async Task LoopbackRefusedIsRouterNotRunningNotTransport()
    {
        var handler = new ScriptedHandler((_, _) =>
            throw new HttpRequestException("Connection refused",
                new SocketException((int)SocketError.ConnectionRefused)));
        using var client = Client(handler);

        var refused = await Assert.ThrowsAsync<ControlApiException>(() => client.GetServersAsync());

        Assert.Equal(ControlApiFailure.RouterNotRunning, refused.Kind);
        Assert.Equal("The router isn't running", refused.Headline);
        Assert.Equal("Start the router", refused.ActionLabel);
        Assert.StartsWith(
            "The router isn't running. Nothing is listening on the control port",
            refused.UserFacingDescription);
    }

    [Fact]
    public async Task ABodyThisVersionCannotReadIsMalformedNotACrash()
    {
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.OK, "<html>not the wire</html>"));
        using var client = Client(handler);

        var malformed = await Assert.ThrowsAsync<ControlApiException>(() => client.GetHarnessesAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, malformed.Kind);
        Assert.Equal("The router sent a response this version doesn't understand", malformed.Headline);
    }

    [Fact]
    public async Task AnUnreadableErrorBodyStillCarriesTheStatus()
    {
        var handler = new ScriptedHandler((_, _) => new HttpResponseMessage(HttpStatusCode.BadGateway)
        {
            Content = new StringContent("gateway noise", Encoding.UTF8, "text/plain"),
        });
        using var client = Client(handler);

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetServersAsync());

        Assert.Equal(ControlApiFailure.Transport, failure.Kind);
        Assert.Contains("502", failure.Detail);
    }

    /// <summary>The wire records are strict; a success that cannot decode is a router this
    /// version does not understand, not an empty board.</summary>
    [Fact]
    public async Task AMalformedSuccessIsReportedThroughTheClient()
    {
        var broken = Fixture("servers.json").Replace("\"disabled\":false,", "", StringComparison.Ordinal);
        var handler = new ScriptedHandler((_, _) => Text(HttpStatusCode.OK, broken));
        using var client = Client(handler);

        var malformed = await Assert.ThrowsAsync<ControlApiException>(() => client.GetServersAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, malformed.Kind);
    }
}

/// <summary>
/// The harness route's 503 — "harness detection is unavailable" — is a refusal the board must
/// render as its own partial state, so the error body's shape it arrives in is pinned here.
/// </summary>
public sealed class HarnessUnavailableTests
{
    [Fact]
    public async Task The503CarriesItsReasonAndTheBoardCopyWrapsIt()
    {
        var handler = new ScriptedHandler503();
        using var client = new ControlApiClient(tokenProvider: () => "", handler: handler);

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetHarnessesAsync());

        Assert.Equal(ControlApiFailure.Server, failure.Kind);
        Assert.Equal(503, failure.Status);
        Assert.Equal(
            "Harnesses unavailable: harness detection is unavailable: this router has no inventory source",
            ServersCopy.HarnessUnavailable(failure.Detail));
    }

    private sealed class ScriptedHandler503 : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var response = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                Content = new StringContent(
                    "{\"error\":\"harness detection is unavailable: this router has no inventory source\"}",
                    Encoding.UTF8,
                    "application/json"),
            };
            return Task.FromResult(response);
        }
    }
}

/// <summary>Guards the copy constants against drift from the spec's state matrix.</summary>
public sealed class ServersCopyTests
{
    [Fact]
    public void TheDisconnectedCopyIsTheMacClientsWording()
    {
        // §6: one name per state across devices. These strings are the port of
        // ControlAPIError.routerNotRunning's headline and advice; rewording one side without
        // the other is the two-wordings failure the rule exists to prevent.
        var refused = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");
        Assert.Equal("The router isn't running", refused.Headline);
        Assert.Equal(
            "Nothing is listening on the control port, so there is nothing to show yet. " +
            "Starting it takes a moment and your servers stay exactly as you left them.",
            refused.Advice);
    }

    [Fact]
    public void EveryUserFacingSentenceIsSentenceCase()
    {
        var sentences = new[]
        {
            ServersCopy.BoardSentence,
            ServersCopy.ReapIdleReason,
            ServersCopy.EmptyHeadline,
            ServersCopy.EmptySentence,
            ServersCopy.EmptyAction,
            ServersCopy.RetryLabel,
            ServersCopy.StartRouterLabel,
            ServersCopy.CannotStartRouterReason,
            ServersCopy.LoadingLine,
            ServersCopy.HeldBandBody,
            ServersCopy.ReviewChangesLabel,
            ServersCopy.AddDialogTitle,
            ServersCopy.AddCommitLabel,
            ServersCopy.AddCancelLabel,
            ServersCopy.AddNameLabel,
            ServersCopy.AddCommandLabel,
            ServersCopy.AddArgsLabel,
            ServersCopy.AddArgsHelper,
            ServersCopy.AddUrlLabel,
            ServersCopy.AddUrlHelper,
            ServersCopy.AddAnywayLabel,
            ServersCopy.RemoveLabel,
            ServersCopy.RemoveDisabledReason,
            ServersCopy.RemoveCommitLabel,
            ServersCopy.RemoveCancelLabel,
            ServersCopy.RemoveDialogBody,
            ServersCopy.RemoveDialogTitle("postgres-mcp"),
            ServersCopy.Removed("postgres-mcp"),
            ServersCopy.RemovedWithoutAsking("postgres-mcp"),
        };

        foreach (var sentence in sentences)
        {
            Assert.False(string.IsNullOrWhiteSpace(sentence));
            Assert.False(char.IsLower(sentence[0]), sentence);

            // "No all-caps" is a rule about shouted labels, not about initialisms: a field
            // labelled Url would be wrong in the other direction. The allowed set is named,
            // so it cannot grow quietly.
            const string Initialisms = "URL";
            if (!Initialisms.Contains(sentence, StringComparison.Ordinal))
            {
                Assert.False(sentence.All(char.IsUpper), sentence);
            }
        }
    }

    [Fact]
    public void TheStaleLineNamesWhenTheReadingWasTaken()
    {
        Assert.Equal(
            "The last refresh didn't complete — showing the reading from 14:02:07.",
            ServersCopy.StaleLine("14:02:07"));
    }

    [Fact]
    public void TheHeldBandCountsItsNoun()
    {
        Assert.Equal("1 tool on mobbin changed their input schema",
            ServersCopy.HeldBandHead(1, "mobbin"));
        Assert.Equal("2 tools on mobbin changed their input schema",
            ServersCopy.HeldBandHead(2, "mobbin"));
    }

    /// <summary>The reap decision, the carried adopt action and the ellipsis convention are all
    /// claimed by spec-WIN4; this holds the spec to the copy that ships under it.</summary>
    [Fact]
    public void TheSpecAndTheCopyAgreeAboutTheCarriedReapAndTheEllipsis()
    {
        var spec = RepoRoot.Read("planning/specs/spec-WIN4.md");

        Assert.Contains("Add server…", spec);
        Assert.Contains("Add one by hand…", spec);
        Assert.Contains("NOT-RUN on the wire", spec);
        Assert.Contains("Reap idle", spec);
    }
}
