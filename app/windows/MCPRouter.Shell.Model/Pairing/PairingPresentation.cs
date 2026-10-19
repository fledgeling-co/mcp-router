using System;

namespace MCPRouter.Shell.Model.Pairing;

public static class PairingPresentation
{
    public const string Title = "Pair iPhone";
    public const string Lede = "On your phone: Conduit → Settings → Pair PC, then scan this.";
    public const string Warning = "Treat this code like a password. Anyone who scans it can put items in your inbox until it expires.";
    public const string TypeInsteadDetail = "Can't scan? Type those eight characters into your phone instead — it is the same pairing.";
    public const string DoneAction = "Done";

    public const string ExpiredHeadline = "This code has expired.";
    public const string Preparing = "Asking the router for a code…";
    public const string NewCodeAction = "New code";
    public const string RetryAction = "Try again";
    public const string PairingOffHeadline = "Pairing is turned off on this router";
    public const string PairingOffAdvice = "There is no code to show while it is off. Your servers are unchanged.";

    public const string SecretStorageNote = "Pairing secrets are securely stored in Windows Credential Manager and never logged or written to disk in plaintext.";

    /// <summary>The code in the two groups of four the phone is typed from, as the Mac draws it.</summary>
    public static string Formatted(string canonical) => $"{canonical[..4]}-{canonical[4..]}";

    /// <summary>The one line under the code: the countdown while a code is live, and the state otherwise.</summary>
    public static string StatusLine(PairingSessionState state) => state.Phase switch
    {
        PairingPhase.AwaitingScanOrCode => ExpiresIn(state.RemainingTime),
        PairingPhase.Expired => ExpiredHeadline,
        PairingPhase.Preparing => Preparing,
        _ => "",
    };

    /// <summary>The unavailable headline: the router's own wording when it refused, otherwise the pairing-off copy.</summary>
    public static string UnavailableHeadline(PairingSessionState state) =>
        state.Failure?.Headline ?? PairingOffHeadline;

    /// <summary>The unavailable advice, in the same two-source order as <see cref="UnavailableHeadline"/>.</summary>
    public static string UnavailableAdvice(PairingSessionState state) =>
        state.Failure?.Advice ?? PairingOffAdvice;

    public static string ExpiresIn(TimeSpan remaining)
    {
        return $"expires in {remaining.Minutes}:{remaining.Seconds:D2}";
    }

    public static string RefusalMessage(PairingRefusalReason reason)
    {
        return reason switch
        {
            PairingRefusalReason.NotRecognised => "That code is not the one on screen. Check the eight characters and try again.",
            PairingRefusalReason.Expired => "That code has expired. A new one is on screen.",
            PairingRefusalReason.AlreadyUsed => "That code has already paired a device. Each one works once.",
            PairingRefusalReason.UnsupportedVersion => "That phone speaks an incompatible pairing protocol version.",
            PairingRefusalReason.Declined => "You dismissed that request. Nothing was paired.",
            PairingRefusalReason.FirewallBlocked => "Windows Defender Firewall blocked the pairing port. Allow MCP Router through Windows Firewall to pair.",
            _ => "Pairing could not be completed."
        };
    }
}
