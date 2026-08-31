using System.Text.Json.Serialization;

namespace MCPRouter.Checks.Model;

/// <summary>
/// One server as the control API's <c>GET /servers</c> describes it — the fields
/// <c>describe()</c> in src/control.ts serves, transcribed. Only the fields the checks and the
/// board read are typed; the rest pass through unmodelled rather than being invented.
///
/// Note what never appears here: env and header <b>values</b>. The endpoint serves key names only,
/// so nothing secret can cross this boundary (fleet rule 4 is structural here, not a discipline).
/// </summary>
public sealed record ServerRecord
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("transport")]
    public string Transport { get; init; } = string.Empty;

    [JsonPropertyName("state")]
    public string State { get; init; } = string.Empty;

    [JsonPropertyName("hash")]
    public string? Hash { get; init; }

    [JsonPropertyName("tools")]
    public int Tools { get; init; }

    [JsonPropertyName("indexedAt")]
    public string? IndexedAt { get; init; }

    [JsonPropertyName("indexError")]
    public string? IndexError { get; init; }

    [JsonPropertyName("placard")]
    public PlacardRecord? Placard { get; init; }

    [JsonPropertyName("pendingChange")]
    public PendingChangeRecord? PendingChange { get; init; }

    [JsonPropertyName("auth")]
    public AuthRecord Auth { get; init; } = new();

    [JsonPropertyName("usage")]
    public UsageRecord Usage { get; init; } = new();
}

/// <summary>Why a server is inoperative, and what stands in for it meanwhile.</summary>
public sealed record PlacardRecord(
    [property: JsonPropertyName("reason")] string Reason,
    [property: JsonPropertyName("substitute")] string? Substitute,
    [property: JsonPropertyName("until")] string? Until);

/// <summary>A tool-description change the router has seen and is holding for review.</summary>
public sealed record PendingChangeRecord(
    [property: JsonPropertyName("seenAt")] string SeenAt,
    [property: JsonPropertyName("count")] int Count);

/// <summary>The authorization facts for one server, as served.</summary>
public sealed record AuthRecord
{
    [JsonPropertyName("supported")]
    public bool Supported { get; init; }

    [JsonPropertyName("authorized")]
    public bool Authorized { get; init; }
}

/// <summary>The recorded call window for one server. This is what <c>POST /usage/reset</c> clears
/// and what every sentence about calls is scoped to.</summary>
public sealed record UsageRecord
{
    [JsonPropertyName("calls")]
    public int Calls { get; init; }

    [JsonPropertyName("errors")]
    public int Errors { get; init; }
}

/// <summary>The <c>GET /servers</c> envelope.</summary>
public sealed record ServersResponse
{
    [JsonPropertyName("port")]
    public int Port { get; init; }

    [JsonPropertyName("servers")]
    public IReadOnlyList<ServerRecord> Servers { get; init; } = Array.Empty<ServerRecord>();
}
