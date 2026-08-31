using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class AmbientPresentationTests
{
    [Theory]
    [InlineData(AmbientRouterState.AtRest, "Router ready", "MCP Router — Ready")]
    [InlineData(AmbientRouterState.Working, "Serving tool calls", "MCP Router — Working")]
    [InlineData(AmbientRouterState.SomethingWaiting, "Decisions waiting", "MCP Router — 3 waiting")]
    [InlineData(AmbientRouterState.CannotReachRouter, "Cannot reach router", "MCP Router — Offline")]
    public void PresentationTitlesAndTooltips_MatchExpected(AmbientRouterState state, string expectedTitle, string expectedTooltip)
    {
        Assert.Equal(expectedTitle, AmbientPresentation.StateTitle(state));
        Assert.Equal(expectedTooltip, AmbientPresentation.TrayToolTip(state, 3));
    }

    [Fact]
    public void StateDetail_FormatsPluralsCorrectly()
    {
        Assert.Contains("1 item queued", AmbientPresentation.StateDetail(AmbientRouterState.SomethingWaiting, 1, 0));
        Assert.Contains("4 items queued", AmbientPresentation.StateDetail(AmbientRouterState.SomethingWaiting, 4, 0));

        Assert.Contains("1 active tool call", AmbientPresentation.StateDetail(AmbientRouterState.Working, 0, 1));
        Assert.Contains("5 active tool calls", AmbientPresentation.StateDetail(AmbientRouterState.Working, 0, 5));
    }
}
