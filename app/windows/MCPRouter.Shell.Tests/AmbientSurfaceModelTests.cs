using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class AmbientSurfaceModelTests
{
    [Fact]
    public void InitialState_IsAtRest()
    {
        var model = new AmbientSurfaceModel();
        var info = model.GetStatusInfo();

        Assert.Equal(AmbientRouterState.AtRest, info.State);
        Assert.Equal("Router ready", info.StatusText);
        Assert.Equal(0, info.WaitingCount);
    }

    [Fact]
    public void UpdateState_UpdatesStatusInfo()
    {
        var model = new AmbientSurfaceModel();
        model.UpdateState(AmbientRouterState.SomethingWaiting, waitingCount: 2);

        var info = model.GetStatusInfo();
        Assert.Equal(AmbientRouterState.SomethingWaiting, info.State);
        Assert.Equal("Decisions waiting", info.StatusText);
        Assert.Equal(2, info.WaitingCount);
    }
}
