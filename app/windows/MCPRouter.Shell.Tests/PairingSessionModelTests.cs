using MCPRouter.Shell.Model.Pairing;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class PairingSessionModelTests
{
    [Fact]
    public void InitialState_HasCodeAndCountdown()
    {
        var model = new PairingSessionModel();
        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal("K7X9-W4M2", model.CurrentState.PairingCode);
    }

    [Fact]
    public void CompletePairing_TransitionsToPaired()
    {
        var model = new PairingSessionModel();
        model.CompletePairing("Luke's iPhone");

        Assert.Equal(PairingPhase.Paired, model.CurrentState.Phase);
        Assert.Equal("Luke's iPhone", model.CurrentState.PairedDeviceName);
    }
}
