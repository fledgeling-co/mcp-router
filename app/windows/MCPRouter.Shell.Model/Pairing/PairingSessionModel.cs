using System;

namespace MCPRouter.Shell.Model.Pairing;

public sealed class PairingSessionModel
{
    public PairingSessionState CurrentState { get; private set; }

    public PairingSessionModel()
    {
        CurrentState = new PairingSessionState(
            PairingPhase.AwaitingScanOrCode,
            "K7X9-W4M2",
            TimeSpan.FromMinutes(5),
            null,
            null
        );
    }

    public void CompletePairing(string deviceName)
    {
        CurrentState = new PairingSessionState(
            PairingPhase.Paired,
            CurrentState.PairingCode,
            CurrentState.RemainingTime,
            deviceName,
            null
        );
    }

    public void FailPairing(PairingRefusalReason reason)
    {
        CurrentState = new PairingSessionState(
            PairingPhase.Failed,
            CurrentState.PairingCode,
            CurrentState.RemainingTime,
            null,
            reason
        );
    }
}
