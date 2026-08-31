using System.Text.Json.Serialization;

namespace MCPRouter.Checks.Model;

/// <summary>Which kind of subject a stored run belongs to.</summary>
public enum CheckSubjectKind
{
    Server = 0,
}

/// <summary>
/// Which subject a stored run belongs to, keyed by kind and id — the Mac's shape, kept so a
/// future skill subject (whose id is its resolved path) cannot collide with a server of the same
/// name in the store.
/// </summary>
public sealed record SubjectKey(
    [property: JsonPropertyName("kind")] CheckSubjectKind Kind,
    [property: JsonPropertyName("id")] string Id)
{
    public static SubjectKey Server(string name) => new(CheckSubjectKind.Server, name);

    /// <summary>The store's key spelling: "server:name".</summary>
    public string StoreKey => $"{KindString}:{Id}";

    /// <summary>The JSON enum word, matching the Mac's raw value so the file shape is shared.</summary>
    public string KindString => Kind switch
    {
        CheckSubjectKind.Server => "server",
        _ => throw new ArgumentOutOfRangeException(nameof(Kind), Kind, "no word for this subject kind"),
    };
}

/// <summary>
/// A fingerprint a result can be stamped against.
///
/// Failable on purpose, and this is the whole of the "no result without a version" rule: a
/// subject with no live stamp has no stamp to hand the store, so the refusal is a type rather
/// than a rule a caller has to remember.
///
/// A server's stamp is the router's own config-identity digest of the entry as declared —
/// <c>upstreamHash</c>, 16 hex characters of sha256 over the command, args, cwd and env names for
/// stdio, or the transport, URL and header names otherwise (src/config.ts). It moves when the user
/// edits the entry and at no other time; an upstream that silently changes its tools does not
/// move it. That is what it is good for: stamping evidence about a declared server, so a stored
/// run can say it was gathered before the entry was edited.
/// </summary>
public sealed record Stamp(string Value)
{
    /// <summary>Nil for anything blank — the failable half of "no result without a version".</summary>
    public static Stamp? ForServer(ServerRecord server)
    {
        if (string.IsNullOrWhiteSpace(server.Hash))
        {
            return null;
        }

        return new Stamp(server.Hash);
    }
}

/// <summary>
/// One run of a subject's checks, as stored.
///
/// The stamp travels with the results rather than beside them, so two runs against different
/// versions are visibly different evidence and can never be merged into one history row. The
/// verdict words on disk are the observation vocabulary (<see cref="CheckVerdictWords"/>).
/// </summary>
public sealed record StoredRun(
    [property: JsonPropertyName("stamp")] string Stamp,
    [property: JsonPropertyName("ranAt")] DateTimeOffset RanAt,
    [property: JsonPropertyName("results")] IReadOnlyList<StoredResult> Results)
{
    /// <summary>The typed stamp, for comparisons against a live one.</summary>
    [JsonIgnore]
    public Checks.Model.Stamp StampValue => new(Stamp);
}

/// <summary>One check's outcome as persisted — the same shape the Mac writes.</summary>
public sealed record StoredResult(
    [property: JsonPropertyName("check")] string Check,
    [property: JsonPropertyName("verdict")] string Verdict,
    [property: JsonPropertyName("reason")] string? Reason)
{
    public CheckId CheckId => ParseCheck(Check);
    public CheckVerdict VerdictValue => ParseVerdict(Verdict);

    public static StoredResult From(CheckResult result) => new(
        CheckIdWords.For(result.Check),
        CheckVerdictWords.Disk(result.Verdict),
        result.Reason);

    public CheckResult ToResult() => new(CheckId, VerdictValue, Reason);

    internal static CheckId ParseCheck(string raw) => raw switch
    {
        "indexes" => CheckId.Indexes,
        "declaresTools" => CheckId.DeclaresTools,
        "authorized" => CheckId.Authorized,
        "surfaceApproved" => CheckId.SurfaceApproved,
        "operative" => CheckId.Operative,
        "callsSucceed" => CheckId.CallsSucceed,
        _ => throw new FormatException($"no such check on disk: '{raw}'"),
    };

    internal static CheckVerdict ParseVerdict(string raw) => raw switch
    {
        "confirmed" => CheckVerdict.Passed,
        "notMet" => CheckVerdict.Failed,
        "notObserved" => CheckVerdict.Unknown,
        "notApplicable" => CheckVerdict.NotApplicable,
        _ => throw new FormatException($"no such verdict on disk: '{raw}'"),
    };
}
