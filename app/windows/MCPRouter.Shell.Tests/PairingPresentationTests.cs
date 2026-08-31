using System;
using MCPRouter.Shell.Model.Pairing;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class PairingPresentationTests
{
    [Fact]
    public void ExpiresIn_FormatsTimeCorrectly()
    {
        Assert.Equal("expires in 4:45", PairingPresentation.ExpiresIn(TimeSpan.FromSeconds(285)));
        Assert.Equal("expires in 0:30", PairingPresentation.ExpiresIn(TimeSpan.FromSeconds(30)));
    }

    [Theory]
    [InlineData(PairingRefusalReason.NotRecognised, "That code is not the one on screen")]
    [InlineData(PairingRefusalReason.Expired, "That code has expired")]
    [InlineData(PairingRefusalReason.AlreadyUsed, "That code has already paired a device")]
    [InlineData(PairingRefusalReason.FirewallBlocked, "Windows Defender Firewall blocked")]
    public void RefusalMessages_ProvideActionableGuidance(PairingRefusalReason reason, string snippet)
    {
        Assert.Contains(snippet, PairingPresentation.RefusalMessage(reason));
    }
}
