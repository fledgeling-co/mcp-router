using System.Net;
using MCPRouter.Shell.Model.Control;
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

    [Fact]
    public async Task ReadsCarryNoAuthorizationHeader()
    {
        var handler = new StubHandler(_ => Json(200, "{ \"skills\": [], \"clients\": [] }"));
        var client = new LiveSkillsControlClient(new HttpClient(handler));

        await client.SkillsAsync();

        // The router requires the token on mutating requests only; a read that shipped one would
        // be the read path inventing a credential requirement - and a test-time giveaway of the
        // token's very existence.
        Assert.False(handler.LastRequest!.Headers.Contains("Authorization"));
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
