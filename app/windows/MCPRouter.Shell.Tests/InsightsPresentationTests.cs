using MCPRouter.Shell.Model.Insights;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InsightsPresentationTests
{
    [Theory]
    [InlineData(InsightsPeriod.Last24Hours, "Last 24 hours")]
    [InlineData(InsightsPeriod.Last7Days, "Last 7 days")]
    [InlineData(InsightsPeriod.Last30Days, "Last 30 days")]
    public void PeriodLabel_ReturnsExpectedCopy(InsightsPeriod period, string expected)
    {
        Assert.Equal(expected, InsightsPresentation.PeriodLabel(period));
    }

    [Fact]
    public void BoardDescription_AffirmsCountedNotModelled()
    {
        Assert.Contains("none of it is modelled", InsightsPresentation.BoardDescription);
    }
}
