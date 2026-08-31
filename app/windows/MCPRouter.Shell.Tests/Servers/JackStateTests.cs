using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The jack's precedence, over the cross product of the inputs that can coexist on one row —
/// the fixture set cannot produce every combination a machine will, and the prototype shipped
/// wrong answers from exactly this class of branch. The numbers below recover the design of
/// record's own: an idle horizon of 300000ms with 79 idle seconds is the mock's `3:41 left`.
/// </summary>
public sealed class JackStateTests
{
    private static ServerRow Row(
        bool disabled = false,
        string state = "idle",
        bool warm = false,
        Placard? placard = null,
        PendingChange? pendingChange = null,
        bool authSupported = false,
        bool authAuthorized = true,
        int idleSec = 0,
        int pendingCount = 2) => new()
    {
        Name = "probe",
        Transport = "stdio",
        State = state,
        InFlight = 0,
        CallsServed = 0,
        IdleSec = idleSec,
        Hash = "h",
        Tools = 0,
        ToolNames = [],
        Projects = [],
        Warm = warm,
        Disabled = disabled,
        Placard = placard,
        PendingChange = pendingChange,
        Auth = new ServerAuth { Supported = authSupported, Authorized = authAuthorized },
        Usage = new ServerUsage { Calls = 0, Errors = 0 },
    };

    private static readonly Placard Placard = new() { Reason = "under review" };
    private static PendingChange Held(int count = 2) => new() { SeenAt = "2026-08-25T11:45:33.372Z", Count = count };

    // ------------------------------------------------------------------ the precedence chain

    [Fact]
    public void ADisabledServerIsDormantEvenWithAChildAndEverySummons()
    {
        var row = Row(disabled: true, state: "running", placard: Placard, pendingChange: Held(),
            authSupported: true, authAuthorized: false);

        Assert.Equal(JackState.Dormant, JackPresentation.ForServer(row));
        Assert.Equal("disabled by you", JackCondition.ForServer(row, null).Word);
    }

    [Fact]
    public void ARunningServerIsLitEvenWhileHoldingPlacardsAndRefusals()
    {
        var row = Row(state: "running", placard: Placard, pendingChange: Held(),
            authSupported: true, authAuthorized: false);

        Assert.Equal(JackState.Live, JackPresentation.ForServer(row));
    }

    [Fact]
    public void APlacardedServerIsTripped()
    {
        Assert.Equal(JackState.Tripped, JackPresentation.ForServer(Row(placard: Placard)));
    }

    [Fact]
    public void AnIndexErrorIsNotASixthStateItArrivesAsAPlacard()
    {
        // The wire rule: placardFor() echoes the user's placard first and {reason: error}
        // second, so a failed index always reaches the client carrying a placard.
        var indexed = Row(placard: new Placard { Reason = "spawn echo ENOENT" });
        Assert.Equal(JackState.Tripped, JackPresentation.ForServer(indexed));
    }

    [Fact]
    public void AHeldServerIsHeld()
    {
        Assert.Equal(JackState.Held, JackPresentation.ForServer(Row(pendingChange: Held())));
    }

    [Fact]
    public void AnUnauthorisedServerNeedsSignIn()
    {
        Assert.Equal(JackState.NeedsSignIn, JackPresentation.ForServer(Row(authSupported: true, authAuthorized: false)));
    }

    [Fact]
    public void APlainServerIsDormant()
    {
        Assert.Equal(JackState.Dormant, JackPresentation.ForServer(Row()));
    }

    // ------------------------------------------------------------------ the word

    [Fact]
    public void TheFiveWordsAreTheDesignOfRecordsFiveWords()
    {
        Assert.Equal("awake", JackState.Live.Word());
        Assert.Equal("tripped", JackState.Tripped.Word());
        Assert.Equal("held", JackState.Held.Word());
        Assert.Equal("needs sign-in", JackState.NeedsSignIn.Word());
        Assert.Equal("dormant", JackState.Dormant.Word());
    }

    [Fact]
    public void AWarmLiveServerNeverShowsACountdown()
    {
        // The reaper skips a warm server; counting down to a reap that will never happen,
        // beside a hub counting that server at rest, is a contradiction on one surface.
        var row = Row(state: "running", warm: true, idleSec: 0);
        var condition = JackCondition.ForServer(row, idleMs: 300000);

        Assert.Equal("never reaped", condition.Word);
        Assert.Equal("warm", condition.Contracted);
    }

    [Fact]
    public void ACountdownUsesTheHorizonTheRouterSent()
    {
        var row = Row(state: "running", idleSec: 79);
        var condition = JackCondition.ForServer(row, idleMs: 300000);

        Assert.Equal("3:41 left", condition.Word);
        Assert.Equal("3:41", condition.Contracted);
    }

    [Fact]
    public void AServerPastItsHorizonFloorsAtZero()
    {
        var row = Row(state: "running", idleSec: 500);
        var condition = JackCondition.ForServer(row, idleMs: 300000);

        Assert.Equal("0:00 left", condition.Word);
    }

    [Fact]
    public void AnUnknownHorizonSaysAwakeWithNoNumber()
    {
        // "How long is left" is a question nothing has answered; 300000 is precisely the
        // prototype's hardcoded horizon, which §6 forbids displaying as an observation.
        var condition = JackCondition.ForServer(Row(state: "running"), idleMs: null);

        Assert.Equal("awake", condition.Word);
        Assert.Equal("awake", condition.Contracted);
    }

    [Fact]
    public void AWarmDormantServerReadsWarm()
    {
        Assert.Equal("warm", JackCondition.ForServer(Row(warm: true), null).Word);
    }

    [Fact]
    public void HeldCountsTheirNoun()
    {
        Assert.Equal("1 held change", JackCondition.ForServer(Row(pendingChange: Held(1)), null).Word);
        Assert.Equal("2 held changes", JackCondition.ForServer(Row(pendingChange: Held(2)), null).Word);
        Assert.Equal("2 held", JackCondition.ForServer(Row(pendingChange: Held(2)), null).Contracted);
    }

    // ------------------------------------------------------------------ the row's cell

    [Fact]
    public void TheStateCellNeverDrawsABareClockUnderASuccessDot()
    {
        // On Windows SystemFillColorSuccess and SystemFillColorCritical are the same luminance
        // (§12's 1.00:1 finding), so the state's word is the only channel some users have.
        var row = Row(state: "running", idleSec: 79);
        Assert.Equal("Awake · 3:41 left", JackPresentation.StateCell(row, 300000));
        Assert.Equal("Awake", JackPresentation.StateCell(Row(state: "running"), null));
        Assert.Equal("Awake · never reaped", JackPresentation.StateCell(Row(state: "running", warm: true), 300000));
    }

    [Fact]
    public void TheStateCellRaisesOnlyTheFirstLetter()
    {
        Assert.Equal("Needs sign-in", JackPresentation.StateCell(Row(authSupported: true, authAuthorized: false), null));
        Assert.Equal("Disabled by you", JackPresentation.StateCell(Row(disabled: true), null));
        Assert.Equal("Tripped", JackPresentation.StateCell(Row(placard: Placard), null));
        Assert.Equal("Dormant", JackPresentation.StateCell(Row(), null));
        Assert.Equal("2 held changes", JackPresentation.StateCell(Row(pendingChange: Held()), null));
    }

    // ------------------------------------------------------------------ the clock and the stamp

    [Fact]
    public void TheClockDoesNotRollOverAtAnHour()
    {
        Assert.Equal("3:41", JackPresentation.Mmss(221));
        Assert.Equal("221:00", JackPresentation.Mmss(13260));
        Assert.Equal("0:00", JackPresentation.Mmss(-5));
    }

    [Fact]
    public void LastCallRendersRelativeOrNever()
    {
        var now = DateTimeOffset.Parse("2026-08-25T11:45:31.625Z");

        ServerRow Used(string iso) => Row() with
        {
            Usage = new ServerUsage { Calls = 1, Errors = 0, LastUsed = iso },
        };

        Assert.Equal("never", JackPresentation.RelativeLastCall(Row(), now));
        Assert.Equal("12 s ago", JackPresentation.RelativeLastCall(Used("2026-08-25T11:45:19.625Z"), now));
        Assert.Equal("2 min ago", JackPresentation.RelativeLastCall(Used("2026-08-25T11:43:31.625Z"), now));
        Assert.Equal("2 h ago", JackPresentation.RelativeLastCall(Used("2026-08-25T09:45:31.625Z"), now));
        Assert.Equal("4 d ago", JackPresentation.RelativeLastCall(Used("2026-08-21T11:45:31.625Z"), now));
    }
}
