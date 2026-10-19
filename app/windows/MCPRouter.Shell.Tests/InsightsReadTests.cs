using System.Net;
using System.Text;
using MCPRouter.Shell.Model.Insights;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Insights board's read and its one action, exercised through the shipping client over an
/// injected handler.
///
/// <para>The router gates both <c>GET /insights</c> and <c>POST /insights/analyse</c> behind the control
/// token, so both must carry it. The wire's <c>lane</c> and <c>cadence</c> words are closed sets, so an
/// unlisted word fails the decode. The error strings below are the router's own, copied from
/// <c>src/analyst.ts</c> and <c>src/control.ts</c>.</para>
/// </summary>
public sealed class InsightsReadTests
{
    private const string Token = "test-token-insights-not-a-secret-just-a-marker";

    private sealed class RecordingHandler(HttpStatusCode status, string body) : HttpMessageHandler
    {
        public HttpMethod? Method { get; private set; }
        public string? Path { get; private set; }
        public string? Authorization { get; private set; }
        public string? ContentType { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Method = request.Method;
            Path = request.RequestUri?.AbsolutePath;
            Authorization = request.Headers.Authorization?.ToString();
            ContentType = request.Content?.Headers.ContentType?.MediaType;
            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    private static ControlApiClient Client(RecordingHandler handler) =>
        new(tokenProvider: () => Token, handler: handler);

    [Fact]
    public void TheCapturedPopulatedBodyDecodesEveryMemberTheBoardReads()
    {
        var envelope = InsightsRouteFixture.Populated();

        Assert.Equal(24, envelope.WindowHours);
        Assert.Equal(12, envelope.Calls.Total);
        Assert.Equal(2, envelope.Calls.Failed);
        Assert.Equal(1, envelope.Calls.UnreadableLines);
        Assert.Equal(0, envelope.Children.Alive);
        Assert.Equal(1, envelope.Children.Declared);
        Assert.Null(envelope.Resident);
        Assert.Equal(4, envelope.OtherCalls);

        var claude = Assert.Single(envelope.CallsByHarness, h => h.Harness == "claudeCode");
        Assert.Equal("Claude Code", claude.DisplayName);
        Assert.Equal(8, claude.Calls);
        Assert.Null(claude.Reason);

        var codex = Assert.Single(envelope.CallsByHarness, h => h.Harness == "codexCLI");
        Assert.Null(codex.Calls);
        Assert.NotEmpty(codex.Reason);

        var gemini = Assert.Single(envelope.CallsByHarness, h => h.Harness == "geminiCLI");
        Assert.Equal(0, gemini.Calls);
        Assert.Null(gemini.Reason);
    }

    [Fact]
    public void TheCallsReconcileWithTheHeadlineTotal()
    {
        var envelope = InsightsRouteFixture.Populated();

        var attributed = envelope.CallsByHarness.Where(h => h.Calls is not null).Sum(h => h.Calls!.Value);

        Assert.Equal(envelope.Calls.Total, attributed + envelope.OtherCalls);
    }

    [Fact]
    public void TheCapturedPopulatedAnalystMemberCarriesItsLastRunAndItsStores()
    {
        var analyst = InsightsRouteFixture.Populated().Analyst!;

        Assert.Equal("claude", analyst.Primary.Lane);
        Assert.Equal("Claude CLI · haiku", analyst.Primary.Label);
        Assert.Equal("grok", analyst.Fallback!.Lane);
        Assert.Equal("sixHourly", analyst.Cadence);
        Assert.Equal("Every 6 hours", analyst.CadenceLabel);
        Assert.False(analyst.Scheduled);
        Assert.NotNull(analyst.NextRunAt);

        Assert.Equal("claude", analyst.Lane!.Lane);
        Assert.NotNull(analyst.RanAt);
        Assert.Equal(12400, analyst.LinesRead);
        Assert.Equal(1, analyst.Findings);
        Assert.False(analyst.UsedFallback);

        Assert.Equal(3, analyst.Stores.Count);
        var cursor = Assert.Single(analyst.Stores, s => s.Harness == "cursor");
        Assert.False(cursor.Read);
        Assert.Equal("SQLite store, not read by this reader", cursor.Reason);
    }

    [Fact]
    public void TheCapturedIdleBodyIsAnEmptyWindowAndAnAnalystThatHasNeverRun()
    {
        var envelope = InsightsRouteFixture.Idle();

        Assert.Equal(0, envelope.Calls.Total);
        Assert.Null(envelope.Resident);
        Assert.Equal(0, envelope.OtherCalls);

        var analyst = envelope.Analyst!;
        Assert.Null(analyst.Lane);
        Assert.Null(analyst.RanAt);
        Assert.Null(analyst.LinesRead);
        Assert.Empty(analyst.Stores);
        Assert.Null(analyst.NextRunAt);
    }

    [Fact]
    public async Task ALaneWordTheRouterDoesNotSendFailsTheDecode()
    {
        var broken = InsightsRouteFixture.PopulatedText()
            .Replace("\"lane\":\"claude\"", "\"lane\":\"gpt\"", StringComparison.Ordinal);
        using var client = Client(new RecordingHandler(HttpStatusCode.OK, broken));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetInsightsAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, failure.Kind);
    }

    [Fact]
    public async Task ACadenceWordTheRouterDoesNotSendFailsTheDecode()
    {
        var broken = InsightsRouteFixture.PopulatedText()
            .Replace("\"cadence\":\"sixHourly\"", "\"cadence\":\"hourly\"", StringComparison.Ordinal);
        using var client = Client(new RecordingHandler(HttpStatusCode.OK, broken));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetInsightsAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, failure.Kind);
    }

    [Fact]
    public async Task TheReadCarriesTheControlTokenBecauseTheRouteGatesIt()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, InsightsRouteFixture.PopulatedText());
        using var client = Client(handler);

        await client.GetInsightsAsync();

        Assert.Equal(HttpMethod.Get, handler.Method);
        Assert.Equal("/insights", handler.Path);
        Assert.Equal($"Bearer {Token}", handler.Authorization);
    }

    [Fact]
    public async Task ARefusedReadIsUnauthorisedAndKeepsTheRoutersOwnWording()
    {
        var refusal = RepoRoot.Read("app/Sources/MCPRouterKit/Control/Fixtures/unauthorized.json");
        using var client = Client(new RecordingHandler(HttpStatusCode.Unauthorized, refusal));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.GetInsightsAsync());

        Assert.Equal(ControlApiFailure.Unauthorized, failure.Kind);
        Assert.Equal(401, failure.Status);
        Assert.DoesNotContain(Token, failure.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnalyseNowPostsWithTheTokenAsJsonAndDecodesTheRunItAnswers()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, InsightsRouteFixture.AnalystText());
        using var client = Client(handler);

        var analyst = await client.AnalyseInsightsAsync();

        Assert.Equal(HttpMethod.Post, handler.Method);
        Assert.Equal("/insights/analyse", handler.Path);
        Assert.Equal($"Bearer {Token}", handler.Authorization);
        Assert.Equal("application/json", handler.ContentType);
        Assert.Equal("claude", analyst.Lane!.Lane);
        Assert.Equal(12400, analyst.LinesRead);
    }

    [Theory]
    [InlineData(503, "session analysis is unavailable: this router has no analyst")]
    [InlineData(409, "an analysis is already running")]
    [InlineData(502, "no analyst model answered — claude: not signed in; grok: not installed")]
    public async Task ARefusedAnalyseKeepsTheRouterStatusAndItsWording(int status, string error)
    {
        var body = $"{{\"error\":\"{error}\"}}";
        using var client = Client(new RecordingHandler((HttpStatusCode)status, body));

        var failure = await Assert.ThrowsAsync<ControlApiException>(() => client.AnalyseInsightsAsync());

        Assert.Equal(ControlApiFailure.Server, failure.Kind);
        Assert.Equal(status, failure.Status);
        Assert.Contains(error, failure.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(Token, failure.Message, StringComparison.Ordinal);
    }
}
