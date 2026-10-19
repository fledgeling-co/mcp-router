using System;
using MCPRouter.Shell.Model.Pairing;
using MCPRouter.Shell.Model.Servers;
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

    [Fact]
    public void Formatted_SplitsTheCanonicalEightCharactersLikeTheMac()
    {
        Assert.Equal("K7X9-W4M2", PairingPresentation.Formatted("K7X9W4M2"));
    }

    [Fact]
    public void StatusLine_ReadsTheCountdownOnlyWhileACodeIsLive()
    {
        var live = new PairingSessionState(PairingPhase.AwaitingScanOrCode, "K7X9W4M2", TimeSpan.FromSeconds(285));
        var expired = new PairingSessionState(PairingPhase.Expired, null, TimeSpan.Zero);

        Assert.Equal("expires in 4:45", PairingPresentation.StatusLine(live));
        Assert.Equal(PairingPresentation.ExpiredHeadline, PairingPresentation.StatusLine(expired));
    }

    [Fact]
    public void Unavailable_WhenPairingIsOffSaysSoWithoutBlamingAnyone()
    {
        var off = new PairingSessionState(PairingPhase.Unavailable, null, TimeSpan.Zero);

        Assert.Equal(PairingPresentation.PairingOffHeadline, PairingPresentation.UnavailableHeadline(off));
        Assert.Equal(PairingPresentation.PairingOffAdvice, PairingPresentation.UnavailableAdvice(off));
    }

    [Fact]
    public void Unavailable_WhenTheRouterRefusesReadsTheOneWordingTheClientOwns()
    {
        var failure = new ControlApiException(ControlApiFailure.RouterNotRunning, "connection refused");
        var refused = new PairingSessionState(PairingPhase.Unavailable, null, TimeSpan.Zero, Failure: failure);

        Assert.Equal(failure.Headline, PairingPresentation.UnavailableHeadline(refused));
        Assert.Equal(failure.Advice, PairingPresentation.UnavailableAdvice(refused));
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
