namespace MCPRouter.Checks.Model;

/// <summary>
/// The checks MCP Router can genuinely perform against a declared server or a skill, as a closed set.
///
/// A closed enum rather than a list of strings, for the reason the Mac's <c>CheckID</c> is one:
/// a new check cannot be added without every exhaustive switch failing to compile until it is given
/// a statement and a reason.
///
/// The first six are server checks, each a field the control API serves for a declared server. The
/// last five are skill checks, each a field <c>GET /skills</c> serves (<c>src/skills.ts</c>). A skill
/// is never executed by the router, so no check here reports how one behaved.
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

    /// <summary>At least one client can load it.</summary>
    Reachable,

    /// <summary>It carries a version a result can be stamped against.</summary>
    Versioned,

    /// <summary>Its marketplace still resolves where the router first saw it.</summary>
    OriginUnchanged,

    /// <summary>Any newer version held asks for nothing extra.</summary>
    UpdateWantsNoMore,

    /// <summary>Its <c>SKILL.md</c> declares a description an agent can route on.</summary>
    Described,
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
        CheckId.Reachable => "reachable",
        CheckId.Versioned => "versioned",
        CheckId.OriginUnchanged => "originUnchanged",
        CheckId.UpdateWantsNoMore => "updateWantsNoMore",
        CheckId.Described => "described",
        _ => throw new ArgumentOutOfRangeException(nameof(check), check, "no word for this check"),
    };
}
