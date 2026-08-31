using MCPRouter.Shell.Model.CapabilityDocument;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class CapabilityDocumentPresentationTests
{
    [Theory]
    [InlineData(CapabilityDocumentTab.Capabilities, "Capabilities")]
    [InlineData(CapabilityDocumentTab.Changelog, "Changelog")]
    [InlineData(CapabilityDocumentTab.FlagsWorthKnowing, "Flags worth knowing")]
    public void TabTitle_ReturnsExpectedNames(CapabilityDocumentTab tab, string expected)
    {
        Assert.Equal(expected, CapabilityDocumentPresentation.TabTitle(tab));
    }

    [Fact]
    public void UpdateGateCopy_ReflectsCoreSecurityGuarantee()
    {
        Assert.Contains("capability diff is empty", CapabilityDocumentPresentation.UpdateGateExplanation);
    }
}
