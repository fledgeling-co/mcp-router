using MCPRouter.Shell.Model.Harnesses;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class HarnessPresentationTests
{
    [Theory]
    [InlineData(HarnessReading.NotRouted, "Not routed")]
    [InlineData(HarnessReading.RoutedOverHTTP, "Routed (HTTP)")]
    [InlineData(HarnessReading.RoutedViaShim, "Routed (stdio shim)")]
    [InlineData(HarnessReading.RoutedWithDirectServers, "Double-running")]
    public void StateLabel_FormatsCorrectly(HarnessReading state, string expected)
    {
        Assert.Equal(expected, HarnessPresentation.StateLabel(state));
    }

    [Fact]
    public void DoubleRunningWarning_FormatsPluralsCorrectly()
    {
        Assert.Equal("1 server declared directly here that this router already fronts.", HarnessPresentation.DoubleRunningWarning(1));
        Assert.Equal("4 servers declared directly here that this router already fronts.", HarnessPresentation.DoubleRunningWarning(4));
    }
}
