using System.Net;
using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class RouterStatusReaderTests
{
    private sealed class Canned : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _answer;
        public string? LastUrl { get; private set; }

        public Canned(Func<HttpRequestMessage, HttpResponseMessage> answer) => _answer = answer;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastUrl = request.RequestUri?.ToString();
            return Task.FromResult(_answer(request));
        }
    }

    [Fact]
    public async Task ItAsksTheStatusEndpointOnTheResolvedPort()
    {
        var handler = new Canned(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("""{"ok":true,"children":[],"pendingAuth":[]}"""),
        });
        using var reader = new RouterStatusReader(() => "http://127.0.0.1:51234", handler);

        var reading = await reader.ReadAsync();

        Assert.Equal("http://127.0.0.1:51234/status", handler.LastUrl);
        Assert.Equal(AmbientRouterState.AtRest, reading.State);
    }

    /// <summary>
    /// The reading that matters: a router that is not there must never come back as a quiet one.
    /// </summary>
    [Fact]
    public async Task ARouterThatDoesNotAnswer_ReadsAsUnreachable_NotAtRest()
    {
        var handler = new Canned(_ => throw new HttpRequestException("connection refused"));
        using var reader = new RouterStatusReader(() => "http://127.0.0.1:51234", handler);

        var reading = await reader.ReadAsync();

        Assert.Equal(AmbientRouterState.CannotReachRouter, reading.State);
    }

    [Fact]
    public async Task AnErrorStatus_ReadsAsUnreachable()
    {
        var handler = new Canned(_ => new HttpResponseMessage(HttpStatusCode.NotFound));
        using var reader = new RouterStatusReader(() => "http://127.0.0.1:51234", handler);

        Assert.Equal(AmbientRouterState.CannotReachRouter, (await reader.ReadAsync()).State);
    }
}
