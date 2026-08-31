using MCPRouter.Shell.Model.Skills;

namespace MCPRouter.Shell.Model.Control;

/// <summary>
/// Why a skills read failed, and what the board says about it - the Windows port of the Mac's
/// <c>ControlAPIError</c>, carrying the same five cases and the same user copy, because DESIGN.md
/// §6 asks for one wording per state across both devices.
///
/// <see cref="RouterNotRunning"/> is a distinct case rather than one more transport failure,
/// because the router is loopback: a connect failure is not a network fault, it is "the router is
/// not running", and that is the condition the user actually has and can actually fix.
/// </summary>
public abstract record SkillsControlError
{
    /// <summary>Nothing is listening on the control port, or the router has never run (no token file).</summary>
    public sealed record RouterNotRunning : SkillsControlError;

    /// <summary>The control token was missing, wrong, or has been rotated.</summary>
    public sealed record Unauthorized : SkillsControlError;

    /// <summary>The router answered with an error status and a message, plus its own hint where it sent one.</summary>
    public sealed record Server(int Status, string Message, string? Hint) : SkillsControlError;

    /// <summary>
    /// The response could not be understood - including the <b>expected</b> case on today's
    /// router: a 404 from a daemon that predates the skills routes. The Mac's
    /// <c>skillsRead</c> maps that 404 here rather than to <see cref="Server"/>, because "the
    /// router couldn't complete that" is the wrong sentence for version skew.
    /// </summary>
    public sealed record MalformedResponse(string Detail) : SkillsControlError;

    /// <summary>The request did not complete for a reason that is not "not running".</summary>
    public sealed record Transport(string Detail) : SkillsControlError;

    /// <summary>The pane title for this condition - the Mac's headlines, verbatim.</summary>
    public string Headline => this switch
    {
        RouterNotRunning => "The router isn't running",
        Unauthorized => "This app isn't authorised to talk to the router",
        MalformedResponse => "The router sent a response this version doesn't understand",
        Server => "The router couldn't complete that",
        Transport => "Couldn't reach the router",
        _ => "Couldn't reach the router",
    };

    /// <summary>What to do about it. Never blames the user, never emotes, and always says what is safe.</summary>
    public string Advice => this switch
    {
        RouterNotRunning =>
            "Nothing is listening on the control port, so there is nothing to show yet. Starting "
            + "it takes a moment and your servers stay exactly as you left them.",
        Unauthorized =>
            "The control token was rotated or removed. Re-pair to continue - your servers and "
            + "their history are untouched.",
        MalformedResponse detail =>
            $"The router may be newer or older than this app ({detail.Detail}).",
        Server server => string.IsNullOrEmpty(server.Hint)
            ? $"The router returned {server.Status} - {server.Message}."
            : $"The router returned {server.Status} - {server.Message}. {server.Hint}",
        Transport transport => $"The request did not complete ({transport.Detail}).",
        _ => "",
    };

    /// <summary>Composed from the same two strings the pane renders, so there is no second wording to keep in step.</summary>
    public string UserFacingDescription => $"{Headline}. {Advice}";
}

/// <summary>
/// What the Windows client may ask the router for on the Skills board: two reads, no writes. The
/// narrowness is the point - the board is read-only (spec-WIN6 §2.2), so the boundary that would
/// carry a write does not exist yet to be called by mistake.
/// </summary>
public interface ISkillsControlClient
{
    Task<SkillsResponse> SkillsAsync(CancellationToken cancellationToken = default);

    Task<MarketplacesResponse> MarketplacesAsync(CancellationToken cancellationToken = default);
}
