using System.Net;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Xunit;
using static MCPRouter.Shell.Tests.SkillWritesFixture;

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
        /// <summary>The request body as sent, read before the client disposes the request.</summary>
        public string? LastBody { get; private set; }
        public string? LastContentType { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            LastRequest = request;
            LastBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            LastContentType = request.Content?.Headers.ContentType?.MediaType;
            return respond(request);
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
    public async Task MarketplacesDecodeTheRoutersBodyAndCarryTheControlToken()
    {
        // The router gates GET /marketplaces on the token, so the read sends it when the token file is present.
        var home = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);
        try
        {
            File.WriteAllText(Path.Combine(home, "control.token"), "test-token");
            var handler = new StubHandler(_ => Json(200, RepoRoot.Read("app/windows/MCPRouter.Shell.Tests/Fixtures/marketplaces.json")));
            var client = new LiveSkillsControlClient(new HttpClient(handler), tokenFile: new RouterTokenFile(home));

            var response = await client.MarketplacesAsync();

            Assert.Equal(2, response.MarketplaceList.Count);
            Assert.Equal("Bearer test-token", handler.LastRequest?.Headers.Authorization?.ToString());
        }
        finally
        {
            Directory.Delete(home, recursive: true);
        }
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

    // ------------------------------------------------------------------ the held-version routes

    private static LiveSkillsControlClient TokenedClient(StubHandler handler, string home)
    {
        File.WriteAllText(System.IO.Path.Combine(home, "control.token"), "test-token-value");
        return new LiveSkillsControlClient(new HttpClient(handler), tokenFile: new RouterTokenFile(home));
    }

    private static async Task<SkillsControlException> FailureOf(
        StubHandler handler, Func<LiveSkillsControlClient, Task> call)
    {
        var client = new LiveSkillsControlClient(new HttpClient(handler));
        return await Assert.ThrowsAsync<SkillsControlException>(() => call(client));
    }

    [Fact]
    public async Task TheUpdateCheckDecodesTheBodyTheRouterServes()
    {
        var (status, body) = SkillWritesFixture.Captured("updates");
        var handler = new StubHandler(_ => Json(status, body));
        var client = new LiveSkillsControlClient(new HttpClient(handler));

        var updates = await client.ExtensionUpdatesAsync();

        Assert.EndsWith("/extensions/updates", handler.LastRequest!.RequestUri!.ToString());
        var offer = Assert.Single(updates.EntryList, entry => entry.HasUpdate);
        Assert.Equal(StoredExtensionKind.Plugins, offer.Kind);
        Assert.Equal("trawl@fledgeling-plugins", offer.Name);
        Assert.Equal("2.2.0", offer.Installed);
        Assert.Equal("2.3.0", offer.Available);
        // The changelog of the version offered, exactly as the router read it from Claude's cache.
        Assert.Equal(
            "# Changelog\n\n## 2.3.0\n\n- Reads the session transcripts directly.\n- Adds a date filter.\n",
            offer.Changelog?.Text);
        Assert.Equal("CHANGELOG.md from the cached 2.3.0 copy", offer.Changelog?.Note);
    }

    [Fact]
    public async Task AnUpdateCheckRefusalIsAServerErrorNotVersionSkew()
    {
        // The update check is not one of the two skew reads. A 404 there is an answer the router gave, and the
        // Mac's shared send reads it as a refusal carrying the router's own sentence.
        var exception = await FailureOf(
            new StubHandler(_ => Json(404, "{ \"error\": \"no such route\" }")),
            client => client.ExtensionUpdatesAsync());

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal(404, server.Status);
        Assert.Equal("no such route", server.Message);
    }

    [Fact]
    public async Task KeepSendsTheVersionAsJsonToThePluginEntryWithTheToken()
    {
        var (status, body) = SkillWritesFixture.Captured("keep");
        var handler = new StubHandler(_ => Json(status, body));
        var client = TokenedClient(handler, NewHome());

        var ack = await client.KeepHeldVersionAsync("trawl@fledgeling-plugins", "2.3.0");

        Assert.Equal(HttpMethod.Post, handler.LastRequest!.Method);
        Assert.EndsWith(
            "/extensions/plugins/trawl%40fledgeling-plugins/keep",
            handler.LastRequest.RequestUri!.ToString());
        Assert.Equal("{\"pluginVersion\":\"2.3.0\"}", handler.LastBody);
        Assert.Equal("application/json", handler.LastContentType);
        Assert.Equal("Bearer test-token-value", handler.LastRequest.Headers.Authorization?.ToString());
        Assert.Equal("trawl@fledgeling-plugins", ack.Kept);
        Assert.Equal("2.3.0", ack.PluginVersion);
    }

    [Fact]
    public async Task PromoteFromCacheSendsTheCacheSourceAndTheVersionOnly()
    {
        // The board never holds the files it installs: nothing is sent but the version and the source.
        var (status, body) = SkillWritesFixture.Captured("promote");
        var handler = new StubHandler(_ => Json(status, body));
        var client = TokenedClient(handler, NewHome());

        var ack = await client.PromoteFromCacheAsync("trawl@fledgeling-plugins", "2.3.0");

        Assert.EndsWith(
            "/extensions/plugins/trawl%40fledgeling-plugins/promote",
            handler.LastRequest!.RequestUri!.ToString());
        Assert.Equal("{\"source\":\"cache\",\"pluginVersion\":\"2.3.0\"}", handler.LastBody);
        Assert.Equal("application/json", handler.LastContentType);
        Assert.Equal("trawl@fledgeling-plugins", ack.Promoted);
        Assert.Equal("2.2.0", ack.Replaced);
        Assert.Equal("1002", ack.Restore);
    }

    [Fact]
    public async Task UndoSendsTheRestoreReferenceAndReadsWhatWasWithdrawn()
    {
        var (status, body) = SkillWritesFixture.Captured("undo");
        var handler = new StubHandler(_ => Json(status, body));
        var client = TokenedClient(handler, NewHome());

        var ack = await client.UndoPromotionAsync("trawl@fledgeling-plugins", "1002");

        Assert.EndsWith(
            "/extensions/plugins/trawl%40fledgeling-plugins/undo-promote",
            handler.LastRequest!.RequestUri!.ToString());
        Assert.Equal("{\"restore\":\"1002\"}", handler.LastBody);
        Assert.Equal("2.2.0", ack.Version);
        Assert.Equal("2.3.0", ack.Withdrawn);
    }

    [Fact]
    public async Task AWriteRefusalIsAServerErrorWithTheRoutersOwnSentence()
    {
        // A version the cache does not hold. On a write a 404 names what the caller asked for, so it is a refusal
        // and never version skew.
        var (status, body) = SkillWritesFixture.Captured("refusePromoteMissingVersion");
        var exception = await FailureOf(
            new StubHandler(_ => Json(status, body)),
            client => client.PromoteFromCacheAsync("trawl@fledgeling-plugins", "9.9.9"));

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal(404, server.Status);
        Assert.Equal("the plugin cache holds no copy of trawl@fledgeling-plugins at 9.9.9", server.Message);
        Assert.Equal("The router couldn't complete that", exception.Error.Headline);
    }

    [Fact]
    public async Task AWriteRefusalKeepsTheRoutersHint()
    {
        var exception = await FailureOf(
            new StubHandler(_ => Json(409, "{ \"error\": \"a kept version already exists\", \"hint\": \"undo first\" }")),
            client => client.KeepHeldVersionAsync("trawl@fledgeling-plugins", "2.3.0"));

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal(409, server.Status);
        Assert.Equal("undo first", server.Hint);
        Assert.Contains("undo first", exception.Error.Advice);
    }

    [Fact]
    public async Task AnUndoRefusalCarriesTheSentenceTheRouterGave()
    {
        var (status, body) = SkillWritesFixture.Captured("refuseUndoAbsent");
        var exception = await FailureOf(
            new StubHandler(_ => Json(status, body)),
            client => client.UndoPromotionAsync("trawl@fledgeling-plugins", "999"));

        var server = Assert.IsType<SkillsControlError.Server>(exception.Error);
        Assert.Equal("no promotion of plugin \"trawl@fledgeling-plugins\" is recorded at 999", server.Message);
    }

    [Fact]
    public async Task AWriteOn401IsUnauthorized()
    {
        var exception = await FailureOf(
            new StubHandler(_ => Json(401, "{}")),
            client => client.KeepHeldVersionAsync("trawl@fledgeling-plugins", "2.3.0"));

        Assert.IsType<SkillsControlError.Unauthorized>(exception.Error);
    }

    [Fact]
    public async Task AWriteWithNoRouterRunningIsRouterNotRunning()
    {
        HttpResponseMessage Throw(HttpRequestMessage _) =>
            throw new HttpRequestException("Connection refused", inner: null);

        var exception = await FailureOf(
            new StubHandler(Throw),
            client => client.PromoteFromCacheAsync("trawl@fledgeling-plugins", "2.3.0"));

        Assert.IsType<SkillsControlError.RouterNotRunning>(exception.Error);
    }

    [Fact]
    public async Task AWriteWhoseReplyDoesNotDecodeIsMalformedNotServer()
    {
        var exception = await FailureOf(
            new StubHandler(_ => Json(200, "{ not json")),
            client => client.KeepHeldVersionAsync("trawl@fledgeling-plugins", "2.3.0"));

        Assert.IsType<SkillsControlError.MalformedResponse>(exception.Error);
    }
}
