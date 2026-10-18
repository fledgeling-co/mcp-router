using MCPRouter.Shell.Model.Insights;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InsightsBoardModelTests
{
    [Fact]
    public void GetSummary_IncludesDenominatorsForEveryMetric()
    {
        var model = new InsightsBoardModel();
        var summary = model.GetSummary();

        Assert.NotEmpty(summary.ChildProcesses.DenominatorOrProvenance);
        Assert.NotEmpty(summary.ResidentMemory.DenominatorOrProvenance);
        Assert.NotEmpty(summary.ToolCalls.DenominatorOrProvenance);
        Assert.NotEmpty(summary.FailedCalls.DenominatorOrProvenance);

        Assert.Contains("measured, not modelled", summary.ResidentMemory.DenominatorOrProvenance);
        Assert.Contains("12 of 9,418", summary.FailedCalls.DenominatorOrProvenance);
    }

    [Fact]
    public void GetSummary_ZeroAttributionCarriesExplanation()
    {
        var model = new InsightsBoardModel();
        var summary = model.GetSummary();

        var zeroHarness = Assert.Single(summary.HarnessBreakdown, h => h.CallCount == 0);
        Assert.NotNull(zeroHarness.Explanation);
        Assert.NotEmpty(zeroHarness.Explanation);
    }
}
