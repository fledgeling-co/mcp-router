using System;
using MCPRouter.Shell.Model.Servers;

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

    public PairingSessionModel(ControlApiClient client, bool pairingAvailable = true, Func<DateTimeOffset>? clock = null)
    {
        throw new NotImplementedException();
    }

    public Task OpenAsync(CancellationToken cancellation = default) => throw new NotImplementedException();

    public Task ReissueAsync(CancellationToken cancellation = default) => throw new NotImplementedException();

    public Task CloseAsync(CancellationToken cancellation = default) => throw new NotImplementedException();

    public void Tick() => throw new NotImplementedException();

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
