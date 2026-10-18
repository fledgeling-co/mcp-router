using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The mapping from the router's own <c>/status</c> document to the state the ambient surface
/// renders. The bodies below are the shape <c>src/router.ts</c> answers with.
/// </summary>
public sealed class AmbientStatusMappingTests
{
    private const string Quiet =
        """{"ok":true,"port":8879,"idleMs":900000,"children":[{"name":"a","transport":"stdio","state":"idle","callsServed":0,"inFlight":0,"idleSec":0}],"pendingAuth":[],"tools":12}""";

    private const string Busy =
        """{"ok":true,"port":8879,"idleMs":900000,"children":[{"name":"a","inFlight":2},{"name":"b","inFlight":1}],"pendingAuth":[],"tools":12}""";

    private const string Waiting =
        """{"ok":true,"port":8879,"children":[{"name":"a","inFlight":0}],"pendingAuth":[{"name":"b"}],"tools":12}""";

    [Fact]
    public void AQuietRouter_ReadsAsAtRest()
    {
        var reading = AmbientStatusMapping.FromStatusJson(Quiet);
        Assert.Equal(AmbientRouterState.AtRest, reading.State);
        Assert.Equal(0, reading.ActiveCallCount);
    }

    [Fact]
    public void CallsInFlight_ReadAsWorking_AndAreSummedAcrossUpstreams()
    {
        var reading = AmbientStatusMapping.FromStatusJson(Busy);
        Assert.Equal(AmbientRouterState.Working, reading.State);
        Assert.Equal(3, reading.ActiveCallCount);
        Assert.Equal("3 active tool calls in flight.",
            AmbientPresentation.StateDetail(reading.State, reading.WaitingCount, reading.ActiveCallCount));
    }

    [Fact]
    public void APendingSignIn_OutranksWorkTheRouterIsDoingOnItsOwn()
    {
        var reading = AmbientStatusMapping.FromStatusJson(Waiting);
        Assert.Equal(AmbientRouterState.SomethingWaiting, reading.State);
        Assert.Equal(1, reading.WaitingCount);
    }

    /// <summary>
    /// A body this version cannot read is not evidence that the router is idle - which is the
    /// whole shape of DEF-301, one layer down.
    /// </summary>
    [Theory]
    [InlineData("")]
    [InlineData("not json at all")]
    [InlineData("[1,2,3]")]
    [InlineData("\"a string\"")]
    public void AnUnreadableAnswer_IsNeverAtRest(string body)
    {
        Assert.Equal(AmbientRouterState.CannotReachRouter,
            AmbientStatusMapping.FromStatusJson(body).State);
    }
}
