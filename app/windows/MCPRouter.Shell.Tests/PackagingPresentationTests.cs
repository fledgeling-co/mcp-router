using MCPRouter.Shell.Model.Packaging;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class PackagingPresentationTests
{
    [Theory]
    [InlineData(DistributionChannel.Winget, "Windows Package Manager (winget)")]
    [InlineData(DistributionChannel.DirectMsix, "MSIX Bundle")]
    [InlineData(DistributionChannel.ZipPortable, "Portable ZIP Archive")]
    public void ChannelLabel_FormatsCorrectly(DistributionChannel channel, string expected)
    {
        Assert.Equal(expected, PackagingPresentation.ChannelLabel(channel));
    }

    [Fact]
    public void PackagingProperties_AreValid()
    {
        Assert.Equal("Fledgeling.MCPRouter", PackagingPresentation.PackageIdentity);
        Assert.Contains("SmartScreen", PackagingPresentation.SmartScreenNotice);
        Assert.Contains("preserving %USERPROFILE%", PackagingPresentation.UninstallGuidance);
    }
}
