using MCPRouter.Shell.Model.Insights;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InsightsPresentationTests
{
    [Fact]
    public void WindowLabel_NamesTheWindowTheRouterAnswersOver()
    {
        Assert.Equal("Last 24 hours", InsightsPresentation.WindowLabel(24));
    }

    [Fact]
    public void WindowLabel_NamesASevenDayWindowByItsDays()
    {
        Assert.Equal("Last 7 days", InsightsPresentation.WindowLabel(168));
        Assert.Equal("in the last 7 days", InsightsPresentation.InWindow(168));
    }

    [Fact]
    public void Periods_OfferTheDayAndTheWeekInTheRegistryWords()
    {
        // SURF-040 names its period control "Last 7 days"; the day option is the one the Mac board offers beside it.
        Assert.Equal(new[] { "Last 24 hours", "Last 7 days" }, InsightsPresentation.Periods.Select(InsightsPresentation.PeriodTitle));
    }

    [Fact]
    public void EachPeriod_AsksTheRouterForItsOwnWindow()
    {
        Assert.Equal(24, InsightsPresentation.PeriodHours(InsightsPeriod.Last24Hours));
        Assert.Equal("24h", InsightsPresentation.PeriodQuery(InsightsPeriod.Last24Hours));
        Assert.Equal(168, InsightsPresentation.PeriodHours(InsightsPeriod.Last7Days));
        Assert.Equal("7d", InsightsPresentation.PeriodQuery(InsightsPeriod.Last7Days));
    }

    [Fact]
    public void BoardDescription_AffirmsCountedNotModelled()
    {
        Assert.Contains("none of it is modelled", InsightsPresentation.BoardDescription);
    }
}
