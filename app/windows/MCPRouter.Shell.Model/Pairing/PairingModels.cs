using System;

namespace MCPRouter.Shell.Model.Pairing;

public enum PairingPhase
{
    Preparing,
    AwaitingScanOrCode,
    Paired,
    Expired,
    Failed
}

public enum PairingRefusalReason
{
    NotRecognised,
    Expired,
    AlreadyUsed,
    UnsupportedVersion,
    Declined,
    FirewallBlocked
}

public sealed record PairingSessionState(
    PairingPhase Phase,
    string PairingCode,
    TimeSpan RemainingTime,
    string? PairedDeviceName = null,
    PairingRefusalReason? Refusal = null
);
