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
    public const string PairingOffHeadline = "Pairing is turned off on this router";
    public const string PairingOffAdvice = "There is no code to show while it is off. Your servers are unchanged.";

    public const string SecretStorageNote = "Pairing secrets are securely stored in Windows Credential Manager and never logged or written to disk in plaintext.";

    public static string Formatted(string canonical) => throw new NotImplementedException();

    public static string StatusLine(PairingSessionState state) => throw new NotImplementedException();

    public static string UnavailableHeadline(PairingSessionState state) => throw new NotImplementedException();

    public static string UnavailableAdvice(PairingSessionState state) => throw new NotImplementedException();

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
