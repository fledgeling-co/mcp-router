using System.Net;
using System.Text;
using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The client against a real HTTP listener on loopback — the actual boundary, not a mock: real
/// requests, real status codes, real bodies. The fixture bodies are what src/control.ts writes
/// on each path.
/// </summary>
public sealed class RegistryClientTests : IDisposable
{
    private readonly HttpListener _listener;
    private readonly string _url;

    public RegistryClientTests()
    {
        var port = TcpPortFree();
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        _listener.Start();
        _url = $"http://127.0.0.1:{port}";
    }

    public void Dispose()
    {
        try { _listener.Stop(); } catch (ObjectDisposedException) { }
        _listener.Close();
    }

    private static int TcpPortFree()
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

    /// <summary>Answers one request with the given status and body, then stops the task.</summary>
    private Task<HttpListenerRequest> AnswerOnceAsync(int status, string body, Action<HttpListenerRequest>? inspect = null)
    {
        var contextTask = _listener.GetContextAsync();
        return Task.Run(async () =>
        {
            var context = await contextTask;
            inspect?.Invoke(context.Request);
            var bytes = Encoding.UTF8.GetBytes(body);
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes);
            context.Response.Close();
            return context.Request;
        });
    }

    // ----------------------------------------------------------------- search

    [Fact]
    public async Task SearchHitsTheRegistryRouteWithTheQuery()
    {
        // The request object is disposed when the response closes, so the values are copied
        // inside the answer callback rather than read after the await.
        string? path = null, query = null, limit = null;
        var answer = AnswerOnceAsync(200, """{"results":[],"sources":{"official":0,"smithery":0,"merged":0},"warnings":[]}""", r =>
        {
            path = r.Url!.AbsolutePath;
            query = r.QueryString["q"];
            limit = r.QueryString["limit"];
        });
        using var client = new RegistryClient(_url);

        var result = await client.SearchAsync("postgres", 30);

        await answer;
        Assert.True(result.Ok);
        Assert.Equal("/registry/search", path);
        Assert.Equal("postgres", query);
        Assert.Equal("30", limit);
    }

    [Fact]
    public async Task SearchParsesRowsAndTheInstalledFlag()
    {
        _ = AnswerOnceAsync(200, """
            {"results":[{"id":"smithery:@o/t","name":"@o/t","displayName":"t","description":"","source":"smithery","useCount":12,"installed":true}],
             "sources":{"official":0,"smithery":1,"merged":1},"warnings":[]}
            """);
        using var client = new RegistryClient(_url);

        var result = await client.SearchAsync("");
        var row = Assert.Single(result.Response!.Results);
        Assert.Equal(12, row.UseCount);
        Assert.True(row.Installed);
    }

    [Fact]
    public async Task SearchReadsServerErrorBodies()
    {
        // The 502 path: the router caught an exception reaching an index and reported it.
        _ = AnswerOnceAsync(502, """{"error":"official registry unreachable: HTTP 503"}""");
        using var client = new RegistryClient(_url);

        var result = await client.SearchAsync("");
        Assert.False(result.Ok);
        Assert.Equal(RegistryClient.SearchFailureKind.RouterError, result.Failure!.Kind);
        Assert.Equal("502", result.Failure.RouterStatus);
        Assert.Contains("official registry unreachable", result.Failure.Detail);
    }

    [Fact]
    public async Task SearchOnNothingListeningIsRouterUnreachable()
    {
        // A port with no listener: the board's disconnected state, really exercised.
        var deadPort = TcpPortFree();
        using var client = new RegistryClient($"http://127.0.0.1:{deadPort}");

        var result = await client.SearchAsync("");
        Assert.False(result.Ok);
        Assert.Equal(RegistryClient.SearchFailureKind.RouterUnreachable, result.Failure!.Kind);
    }

    [Fact]
    public async Task SearchOnGarbageBytesIsMalformed()
    {
        _ = AnswerOnceAsync(200, "<html>not json</html>");
        using var client = new RegistryClient(_url);

        var result = await client.SearchAsync("");
        Assert.Equal(RegistryClient.SearchFailureKind.MalformedResponse, result.Failure!.Kind);
    }

    // ----------------------------------------------------------------- add

    private static readonly NewServer Declaration = new()
    {
        Name = "io.github/owner/thing",
        Command = "npx",
        Args = ["-y", "@owner/thing"],
        Env = new Dictionary<string, string> { ["API_KEY"] = "sk-123" },
    };

    [Fact]
    public async Task AddSendsTokenHeaderJsonBodyAndContentType()
    {
        string? authorization = null, contentType = null, body = null;
        _listener.AuthenticationSchemes = AuthenticationSchemes.Anonymous;
        var answer = Task.Run(async () =>
        {
            var context = await _listener.GetContextAsync();
            authorization = context.Request.Headers["Authorization"];
            contentType = context.Request.ContentType;
            body = await new System.IO.StreamReader(context.Request.InputStream, Encoding.UTF8).ReadToEndAsync();
            var bytes = Encoding.UTF8.GetBytes("""{"added":"io.github/owner/thing","tools":4,"error":null,"needsAuth":false}""");
            context.Response.StatusCode = 201;
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes);
            context.Response.Close();
        });
        using var client = new RegistryClient(_url, tokenReader: () => "test-token");

        var result = await client.AddAsync(Declaration);
        await answer;

        Assert.True(result.Ok);
        Assert.Equal("io.github/owner/thing", result.AddedName);
        // The header arrives as one "Bearer <token>" string, read exactly as the router reads it.
        Assert.Equal("Bearer test-token", authorization);
        Assert.Equal("application/json", contentType!.Split(';')[0]);
        Assert.Contains("\"name\":\"io.github/owner/thing\"", body);
        Assert.Contains("\"command\":\"npx\"", body);
        Assert.Contains("\"API_KEY\":\"sk-123\"", body);
    }

    [Fact]
    public async Task AddWithoutATokenNeverTouchesTheWire()
    {
        using var client = new RegistryClient(_url, tokenReader: () => null);

        var result = await client.AddAsync(Declaration);
        Assert.False(result.Ok);
        Assert.Equal(RegistryClient.AddFailureKind.NoToken, result.Failure!.Kind);
        Assert.True(_listener.IsListening); // and nothing raced in to answer a request
    }

    [Fact]
    public async Task AddOn409ReadsAsAlreadyDeclared()
    {
        _ = AnswerOnceAsync(409, """{"error":"a server named \"io.github/owner/thing\" already exists"}""");
        using var client = new RegistryClient(_url, tokenReader: () => "t");

        var result = await client.AddAsync(Declaration);
        Assert.Equal(RegistryClient.AddFailureKind.AlreadyDeclared, result.Failure!.Kind);
        Assert.Contains("already exists", result.Failure.RouterMessage);
    }

    [Fact]
    public async Task AddOn422CarriesTheRouterMessageAndNeverForces()
    {
        // The router's first-index failure: surfaced, not pushed past. The force query parameter
        // the router offers is not sent by this client at all.
        string? query = null;
        _ = AnswerOnceAsync(422, """{"error":"connect ECONNREFUSED 127.0.0.1:9999"}""", r => query = r.Url!.Query);
        using var client = new RegistryClient(_url, tokenReader: () => "t");

        var result = await client.AddAsync(Declaration);
        Assert.Equal(RegistryClient.AddFailureKind.IndexFailed, result.Failure!.Kind);
        Assert.Contains("ECONNREFUSED", result.Failure.RouterMessage);
        Assert.DoesNotContain("force", query, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task AddOn401ReadsAsUnauthorized()
    {
        _ = AnswerOnceAsync(401, """{"error":"unauthorized"}""");
        using var client = new RegistryClient(_url, tokenReader: () => "wrong");

        var result = await client.AddAsync(Declaration);
        Assert.Equal(RegistryClient.AddFailureKind.Unauthorized, result.Failure!.Kind);
    }

    [Fact]
    public async Task AddOnNothingListeningIsRouterUnreachable()
    {
        var deadPort = TcpPortFree();
        using var client = new RegistryClient($"http://127.0.0.1:{deadPort}", tokenReader: () => "t");

        var result = await client.AddAsync(Declaration);
        Assert.Equal(RegistryClient.AddFailureKind.RouterUnreachable, result.Failure!.Kind);
    }

    // ----------------------------------------------------------------- the token path

    [Fact]
    public void TokenReadingToleratesAMissingOrEmptyFile()
    {
        Assert.Null(RegistryClient.ReadToken(null));
        Assert.Null(RegistryClient.ReadToken(Path.Combine(Path.GetTempPath(), "no-such-token-file-here")));
        var empty = Path.Combine(Path.GetTempPath(), $"empty-token-{Guid.NewGuid():N}");
        File.WriteAllText(empty, "");
        try { Assert.Null(RegistryClient.ReadToken(empty)); }
        finally { File.Delete(empty); }
    }

    [Fact]
    public void TokenReadingTrimsButNeverLogs()
    {
        var path = Path.Combine(Path.GetTempPath(), $"token-{Guid.NewGuid():N}");
        File.WriteAllText(path, "  abc123  \n");
        try { Assert.Equal("abc123", RegistryClient.ReadToken(path)); }
        finally { File.Delete(path); }
    }
}
