using System.Text.Json;
using System.Text.RegularExpressions;

namespace MCPRouter.Shell.Live;

/// <summary>
/// One tool call, as the router wrote it down. The wire type, verbatim against
/// <c>UsageRecord</c> in <c>src/usage.ts</c>.
///
/// Two fields this type carries are the reason the Windows board differs from the Mac's:
/// <see cref="Client"/> is the harness's executable name - the only attribution the wire
/// offers, and the group key the harness column and its tallies are built from - and on
/// Windows <see cref="Cwd"/> and <see cref="Project"/> are always absent, because WIN17
/// measured that a foreign process's working directory is not readable here. Nothing is
/// guessed to fill that gap; the board draws no project anything.
/// </summary>
public sealed partial record CallRecord(
    string Ts,
    string Server,
    string Tool,
    bool Ok,
    int Ms,
    bool Cold,
    int? Pid = null,
    string? Cwd = null,
    string? Project = null,
    string? Client = null,
    string? Err = null)
{
    /// <summary>
    /// Identity for de-duplication. The live stream and the <c>GET /usage</c> backfill overlap
    /// by construction - a call made between the fetch and the subscription arrives on both -
    /// and a log that shows one call twice is a log nobody can count from. The Mac board's
    /// key, carried unchanged.
    /// </summary>
    public string Id => $"{Ts}|{Server}|{Tool}|{Pid ?? 0}";

    /// <summary>The name the harness actually called, as it would be pasted into a terminal.</summary>
    public string NamespacedTool => $"{Server}__{Tool}";

    /// <summary>
    /// The result word the board draws, classified from what the wire actually carries.
    ///
    /// <see cref="CallResultKind.Timeout"/> is decided from the error text because that is the
    /// only place the wire says it: the router reports a timed-out upstream as any other
    /// failure, with the timeout named in <c>err</c>. <see cref="CallResultKind.Held"/> is
    /// produced by nothing on this wire - the router holds tool-surface changes for review,
    /// never calls - and the classification keeps the case anyway so the board's vocabulary
    /// and the design of record's stay one set (spec-WIN5 §3.2).
    /// </summary>
    public CallResultKind ResultKind
    {
        get
        {
            if (Ok) return CallResultKind.Ok;
            return Err is not null && TimeoutPattern().IsMatch(Err)
                ? CallResultKind.Timeout
                : CallResultKind.Failed;
        }
    }

    /// <summary>
    /// What a timeout looks like in the SDK's own error strings. Deliberately two patterns -
    /// "timed out" for a hung transport and "timeout" for a configured deadline - and
    /// deliberately nothing wider, so an ordinary failure is never promoted to a timeout.
    /// </summary>
    [GeneratedRegex("timed out|timeout", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex TimeoutPattern();
}

/// <summary>Which word the board writes in the Result column.</summary>
public enum CallResultKind
{
    Ok,
    Timeout,
    Failed,
    Held,
}

/// <summary>The <c>GET /usage</c> backfill: the counting window's opening and the newest-first tail.</summary>
public sealed record UsageSnapshot(string Since, IReadOnlyList<CallRecord> Records)
{
    /// <summary>How much of the router's tail to ask for. Matches the router's own ring of 500
    /// (<c>RING_SIZE</c> in <c>src/usage.ts</c>) exactly, so the backfill is the whole of what
    /// the router has and the live half tops up to the same bound rather than growing without
    /// limit.</summary>
    public const int Limit = 500;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public static UsageSnapshot Decode(string json)
    {
        var decoded = JsonSerializer.Deserialize<UsageSnapshot>(json, JsonOptions)
            ?? throw new JsonException("the usage response decoded to nothing");
        return decoded;
    }
}
