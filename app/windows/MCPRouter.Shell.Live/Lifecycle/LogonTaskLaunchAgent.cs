using System;
using System.IO;
using MCPRouter.Shell.Model.Lifecycle;
using MCPRouter.Shell.Model.Registry;
using MCPRouter.Shell.Model.Settings;

namespace MCPRouter.Shell.Live.Lifecycle;

/// <summary>
/// "Launch router daemon at sign-in", carried to the Windows task scheduler.
///
/// DEF-087: the switch moved a boolean. <see cref="LogonTaskSupervisor"/> had been able to
/// register and remove the task since WIN23 and nothing on the Settings board called it, so a user
/// who turned the setting off was told something untrue. This is the wire between them.
/// </summary>
/// <remarks>
/// WHAT IT REFUSES TO GUESS. A logon task needs an executable to run, and this app does not ship
/// the daemon. Rather than register a task pointing at a path that may not exist - which produces
/// a scheduled task that fails silently every sign-in, under a switch reporting success - the
/// agent resolves the daemon and reports itself UNAVAILABLE, with the reason, when it cannot. The
/// board then disables the switch and shows the sentence.
///
/// THE TASK NAME IS OVERRIDABLE, for the same reason
/// <c>scripts/windows/win23-logon-task-witness.ps1</c> takes one: a lane that proved this switch
/// worked by registering and deleting the operator's real daemon task would break the thing it
/// measures. <c>shell-lane.ps1</c> sets <see cref="TaskNameVariable"/> before it launches the
/// shell, so the arm drives the shipped code path against a name of the lane's own.
/// </remarks>
public sealed class LogonTaskLaunchAgent : ILaunchAtLoginAgent
{
    /// <summary>Where the daemon executable is, when it is not on PATH.</summary>
    public const string ExecutableVariable = "MCPROUTER_DAEMON_PATH";

    /// <summary>The task name to register under. Set by the witness lane, never by the product.</summary>
    public const string TaskNameVariable = "MCPROUTER_LOGON_TASK_NAME";

    private const string DaemonExecutableName = "mcp-router.exe";

    private readonly LogonTaskSupervisor? _supervisor;
    private readonly DaemonLifecycleConfig? _config;

    public LogonTaskLaunchAgent(
        ITaskSchedulerCli? cli = null,
        string? executablePath = null,
        string? taskName = null)
    {
        // Passed explicitly by the suite and resolved from the environment by the product. The
        // suite must not steer resolution by mutating process-wide environment variables: xunit
        // runs test classes in parallel and PATH is shared, so one test's teardown races another
        // test's setup and the failure lands somewhere else entirely.
        // Null means "resolve it the way the product does"; the empty string means "there is
        // none", which is how the suite reaches the unavailable path without emptying PATH for
        // every other test in the process.
        var executable = executablePath is null
            ? ResolveExecutable()
            : (executablePath.Length == 0 ? null : executablePath);
        if (executable is null)
        {
            UnavailableReason =
                "Unavailable: no router daemon executable was found on PATH or at "
                + ExecutableVariable + ", so there is nothing to register at sign-in. "
                + "Install the router, or set " + ExecutableVariable + " to its path.";
            return;
        }

        var name = taskName ?? Environment.GetEnvironmentVariable(TaskNameVariable);
        _supervisor = new LogonTaskSupervisor(cli ?? new SchtasksCli(), name);
        _config = new DaemonLifecycleConfig(
            DaemonSupervisionKind.LogonTask,
            ControlEndpoint.Port(),
            executable,
            RestartOnCrash: true,
            RestartDelaySeconds: 60);
    }

    public string? UnavailableReason { get; }

    public string? TaskName => _supervisor?.TaskName;

    private static string? ResolveExecutable()
    {
        var configured = Environment.GetEnvironmentVariable(ExecutableVariable);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            // Taken as given rather than probed for existence. The witness lane points this at a
            // path that deliberately does not exist, so that a read-back showing a different
            // Execute is comparing this run's registration against somebody else's task under the
            // same name - the same trick win23-logon-task-witness.ps1 plays.
            return configured;
        }

        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path))
        {
            return null;
        }

        foreach (var directory in path!.Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(directory))
            {
                continue;
            }
            try
            {
                var candidate = Path.Combine(directory.Trim(), DaemonExecutableName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch (ArgumentException)
            {
                // A PATH entry with invalid characters is not a reason to stop looking at the rest.
            }
        }
        return null;
    }

    /// <inheritdoc />
    public bool? CurrentlyRegistered()
    {
        if (_supervisor is null)
        {
            return null;
        }
        try
        {
            return _supervisor.Query().Registered;
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException)
        {
            // Null and not false. Query throws when the scheduler refused for a reason other than
            // "no such task", and reporting that as "not registered" is how a caller is led to
            // register something that is already there.
            return null;
        }
    }

    /// <inheritdoc />
    public ToggleEffectResult Apply(bool enabled)
    {
        if (_supervisor is null || _config is null)
        {
            return ToggleEffectResult.Unavailable(UnavailableReason ?? "no logon-task agent");
        }

        try
        {
            var result = enabled ? _supervisor.Register(_config) : _supervisor.Unregister();
            if (result.Succeeded)
            {
                return new ToggleEffectResult(
                    ToggleEffectOutcome.Applied,
                    (enabled ? "Registered " : "Removed ") + _supervisor.TaskName
                    + " in the Windows task scheduler.");
            }

            // Removing a task that is not there is the requested end state, not a failure. Every
            // other non-zero exit is reported with the scheduler's own words rather than reduced
            // to "it did not work".
            var text = result.StandardError + result.StandardOutput;
            if (!enabled && LogonTaskSupervisor.SaysAbsent(text))
            {
                return new ToggleEffectResult(
                    ToggleEffectOutcome.Applied,
                    "No sign-in task was registered, so there was nothing to remove.");
            }

            return new ToggleEffectResult(
                ToggleEffectOutcome.Failed,
                "The task scheduler refused, exit " + result.ExitCode + ": " + text.Trim());
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return new ToggleEffectResult(ToggleEffectOutcome.Failed, ex.Message);
        }
    }
}
