namespace MCPRouter.Checks.Model;

/// <summary>
/// The checks MCP Router can genuinely perform against a declared server, as a closed set.
///
/// A closed enum rather than a list of strings, for the reason the Mac's <c>CheckID</c> is one:
/// a seventh check cannot be added without every exhaustive switch failing to compile until it
/// is given a statement and a reason.
///
/// The five skill checks are deliberately absent. Their only input is <c>GET /skills</c>, and the
/// router this product installs serves no such route (spec-WIN8 §3.2) — porting them would be a
/// closed set of questions with no way to gather a single answer. They arrive with the endpoint.
/// </summary>
public enum CheckId
{
    /// <summary>The router can start it and read its tool surface.</summary>
    Indexes,

    /// <summary>It offers at least one tool.</summary>
    DeclaresTools,

    /// <summary>Its credentials are current.</summary>
    Authorized,

    /// <summary>No tool description is waiting for review.</summary>
    SurfaceApproved,

    /// <summary>It carries no placard.</summary>
    Operative,

    /// <summary>Its calls come back without error.</summary>
    CallsSucceed,
}

/// <summary>Stable wire/disk spelling of a check, shared with the Mac's raw values.</summary>
public static class CheckIdWords
{
    public static string For(CheckId check) => check switch
    {
        CheckId.Indexes => "indexes",
        CheckId.DeclaresTools => "declaresTools",
        CheckId.Authorized => "authorized",
        CheckId.SurfaceApproved => "surfaceApproved",
        CheckId.Operative => "operative",
        CheckId.CallsSucceed => "callsSucceed",
        _ => throw new ArgumentOutOfRangeException(nameof(check), check, "no word for this check"),
    };
}
