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
        Assert.Equal("PC2E585N", issued.Code);
        Assert.Equal(DateTimeOffset.Parse("2026-10-19T01:59:18Z"), issued.IssuedAt);
        Assert.Equal(DateTimeOffset.Parse("2026-10-19T02:04:18Z"), issued.ExpiresAt);
    }

    [Fact]
    public async Task StateReadCarriesTheTokenBecauseTheRouterGatesGetToo()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.OK, "{\"code\":null,\"awaitingAck\":[]}"));
        using var client = PairingHttp.Client(handler);

        var issued = await client.GetPairingStateAsync();

        var seen = Assert.Single(handler.Requests);
        Assert.Equal("GET", seen.Method);
        Assert.Equal("/pairing/state", seen.Path);
        Assert.Equal($"Bearer {PairingHttp.Token}", seen.Authorization);
        Assert.Null(issued);
    }

    [Fact]
    public async Task StateReadNamesTheLiveCodeWhenThereIsOne()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.OK, $"{{\"code\":{PairingHttp.Fixture},\"awaitingAck\":[]}}"));
        using var client = PairingHttp.Client(handler);

        var issued = await client.GetPairingStateAsync();

        Assert.Equal("PC2E585N", issued!.Code);
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
