using System.Net;
using System.Text;
using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The real HTTP path, exercised against a loopback fixture that answers the same shapes
/// <c>describe()</c> serves. This is real HTTP over real sockets — the machine has no live router
/// (spec-WIN8 §7 gap 1), and this fixture is the closest channel to the installed conversation
/// that can actually be measured here. It is not a run against the router, and the progress note
/// says so.
/// </summary>
public sealed class ControlClientTests : IDisposable
{
    private readonly FixtureServer _server = new();

    public void Dispose() => _server.Dispose();

    [Fact]
    public async Task AServersAnswerDecodesIntoTheFieldsTheChecksRead()
    {
        _server.Respond("/servers", FixtureServer.ServersBody(port: 9941));
        using var client = _server.NewClient();

        var response = await client.ServersAsync();

        var trawl = Assert.Single(response.Servers);
        Assert.Equal("trawl", trawl.Name);
        Assert.Equal("1.4.2", trawl.Hash);
        Assert.Equal(4, trawl.Tools);
        Assert.True(trawl.Auth.Supported);
        Assert.True(trawl.Auth.Authorized);
        Assert.Equal(12, trawl.Usage.Calls);
        Assert.Equal(2, trawl.Usage.Errors);

        // The port the router says it answers on is adopted for subsequent calls.
        Assert.Equal(9941, client.Port);
    }

    [Fact]
    public async Task SubsequentCallsGoToThePortTheRouterNamed()
    {
        _server.Respond("/servers", FixtureServer.ServersBody(port: _server.Port));
        _server.Respond("/skills", "{\"error\":\"no such route\"}", HttpStatusCode.NotFound);
        using var client = _server.NewClient();

        await client.ServersAsync();
        var skills = await client.SkillsAsync();

        Assert.Single(skills.AbsentReason);
        _server.AssertLastRequestStartedWith("/skills");
    }

    [Fact]
    public async Task A404ForSkillsIsANamedAbsenceNotAnException()
    {
        _server.Respond("/servers", FixtureServer.ServersBody(port: _server.Port));
        _server.Respond("/skills", "{\"error\":\"no such route\"}", HttpStatusCode.NotFound);
        using var client = _server.NewClient();

        await client.ServersAsync();
        var skills = await client.SkillsAsync();

        var reason = Assert.Single(skills.AbsentReason);
        Assert.Contains("404", reason, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ARefusedConnectionIsRouterNotRunning()
    {
        // No listener at all on a free port: the socket is refused before a status exists.
        var port = FixtureServer.FreePort();
        using var client = new ControlClient(() => "unused-token", initialPort: port);

        var error = await Assert.ThrowsAsync<ControlApiError>(() => client.ServersAsync());
        Assert.Equal(ControlApiError.ControlErrorKind.RouterNotRunning, error.Kind);
        Assert.Equal(CheckCopy.RouterNotRunningHeadline, error.Headline);
    }

    [Fact]
    public async Task TheReindexCallSendsTheBearerTokenFromTheReader()
    {
        _server.Respond("/servers/trawl/reindex", "{}");
        using var client = _server.NewClient(tokenOverride: "the-test-token");

        await client.ReindexAsync("trawl");

        Assert.Equal("Bearer", _server.LastAuthorizationScheme);
        Assert.Equal("the-test-token", _server.LastAuthorizationParameter);
    }

    [Fact]
    public async Task NoTokenIsUnauthorizedAndNoCredentialIsInvented()
    {
        _server.Respond("/servers/trawl/reindex", "{}", HttpStatusCode.Unauthorized);
        using var client = _server.NewClient(tokenOverride: null);

        // A missing token is refused locally — the write never leaves without the header.
        await Assert.ThrowsAsync<ControlApiError>(() => client.ReindexAsync("trawl"));
        Assert.Equal(0, _server.RequestCount);
    }

    [Fact]
    public async Task A401FromTheRouterMapsToUnauthorized()
    {
        _server.Respond("/servers/trawl/reindex", "{}", HttpStatusCode.Unauthorized);
        using var client = _server.NewClient(tokenOverride: "stale-token");

        var error = await Assert.ThrowsAsync<ControlApiError>(() => client.ReindexAsync("trawl"));

        Assert.Equal(ControlApiError.ControlErrorKind.Unauthorized, error.Kind);
    }

    [Fact]
    public async Task AnErrorStatusCarriesTheRoutersMessageAndHint()
    {
        _server.Respond(
            "/servers/trawl/reindex",
            "{\"error\":\"could not start\",\"hint\":\"check its command\"}",
            HttpStatusCode.UnprocessableEntity);
        using var client = _server.NewClient(tokenOverride: "any");

        var error = await Assert.ThrowsAsync<ControlApiError>(() => client.ReindexAsync("trawl"));

        Assert.Equal(ControlApiError.ControlErrorKind.Server, error.Kind);
        Assert.NotNull(error.Detail);
        Assert.Contains("422", error.Detail, StringComparison.Ordinal);
        Assert.Contains("could not start", error.Detail, StringComparison.Ordinal);
        Assert.Contains("check its command", error.Detail, StringComparison.Ordinal);
        Assert.Equal("The router couldn't complete that", error.Headline);
    }

    [Fact]
    public void TheTokenPathSitsBesideTheRoutersConfig()
    {
        var path = ControlClient.TokenPath;
        Assert.EndsWith("control.token", path, StringComparison.Ordinal);
        Assert.Contains(Path.Combine(".claude", "mcp-router"), path, StringComparison.Ordinal);
    }
}

/// <summary>A loopback HTTP fixture: one listener, one taped response per path, the requests kept
/// for assertion. The token an assertion reads exists only inside the test process.</summary>
internal sealed class FixtureServer : IDisposable
{
    private readonly HttpListener _listener;
    private readonly Dictionary<string, (string Body, HttpStatusCode Status)> _responses = new(StringComparer.Ordinal);
    private readonly CancellationTokenSource _stopping = new();

    public int Port { get; }
    public string? LastAuthorizationParameter { get; private set; }
    public string? LastAuthorizationScheme { get; private set; }
    public string? LastPath { get; private set; }
    public int RequestCount { get; private set; }

    public FixtureServer()
    {
        Port = FreePort();
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://127.0.0.1:{Port}/");
        _listener.Start();
        _ = Task.Run(() => ServeAsync(_stopping.Token));
    }

    public static int FreePort()
    {
        var socket = new System.Net.Sockets.Socket(
            System.Net.Sockets.AddressFamily.InterNetwork,
            System.Net.Sockets.SocketType.Stream,
            System.Net.Sockets.ProtocolType.Tcp);
        socket.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        var port = ((IPEndPoint)socket.LocalEndPoint!).Port;
        socket.Dispose();
        return port;
    }

    public void Respond(string path, string body, HttpStatusCode status = HttpStatusCode.OK) =>
        _responses[path] = (body, status);

    public ControlClient NewClient(string? tokenOverride = null) =>
        new(() => tokenOverride, initialPort: Port);

    public void AssertLastRequestStartedWith(string prefix) =>
        Assert.True(LastPath?.StartsWith(prefix, StringComparison.Ordinal) ?? false, $"last request was {LastPath}");

    public static string ServersBody(int port = 9941) => $$"""
        {
          "port": {{port}},
          "idleMs": 900000,
          "since": "2026-08-30T00:00:00Z",
          "servers": [
            {
              "name": "trawl",
              "transport": "stdio",
              "state": "idle",
              "inFlight": 0,
              "callsServed": 12,
              "idleSec": 42,
              "command": "node",
              "args": ["trawl.js"],
              "cwd": "/tmp/trawl",
              "envKeys": [],
              "hash": "1.4.2",
              "tools": 4,
              "toolNames": ["search", "range", "read", "digest"],
              "indexedAt": "2026-08-30T10:00:00Z",
              "projects": [],
              "warm": false,
              "disabled": false,
              "placard": null,
              "pendingChange": null,
              "auth": { "supported": true, "authorized": true },
              "usage": { "calls": 12, "errors": 2, "projects": {} }
            }
          ]
        }
        """;

    private async Task ServeAsync(CancellationToken stopping)
    {
        while (!stopping.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = await _listener.GetContextAsync().WaitAsync(stopping);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception)
            {
                return;
            }

            RequestCount++;
            LastPath = context.Request.Url?.AbsolutePath;
            var authorization = context.Request.Headers["Authorization"];
            if (authorization is not null)
            {
                var parts = authorization.Split(' ', 2);
                LastAuthorizationScheme = parts[0];
                LastAuthorizationParameter = parts.Length > 1 ? parts[1] : null;
            }

            var (body, status) = _responses.GetValueOrDefault(
                LastPath ?? string.Empty,
                (string.Empty, HttpStatusCode.NotFound));
            var bytes = Encoding.UTF8.GetBytes(body);
            context.Response.StatusCode = (int)status;
            context.Response.ContentType = "application/json";
            await context.Response.OutputStream.WriteAsync(bytes, stopping);
            context.Response.Close();
        }
    }

    public void Dispose()
    {
        _stopping.Cancel();
        try
        {
            _listener.Close();
        }
        catch (ObjectDisposedException)
        {
        }
    }
}
