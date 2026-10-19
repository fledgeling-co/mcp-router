using System.Text.Json;
using System.Text.Json.Serialization;

namespace MCPRouter.Shell.Model.Servers;

/// <summary>
/// The wire shapes the loopback control API speaks, transcribed from the Swift client's
/// <c>Models.swift</c> and <c>Describe.swift</c> — the same shapes, held to the same strictness.
///
/// <para><b>Strictness follows the router, not convenience.</b> <see cref="ServerRow.Disabled"/>,
/// <see cref="ServerRow.Warm"/>, <see cref="ServerRow.Auth"/> and <see cref="ServerRow.Usage"/>
/// are <c>required</c>: the router reports them for every server, and the Swift model's own
/// comment on <c>disabled</c> is why — defaulting a missing key to <c>false</c> would draw a
/// disabled server as live, which is the exact class of claim DESIGN.md §6 forbids. A response
/// that omits one of these fails the decode and the board renders
/// <see cref="ControlApiException"/> as a malformed response rather than a guess.</para>
///
/// <para>One deliberate collapse, recorded: the Swift model distinguishes <c>cwd</c> absent from
/// <c>cwd</c> null, because the reference emits them differently. Both collapse to a null here —
/// nothing on this board draws <c>cwd</c>, and the distinction is the inspector's business.</para>
/// </summary>
public sealed record ServersEnvelope
{
    public required int Port { get; init; }
    public required int IdleMs { get; init; }
    public required string Since { get; init; }

    [JsonPropertyName("pendingAuth")]
    public PendingAuth? PendingAuth { get; init; }

    public required IReadOnlyList<ServerRow> Servers { get; init; }
}

/// <summary>An OAuth flow the router already has open, if any. Absent most of the time.</summary>
public sealed record PendingAuth
{
    public required string Server { get; init; }
    public required string Url { get; init; }
}

/// <summary>Why a server is inoperative, and what stands in for it meanwhile.</summary>
public sealed record Placard
{
    public required string Reason { get; init; }
    public string? Substitute { get; init; }
    public string? Until { get; init; }
}

/// <summary>A tool-description change the router has seen and is holding for review.</summary>
public sealed record PendingChange
{
    public required string SeenAt { get; init; }
    public required int Count { get; init; }
}

/// <summary>The authorization a server supports, as the router reports it.</summary>
public sealed record ServerAuth
{
    public required bool Supported { get; init; }
    public required bool Authorized { get; init; }
    [JsonPropertyName("authorizedAt")]
    public string? AuthorizedAt { get; init; }
    [JsonPropertyName("pendingUrl")]
    public string? PendingUrl { get; init; }
    [JsonPropertyName("rejected")]
    public string? Rejected { get; init; }
}

/// <summary>Per-server usage totals since the router's summary window opened.</summary>
public sealed record ServerUsage
{
    public required int Calls { get; init; }
    public required int Errors { get; init; }
    [JsonPropertyName("firstSeen")]
    public string? FirstSeen { get; init; }
    [JsonPropertyName("lastUsed")]
    public string? LastUsed { get; init; }
    public IReadOnlyDictionary<string, int>? Projects { get; init; }
}

/// <summary>
/// One server as the router describes it. The member order below is the wire's, for reading
/// order if nothing else; the decoder is keyed, not positional.
/// </summary>
public sealed record ServerRow
{
    public required string Name { get; init; }
    [JsonConverter(typeof(ServerTransportWire))]
    public required string Transport { get; init; }
    /// <summary>The pool's lifecycle word. A value outside that set fails the decode — the set
    /// is closed on the wire, so it is closed here, as the Swift model's own doc comment
    /// requires.</summary>
    [JsonConverter(typeof(ServerStateWire))]
    public required string State { get; init; }
    public required int InFlight { get; init; }
    public required int CallsServed { get; init; }
    public required int IdleSec { get; init; }
    public string? Command { get; init; }
    public IReadOnlyList<string>? Args { get; init; }
    public string? Cwd { get; init; }
    public string? Url { get; init; }
    [JsonPropertyName("envKeys")]
    public IReadOnlyList<string>? EnvKeys { get; init; }
    [JsonPropertyName("headerKeys")]
    public IReadOnlyList<string>? HeaderKeys { get; init; }
    public string? Hash { get; init; }
    public required int Tools { get; init; }
    [JsonPropertyName("toolNames")]
    public required IReadOnlyList<string> ToolNames { get; init; }
    [JsonPropertyName("indexedAt")]
    public string? IndexedAt { get; init; }
    [JsonPropertyName("indexError")]
    public string? IndexError { get; init; }
    public required IReadOnlyList<string> Projects { get; init; }
    public required bool Warm { get; init; }
    /// <summary>Required, per the Swift model's comment on this exact member: a response that
    /// omits it is a router to refuse, not one to assume is fine.</summary>
    public required bool Disabled { get; init; }
    public Placard? Placard { get; init; }
    [JsonPropertyName("pendingChange")]
    public PendingChange? PendingChange { get; init; }
    public required ServerAuth Auth { get; init; }
    public required ServerUsage Usage { get; init; }

    public bool IsStdio => Transport == "stdio";
    public bool IsRunning => State == "running";
}

// MARK: - GET /harnesses (M22's route)

public sealed record HarnessesEnvelope
{
    public required int Port { get; init; }
    public required string Scope { get; init; }
    /// <summary>When the files were read. The board's staleness clock — the reading carries when
    /// it was taken rather than leaving the surface to assume it is now.</summary>
    [JsonPropertyName("readAt")]
    public required string ReadAt { get; init; }
    public required IReadOnlyList<HarnessRow> Harnesses { get; init; }
}

/// <summary>
/// One harness, compared against the router's own upstreams. <see cref="Unreadable"/> is the
/// member a consumer reads first: when it is non-null, every other member is the *empty* report
/// rather than a measurement — <c>state</c> reads <c>not-wired</c> and counts read 0, the same
/// bytes a clean unwired harness produces. That collision is exactly why the member exists.
/// </summary>
public sealed record HarnessRow
{
    public required string Harness { get; init; }
    [JsonPropertyName("displayName")]
    public required string DisplayName { get; init; }
    public required string Path { get; init; }
    public required bool Exists { get; init; }
    public string? Unreadable { get; init; }
    /// <summary><c>not-wired</c>, <c>wired-http</c>, <c>wired-shim</c>,
    /// <c>wired-with-duplicates</c>. Closed on the wire, closed here.</summary>
    [JsonConverter(typeof(HarnessStateWire))]
    public required string State { get; init; }
    /// <summary><c>none</c>, <c>http</c>, <c>stdio-shim</c>. Closed on the wire, closed here.</summary>
    [JsonConverter(typeof(HarnessRouteWire))]
    public required string Route { get; init; }
    public string? Bridge { get; init; }
    public required int Entries { get; init; }
    [JsonPropertyName("duplicateCount")]
    public required int DuplicateCount { get; init; }
    [JsonPropertyName("httpCapability")]
    public required string HttpCapability { get; init; }
    public required string Capability { get; init; }
}

// MARK: - Write paths

/// <summary>The envelope the router puts every refusal in. <see cref="Hint"/> carries the
/// router's own advice where it sends one — the sentence that turns a dead end into a next
/// step, and the only thing that turns "Add it anyway" on.</summary>
public sealed record RouterErrorBody
{
    public required string Error { get; init; }
    public string? Hint { get; init; }
}

/// <summary>The body of <c>POST /servers</c> — declaring a new server. The only request shape
/// here that carries a command line, deliberately separate from any patch shape so no future
/// edit can widen a patch into an installer.</summary>
public sealed record NewServerBody
{
    public required string Name { get; init; }
    public string? Command { get; init; }
    public IReadOnlyList<string>? Args { get; init; }
    public string? Url { get; init; }
}

/// <summary>The 201 reply: <c>error</c> is present with <c>needsAuth</c> when the server was
/// adopted anyway because an OAuth upstream is expected to refuse its first connection.</summary>
public sealed record AddedServer
{
    public required string Added { get; init; }
    public required int Tools { get; init; }
    public string? Error { get; init; }
    [JsonPropertyName("needsAuth")]
    public bool? NeedsAuth { get; init; }
}

/// <summary>The response from <c>GET /servers/:name/changes</c>.</summary>
public sealed record HeldChanges
{
    public required string Server { get; init; }
    public required bool Pending { get; init; }
    [JsonPropertyName("seenAt")]
    public string? SeenAt { get; init; }
    public required IReadOnlyList<ToolChange> Changes { get; init; }
}

/// <summary>What changed in one tool between the approved surface and the pending one.</summary>
public sealed record ToolChange
{
    /// <summary><c>added</c>, <c>removed</c>, <c>changed</c>. Closed on the wire, closed here.</summary>
    public required string Kind { get; init; }
    public required string Name { get; init; }
    public ToolShape? Before { get; init; }
    public ToolShape? After { get; init; }
    /// <summary>Codepoints that render as nothing but that a model still reads — the router
    /// names them rather than silently keeping them, and so does this surface.</summary>
    public IReadOnlyList<string>? Invisible { get; init; }
}

/// <summary>One side of a tool's shape — what it described itself as, and its input schema.</summary>
public sealed record ToolShape
{
    public string? Description { get; init; }
    public string? Schema { get; init; }
}

/// <summary>Decoding options shared by every reader. Exact property names — the wire is keyed,
/// and a client that matches case-insensitively would accept a router that drifted.</summary>
public static class ServersWire
{
    public static JsonSerializerOptions Options { get; } = new()
    {
        PropertyNameCaseInsensitive = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        ReadCommentHandling = JsonCommentHandling.Disallow,
    };
}

/// <summary>A string member whose set of values is closed on the wire. An unrecognised value
/// fails the decode rather than being silently treated as a neighbour of itself — the rule the
/// Swift model states for <c>ServerTransport</c> and <c>ServerState</c> both.</summary>
public abstract class ClosedSetWire : JsonConverter<string>
{
    private readonly string[] _values;

    protected ClosedSetWire(params string[] values) => _values = values;

    public override string Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        return value is not null && _values.Contains(value)
            ? value
            : throw new JsonException($"\"{value}\" is not a value this client understands");
    }

    public override void Write(Utf8JsonWriter writer, string value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value);
}

public sealed class ServerStateWire : ClosedSetWire
{
    public ServerStateWire() : base("idle", "starting", "running", "stopping") { }
}

public sealed class ServerTransportWire : ClosedSetWire
{
    public ServerTransportWire() : base("stdio", "http", "sse") { }
}

public sealed class HarnessStateWire : ClosedSetWire
{
    public HarnessStateWire() : base("not-wired", "wired-http", "wired-shim", "wired-with-duplicates") { }
}

public sealed class HarnessRouteWire : ClosedSetWire
{
    public HarnessRouteWire() : base("none", "http", "stdio-shim") { }
}
