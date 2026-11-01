using System.Globalization;
using System.Net;
using MCPRouter.Shell.Model.Pairing;
using MCPRouter.Shell.Model.Servers;
using MCPRouter.Shell.Tests.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class PairingSessionModelTests
{
    /// <summary>The router's clock is the fixture's: a five-minute window starting at issue, read from the recording.</summary>
    private static readonly (string Code, DateTimeOffset IssuedAt, DateTimeOffset ExpiresAt) Recorded = PairingHttp.RecordedIssue();
    private static readonly DateTimeOffset Issued = Recorded.IssuedAt;
    private static readonly DateTimeOffset Expires = Recorded.ExpiresAt;

    private sealed class Clock
    {
        public DateTimeOffset Now { get; set; } = Issued;
    }

    private static PairingSessionModel Model(ControlApiClient client, Clock clock, bool available = true) =>
        new(client, available, () => clock.Now);

    /// <summary>A second code, issued the second after the first one expires, so it is the one a re-open is given.</summary>
    private static readonly string SecondCode =
        "{\"code\":\"K7X9W4M2\",\"issuedAt\":\"" + Iso(Expires.AddSeconds(1)) + "\",\"expiresAt\":\"" + Iso(Expires.AddMinutes(5).AddSeconds(1)) + "\"}";

    private static string Iso(DateTimeOffset instant) =>
        instant.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) + "Z";

    [Fact]
    public void ANewSessionAsksForNothingAndShowsNoCode()
    {
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);

        var model = Model(client, new Clock());

        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task OpeningRequestsACodeAndShowsItsCodeWithTheRoutersWindow()
    {
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Equal(new[] { "GET", "POST" }, handler.Requests.Select(r => r.Method));
        Assert.Equal(PairingPhase.AwaitingScanOrCode, model.CurrentState.Phase);
        Assert.Equal(Recorded.Code, model.CurrentState.PairingCode);
        Assert.Equal(TimeSpan.FromMinutes(5), model.CurrentState.RemainingTime);
    }

    [Fact]
    public async Task TheCountdownIsTakenFromTheRoutersExpiryNotFromAConstant()
    {
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
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
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
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
        Assert.Single(handler.Requests, r => r.Method == "POST");
    }

    [Fact]
    public async Task ReissueAfterExpiryAsksTheRouterForANewCode()
    {
        var handler = PairingHttp.Sheet((i, _) =>
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
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
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
        var handler = PairingHttp.Sheet((_, _) =>
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
        var handler = PairingHttp.Sheet((_, _) =>
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
        var handler = PairingHttp.Sheet((_, _) =>
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
        var firstAsked = new TaskCompletionSource();
        var handler = PairingHttp.Sheet((i, _) =>
        {
            if (i > 0) return PairingHttp.Answer(HttpStatusCode.Created, SecondCode);
            firstAsked.SetResult();
            return late.Task;
        });
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await firstAsked.Task;
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
        var firstAsked = new TaskCompletionSource();
        var handler = PairingHttp.Sheet((i, _) =>
        {
            if (i > 0) return PairingHttp.Answer(HttpStatusCode.Created, SecondCode);
            firstAsked.SetResult();
            return late.Task;
        });
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await firstAsked.Task;
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
        var firstAsked = new TaskCompletionSource();
        var handler = PairingHttp.Sheet((i, _) =>
        {
            if (i == 0)
            {
                firstAsked.SetResult();
                return late.Task;
            }
            return PairingHttp.Answer(HttpStatusCode.OK, "{\"revoked\":false}");
        });
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await firstAsked.Task;
        await model.CloseAsync();
        late.SetResult(PairingHttp.Json(HttpStatusCode.Created, PairingHttp.Fixture));
        await opening;

        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Equal(2, handler.Requests.Count(r => r.Method == "DELETE"));
    }

    /// <summary>
    /// Pairing is off on the router, so the sheet says so and asks for nothing. The state read is the only
    /// request, and no code is minted. That is the difference between an off router and a refusing one.
    /// </summary>
    [Fact]
    public async Task WhenTheRouterIsNotListeningNoCodeIsAskedForAndPairingIsShownAsOff()
    {
        var handler = PairingHttp.Sheet((_, _) => PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture), listening: false);
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Equal(PairingPhase.Unavailable, model.CurrentState.Phase);
        Assert.Null(model.CurrentState.Failure);
        Assert.Null(model.CurrentState.PairingCode);
        Assert.Equal(new[] { "GET" }, handler.Requests.Select(r => r.Method));
    }

    [Fact]
    public async Task AStateReadThatFailsIsShownAsAFailureAndMintsNoCode()
    {
        var handler = new PairingHttp.Scripted((_, request) =>
            request.Method == HttpMethod.Get
                ? PairingHttp.Refused()
                : PairingHttp.Answer(HttpStatusCode.Created, PairingHttp.Fixture));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        await model.OpenAsync();

        Assert.Equal(PairingPhase.Unavailable, model.CurrentState.Phase);
        Assert.Equal(ControlApiFailure.RouterNotRunning, model.CurrentState.Failure!.Kind);
        Assert.DoesNotContain(handler.Requests, r => r.Method == "POST");
    }

    /// <summary>
    /// The state answer is held until after the close, so the open's check is still in flight when the sheet
    /// shuts. The answer then arrives to a sheet that no longer wants a code, and must not mint one.
    /// </summary>
    [Fact]
    public async Task ClosingBeforeTheStateAnswerMintsNoCode()
    {
        var stateAnswer = new TaskCompletionSource<HttpResponseMessage>();
        var handler = new PairingHttp.Scripted((_, request) =>
            request.Method == HttpMethod.Get
                ? stateAnswer.Task
                : PairingHttp.Answer(HttpStatusCode.OK, "{\"revoked\":true}"));
        using var client = PairingHttp.Client(handler);
        var model = Model(client, new Clock());

        var opening = model.OpenAsync();
        await model.CloseAsync();
        stateAnswer.SetResult(PairingHttp.Json(HttpStatusCode.OK, PairingHttp.StateFixture));
        await opening;

        Assert.DoesNotContain(handler.Requests, r => r.Method == "POST");
        Assert.Equal(PairingPhase.Idle, model.CurrentState.Phase);
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
