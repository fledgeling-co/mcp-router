using System;
using System.Collections.Generic;
using System.Linq;
using MCPRouter.Shell.Live.Lifecycle;
using MCPRouter.Shell.Model.Lifecycle;
using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>A schtasks that runs nothing and remembers exactly what it was asked to run.</summary>
/// <remarks>
/// The point of the fake is that the assertions below are about the ARGV and the XML - the two
/// things that decide what the Windows task scheduler is told - rather than about a value this
/// code handed itself. WIN23's original suite asserted that a switch statement returning
/// "Scheduled Task at user logon (restarts on crash, un-elevated)" contained the words "Scheduled
/// Task at user logon", which is true of the string literal and says nothing about any task.
/// </remarks>
internal sealed class FakeTaskSchedulerCli : ITaskSchedulerCli
{
    private readonly Queue<TaskCliResult> _replies = new();

    public List<IReadOnlyList<string>> Calls { get; } = new();

    public FakeTaskSchedulerCli Replies(params TaskCliResult[] replies)
    {
        foreach (var reply in replies)
        {
            _replies.Enqueue(reply);
        }
        return this;
    }

    public TaskCliResult Run(IReadOnlyList<string> arguments)
    {
        Calls.Add(arguments.ToArray());
        return _replies.Count > 0 ? _replies.Dequeue() : new TaskCliResult(0, "", "");
    }

    public IReadOnlyList<string> LastCall => Calls[^1];
}

public sealed class LogonTaskSupervisorTests
{
    private const string User = @"TESTHOST\operator";
    private const string TaskName = @"\MCPRouter\Test Daemon";

    private static DaemonLifecycleConfig Config(
        DaemonSupervisionKind mode = DaemonSupervisionKind.LogonTask,
        bool restart = true,
        int delay = 60) =>
        new(mode, 8890, @"C:\Program Files\MCP Router\mcp-router.exe", restart, delay);

    private static LogonTaskSupervisor Supervisor(FakeTaskSchedulerCli cli) =>
        new(cli, TaskName, User);

    // ------------------------------------------------------------------ the three claims

    [Fact]
    public void Xml_TriggersOnLogonAndNotOnBoot()
    {
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config());

        Assert.Contains("<LogonTrigger>", xml, StringComparison.Ordinal);
        Assert.Contains($"<UserId>{User}</UserId>", xml, StringComparison.Ordinal);

        // The negative is the half that matters. A BootTrigger fires before any user session
        // exists, so a daemon started by one cannot reach the browser it needs for OAuth or the
        // per-user harness configuration - the exact requirement
        // LifecyclePresentation.UserSessionRequirement states. A task with both triggers would
        // satisfy every positive assertion above and still start the daemon in the wrong session.
        Assert.DoesNotContain("<BootTrigger>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_RunsUnelevatedWithTheInteractiveToken()
    {
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config());

        Assert.Contains("<RunLevel>LeastPrivilege</RunLevel>", xml, StringComparison.Ordinal);
        Assert.Contains("<LogonType>InteractiveToken</LogonType>", xml, StringComparison.Ordinal);

        // HighestAvailable is what the scheduler uses when an elevated caller registers a task and
        // says nothing, so "un-elevated" is a thing this document must assert rather than a thing
        // it can leave out.
        Assert.DoesNotContain("HighestAvailable", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_RestartsOnCrash_WithTheConfiguredDelay()
    {
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config(delay: 90));

        Assert.Contains("<RestartOnFailure>", xml, StringComparison.Ordinal);
        Assert.Contains("<Interval>PT90S</Interval>", xml, StringComparison.Ordinal);
        Assert.Contains("<Count>3</Count>", xml, StringComparison.Ordinal);

        // And the part that actually restarts a crashed daemon. The repetition floor is 60 seconds
        // because the scheduler refuses anything shorter, so a 90-second delay gives a 90-second
        // repetition and a 5-second one would still give 60.
        Assert.Contains("<Repetition>", xml, StringComparison.Ordinal);
        Assert.Contains("<StopAtDurationEnd>false</StopAtDurationEnd>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_FloorsTheRepetitionAtTheShortestIntervalTheSchedulerAccepts()
    {
        // A repetition under a minute is refused by the scheduler at registration, so a config
        // asking for five seconds must not produce a document that cannot be registered at all.
        // The RestartOnFailure interval keeps the five, because that one has no such floor and it
        // covers a different failure.
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config(delay: 5));

        Assert.Contains("<Repetition>\n        <Interval>PT60S</Interval>", xml, StringComparison.Ordinal);
        Assert.Contains("<RestartOnFailure>\n      <Interval>PT5S</Interval>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_OmitsTheRestartBlockWhenTheConfigDeclinesIt()
    {
        // The discriminating half of the pair above: without this, a builder that emitted
        // RestartOnFailure unconditionally would pass the restart test while making
        // DaemonLifecycleConfig.RestartOnCrash a decorative flag - a setting the operator can turn
        // off and which changes nothing about the registered task.
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config(restart: false));

        Assert.DoesNotContain("<RestartOnFailure>", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("<Repetition>", xml, StringComparison.Ordinal);
        Assert.Contains("<LogonTrigger>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_LiftsTheExecutionTimeLimit()
    {
        // The scheduler's default execution time limit is three days. A supervised daemon under
        // that default is killed on day three by the thing supervising it, and nothing reports it.
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(Config());

        Assert.Contains("<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_CarriesTheExecutableAndThePort()
    {
        var config = Config();
        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(config);

        Assert.Contains($"<Command>{config.ExecutablePath}</Command>", xml, StringComparison.Ordinal);
        Assert.Contains("<Arguments>--port 8890</Arguments>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Xml_EscapesAPathThatWouldOtherwiseBreakTheDocument()
    {
        var config = new DaemonLifecycleConfig(
            DaemonSupervisionKind.LogonTask, 8890, @"C:\a & b\router<x>.exe", true, 60);

        var xml = Supervisor(new FakeTaskSchedulerCli()).BuildTaskXml(config);

        Assert.Contains("C:\\a &amp; b\\router&lt;x&gt;.exe", xml, StringComparison.Ordinal);
        // And it still parses, which is the assertion the escaping is actually for: an unescaped
        // ampersand produces a document schtasks refuses with a message about XML rather than
        // about the path, and the operator's install path is not something this code chooses.
        var parsed = LogonTaskSupervisor.ParseState(xml);
        Assert.Equal(@"C:\a & b\router<x>.exe", parsed.Command);
    }

    // ------------------------------------------------------------------ the refusal

    [Theory]
    [InlineData(DaemonSupervisionKind.StartupShortcut)]
    [InlineData(DaemonSupervisionKind.InAppSupervised)]
    public void Register_RefusesAModeThisTreeDoesNotImplement(DaemonSupervisionKind mode)
    {
        var cli = new FakeTaskSchedulerCli();

        // The refusal is the honest answer while StartupShortcut and InAppSupervised are still
        // models with no writer and no supervisor behind them. Registering a logon task for either
        // would make the shell report a supervision mode the operator did not choose, and the
        // registration would look correct from every angle except the one that matters.
        Assert.Throws<ArgumentException>(() => Supervisor(cli).Register(Config(mode: mode)));
        Assert.Empty(cli.Calls);
    }

    // ------------------------------------------------------------------ the argv

    [Fact]
    public void Register_AsksSchtasksToCreateFromXmlAndReplaceWhatIsThere()
    {
        var cli = new FakeTaskSchedulerCli();

        Supervisor(cli).Register(Config());

        var argv = cli.LastCall;
        Assert.Equal("/Create", argv[0]);
        Assert.Equal("/TN", argv[1]);
        Assert.Equal(TaskName, argv[2]);
        Assert.Equal("/XML", argv[3]);
        Assert.Contains("/F", argv);

        // /XML rather than /SC ONLOGON, and this assertion is the one that keeps it that way. The
        // flag form cannot express RestartOnFailure at all, so a supervisor that drifted back to it
        // would register a task that starts the daemon once and never notices it died - under a
        // description that promises the opposite.
        Assert.DoesNotContain("/SC", argv);
    }

    [Fact]
    public void Unregister_DeletesByNameWithoutPrompting()
    {
        var cli = new FakeTaskSchedulerCli();

        Supervisor(cli).Unregister();

        Assert.Equal(new[] { "/Delete", "/TN", TaskName, "/F" }, cli.LastCall);
    }

    [Fact]
    public void Query_AsksForThatOneTasksXml()
    {
        var cli = new FakeTaskSchedulerCli().Replies(new TaskCliResult(0, SchedulerXml(), ""));

        Supervisor(cli).Query();

        Assert.Equal(new[] { "/Query", "/TN", TaskName, "/XML", "ONE" }, cli.LastCall);
    }

    // ------------------------------------------------------------------ reading the answer back

    [Fact]
    public void Query_ReportsWhatTheSchedulerHolds()
    {
        var cli = new FakeTaskSchedulerCli().Replies(new TaskCliResult(0, SchedulerXml(), ""));

        var state = Supervisor(cli).Query();

        Assert.True(state.Registered);
        Assert.Equal(@"C:\Program Files\MCP Router\mcp-router.exe", state.Command);
        Assert.Equal("--port 8890", state.Arguments);
        Assert.True(state.HasLogonTrigger);
        Assert.Equal("LeastPrivilege", state.RunLevel);
        Assert.Equal("InteractiveToken", state.LogonType);
        Assert.Equal(3, state.RestartCount);
        Assert.Equal("PT1M", state.RestartInterval);
        Assert.Equal("PT1M", state.RepetitionInterval);
        Assert.True(state.Enabled);
        Assert.True(state.MatchesLogonTaskClaim);
    }

    [Fact]
    public void Query_ReadsAUtf16DocumentWithAByteOrderMark()
    {
        // schtasks /Query /XML emits UTF-16LE with a mark. A reader that assumed UTF-8 would hand
        // the parser a leading U+FEFF and get an XmlException, which ParseState turns into Absent -
        // so the whole lane would report a registered task as missing, and the caller's remedy for
        // a missing task is to register it again.
        var cli = new FakeTaskSchedulerCli().Replies(new TaskCliResult(0, "\uFEFF" + SchedulerXml(), ""));

        Assert.True(Supervisor(cli).Query().Registered);
    }

    [Fact]
    public void Query_ReportsAbsentWhenTheSchedulerSaysThereIsNoSuchTask()
    {
        var cli = new FakeTaskSchedulerCli()
            .Replies(new TaskCliResult(1, "", "ERROR: The system cannot find the file specified."));

        Assert.Equal(LogonTaskState.Absent, Supervisor(cli).Query());
    }

    [Fact]
    public void Query_ThrowsWhenTheFailureIsNotAnAbsence()
    {
        // Access denied is not "not registered", and reporting it as such is the failure mode this
        // test exists for: the caller is told the task is missing, registers it again, is denied
        // again, and nothing in the loop ever names the permission problem.
        var cli = new FakeTaskSchedulerCli()
            .Replies(new TaskCliResult(5, "", "ERROR: Access is denied."));

        var thrown = Assert.Throws<InvalidOperationException>(() => Supervisor(cli).Query());
        Assert.Contains("Access is denied", thrown.Message, StringComparison.Ordinal);
    }

    // ------------------------------------------------------------------ the claim predicate

    [Theory]
    [InlineData("HighestAvailable", 3, true, false, "elevated, which the description denies")]
    [InlineData("LeastPrivilege", 0, true, false, "no restart, which the description promises")]
    [InlineData("LeastPrivilege", 3, false, false, "disabled, so it will never fire")]
    [InlineData("LeastPrivilege", 3, true, true, "all three claims held")]
    public void MatchesLogonTaskClaim_ReadsEveryClaimTheDescriptionMakes(
        string runLevel, int restartCount, bool enabled, bool expected, string why)
    {
        var state = new LogonTaskState(
            Registered: true, Command: "x.exe", Arguments: "--port 1", HasLogonTrigger: true,
            RunLevel: runLevel, LogonType: "InteractiveToken", RestartCount: restartCount,
            RestartInterval: "PT1M", Enabled: enabled, RepetitionInterval: "PT1M");

        Assert.True(state.MatchesLogonTaskClaim == expected, why);
    }

    [Fact]
    public void MatchesLogonTaskClaim_RejectsATaskWithNoLogonTrigger()
    {
        // Registered, un-elevated, restarting, enabled - and scheduled at 3am rather than at
        // logon. Every other term is satisfied, which is what makes this the term worth its own
        // test rather than a row in the table above.
        var state = new LogonTaskState(
            Registered: true, Command: "x.exe", Arguments: "--port 1", HasLogonTrigger: false,
            RunLevel: "LeastPrivilege", LogonType: "InteractiveToken", RestartCount: 3,
            RestartInterval: "PT1M", Enabled: true, RepetitionInterval: "PT1M");

        Assert.False(state.MatchesLogonTaskClaim);
    }

    [Fact]
    public void MatchesLogonTaskClaim_RejectsATaskThatCarriesRestartOnFailureAndNothingElse()
    {
        // THIS IS THE SHAPE THE PRODUCT SHIPPED UNTIL 2026-09-03, and it satisfied every other
        // term: registered, at logon, un-elevated, enabled, RestartCount 3. It was registered for
        // real, started, and its process was killed, and the Windows task scheduler never brought
        // it back - scripts/windows/win23-restart-witness.ps1 is the lane that watched it, and its
        // arming mode still points at this document and still goes red.
        //
        // So this row is not a hypothetical. It is the exact registration the operator was told
        // restarts on crash, and the reason the predicate above needed a sixth term.
        var state = new LogonTaskState(
            Registered: true, Command: "x.exe", Arguments: "--port 1", HasLogonTrigger: true,
            RunLevel: "LeastPrivilege", LogonType: "InteractiveToken", RestartCount: 3,
            RestartInterval: "PT1M", Enabled: true, RepetitionInterval: null);

        Assert.False(state.MatchesLogonTaskClaim);
    }

    [Fact]
    public void ParseState_TreatsAnOmittedEnabledElementAsEnabled()
    {
        // The schema's default is true. Reading the omission as false is the safe-LOOKING error
        // and the wrong one: it reports a perfectly good registration as broken, and the caller's
        // remedy is to re-register a task that is already correct.
        var xml = SchedulerXml().Replace("    <Enabled>true</Enabled>\n", "");

        Assert.True(LogonTaskSupervisor.ParseState(xml).Enabled);
    }

    [Fact]
    public void ParseState_ReportsAbsentRatherThanThrowingOnRubbish()
    {
        Assert.Equal(LogonTaskState.Absent, LogonTaskSupervisor.ParseState("not xml at all"));
        Assert.Equal(LogonTaskState.Absent, LogonTaskSupervisor.ParseState(""));
    }

    [Fact]
    public void BuildTaskXml_RoundTripsThroughParseState()
    {
        // The two halves of this file meet here. Everything above asserts what the builder writes
        // or what the parser reads; this asserts they agree, so a rename on one side that leaves
        // the other reading nothing cannot pass both suites by passing each half separately.
        var supervisor = Supervisor(new FakeTaskSchedulerCli());
        var state = LogonTaskSupervisor.ParseState(supervisor.BuildTaskXml(Config()));

        Assert.True(state.MatchesLogonTaskClaim);
        Assert.Equal("--port 8890", state.Arguments);
        Assert.Equal("PT60S", state.RestartInterval);
        Assert.Equal("PT60S", state.RepetitionInterval);
    }

    // ------------------------------------------------------------------ the decoder

    [Fact]
    public void DecodeByMark_ReadsEachEncodingSchtasksEmits()
    {
        const string subject = "<Task>ok</Task>";
        var utf16 = new List<byte> { 0xFF, 0xFE };
        utf16.AddRange(System.Text.Encoding.Unicode.GetBytes(subject));
        var utf8Bom = new List<byte> { 0xEF, 0xBB, 0xBF };
        utf8Bom.AddRange(System.Text.Encoding.UTF8.GetBytes(subject));

        Assert.Equal(subject, SchtasksCli.DecodeByMark(utf16.ToArray()));
        Assert.Equal(subject, SchtasksCli.DecodeByMark(utf8Bom.ToArray()));
        Assert.Equal(subject, SchtasksCli.DecodeByMark(System.Text.Encoding.UTF8.GetBytes(subject)));
    }

    /// <summary>A document in the shape the real scheduler returns, not the shape we write.</summary>
    /// <remarks>
    /// Deliberately NOT BuildTaskXml's output: the scheduler normalises what it is given - it
    /// rewrites PT60S as PT1M, reorders nothing but adds defaults - so a parser tested only against
    /// this project's own writer is a parser tested against half the inputs it will meet. The one
    /// test that does use the writer's output says so and is about the round trip.
    /// </remarks>
    private static string SchedulerXml() =>
        "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n"
        + "<Task version=\"1.4\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\n"
        + "  <RegistrationInfo>\n"
        + "    <Date>2026-09-02T11:00:00</Date>\n"
        + "    <Author>TESTHOST\\operator</Author>\n"
        + "    <URI>\\MCPRouter\\Test Daemon</URI>\n"
        + "  </RegistrationInfo>\n"
        + "  <Triggers>\n"
        + "    <LogonTrigger>\n"
        + "      <Enabled>true</Enabled>\n"
        + "      <UserId>TESTHOST\\operator</UserId>\n"
        + "      <Repetition>\n"
        + "        <Interval>PT1M</Interval>\n"
        + "        <StopAtDurationEnd>false</StopAtDurationEnd>\n"
        + "      </Repetition>\n"
        + "    </LogonTrigger>\n"
        + "  </Triggers>\n"
        + "  <Principals>\n"
        + "    <Principal id=\"Author\">\n"
        + "      <UserId>TESTHOST\\operator</UserId>\n"
        + "      <LogonType>InteractiveToken</LogonType>\n"
        + "      <RunLevel>LeastPrivilege</RunLevel>\n"
        + "    </Principal>\n"
        + "  </Principals>\n"
        + "  <Settings>\n"
        + "    <AllowStartOnDemand>true</AllowStartOnDemand>\n"
        + "    <RestartOnFailure>\n"
        + "      <Interval>PT1M</Interval>\n"
        + "      <Count>3</Count>\n"
        + "    </RestartOnFailure>\n"
        + "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n"
        + "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n"
        + "    <Enabled>true</Enabled>\n"
        + "  </Settings>\n"
        + "  <Actions Context=\"Author\">\n"
        + "    <Exec>\n"
        + "      <Command>C:\\Program Files\\MCP Router\\mcp-router.exe</Command>\n"
        + "      <Arguments>--port 8890</Arguments>\n"
        + "    </Exec>\n"
        + "  </Actions>\n"
        + "</Task>\n";
}
