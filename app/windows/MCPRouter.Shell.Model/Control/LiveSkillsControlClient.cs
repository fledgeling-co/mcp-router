using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using MCPRouter.Shell.Model.Skills;

namespace MCPRouter.Shell.Model.Control;

/// <summary>
/// Where the router's control-token file lives, and the one fact reading it is allowed to
/// conclude from its absence. The same file the router writes
/// (<c>src/control.ts</c>: <c>TOKEN_PATH</c>) and the Mac's <c>RouterTokenFile</c> reads, with the
/// same <c>MCP_ROUTER_HOME</c> override.
///
/// Absent is not an error here: it means the router has never run on this machine. The caller
/// turns that into "the router isn't running" - the condition the user actually has - rather
/// than into an authorization error, which would send them to re-pair something that was never
/// paired.
/// </summary>
public sealed class RouterTokenFile
{
    public static string DefaultHome =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude", "mcp-router");

    /// <summary>Named FilePath, not Path: System.IO.Path is in scope here and the collision is real.</summary>
    public string FilePath { get; }

    public RouterTokenFile(string? home = null)
    {
        var baseDirectory = home
            ?? Environment.GetEnvironmentVariable("MCP_ROUTER_HOME")
            ?? DefaultHome;
        FilePath = System.IO.Path.Combine(baseDirectory, "control.token");
    }

    /// <summary>The token, or null when the file is absent or empty. This type never logs the value.</summary>
    public string? Read()
    {
        try
        {
            var text = File.ReadAllText(FilePath).Trim();
            return text.Length == 0 ? null : text;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }
}

/// <summary>
/// The real read path: HTTP GETs against the router's control API on the loopback port.
///
/// The status mapping is the Mac's <c>LiveControlAPIClient+Absent.swift</c> rule, carried across
/// rather than reinvented: <b>404 is version skew, not failure</b>. Every other read treats a
/// non-2xx as "the router couldn't complete that"; for <c>/skills</c> and
/// <c>/marketplaces</c> a 404 is the answer from a router built before the route, and the
/// honest reading of it is "the router may be newer or older than this app".
///
/// <c>GET /skills</c> is token-gated on every method (<c>src/control.ts</c>), so each read sends the
/// router's control token when its file is present, read at call time so a rotated token is the one
/// sent. The token is never logged, and an absent file sends no header.
/// </summary>
public sealed class LiveSkillsControlClient : ISkillsControlClient
{
    public static Uri DefaultBaseUri { get; } = new("http://127.0.0.1:8879");

    private readonly HttpClient _http;
    private readonly RouterTokenFile? _tokenFile;
    private readonly bool _disposeHttpClient;

    public LiveSkillsControlClient(
        HttpClient? http = null,
        Uri? baseUri = null,
        RouterTokenFile? tokenFile = null)
    {
        // A handler the caller did not supply is this client's to dispose; one it did supply is
        // not, because the caller may be a test still holding it.
        _http = http ?? new HttpClient(new SocketsHttpHandler
        {
            ConnectTimeout = TimeSpan.FromSeconds(2),
        });
        _disposeHttpClient = http is null;
        _http.BaseAddress ??= baseUri ?? DefaultBaseUri;
        _tokenFile = tokenFile;
    }

    public async Task<SkillsResponse> SkillsAsync(CancellationToken cancellationToken = default) =>
        await ReadAsync<SkillsResponse>("skills", cancellationToken);

    public async Task<MarketplacesResponse> MarketplacesAsync(CancellationToken cancellationToken = default) =>
        await ReadAsync<MarketplacesResponse>("marketplaces", cancellationToken);

    public Task<ExtensionUpdatesResponse> ExtensionUpdatesAsync(CancellationToken cancellationToken = default) =>
        SendAsync<ExtensionUpdatesResponse>(HttpMethod.Get, "extensions/updates", null, cancellationToken);

    public Task<KeepAck> KeepHeldVersionAsync(string name, string pluginVersion, CancellationToken cancellationToken = default) =>
        SendAsync<KeepAck>(HttpMethod.Post, $"extensions/plugins/{Uri.EscapeDataString(name)}/keep", new { pluginVersion }, cancellationToken);

    public Task<PromotionAck> PromoteFromCacheAsync(string name, string pluginVersion, CancellationToken cancellationToken = default) =>
        SendAsync<PromotionAck>(HttpMethod.Post, $"extensions/plugins/{Uri.EscapeDataString(name)}/promote", new { source = "cache", pluginVersion }, cancellationToken);

    public Task<UndoAck> UndoPromotionAsync(string name, string restore, CancellationToken cancellationToken = default) =>
        SendAsync<UndoAck>(HttpMethod.Post, $"extensions/plugins/{Uri.EscapeDataString(name)}/undo-promote", new { restore }, cancellationToken);

    /// <summary>
    /// True when the router's token file is absent, which on a loopback install means the router
    /// has never run here. Reported as not-running rather than fetched-then-failed when it is
    /// already known - the same conclusion the Mac's client reaches from the same absence.
    /// </summary>
    public bool RouterHasNeverRun => _tokenFile is not null && _tokenFile.Read() is null;

    private Task<T> ReadAsync<T>(string path, CancellationToken cancellationToken) =>
        SendAsync<T>(HttpMethod.Get, path, null, cancellationToken, versionSkew: true);

    private async Task<T> SendAsync<T>(HttpMethod method, string path, object? body, CancellationToken cancellationToken, bool versionSkew = false)
    {
        HttpResponseMessage response;
        try
        {
            using var request = new HttpRequestMessage(method, path);
            if (body is not null) request.Content = JsonContent.Create(body);
            if (_tokenFile?.Read() is { } token)
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            }
            response = await _http.SendAsync(request, cancellationToken);
        }
        catch (HttpRequestException exception)
        {
            // A connect failure on the loopback port is "the router isn't running", not a
            // network fault - the case the error taxonomy exists to name.
            throw new SkillsControlError.RouterNotRunning().AsException(exception.Message);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new SkillsControlError.Transport("the request timed out").AsException(null);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                if ((int)response.StatusCode == 404 && versionSkew)
                {
                    throw new SkillsControlError.MalformedResponse(
                        $"this router has no /{path} endpoint").AsException(null);
                }

                if ((int)response.StatusCode == 401)
                {
                    throw new SkillsControlError.Unauthorized().AsException(null);
                }

                var (message, hint) = await ReadErrorBodyAsync(response, cancellationToken);
                throw new SkillsControlError.Server(
                    (int)response.StatusCode, message, hint).AsException(null);
            }

            try
            {
                var parsed = await response.Content
                    .ReadFromJsonAsync<T>(cancellationToken);
                return parsed ?? throw new SkillsControlError.MalformedResponse(
                    $"the /{path} response decoded to nothing").AsException(null);
            }
            catch (JsonException exception)
            {
                throw new SkillsControlError.MalformedResponse(
                    $"the /{path} response was not the shape this version reads "
                    + $"({exception.Message})").AsException(null);
            }
        }
    }

    /// <summary>
    /// The router's error body is <c>{"error": "...", "hint": "..."}</c> where it sends one; a
    /// body that is not that shape is not worth a second failure - the status line alone still
    /// names what happened.
    /// </summary>
    private static async Task<(string Message, string? Hint)> ReadErrorBodyAsync(
        HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            using var document = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
            var message = document.RootElement.TryGetProperty("error", out var error)
                ? error.GetString() ?? "the router sent no message"
                : "the router sent no message";
            var hint = document.RootElement.TryGetProperty("hint", out var hintElement)
                ? hintElement.GetString()
                : null;
            return (message, hint);
        }
        catch (JsonException)
        {
            return ("the router sent no readable error", null);
        }
    }
}

internal static class SkillsControlErrorExtensions
{
    /// <summary>
    /// C# has no thrown unions, so a typed error travels as an exception carrying itself. The
    /// board catches <see cref="SkillsControlException"/> and renders
    /// <see cref="SkillsControlException.Error"/> - the taxonomy stays data, never stringly.
    /// </summary>
    public static SkillsControlException AsException(
        this SkillsControlError error, string? detail) => new(error, detail);
}

/// <summary>The typed error, in exception clothing, for the one boundary that must cross an await.</summary>
public sealed class SkillsControlException : Exception
{
    public SkillsControlException(SkillsControlError error, string? transportDetail)
        : base(error.UserFacingDescription)
    {
        Error = error;
        TransportDetail = transportDetail;
    }

    public SkillsControlError Error { get; }

    /// <summary>The underlying exception's message, where there was one - never a token, never a URL with one.</summary>
    public string? TransportDetail { get; }
}
