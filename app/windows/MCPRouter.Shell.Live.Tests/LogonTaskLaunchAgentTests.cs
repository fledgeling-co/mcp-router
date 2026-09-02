using System;
using System.Linq;
using MCPRouter.Shell.Live.Lifecycle;
using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// DEF-087: the wire between the Settings board's sign-in switch and the logon task WIN23 already
/// knew how to register.
/// </summary>
/// <remarks>
/// The assertions here are about the ARGV the agent sends, read off a fake schtasks, and about
/// the refusals it declines to guess at. They are not evidence that the Windows task scheduler
/// accepted anything; <c>scripts/windows/uia/shell-lane.ps1</c>'s launch-at-sign-in arm is, and
/// its recorder is Get-ScheduledTask rather than the code under test.
///
/// Every case passes the executable and the task name as ARGUMENTS. The product resolves them from
/// the environment, and a suite that arranged itself by setting environment variables would be
/// mutating process-wide state that xunit's parallel classes share.
/// </remarks>
public sealed class LogonTaskLaunchAgentTests
{
    private const string Exe = @"C:\MCPRouter\mcp-router.exe";
    private const string Task = @"\MCPRouter\Agent Test (transient)";

    [Fact]
    public void TurningItOn_RegistersUnderTheConfiguredTaskName()
    {
        var cli = new FakeTaskSchedulerCli();
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        var result = agent.Apply(true);

        Assert.True(result.Applied);
        var call = cli.Calls.Single();
        Assert.Equal("/Create", call[0]);
        Assert.Equal("/TN", call[1]);
        Assert.Equal(Task, call[2]);
    }

    [Fact]
    public void TurningItOff_Unregisters()
    {
        var cli = new FakeTaskSchedulerCli();
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        var result = agent.Apply(false);

        Assert.True(result.Applied);
        Assert.Equal(new[] { "/Delete", "/TN", Task, "/F" }, cli.Calls.Single());
    }

    [Fact]
    public void TurningItOff_WhenNothingIsRegistered_IsTheRequestedEndStateRatherThanAFailure()
    {
        var cli = new FakeTaskSchedulerCli().Replies(
            new TaskCliResult(1, "", "ERROR: The system cannot find the file specified."));
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        Assert.True(agent.Apply(false).Applied);
    }

    [Fact]
    public void ARefusalIsReportedRatherThanSwallowed()
    {
        var cli = new FakeTaskSchedulerCli().Replies(new TaskCliResult(5, "", "ERROR: Access is denied."));
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        var result = agent.Apply(true);

        Assert.Equal(ToggleEffectOutcome.Failed, result.Outcome);
        Assert.Contains("Access is denied", result.Detail);
    }

    [Fact]
    public void WithNoDaemonExecutable_TheSettingIsUnavailableRatherThanRegisteredAtAGuess()
    {
        // Registering a task that points at a path nobody installed produces a sign-in failure
        // every morning under a switch that reported success. The honest answer is to say the
        // setting cannot act, and why.
        var cli = new FakeTaskSchedulerCli();
        var agent = new LogonTaskLaunchAgent(cli, executablePath: "", taskName: Task);

        Assert.NotNull(agent.UnavailableReason);
        Assert.StartsWith("Unavailable:", agent.UnavailableReason);
        Assert.Equal(ToggleEffectOutcome.Unavailable, agent.Apply(true).Outcome);
        Assert.Empty(cli.Calls);
        Assert.Null(agent.CurrentlyRegistered());
    }

    [Fact]
    public void AnUnreadableSchedulerReportsNullRatherThanNotRegistered()
    {
        var cli = new FakeTaskSchedulerCli().Replies(new TaskCliResult(5, "", "ERROR: Access is denied."));
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        // Null, not false: "the scheduler could not be asked" and "the scheduler says no" send the
        // board to different places, and merging them is how a user is shown a switch that is off
        // over a task that exists.
        Assert.Null(agent.CurrentlyRegistered());
    }

    [Fact]
    public void AnAbsentTaskReadsAsNotRegistered()
    {
        var cli = new FakeTaskSchedulerCli().Replies(
            new TaskCliResult(1, "", "ERROR: The system cannot find the file specified."));
        var agent = new LogonTaskLaunchAgent(cli, Exe, Task);

        Assert.False(agent.CurrentlyRegistered());
    }
}
