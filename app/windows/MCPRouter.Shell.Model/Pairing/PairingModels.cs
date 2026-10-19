using System;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Pairing;

public enum PairingPhase
{
    Preparing,
    AwaitingScanOrCode,
    Paired,
    Expired,
    Failed,
    Idle,
    Unavailable
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

/// <summary>One code as the router issued it. The instants are the router's own, so the countdown is
/// the router's window and not a constant this app assumed.</summary>
public sealed record IssuedPairingCode(string Code, DateTimeOffset IssuedAt, DateTimeOffset ExpiresAt);

/// <summary>
/// Whether the router's phone listener is bound. <see cref="Enabled"/> is the router's own answer about what
/// is bound, not what its config asked for, so a listener that failed to bind reads as off. <see cref="Port"/>
/// is null exactly when <see cref="Enabled"/> is false.
/// </summary>
public sealed record PairingListenerState(bool Enabled, int? Port, bool Advertising);

/// <summary>What <c>GET /pairing/state</c> says: the code a phone could still pair with, if any, and the listener.</summary>
public sealed record PairingState(IssuedPairingCode? Code, PairingListenerState Listener);

/// <summary>What the sheet shows. <see cref="Failure"/> is set only when the router refused or could
/// not be reached; a pairing that is off on this machine has no failure, only <see cref="PairingPhase.Unavailable"/>.</summary>
public sealed record PairingSessionState(
    PairingPhase Phase,
    string? PairingCode,
    TimeSpan RemainingTime,
    string? PairedDeviceName = null,
    PairingRefusalReason? Refusal = null,
    ControlApiException? Failure = null
);
