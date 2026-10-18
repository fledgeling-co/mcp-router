using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class AmbientSurfaceModelTests
{
    /// <summary>
    /// DEF-301, as an assertion. The model used to open at <see cref="AmbientRouterState.AtRest"/>
    /// and this test used to require exactly that - so the defect was covered rather than caught.
    /// A surface that has read nothing may not say the router is ready.
    /// </summary>
    [Fact]
    public void BeforeAnyReading_TheSurfaceDoesNotClaimTheRouterIsReady()
    {
        var model = new AmbientSurfaceModel();
        var info = model.GetStatusInfo();

        Assert.False(model.HasReading);
        Assert.Null(model.LastReadAt);
        Assert.Equal(AmbientRouterState.Unknown, info.State);
        Assert.NotEqual("Router ready", info.StatusText);
        Assert.Equal("Reading the router", info.StatusText);
        Assert.Equal("Nothing has read the router yet.", info.Subtitle);
        Assert.Equal("MCP Router", AmbientPresentation.TrayToolTip(info.State, info.WaitingCount));
    }

    [Fact]
    public void DefaultOfTheEnum_IsUnknown()
    {
        // The zero value is what an uninitialised field, a default struct member and a missing
        // JSON property all become, so it is the one that must not read as a claim.
        Assert.Equal(AmbientRouterState.Unknown, default(AmbientRouterState));
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
        Assert.True(model.HasReading);
    }

    [Fact]
    public void Apply_ReportsWhetherTheRenderedStateMoved()
    {
        var model = new AmbientSurfaceModel();

        Assert.True(model.Apply(new AmbientReading(AmbientRouterState.AtRest)));
        Assert.False(model.Apply(new AmbientReading(AmbientRouterState.AtRest)));
        Assert.True(model.Apply(new AmbientReading(AmbientRouterState.Working, 0, 2)));
        Assert.True(model.Apply(new AmbientReading(AmbientRouterState.Working, 0, 3)));
        Assert.False(model.Apply(new AmbientReading(AmbientRouterState.Working, 0, 3)));
    }
}
