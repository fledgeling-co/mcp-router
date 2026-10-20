using System.Net;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The live read path, against canned HTTP statuses - the real boundary's mapping, exercised
/// without a network. The 404 case is the one that matters most: it is the answer today's router
/// actually gives, and it must arrive as version skew, never as "the router couldn't complete
/// that".
/// </summary>
public sealed class SkillsControlClientTests
{
    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond)
        : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        public int CallCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            LastRequest = request;
            return Task.FromResult(respond(request));
        }
    }

    private static HttpResponseMessage Json(int status, string body) => new((HttpStatusCode)status)
    {
        Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json"),
    };

    private static async Task<SkillsControlException> RunAsync(
        StubHandler handler, string path = "skills")
    {
        var client = new LiveSkillsControlClient(new HttpClient(handler));
        Task task = path == "skills" ? (Task)client.SkillsAsync() : client.MarketplacesAsync();
        return await Assert.ThrowsAsync<SkillsControlException>(() => task);
    }

    [Fact]
    public async Task ASuccessfulReadDecodesTheSkillsEnvelope()
    {
        const string body = """
        {
          "skills": [ { "name": "trawl", "path": "p",
            "source": { "kind": "standalone", "path": "p" }, "presence": {}, "held": null, "provenance": null } ],
          "clients": []
        }
        """;
        var handler = new StubHandler(_ => Json(200, body));
        var client = new LiveSkillsControlClient(new HttpClient(handler));

        var response = await client.SkillsAsync();

        Assert.Single(response.SkillList);
        Assert.EndsWith("/skills", handler.LastRequest?.RequestUri?.ToString());
    }

    /// <summary>
    /// The body <c>GET /skills</c> answered with, captured from the TypeScript router
    /// (<c>Fixtures/skills.json</c>), read through the live client so the decode is the one the board
    /// performs. A hand-written body would prove the decoder agrees with its author.
    /// </summary>
    [Fact]
    public async Task DecodesTheBodyTheRouterActuallyServes()
    {
        var handler = new StubHandler(_ => Json(200, RepoRoot.Read("app/windows/MCPRouter.Shell.Tests/Fixtures/skills.json")));
        var client = new LiveSkillsControlClient(new HttpClient(handler));

        var response = await client.SkillsAsync();

        var trawl = Assert.Single(response.SkillList, s => s.Name == "trawl");
        var origin = Assert.IsType<SkillSource.PluginOrigin>(trawl.Source);
        Assert.Equal("2.2.0", origin.PluginVersion);
        Assert.Equal("fledgeling-plugins", origin.Marketplace);
        Assert.Equal(1, origin.SiblingSkillCount);
        Assert.Equal(SkillPresence.Present, trawl.Presence["claudeCode"]);
        Assert.Equal("2.3.0", trawl.Held?.PluginVersion);
        Assert.True(trawl.Held?.WantsMore);

        var graphify = Assert.Single(response.SkillList, s => s.Name == "graphify");
        Assert.True(graphify.Source.IsStandalone);
        Assert.Null(graphify.Held);

        Assert.Equal(8, response.ClientList.Count);
        Assert.Equal(6, response.SlotClients.Count);
        Assert.Equal(2, response.UnsupportedClients.Count);
        Assert.Equal(SkillClientStatus.Read, response.ClientList.Single(c => c.Id == "claudeCode").Status);
    }

    /// <summary>
    /// <c>GET /skills</c> is token-gated on every method (<c>src/control.ts</c>), so the read carries the
    /// router's own control token, read from its file at call time the way the Servers client sends it.
    /// </summary>
    [Fact]
    public async Task ReadsCarryTheControlTokenAsABearerHeader()
    {
        var home = NewHome();
        File.WriteAllText(System.IO.Path.Combine(home, "control.token"), "test-token-value");
        var handler = new StubHandler(_ => Json(200, "{ \"skills\": [], \"clients\": [] }"));
        var client = new LiveSkillsControlClient(new HttpClient(handler), tokenFile: new RouterTokenFile(home));

        await client.SkillsAsync();

        Assert.Equal("Bearer test-token-value", handler.LastRequest!.Headers.Authorization?.ToString());
    }

    [Fact]
    public async Task ReadsSendNoAuthorizationWhenThereIsNoTokenFile()
    {
        // No token file means the router has never run here, so there is no credential to send and
        // no reason for the read to invent one.
        var handler = new StubHandler(_ => Json(200, "{ \"skills\": [], \"clients\": [] }"));
        var client = new LiveSkillsControlClient(new HttpClient(handler), tokenFile: new RouterTokenFile(NewHome()));

        await client.SkillsAsync();

        Assert.False(handler.LastRequest!.Headers.Contains("Authorization"));
    }

    private static string NewHome()
    {
        var home = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "win-skills-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);
        return home;
    }

    [Fact]
    public async Task A404IsVersionSkewWithTheMacCarriedWording()
    {
        var exception = await RunAsync(new StubHandler(_ => Json(404, "{}")));

        var malformed = Assert.IsType<SkillsControlError.MalformedResponse>(exception.Error);
        Assert.Equal("this router has no /skills endpoint", malformed.Detail);
        // And the sentence the user reads is the skew sentence, not the failure sentence.
        Assert.Contains("newer or older", exception.Error.Advice);
        Assert.Equal(
            "The router sent a response this version doesn't understand",
            exception.Error.Headline);
    }

    [Fact]
    public async Task A404OnMarketplacesNamesMarketplaces()
    {
        var exception = await RunAsync(new StubHandler(_ => Json(404, "{}")), path: "marketplaces");

        var malformed = Assert.IsType<SkillsControlError.MalformedResponse>(exception.Error);
        Assert.Equal("this router has no /marketplaces endpoint", malformed.Detail);
    }

    [Fact]
    public async Task A401IsUnauthorized()
    {
        var exception = await RunAsync(new StubHandler(_ => Json(401, "{}")));

        Assert.IsType<SkillsControlError.Unauthorized>(exception.Error);
        Assert.Equal(
            "This app isn't authorised to talk to the router",
            exception.Error.Headline);
    }

    [Fact]
    public async Task A500CarriesTheRoutersOwnMessageAndHint()
    {
        var exception = await RunAsync(new StubHandler(_ => Json(500,
            "{ \"error\": \"skills index unavailable\", \"hint\": \"retry shortly\" }")));

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal(500, server.Status);
        Assert.Equal("skills index unavailable", server.Message);
        Assert.Equal("retry shortly", server.Hint);
        Assert.Contains("retry shortly", exception.Error.Advice);
    }

    [Fact]
    public async Task ANonJsonErrorBodyStillNamesTheStatus()
    {
        var handler = new StubHandler(_ => Json(503, "<html>busy</html>"));
        var exception = await RunAsync(handler);

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal(503, server.Status);
        Assert.Equal("the router sent no readable error", server.Message);
    }

    [Fact]
    public async Task UnparsableSuccessBodyIsMalformedNotServer()
    {
        var exception = await RunAsync(new StubHandler(_ => Json(200, "{ not json")));

        Assert.IsType<SkillsControlError.MalformedResponse>(exception.Error);
    }

    [Fact]
    public async Task AConnectFailureIsTheRouterNotRunning()
    {
        HttpResponseMessage Throw(HttpRequestMessage _)
        {
            throw new HttpRequestException("Connection refused", inner: null);
        }

        var handler = new StubHandler(Throw);
        var exception = await RunAsync(handler);

        Assert.IsType<SkillsControlError.RouterNotRunning>(exception.Error);
        Assert.Equal("The router isn't running", exception.Error.Headline);
    }

    [Fact]
    public void TheTokenFileNeverBeingWrittenMeansNotRunningWithoutARequest()
    {
        // An empty home directory: the router has never run here. The client reports the
        // conclusion without pretending the wire said it.
        var home = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(), "win6-tests", Guid.NewGuid().ToString("N"));
        var tokenFile = new RouterTokenFile(home);

        Assert.False(System.IO.File.Exists(tokenFile.FilePath));
        Assert.Null(tokenFile.Read());
    }

    [Fact]
    public void TheTokenFilePathFollowsTheRoutersOwnLayout()
    {
        var tokenFile = new RouterTokenFile("C:/tmp/router-home");

        Assert.Equal(
            System.IO.Path.Combine("C:/tmp/router-home", "control.token"),
            tokenFile.FilePath);
    }
}
