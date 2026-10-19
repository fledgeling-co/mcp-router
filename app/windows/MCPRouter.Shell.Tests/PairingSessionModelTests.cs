using System.Net;
using MCPRouter.Shell.Model.Pairing;
using MCPRouter.Shell.Model.Servers;
using MCPRouter.Shell.Tests.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class PairingSessionModelTests
{
    /// <summary>The router's clock is the fixture's: a five-minute window starting at issue.</summary>
    private static readonly DateTimeOffset Issued = DateTimeOffset.Parse("2026-10-19T01:59:18Z");
    private static readonly DateTimeOffset Expires = DateTimeOffset.Parse("2026-10-19T02:04:18Z");

    private sealed class Clock
    {
        public DateTimeOffset Now { get; set; } = Issued;
    }

    private static PairingSessionModel Model(ControlApiClient client, Clock clock, bool available = true) =>
        new(client, available, () => clock.Now);

    private const string SecondCode = "{\"code\":\"K7X9W4M2\",\"issuedAt\":\"2026-10-19T02:04:20Z\",\"expiresAt\":\"2026-10-19T02:09:20Z\"}";

    [Fact]
    public void ANewSessionAsksForNothingAndShowsNoCode()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);

        var model = Model(client, new Clock());

        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task OpeningRequestsACodeAndShowsItsCodeWithTheRoutersWindow()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Single(handler.Requests);
        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal("PC2E585N", model.CurrentState.PairingCode);
        Assert.Equal(TimeSpan.FromMinutes(5), model.CurrentState.RemainingTime);
    }

    [Fact]
    public async Task TheCountdownIsTakenFromTheRoutersExpiryNotFromAConstant()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var clock = new Clock();
        var model = Model(client, clock);
        await model.OpenAsync();

        clock.Now = Issued.AddSeconds(285);
        model.Tick();

        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal(TimeSpan.FromSeconds(15), model.CurrentState.RemainingTime);
    }

    [Fact]
    public async Task ACodeThatOutlivesItsWindowMovesToExpiredAndIsNoLongerShown()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var clock = new Clock();
        var model = Model(client, clock);
        await model.OpenAsync();

        clock.Now = Expires.AddSeconds(-1);
        model.Tick();
        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);

        clock.Now = Expires;
        model.Tick();

        Assert.Equal(PairingPhase.Expired, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task ReissueAfterExpiryAsksTheRouterForANewCode()
    {
        var handler = new PairingHttp.Scripted((i, _) =>
            PairingHttp.Answer(HttpStatusCode.Created, i == 0 ? PairingHttp.Fixture : SecondCode));
        using var client = PairingHttp.Client(handler);
        var clock = new Clock();
        var model = Model(client, clock);
        await model.OpenAsync();
        clock.Now = Expires;
        model.Tick();

        await model.ReissueAsync();

        Assert.Equal(2, handler.Requests.Count(r => r.Method == "POST"));
        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal("K7X9W4M2", model.CurrentState.PairingCode);
    }

    [Fact]
    public async Task WhenPairingIsOffNothingIsRequestedAndTheStateSaysSo()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock(), available: false);

        await model.OpenAsync();
        await model.ReissueAsync();

        Assert.Empty(handler.Requests);
        Assert.Equal(PairingPhase.Unavailable, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Null(model.CurrentState.Failure);
    }

    [Fact]
    public async Task ARouterThatRefusesIsShownAsUnavailableWithItsKind()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.Unauthorized, "{\"error\":\"unauthorised\"}"));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Equal(PairingPhase.Unavailable, model.CurrentState.Phase);
        Assert.Equal(ControlApiFailure.Unauthorized, model.CurrentState.Failure!.Kind);
        Assert.Null(model.CurrentState.PairingCode);
    }

    [Fact]
    public async Task ANotRunningRouterIsShownAsNotRunning()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Refused());
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Equal(PairingPhase.Unavailable, model.CurrentState.Phase);
        Assert.Equal(ControlApiFailure.RouterNotRunning, model.CurrentState.Failure!.Kind);
    }

    [Fact]
    public async Task ClosingRevokesALiveCodeOnTheRouter()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());
        await model.OpenAsync();
        handler.Requests.Clear();

        await model.CloseAsync();

        var revoke = Assert.Single(handler.Requests);
        Assert.Equal("DELETE", revoke.Method);
        Assert.Equal("/pairing/codes", revoke.Path);
        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
    }

    [Fact]
    public async Task ClosingAfterARefusalHasNothingOnTheRouterToRevoke()
    {
        var handler = new PairingHttp.Scripted((_, _) =>
            PairingHttp.Answer(HttpStatusCode.Unauthorized, "{\"error\":\"unauthorised\"}"));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());
        await model.OpenAsync();
        handler.Requests.Clear();

        await model.CloseAsync();

        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task AReissueOvertakesAnOpenThatIsStillInFlight()
    {
        var late = new TaskCompletionSource<HttpResponseMessage>();
        var handler = new PairingHttp.Scripted((i, _) =>
            i == 0 ? late.Task : PairingHttp.Answer(HttpStatusCode.Created, SecondCode));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await model.ReissueAsync();
        Assert.Equal("K7X9W4M2", model.CurrentState.PairingCode);

        late.SetResult(PairingHttp.Json(HttpStatusCode.Created, PairingHttp.Fixture));
        await opening;

        Assert.Equal("K7X9W4M2", model.CurrentState.PairingCode);
        Assert.DoesNotContain(handler.Requests, r => r.Method == "DELETE");
    }

    [Fact]
    public async Task AFailedAnswerOvertakenByAReissueDoesNotReplaceTheCurrentCode()
    {
        var late = new TaskCompletionSource<HttpResponseMessage>();
        var handler = new PairingHttp.Scripted((i, _) =>
            i == 0 ? late.Task : PairingHttp.Answer(HttpStatusCode.Created, SecondCode));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await model.ReissueAsync();

        late.SetResult(PairingHttp.Json(HttpStatusCode.InternalServerError, "{\"error\":\"boom\"}"));
        await opening;

        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal("K7X9W4M2", model.CurrentState.PairingCode);
        Assert.Null(model.CurrentState.Failure);
    }

    [Fact]
    public async Task AnAnswerThatArrivesAfterCloseIsTakenBackOnTheRouter()
    {
        var late = new TaskCompletionSource<HttpResponseMessage>();
        var handler = new PairingHttp.Scripted((i, _) =>
            i == 0 ? late.Task : PairingHttp.Answer(HttpStatusCode.OK, "{\"revoked\":false}"));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await model.CloseAsync();
        late.SetResult(PairingHttp.Json(HttpStatusCode.Created, PairingHttp.Fixture));
        await opening;

        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Equal(2, handler.Requests.Count(r => r.Method == "DELETE"));
    }

    [Fact]
    public void CompletePairingStillMarksTheSessionPaired()
    {
        var handler = new PairingHttp.Scripted((_, _) => PairingHttp.Refused());
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        model.CompletePairing("Luke's iPhone");

        Assert.Equal(PairingPhase.Paired, model.CurrentState.Phase);
        Assert.Equal("Luke's iPhone", model.CurrentState.PairedDeviceName);
    }
}
