using MCPRouter.Shell.Model.Insights;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InsightsPresentationTests
{
    [Fact]
    public void WindowLabel_NamesTheWindowTheRouterAnswersOver()
    {
        // The router answers over one fixed window, so the board names that window and offers no selector.
        Assert.Equal("Last 24 hours", InsightsPresentation.WindowLabel(24));
    }

    [Fact]
    public void BoardDescription_AffirmsCountedNotModelled()
    {
        Assert.Contains("none of it is modelled", InsightsPresentation.BoardDescription);
    }
}
