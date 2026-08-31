using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// The real client for the router's registry boundary.
///
/// Reads are unauthenticated — the router gates only mutating control paths with the token
/// (<c>src/control.ts:464</c>), and this client asks for no more permission than the route it
/// calls. Writes send the control token as a bearer header over loopback; the token exists in
/// memory for the life of one request and is never logged, printed, or persisted here.
///
/// Every refusal is a typed result rather than an exception carrying the router's free-text body:
/// the body is written for a developer and can quote whatever a third-party index returned, so it
/// is captured as data for surfaces that choose to show it, and the typed kind is what surfaces
/// switch on.
/// </summary>
public sealed class RegistryClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly Func<string?> _tokenReader;

    public RegistryClient(string? baseUrl = null, Func<string?>? tokenReader = null, HttpClient? http = null)
    {
        _http = http ?? new HttpClient();
        _baseUrl = (baseUrl ?? ControlEndpoint.BaseUrl()).TrimEnd('/');
        _tokenReader = tokenReader ?? (() => ReadToken(ControlEndpoint.ControlTokenPath()));
    }

    public string BaseUrl => _baseUrl;

    public static string? ReadToken(string? path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        try
        {
            var token = File.ReadAllText(path).Trim();
            return token.Length == 0 ? null : token;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return null;
        }
    }

    // ----------------------------------------------------------------- search

    public sealed record SearchResult(RegistrySearchResponse? Response, SearchFailure? Failure)
    {
        public bool Ok => Response is not null;
    }

    public sealed record SearchFailure(SearchFailureKind Kind, string? RouterStatus, string? Detail);

    public enum SearchFailureKind
    {
        /// <summary>The router is not running or refused the connection — its own surface state.</summary>
        RouterUnreachable,
        /// <summary>The router answered and refused the request.</summary>
        Unauthorized,
        /// <summary>The router answered with an error (its proxy status and message are captured).</summary>
        RouterError,
        /// <summary>The router answered with something this client cannot parse.</summary>
        MalformedResponse,
    }

    public async Task<SearchResult> SearchAsync(string query, int limit = 60, CancellationToken cancellationToken = default)
    {
        var url = $"{_baseUrl}/registry/search?q={Uri.EscapeDataString(query)}&limit={limit}";
        try
        {
            using var response = await _http.GetAsync(url, cancellationToken);
            if ((int)response.StatusCode == 401 || (int)response.StatusCode == 403)
            {
                return new SearchResult(null, new SearchFailure(SearchFailureKind.Unauthorized, ((int)response.StatusCode).ToString(), null));
            }

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(cancellationToken);
                return new SearchResult(null, new SearchFailure(
                    SearchFailureKind.RouterError,
                    ((int)response.StatusCode).ToString(),
                    body.Length > 0 ? body : null));
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            var parsed = await JsonSchema.ParseAsync(stream, cancellationToken);
            return new SearchResult(parsed, null);
        }
        catch (HttpRequestException)
        {
            return new SearchResult(null, new SearchFailure(SearchFailureKind.RouterUnreachable, null, null));
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // A timeout, not a user cancellation: the request deadline elapsed.
            return new SearchResult(null, new SearchFailure(SearchFailureKind.RouterUnreachable, null, null));
        }
        catch (JsonException)
        {
            return new SearchResult(null, new SearchFailure(SearchFailureKind.MalformedResponse, null, null));
        }
    }

    // ----------------------------------------------------------------- add

    public sealed record AddResult(string? AddedName, AddFailure? Failure)
    {
        public bool Ok => Failure is null;
    }

    public sealed record AddFailure(AddFailureKind Kind, string? RouterMessage, bool NeedsAuth);

    public enum AddFailureKind
    {
        /// <summary>No control token on disk — the router has never run, or its home moved.</summary>
        NoToken,
        /// <summary>The router refused the token.</summary>
        Unauthorized,
        /// <summary>A server with this name is already declared (HTTP 409).</summary>
        AlreadyDeclared,
        /// <summary>The entry reached the router and its first index failed (HTTP 422). The
        /// router's message is carried for the surface to draw; this client never sends
        /// <c>force</c> to push past it.</summary>
        IndexFailed,
        /// <summary>The declaration was malformed (HTTP 400).</summary>
        Invalid,
        /// <summary>The router could not be reached at all.</summary>
        RouterUnreachable,
    }

    public async Task<AddResult> AddAsync(NewServer declaration, CancellationToken cancellationToken = default)
    {
        var token = _tokenReader();
        if (string.IsNullOrEmpty(token))
        {
            return new AddResult(null, new AddFailure(AddFailureKind.NoToken, null, NeedsAuth: false));
        }

        var url = $"{_baseUrl}/servers";
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(declaration, JsonSchema.Options), Encoding.UTF8, "application/json"),
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            using var response = await _http.SendAsync(request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var message = ReadError(body);

            return (int)response.StatusCode switch
            {
                201 or 200 => new AddResult(ReadAddedName(body), null),
                401 or 403 => new AddResult(null, new AddFailure(AddFailureKind.Unauthorized, message, NeedsAuth: false)),
                409 => new AddResult(null, new AddFailure(AddFailureKind.AlreadyDeclared, message, NeedsAuth: false)),
                422 => new AddResult(null, new AddFailure(AddFailureKind.IndexFailed, message, NeedsAuth: ReadNeedsAuth(body))),
                400 => new AddResult(null, new AddFailure(AddFailureKind.Invalid, message, NeedsAuth: false)),
                _ => new AddResult(null, new AddFailure(AddFailureKind.IndexFailed, message ?? $"HTTP {(int)response.StatusCode}", NeedsAuth: false)),
            };
        }
        catch (HttpRequestException)
        {
            return new AddResult(null, new AddFailure(AddFailureKind.RouterUnreachable, null, NeedsAuth: false));
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new AddResult(null, new AddFailure(AddFailureKind.RouterUnreachable, null, NeedsAuth: false));
        }
    }

    private static string? ReadError(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.String
                ? error.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? ReadAddedName(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("added", out var added)
                && added.ValueKind == JsonValueKind.String
                ? added.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static bool ReadNeedsAuth(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("needsAuth", out var needsAuth)
                && needsAuth.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public void Dispose() => _http.Dispose();

    // ----------------------------------------------------------------- the wire schema

    public static class JsonSchema
    {
        public static readonly JsonSerializerOptions Options = new()
        {
            // The wire is camelCase ("useCount", "displayName", "iconUrl") — the router serves
            // TypeScript field names verbatim, so the policy must match the wire exactly.
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
        };

        public static async Task<RegistrySearchResponse> ParseAsync(Stream stream, CancellationToken token) =>
            await JsonSerializer.DeserializeAsync<RegistrySearchResponse>(stream, Options, token)
            ?? new RegistrySearchResponse();
    }
}
