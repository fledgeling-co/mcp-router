using MCPRouter.Shell.Model.Ambient;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class AmbientPresentationTests
{
    [Theory]
    [InlineData(AmbientRouterState.Unknown, "Reading the router", "MCP Router")]
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
        // WORDED FROM WHAT IS COUNTED. This used to assert "1 item queued", which described a
        // queue from the operator's phone that nothing in this build reads. What the surface
        // actually counts is the router's own pendingAuth list, so that is what it says.
        Assert.Equal("1 server is waiting for you to sign in.",
            AmbientPresentation.StateDetail(AmbientRouterState.SomethingWaiting, 1, 0));
        Assert.Equal("4 servers are waiting for you to sign in.",
            AmbientPresentation.StateDetail(AmbientRouterState.SomethingWaiting, 4, 0));

        Assert.Contains("1 active tool call", AmbientPresentation.StateDetail(AmbientRouterState.Working, 0, 1));
        Assert.Contains("5 active tool calls", AmbientPresentation.StateDetail(AmbientRouterState.Working, 0, 5));
    }

    /// <summary>
    /// The unreachable sentence names the endpoint this app is polling. It used to name the
    /// literal 127.0.0.1:8879 whatever port the router was on.
    /// </summary>
    /// <summary>
    /// DEF-380. The flyout's inbox button used to be written in its code-behind, where nothing
    /// could test it. Its count is what decides whether the operator can press it at all.
    /// </summary>
    [Fact]
    public void TheInboxButtonCountsWhatIsWaiting()
    {
        Assert.Equal("Review Inbox (0)", AmbientPresentation.InboxButtonText(0));
        Assert.False(AmbientPresentation.InboxButtonEnabled(0));

        Assert.Equal("Review Inbox (3)", AmbientPresentation.InboxButtonText(3));
        Assert.True(AmbientPresentation.InboxButtonEnabled(3));
    }

    [Fact]
    public void TheUnreachableSentence_NamesTheEndpointThatWasPolled()
    {
        Assert.Equal(
            "The router daemon is not responding on 127.0.0.1:51234.",
            AmbientPresentation.StateDetail(
                AmbientRouterState.CannotReachRouter, 0, 0, "127.0.0.1:51234"));
    }
}
