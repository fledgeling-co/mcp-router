using System.Net;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The three pairing calls against the router's <c>/pairing/*</c> routes. The router gates every
/// method on that prefix, GET included (src/control.ts), so each request is asserted to carry the
/// bearer token: a read that dropped it would be refused by the router, not by this test.
/// </summary>
public sealed class ControlApiClientPairingTests
{
    [Fact]
    public async Task IssueIsAGatedJsonPostThatDecodesTheRecordedCode()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);

        var issued = await client.IssuePairingCodeAsync();

        var seen = Assert.Single(handler.Requests);
        Assert.Equal("POST", seen.Method);
        Assert.Equal("/pairing/codes", seen.Path);
        Assert.Equal($"Bearer {PairingHttp.Token}", seen.Authorization);
        Assert.Equal("application/json", seen.ContentType);
        Assert.Equal("4R74JHBM", issued.Code);
        Assert.Equal(DateTimeOffset.Parse("2026-10-19T15:52:11Z"), issued.IssuedAt);
        Assert.Equal(DateTimeOffset.Parse("2026-10-19T15:57:11Z"), issued.ExpiresAt);
    }

    [Fact]
    public async Task StateReadCarriesTheTokenBecauseTheRouterGatesGetToo()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.OK, "{\"code\":null,\"awaitingAck\":[],\"listener\":{\"enabled\":true,\"port\":8882,\"advertising\":true}}"));
        using var client = PairingHttp.Client(handler);

        var state = await client.GetPairingStateAsync();

        var seen = Assert.Single(handler.Requests);
        Assert.Equal("GET", seen.Method);
        Assert.Equal("/pairing/state", seen.Path);
        Assert.Equal($"Bearer {PairingHttp.Token}", seen.Authorization);
        Assert.Null(state.Code);
        Assert.True(state.Listener.Enabled);
    }

    [Fact]
    public async Task StateReadNamesTheLiveCodeWhenThereIsOne()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.OK, PairingHttp.StateFixture));
        using var client = PairingHttp.Client(handler);

        var state = await client.GetPairingStateAsync();

        Assert.Equal("4R74JHBM", state.Code!.Code);
        Assert.True(state.Listener.Enabled);
        Assert.NotNull(state.Listener.Port);
    }

    [Fact]
    public async Task StateReadReportsAnUnboundListenerAsOffWithNoPort()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.OK, PairingHttp.StateOff));
        using var client = PairingHttp.Client(handler);

        var state = await client.GetPairingStateAsync();

        Assert.Null(state.Code);
        Assert.False(state.Listener.Enabled);
        Assert.Null(state.Listener.Port);
        Assert.False(state.Listener.Advertising);
    }

    /// <summary>A state body that does not say whether the listener is bound is not one the sheet can read, so it is refused rather than read as off.</summary>
    [Fact]
    public async Task StateReadRefusesABodyThatDoesNotSayWhetherTheListenerIsBound()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.OK, "{\"code\":null,\"awaitingAck\":[]}"));
        using var client = PairingHttp.Client(handler);

        var malformed = await Assert.ThrowsAsync<ControlApiException>(() => client.GetPairingStateAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, malformed.Kind);
    }

    [Fact]
    public async Task RevokeIsAGatedDeleteThatReportsWhetherACodeWasLive()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.OK, "{\"revoked\":true}"));
        using var client = PairingHttp.Client(handler);

        var revoked = await client.RevokePairingCodeAsync();

        var seen = Assert.Single(handler.Requests);
        Assert.Equal("DELETE", seen.Method);
        Assert.Equal("/pairing/codes", seen.Path);
        Assert.Equal($"Bearer {PairingHttp.Token}", seen.Authorization);
        Assert.True(revoked);
    }

    [Fact]
    public async Task AnUnauthorisedIssueIsNamedAsSuchAndNeverCarriesTheToken()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.Unauthorized, "{\"error\":\"unauthorised\"}"));
        using var client = PairingHttp.Client(handler);

        var refused = await Assert.ThrowsAsync<ControlApiException>(() => client.IssuePairingCodeAsync());

        Assert.Equal(ControlApiFailure.Unauthorized, refused.Kind);
        Assert.DoesNotContain(PairingHttp.Token, refused.Message);
        Assert.DoesNotContain(PairingHttp.Token, refused.Detail);
    }

    [Fact]
    public async Task NothingListeningIsTheRouterNotRunning()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Refused());
        using var client = PairingHttp.Client(handler);

        var refused = await Assert.ThrowsAsync<ControlApiException>(() => client.IssuePairingCodeAsync());

        Assert.Equal(ControlApiFailure.RouterNotRunning, refused.Kind);
    }

    [Fact]
    public async Task ACodeOutsideTheCrockfordAlphabetIsRefusedNotDefaulted()
    {
        // U is excluded from the alphabet (PairingCode.swift), so this is not a code the phone could type.
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.Created,
                "{\"code\":\"PC2E585U\",\"issuedAt\":\"2026-10-19T01:59:18Z\",\"expiresAt\":\"2026-10-19T02:04:18Z\"}"));
        using var client = PairingHttp.Client(handler);

        var malformed = await Assert.ThrowsAsync<ControlApiException>(() => client.IssuePairingCodeAsync());

        Assert.Equal(ControlApiFailure.MalformedResponse, malformed.Kind);
    }
}
