using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text.Json;

namespace MCPRouter.Shell.Model.Servers;

/// <summary>Everything that can go wrong talking to the router.</summary>
public enum ControlApiFailure
{
    /// <summary>Nothing is listening on the loopback control port.</summary>
    RouterNotRunning,

    /// <summary>The control token was missing, wrong, or has been rotated.</summary>
    Unauthorized,

    /// <summary>The router answered, but not with something this version understands.</summary>
    MalformedResponse,

    /// <summary>The router answered with an error status and a message.</summary>
    Server,

    /// <summary>The request did not complete.</summary>
    Transport,
}

/// <summary>
/// Everything that can go wrong talking to the router, carrying the one wording each state owns.
///
/// <para><see cref="RouterNotRunning"/> is a distinct case rather than one more transport
/// failure, because the design treats it as a first-class state with its own surface: the router
/// is loopback, so "unreachable" does not mean the network is down — it means the daemon is not
/// running on this machine, and the honest response is to say so and offer to start it.</para>
///
/// <para>The strings below are ported verbatim from the Swift client's
/// <c>ControlAPIError</c> because DESIGN.md §6 asks for <b>one</b> wording per state across
/// devices; a paraphrased sentence here would be the two-wordings failure that rule exists to
/// prevent. spec-WIN4 §4 holds this wording to itself, so rewording either file alone turns a
/// gate red.</para>
/// </summary>
public sealed class ControlApiException : Exception
{
    public ControlApiFailure Kind { get; }

    /// <summary>The status the router answered with, for the <see cref="ControlApiFailure.Server"/> case.</summary>
    public int? Status { get; }

    /// <summary>The router's own advice where it sent one — the field that turns a dead end into
    /// a next step. Never synthesized from a status code.</summary>
    public string? Hint { get; }

    /// <summary>The pane headline for this condition.</summary>
    public string Headline => Kind switch
    {
        ControlApiFailure.RouterNotRunning => "The router isn't running",
        ControlApiFailure.Unauthorized => "This app isn't authorised to talk to the router",
        ControlApiFailure.MalformedResponse => "The router sent a response this version doesn't understand",
        ControlApiFailure.Server => "The router couldn't complete that",
        ControlApiFailure.Transport => "Couldn't reach the router",
        _ => "Couldn't reach the router",
    };

    /// <summary>What to do about it. Never blames the user, never emotes, and always says what is safe.</summary>
    public string Advice => Kind switch
    {
        ControlApiFailure.RouterNotRunning =>
            "Nothing is listening on the control port, so there is nothing to show yet. " +
            "Starting it takes a moment and your servers stay exactly as you left them.",
        ControlApiFailure.Unauthorized =>
            "The control token was rotated or removed. Re-pair to continue — " +
            "your servers and their history are untouched.",
        ControlApiFailure.MalformedResponse =>
            $"The router may be newer or older than this app ({Detail}).",
        ControlApiFailure.Server when !string.IsNullOrEmpty(Hint) =>
            $"The router returned {Status} — {Detail}. {Hint}",
        ControlApiFailure.Server =>
            $"The router returned {Status} — {Detail}.",
        ControlApiFailure.Transport =>
            $"The request did not complete ({Detail}).",
        _ => $"The request did not complete ({Detail}).",
    };

    /// <summary>The label of the one action that fixes this, where there is one. Verb-first, per §6.</summary>
    public string? ActionLabel => Kind switch
    {
        ControlApiFailure.RouterNotRunning => "Start the router",
        ControlApiFailure.Unauthorized => "Re-pair…",
        _ => null,
    };

    /// <summary>The one-line form, for a place too small for a pane — composed from the same two
    /// strings the pane renders rather than written separately.</summary>
    public string UserFacingDescription => $"{Headline}. {Advice}";

    /// <summary>The raw message behind a server or transport failure. Never carries the token.</summary>
    public string Detail { get; }

    public ControlApiException(ControlApiFailure kind, string detail, int? status = null, string? hint = null)
        : base(detail)
    {
        Kind = kind;
        Detail = detail;
        Status = status;
        Hint = hint;
    }
}

/// <summary>
/// Where the router keeps its state on this machine — the same resolution the router itself
/// performs, so a client that reads the token reads the one the running router minted.
/// </summary>
public static class RouterHome
{
    public static string Root =>
        Environment.GetEnvironmentVariable("MCP_ROUTER_HOME") is { Length: > 0 } override_
            ? override_
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "mcp-router");

    public static string TokenPath => Path.Combine(Root, "control.token");
}

/// <summary>
/// The one boundary between this board and the router.
///
/// <para>Real loopback HTTP: GET is ungated exactly as the router gates it, except GET /harnesses,
/// which the router gates and which therefore carries the token; every mutating call
/// reads the bearer token from <see cref="RouterHome.TokenPath"/> at call time and sends it as
/// <c>Authorization: Bearer …</c> with a JSON content type — the pair the router's gate requires,
/// and the reason a web page cannot forge a write. <b>The token is never logged, never echoed and
/// never embedded in an exception message</b>; a test holds that to this class.</para>
///
/// <para>The base address and the token source are constructor seams, so the tests exercise this
/// class for real through an injected <see cref="HttpMessageHandler"/> rather than through a
/// stub of it.</para>
/// </summary>
public sealed class ControlApiClient : IDisposable
{
    private const string DefaultBase = "http://127.0.0.1:8879/";

    private readonly HttpClient _http;
    private readonly Func<string> _readToken;

    public ControlApiClient(
        Uri? baseAddress = null,
        Func<string>? tokenProvider = null,
        HttpMessageHandler? handler = null)
    {
        _http = new HttpClient(handler ?? new HttpClientHandler())
        {
            BaseAddress = baseAddress ?? new Uri(DefaultBase),
            Timeout = TimeSpan.FromSeconds(3),
        };
        _readToken = tokenProvider ?? ReadRouterToken;
    }

    private static string ReadRouterToken()
    {
        try
        {
            return File.ReadAllText(RouterHome.TokenPath).Trim();
        }
        catch (IOException)
        {
            // A missing or unreadable token is not a reason to refuse the call: most GETs are ungated,
            // and a call the router cannot authenticate answers 401 on its own terms.
            return "";
        }
    }

    // ------------------------------------------------------------------ reads

    public async Task<ServersEnvelope> GetServersAsync(CancellationToken cancellation = default)
    {
        using var response = await SendAsync(HttpMethod.Get, "servers", write: false, cancellation);
        return await DecodeAsync<ServersEnvelope>(response, cancellation);
    }

    public async Task<HarnessesEnvelope> GetHarnessesAsync(CancellationToken cancellation = default)
    {
        // The router gates this one read behind the control token (src/control.ts), unlike the GETs
        // above, so it carries the token the way a write does.
        using var response = await SendAsync(HttpMethod.Get, "harnesses", write: false, cancellation, gated: true);
        return await DecodeAsync<HarnessesEnvelope>(response, cancellation);
    }

    public async Task<HeldChanges> GetChangesAsync(string serverName, CancellationToken cancellation = default)
    {
        using var response = await SendAsync(HttpMethod.Get, $"servers/{Uri.EscapeDataString(serverName)}/changes", write: false, cancellation);
        return await DecodeAsync<HeldChanges>(response, cancellation);
    }

    // ------------------------------------------------------------------ writes

    public async Task<AddedServer> AddServerAsync(NewServerBody body, bool force = false, CancellationToken cancellation = default)
    {
        var path = force ? "servers?force=1" : "servers";
        using var response = await SendAsync(
            HttpMethod.Post, path, write: true, cancellation,
            content: JsonContent.Create(body, options: ServersWire.Options));
        return await DecodeAsync<AddedServer>(response, cancellation);
    }

    /// <summary>
    /// Remove a server from the router's list. The one destructive verb this client speaks.
    /// </summary>
    /// <remarks>
    /// DEF-102. The router deletes the entry from <c>servers.json</c>, reloads, tells every
    /// attached session the tool list changed, clears any stored authorization, and - unless
    /// <c>?keepHistory=1</c> - forgets the server's usage history (src/control.ts, the DELETE
    /// branch of <c>/servers/{name}</c>). None of that is undoable from this app, which is why the
    /// board asks first and why "Confirm before removing a server" is a setting rather than a
    /// hardcoded prompt.
    ///
    /// History is KEPT. A confirmation the user gave to removing a server is not consent to
    /// discarding months of call counts, and the two decisions are not offered together anywhere
    /// in this build; taking the narrower one is the only reading that does not assume an answer
    /// nobody was asked for.
    /// </remarks>
    public async Task RemoveServerAsync(string name, CancellationToken cancellation = default)
    {
        using var response = await SendAsync(
            HttpMethod.Delete,
            $"servers/{Uri.EscapeDataString(name)}?keepHistory=1",
            write: true,
            cancellation);
    }

    // ------------------------------------------------------------------ the one send

    private async Task<HttpResponseMessage> SendAsync(
        HttpMethod method, string path, bool write, CancellationToken cancellation, HttpContent? content = null, bool gated = false)
    {
        using var request = new HttpRequestMessage(method, path);
        if (content is not null) request.Content = content;

        if (write || gated)
        {
            // Read at call time, not at construction: a router that rotates its token between
            // this app starting and the user acting is answered with the token it minted last.
            var token = _readToken();
            if (token.Length > 0) request.Headers.Add("Authorization", $"Bearer {token}");
        }

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request, cancellation);
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        {
            throw new ControlApiException(ControlApiFailure.Transport, "the request timed out");
        }
        catch (HttpRequestException ex) when (ex.InnerException is SocketException { SocketErrorCode: SocketError.ConnectionRefused })
        {
            // Loopback refused is not "the network is down" — it is the daemon not running, and
            // the board renders it as that state with its own surface.
            throw new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");
        }
        catch (HttpRequestException ex)
        {
            throw new ControlApiException(ControlApiFailure.Transport, ex.Message);
        }

        if (!response.IsSuccessStatusCode)
        {
            var (message, hint) = await ReadErrorBodyAsync(response, cancellation);
            throw message is null
                ? new ControlApiException(
                    ControlApiFailure.Transport,
                    $"the router answered HTTP {(int)response.StatusCode} with an unreadable body",
                    (int)response.StatusCode)
                : new ControlApiException(
                    response.StatusCode == System.Net.HttpStatusCode.Unauthorized
                        ? ControlApiFailure.Unauthorized
                        : ControlApiFailure.Server,
                    message,
                    (int)response.StatusCode,
                    hint);
        }

        return response;
    }

    /// <summary>Decodes the router's refusal envelope. A body that does not decode is reported as
    /// a transport-shaped failure with the status — the status is real even when the prose is not.</summary>
    private static async Task<(string? Message, string? Hint)> ReadErrorBodyAsync(
        HttpResponseMessage response, CancellationToken cancellation)
    {
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(cancellation);
            var body = await JsonSerializer.DeserializeAsync<RouterErrorBody>(stream, ServersWire.Options, cancellation);
            return body is null ? (null, null) : (body.Error, body.Hint);
        }
        catch (JsonException)
        {
            return (null, null);
        }
    }

    private static async Task<T> DecodeAsync<T>(HttpResponseMessage response, CancellationToken cancellation)
        where T : class
    {
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(cancellation);
            var decoded = await JsonSerializer.DeserializeAsync<T>(stream, ServersWire.Options, cancellation);
            return decoded ?? throw new ControlApiException(
                ControlApiFailure.MalformedResponse, "the body decoded to nothing");
        }
        catch (JsonException ex)
        {
            throw new ControlApiException(ControlApiFailure.MalformedResponse, ex.Message);
        }
    }

    public void Dispose() => _http.Dispose();
}
