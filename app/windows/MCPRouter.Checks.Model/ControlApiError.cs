namespace MCPRouter.Checks.Model;

/// <summary>
/// Everything that can go wrong talking to the router, and the sentences the board says about
/// each. Ported from the Mac's <c>ControlAPIError</c>, whose headline strings are the one wording
/// per state across platforms (DESIGN.md §6).
///
/// It is an exception, because the natural shape of a failed call is throw — and it is built
/// through the named builders below rather than a public constructor, so every instance is fresh
/// (a thrown exception singleton carries a mutable stack trace from its first throw) and no call
/// site constructs a Kind the vocabulary cannot render.
///
/// <see cref="ControlErrorKind.RouterNotRunning"/> is a distinct case rather than one more
/// transport failure, because the design treats it as a first-class state with its own surface:
/// the router is loopback, so "unreachable" does not mean the network is down — it means the
/// daemon is not running on this machine. A client that folds this into a generic connection
/// error cannot draw that state, and the user gets "something went wrong" for a condition with
/// one obvious fix.
/// </summary>
public sealed class ControlApiError : Exception
{
    public enum ControlErrorKind
    {
        RouterNotRunning,
        Unauthorized,
        MalformedResponse,
        Server,
        Transport,
    }

    public ControlErrorKind Kind { get; }

    /// <summary>The router's own words where it sent any — the status, message and hint of a
    /// refused call, or the parse failure of an unreadable body.</summary>
    public string? Detail { get; }

    private ControlApiError(ControlErrorKind kind, string? detail, Exception? inner)
        : base(inner is null ? null : inner.Message, inner)
    {
        Kind = kind;
        Detail = detail;
    }

    public static ControlApiError RouterNotRunning() => new(ControlErrorKind.RouterNotRunning, null, null);
    public static ControlApiError Unauthorized() => new(ControlErrorKind.Unauthorized, null, null);

    public static ControlApiError Malformed(string detail) => new(ControlErrorKind.MalformedResponse, detail, null);

    public static ControlApiError ServerError(int status, string message, string? hint) =>
        new(ControlErrorKind.Server, $"{status}: {message}{(string.IsNullOrEmpty(hint) ? string.Empty : $" — {hint}")}", null);

    public static ControlApiError Transport(string detail) => new(ControlErrorKind.Transport, detail, null);

    /// <summary>What happened. The Mac's wording, verbatim — one name per state.</summary>
    public string Headline => Kind switch
    {
        ControlErrorKind.RouterNotRunning => CheckCopy.RouterNotRunningHeadline,
        ControlErrorKind.Unauthorized => "This app isn't authorised to talk to the router",
        ControlErrorKind.MalformedResponse => "The router sent a response this version doesn't understand",
        ControlErrorKind.Server => "The router couldn't complete that",
        ControlErrorKind.Transport => "Couldn't reach the router",
        _ => throw new ArgumentOutOfRangeException(nameof(Kind), Kind, "no headline for this error"),
    };

    /// <summary>What to do about it. Never blames the user, never emotes, always says what is
    /// safe.</summary>
    public string Advice => Kind switch
    {
        ControlErrorKind.RouterNotRunning => CheckCopy.RouterNotRunningAdvice,
        ControlErrorKind.Unauthorized =>
            "The control token was rotated or removed. Authorize this app to the router to continue — "
            + "your servers and their history are untouched.",
        ControlErrorKind.MalformedResponse => $"The router may be newer or older than this app ({Detail}).",
        ControlErrorKind.Server => $"The router returned {Detail}.",
        ControlErrorKind.Transport => $"The request did not complete ({Detail}).",
        _ => throw new ArgumentOutOfRangeException(nameof(Kind), Kind, "no advice for this error"),
    };

    /// <summary>The one-line form, for a place too small for a pane — composed from the same two
    /// strings the pane renders, so there is no second wording to keep in step.</summary>
    public string UserFacingDescription => $"{Headline}. {Advice}";
}
