using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The wire doubles the pairing tests share. Each is a real <see cref="HttpMessageHandler"/>
/// handed to the shipping <see cref="ControlApiClient"/>, so the class under test is the one that
/// ships, and every request it sends is recorded for the assertions.
/// </summary>
internal static class PairingHttp
{
    /// <summary>A test constant. The assertions check that it reaches the wire and never reaches an exception.</summary>
    public const string Token = "test-token-PAIRING-not-a-secret-just-a-marker";

    /// <summary>The recorded body the router answered <c>POST /pairing/codes</c> with.</summary>
    public static string Fixture => RepoRoot.Read("app/Sources/MCPRouterKit/Control/Fixtures/pairing-code.json");

    /// <summary>
    /// The code, issue instant and expiry the recorded issue body carries. Read from the recording rather than typed
    /// in, so a re-record moves the clock and the expected code together.
    /// </summary>
    public static (string Code, DateTimeOffset IssuedAt, DateTimeOffset ExpiresAt) RecordedIssue()
    {
        var body = JsonDocument.Parse(Fixture).RootElement;
        return (
            body.GetProperty("code").GetString()!,
            DateTimeOffset.Parse(body.GetProperty("issuedAt").GetString()!),
            DateTimeOffset.Parse(body.GetProperty("expiresAt").GetString()!));
    }

    /// <summary>The recorded body the router answered <c>GET /pairing/state</c> with, while its phone listener was bound.</summary>
    public static string StateFixture
    {
        get
        {
            var state = System.Text.Json.Nodes.JsonNode.Parse(RepoRoot.Read("app/Sources/MCPRouterKit/Control/Fixtures/pairing-state.json"))!;
            state["listener"]!["host"] = "router-test.local";
            state["listener"]!["fingerprint"] = new string('a', 64);
            state["confirmedPhones"] = new System.Text.Json.Nodes.JsonArray();
            return state.ToJsonString();
        }
    }

    /// <summary>The state the router answers while pairing is off: nothing bound, nothing announced, no code.</summary>
    public const string StateOff = "{\"code\":null,\"awaitingAck\":[],\"listener\":{\"enabled\":false,\"port\":null,\"advertising\":false}}";

    public static HttpResponseMessage Json(HttpStatusCode status, string body) => new(status)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json"),
    };

    public static Task<HttpResponseMessage> Answer(HttpStatusCode status, string body) =>
        Task.FromResult(Json(status, body));

    /// <summary>What the socket layer raises when nothing is listening on the control port.</summary>
    public static Task<HttpResponseMessage> Refused() =>
        Task.FromException<HttpResponseMessage>(
            new HttpRequestException("connection refused", new SocketException((int)SocketError.ConnectionRefused)));

    public static ControlApiClient Client(HttpMessageHandler handler) =>
        new(tokenProvider: () => Token, handler: handler);

    /// <summary>One request as it left the client.</summary>
    public sealed record Seen(string Method, string Path, string? Authorization, string? ContentType, string Body);

    /// <summary>
    /// The router the sheet talks to. The state read is answered from <paramref name="listening"/>, and every
    /// other request goes to <paramref name="respond"/> with a count over those requests only, so a script
    /// reads the same whether or not the state was read first.
    /// </summary>
    public static Scripted Sheet(Func<int, HttpRequestMessage, Task<HttpResponseMessage>> respond, bool listening = true)
    {
        var answered = 0;
        return new Scripted((_, request) =>
            IsStateRead(request)
                ? Answer(HttpStatusCode.OK, listening ? StateFixture : StateOff)
                : respond(answered++, request));
    }

    private static bool IsStateRead(HttpRequestMessage request) =>
        request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/pairing/state";

    /// <summary>Answers each request from a script, and records it. The script sees the request and the
    /// zero-based index of the call, so a test can answer the first call late and the second at once.</summary>
    public sealed class Scripted(Func<int, HttpRequestMessage, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        public List<Seen> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null
                ? ""
                : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new Seen(
                request.Method.Method,
                request.RequestUri!.PathAndQuery,
                request.Headers.Authorization?.ToString(),
                request.Content?.Headers.ContentType?.MediaType,
                body));
            return await respond(Requests.Count - 1, request);
        }
    }
}
