using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace MCPRouter.Checks.Model;

/// <summary>What the board needs from the router. The seam the fakes stand behind in the gates —
/// one read for the whole server list, one read for skills, one write for a server's re-index.
/// Nothing else crosses this boundary, so nothing else can become a second channel.</summary>
public interface IChecksControlClient
{
    Task<ServersResponse> ServersAsync(CancellationToken cancellation = default);
    Task<SkillsRead> SkillsAsync(CancellationToken cancellation = default);
    Task ReindexAsync(string serverName, CancellationToken cancellation = default);
}

/// <summary>The outcome of the skills read. The router this product installs serves no
/// <c>/skills</c> route, so absence-with-a-reason is a first-class outcome here, not an
/// exception: the board draws what arrived and what did not (DESIGN.md §5's Partial row) instead
/// of failing a surface whose server half loaded fine.</summary>
public sealed record SkillsRead(IReadOnlyList<string> AbsentReason);

/// <summary>
/// The real read/write path to the router's loopback control API.
///
/// Loopback only, default port 8879; the first successful <c>/servers</c> answer carries
/// <c>port</c> and it is adopted, so the address is the port the router actually answered on
/// (the Mac's LoopbackAddress rule) rather than a constant that can go stale.
///
/// Reads need no token — the control API authenticates only mutations. The one write this board
/// triggers, reindex, sends the bearer token from the router's own <c>control.token</c> file. The
/// token is read into the request header and nowhere else: never logged, never persisted, never
/// echoed into an exception message (fleet rule 4).
/// </summary>
public sealed class ControlClient : IChecksControlClient, IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
    };

    private readonly HttpClient _http;
    private readonly Func<string?> _readToken;
    private readonly object _portGate = new();
    private int _port;

    /// <summary>The loopback port the router last answered on — 8879 until a router says
    /// otherwise.</summary>
    public int Port
    {
        get
        {
            lock (_portGate)
            {
                return _port == 0 ? DefaultPort : _port;
            }
        }
    }

    public const int DefaultPort = 8879;

    public ControlClient(Func<string?>? tokenReader = null, int initialPort = DefaultPort)
        : this(new HttpClient(), tokenReader, initialPort)
    {
    }

    public ControlClient(HttpClient http, Func<string?>? tokenReader = null, int initialPort = DefaultPort)
    {
        _http = http;
        _readToken = tokenReader ?? ReadRouterToken;
        _port = initialPort;
    }

    /// <summary>The router's control-token path, beside its config. The file's contents are the
    /// secret; the path is not.</summary>
    public static string TokenPath =>
        Path.Combine(
            Environment.GetEnvironmentVariable("MCP_ROUTER_HOME")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "mcp-router"),
            "control.token");

    private static string? ReadRouterToken()
    {
        try
        {
            var path = TokenPath;
            return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private Uri BaseUri(int port) => new($"http://127.0.0.1:{port}/");

    public async Task<ServersResponse> ServersAsync(CancellationToken cancellation = default)
    {
        var (response, port) = await GetAsync("servers", Port, cancellation).ConfigureAwait(false);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            throw ControlApiError.ServerError(404, "no /servers endpoint", null);
        }

        ServersResponse servers;
        try
        {
            servers = await response.Content
                .ReadFromJsonAsync<ServersResponse>(JsonOptions, cancellation)
                .ConfigureAwait(false)
                ?? throw ControlApiError.Malformed("the body decoded to nothing");
        }
        catch (JsonException error)
        {
            throw ControlApiError.Malformed(error.Message);
        }

        AdoptPort(servers.Port != 0 ? servers.Port : port);
        return servers;
    }

    public async Task<SkillsRead> SkillsAsync(CancellationToken cancellation = default)
    {
        var (response, _) = await GetAsync("skills", Port, cancellation).ConfigureAwait(false);
        if (response.IsSuccessStatusCode)
        {
            // A router that serves skills will one day answer here with the skills envelope; this
            // build reads none of its fields, so a success is recorded as an unread shape rather
            // than parsed badly — until the five skill checks port with the endpoint (§3.2).
            throw ControlApiError.Malformed("a /skills answer arrived that this build does not yet read");
        }

        return new SkillsRead([$"the router answered {(int)response.StatusCode} for /skills"]);
    }

    public async Task ReindexAsync(string serverName, CancellationToken cancellation = default)
    {
        var token = _readToken();
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(BaseUri(Port), $"servers/{Uri.EscapeDataString(serverName)}/reindex"));
        if (string.IsNullOrEmpty(token))
        {
            // The mutation half of the API answers 401 without it, and that is the state the board
            // reports — this client never invents a credential.
            throw ControlApiError.Unauthorized();
        }

        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request, cancellation).ConfigureAwait(false);
        }
        catch (HttpRequestException error)
        {
            throw Classify(error, $"POST /servers/{serverName}/reindex");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                var (message, hint) = await ReadErrorBodyAsync(response, cancellation).ConfigureAwait(false);
                throw response.StatusCode == System.Net.HttpStatusCode.Unauthorized
                    ? ControlApiError.Unauthorized()
                    : ControlApiError.ServerError((int)response.StatusCode, message, hint);
            }
        }
    }

    private async Task<(HttpResponseMessage Response, int Port)> GetAsync(string path, int port, CancellationToken cancellation)
    {
        var uri = new Uri(BaseUri(port), path);
        HttpResponseMessage response;
        try
        {
            response = await _http.GetAsync(uri, cancellation).ConfigureAwait(false);
        }
        catch (HttpRequestException error)
        {
            throw Classify(error, $"GET /{path}");
        }

        return (response, port);
    }

    private static ControlApiError Classify(HttpRequestException error, string what)
    {
        // A refused loopback connection is the router not running — a named state with its own
        // surface, not a generic failure. Everything else stays transport.
        for (var inner = error.InnerException; inner is not null; inner = inner.InnerException)
        {
            if (inner is System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.ConnectionRefused })
            {
                return ControlApiError.RouterNotRunning();
            }
        }

        return ControlApiError.Transport($"{what}: {error.Message}");
    }

    private static async Task<(string Message, string? Hint)> ReadErrorBodyAsync(HttpResponseMessage response, CancellationToken cancellation)
    {
        try
        {
            var body = await response.Content.ReadFromJsonAsync<ErrorBody>(JsonOptions, cancellation).ConfigureAwait(false);
            return (body?.Error ?? response.ReasonPhrase ?? "error", body?.Hint);
        }
        catch (JsonException)
        {
            return (response.ReasonPhrase ?? "error", null);
        }
    }

    private void AdoptPort(int port)
    {
        lock (_portGate)
        {
            _port = port;
        }
    }

    private sealed record ErrorBody(string? Error, string? Hint);

    public void Dispose() => _http.Dispose();
}
