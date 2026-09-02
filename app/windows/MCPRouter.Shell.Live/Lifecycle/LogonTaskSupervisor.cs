using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security;
using System.Text;
using System.Xml.Linq;
using MCPRouter.Shell.Model.Lifecycle;

namespace MCPRouter.Shell.Live.Lifecycle;

/// <summary>What the Windows task scheduler actually holds for the daemon's logon task.</summary>
/// <remarks>
/// Every field here is READ BACK OUT OF THE SCHEDULER'S OWN XML, never carried over from the
/// config that asked for the registration. That distinction is the whole point of the type: a
/// Query that returned its caller's intent would report success whenever the caller had intended
/// success, which is precisely the shape DEF-074 found - a supervision "mode" that was a switch
/// statement returning the sentence describing itself.
/// </remarks>
public sealed record LogonTaskState(
    bool Registered,
    string? Command,
    string? Arguments,
    bool HasLogonTrigger,
    string? RunLevel,
    string? LogonType,
    int RestartCount,
    string? RestartInterval,
    bool Enabled,
    // Last and defaulted so that adding it did not have to touch every construction site, which
    // would have made a behavioural change look like a mechanical one in review.
    string? RepetitionInterval = null)
{
    public static LogonTaskState Absent { get; } =
        new(false, null, null, false, null, null, 0, null, false, null);

    /// <summary>Whether the scheduler holds what DaemonSupervisionKind.LogonTask claims.</summary>
    /// <remarks>
    /// The claim being checked is the one LifecyclePresentation.ModeDescription prints to the
    /// operator - "Scheduled Task at user logon (restarts on crash, un-elevated)" - broken into
    /// the facts it asserts. Any of them false and the sentence is a lie the UI is telling, so all
    /// of them are read rather than the presence of the task alone. A task that exists and runs
    /// elevated on a schedule satisfies "registered" and satisfies none of what the operator was
    /// told.
    ///
    /// RepetitionInterval is a term of this predicate and RestartCount is not enough on its own,
    /// because MEASUREMENT said so. A task carrying RestartOnFailure and nothing else was started,
    /// its process was killed, and the Windows task scheduler never brought it back - watched for
    /// 150 seconds against a 60-second interval, on both scheduling engines, for a trigger-started
    /// run and an on-demand one. RestartOnFailure governs a task that fails to LAUNCH; the
    /// repetition is what covers one that launched and then died. A predicate that read
    /// RestartCount alone would report "restarts on crash" as satisfied by a registration this
    /// repository has watched fail to do it.
    /// </remarks>
    public bool MatchesLogonTaskClaim =>
        Registered
        && HasLogonTrigger
        && string.Equals(RunLevel, "LeastPrivilege", StringComparison.Ordinal)
        && RestartCount > 0
        && !string.IsNullOrWhiteSpace(RepetitionInterval)
        && Enabled;
}

/// <summary>
/// Registers, queries and removes the router daemon's user-logon scheduled task, through
/// schtasks.exe and the Task Scheduler's own XML.
/// </summary>
/// <remarks>
/// WHY THIS EXISTS. WIN23 shipped DaemonSupervisionKind.LogonTask, a description reading
/// "Scheduled Task at user logon (restarts on crash, un-elevated)", and a test asserting that the
/// description contains a substring of itself. No line of it registered anything: TaskService,
/// schtasks, ServiceBase and StartupTask appeared nowhere outside two unrelated harness scripts.
/// DEF-074 recorded the gap and named the two honest ways out - implement the registration with a
/// case at the effect-witness rung whose recorder is the Windows task scheduler itself, or record
/// the item as a supervision MODEL awaiting an implementer. This is the first.
///
/// THE THREE CLAIMS AND WHERE EACH LANDS IN THE XML, because a supervisor that registers *a* task
/// is not a supervisor that registers the one the operator was promised:
///
///   "at user logon"      -> a LogonTrigger carrying the principal's own UserId. NOT a BootTrigger,
///                           which fires before the user session exists, and the daemon must run IN
///                           that session - LifecyclePresentation.UserSessionRequirement says why:
///                           local browser instances for OAuth and per-user harness configuration.
///   "restarts on crash"  -> a Repetition on the trigger PLUS RestartOnFailure, because MEASUREMENT
///                           showed the second one alone does not do what its name says. Neither
///                           can be expressed through schtasks' flag form, which is why
///                           registration goes through /XML rather than /SC ONLOGON.
///
///                           MEASURED 2026-09-03 on the reference machine, four registrations, each
///                           started and then killed, with the scheduler read back through
///                           Get-ScheduledTaskInfo and the process table read through CIM:
///
///                             RestartOnFailure alone, run started by a trigger, action process
///                             killed  ->  LastTaskResult became 0xFFFFFFFF and the daemon was
///                             NEVER restarted. Watched for 150 seconds against a 60-second
///                             interval and a count of 3. Same with the legacy scheduling engine,
///                             and same for an on-demand start.
///
///                             RestartOnFailure alone, action that could not be LAUNCHED at all -
///                             a Command naming a file that does not exist  ->  restarted three
///                             times at 60-second intervals, exactly as configured.
///
///                           So RestartOnFailure governs a task that FAILS TO START and says
///                           nothing about an action that started and later died, which is the only
///                           case "restarts on crash" was ever about. It is kept, because the
///                           launch-failure case is real and nothing else covers it.
///
///                           The repetition is what covers the crash. The trigger re-fires every
///                           interval for as long as the session lasts; MultipleInstancesPolicy
///                           IgnoreNew makes the scheduler discard a re-fire while the daemon is
///                           alive - LastTaskResult 0x8004131F, "an instance is already running" -
///                           and start it again once it is not. Measured the same day: killed at
///                           03:04:2x, a new process at 03:04:37, and the repetitions after that
///                           refused as duplicates for as long as it lived.
///
///                           WHAT IT COSTS, said here because it is not free: the scheduler
///                           evaluates the trigger once a minute for the life of the session, and
///                           the daemon can be down for up to one whole interval before it comes
///                           back. Restarting within a second needs a supervising process, which is
///                           the InAppSupervised model this tree does not implement.
///   "un-elevated"        -> RunLevel LeastPrivilege, with LogonType InteractiveToken. The default
///                           for a task created by an elevated caller is HighestAvailable, so this
///                           is a thing to set and not a thing to leave alone.
///
/// WHAT THIS CLASS CANNOT ESTABLISH. That the scheduler accepted the XML, that the trigger fires at
/// logon, or that a killed daemon comes back. The first is measured by
/// scripts/windows/win23-logon-task-witness.ps1, which registers for real and reads the result back
/// through the Task Scheduler WMI provider rather than through schtasks. The THIRD is measured by
/// scripts/windows/win23-restart-witness.ps1, which starts a real process under a real trigger,
/// kills it, and watches the scheduler bring it back. That lane is where the repetition above came
/// from: it went red against the RestartOnFailure-only document this method used to write, and the
/// same lane's arming mode still points at that document and still goes red. The SECOND is measured
/// nowhere - proving the trigger fires at logon needs a logon - and DEF-081 carries it rather than
/// it being closed on the strength of the registration being right.
/// </remarks>
public sealed class LogonTaskSupervisor
{
    public const string DefaultTaskName = @"\MCPRouter\Router Daemon (logon)";

    private const string TaskNs = "http://schemas.microsoft.com/windows/2004/02/mit/task";

    private readonly ITaskSchedulerCli _cli;
    private readonly string _taskName;
    private readonly string _userId;

    /// <param name="cli">The schtasks seam. A fake here reads the argv; the real one mutates the machine.</param>
    /// <param name="taskName">
    /// Injectable so the witness lane can register under a name of its own. Without that the
    /// witness would have to delete and recreate the operator's real registration to prove
    /// anything, which is a lane that breaks the thing it measures.
    /// </param>
    /// <param name="userId">
    /// Defaults to the running user. Passed explicitly by the tests, because a principal derived
    /// from the environment makes the generated XML differ per machine, and the assertions over it
    /// would then be assertions about this machine.
    /// </param>
    public LogonTaskSupervisor(ITaskSchedulerCli cli, string? taskName = null, string? userId = null)
    {
        _cli = cli ?? throw new ArgumentNullException(nameof(cli));
        _taskName = string.IsNullOrWhiteSpace(taskName) ? DefaultTaskName : taskName!;
        _userId = string.IsNullOrWhiteSpace(userId) ? CurrentUserId() : userId!;
    }

    public string TaskName => _taskName;

    public string UserId => _userId;

    private static string CurrentUserId()
    {
        var domain = Environment.UserDomainName;
        var user = Environment.UserName;
        return string.IsNullOrEmpty(domain) ? user : domain + "\\" + user;
    }

    // ------------------------------------------------------------------ the XML

    /// <summary>Build the Task Scheduler document that carries all three of the mode's claims.</summary>
    /// <remarks>
    /// ELEMENT ORDER IS LOAD-BEARING. taskSchedulerSchema declares Settings as an ordered sequence,
    /// so a document with the right elements in the wrong order is refused with a message about the
    /// element rather than about the order. That refusal is a good failure - it happens at
    /// registration, loudly - but it is a failure only the real scheduler can report, which is
    /// another reason the witness lane is not optional.
    /// </remarks>
    public string BuildTaskXml(DaemonLifecycleConfig config)
    {
        if (config is null)
        {
            throw new ArgumentNullException(nameof(config));
        }
        if (config.Mode != DaemonSupervisionKind.LogonTask)
        {
            // Refused rather than silently registered. StartupShortcut and InAppSupervised are
            // still MODELS - there is no shortcut writer and no in-process supervisor in this tree
            // - and quietly registering a logon task for them would make the shell report a
            // supervision mode the operator did not choose.
            throw new ArgumentException(
                $"LogonTaskSupervisor registers {nameof(DaemonSupervisionKind.LogonTask)} only; "
                + $"'{config.Mode}' has no implementation in this tree and must not be registered "
                + "as something else.",
                nameof(config));
        }

        var restartSeconds = Math.Max(config.RestartDelaySeconds, 1);

        // The scheduler refuses a repetition interval under a minute, so 60 is a floor rather than
        // a preference. It is kept separate from restartSeconds deliberately: a caller asking for a
        // 5-second restart delay gets a 5-second RestartOnFailure interval, which is honoured for
        // the launch-failure case, and a 60-second repetition, which is the fastest the crash case
        // can be covered at all. Rounding both to the same number would hide that difference.
        var repetitionSeconds = Math.Max(restartSeconds, 60);
        var user = Escape(_userId);
        var command = Escape(config.ExecutablePath);
        var arguments = Escape(ArgumentsFor(config));

        // THE REPETITION IS THE PART THAT ACTUALLY RESTARTS A CRASHED DAEMON. It is emitted only
        // when the config asks for supervision, for the same reason RestartOnFailure is: an
        // operator who turns supervision off must get a task that genuinely does not come back.
        // It sits after UserId because that is the document the scheduler was measured to accept
        // and to honour - element order inside a trigger is schema-checked, and a wrong one is
        // refused at registration rather than quietly ignored.
        var repetition = config.RestartOnCrash
            ? "      <Repetition>\n"
              + $"        <Interval>PT{repetitionSeconds.ToString(CultureInfo.InvariantCulture)}S</Interval>\n"
              + "        <StopAtDurationEnd>false</StopAtDurationEnd>\n"
              + "      </Repetition>\n"
            : string.Empty;

        // RestartOnFailure is emitted on the same condition, and covers a different failure: a task
        // the scheduler could not LAUNCH at all. Measured, it does nothing whatever for an action
        // that started and later died, which is why it is no longer alone up there.
        var restart = config.RestartOnCrash
            ? "    <RestartOnFailure>\n"
              + $"      <Interval>PT{restartSeconds.ToString(CultureInfo.InvariantCulture)}S</Interval>\n"
              + "      <Count>3</Count>\n"
              + "    </RestartOnFailure>\n"
            : string.Empty;

        var builder = new StringBuilder();
        builder.Append("<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n");
        builder.Append($"<Task version=\"1.4\" xmlns=\"{TaskNs}\">\n");
        builder.Append("  <RegistrationInfo>\n");
        builder.Append("    <Description>MCP Router daemon, started at user logon so it shares the "
                       + "session that owns the browser and the per-user harness configuration."
                       + "</Description>\n");
        builder.Append($"    <URI>{Escape(_taskName)}</URI>\n");
        builder.Append("  </RegistrationInfo>\n");
        builder.Append("  <Triggers>\n");
        builder.Append("    <LogonTrigger>\n");
        builder.Append("      <Enabled>true</Enabled>\n");
        builder.Append($"      <UserId>{user}</UserId>\n");
        builder.Append(repetition);
        builder.Append("    </LogonTrigger>\n");
        builder.Append("  </Triggers>\n");
        builder.Append("  <Principals>\n");
        builder.Append("    <Principal id=\"Author\">\n");
        builder.Append($"      <UserId>{user}</UserId>\n");
        builder.Append("      <LogonType>InteractiveToken</LogonType>\n");
        builder.Append("      <RunLevel>LeastPrivilege</RunLevel>\n");
        builder.Append("    </Principal>\n");
        builder.Append("  </Principals>\n");
        builder.Append("  <Settings>\n");
        builder.Append("    <AllowStartOnDemand>true</AllowStartOnDemand>\n");
        builder.Append(restart);
        builder.Append("    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n");
        builder.Append("    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n");
        builder.Append("    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n");
        builder.Append("    <AllowHardTerminate>true</AllowHardTerminate>\n");
        builder.Append("    <StartWhenAvailable>false</StartWhenAvailable>\n");
        builder.Append("    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\n");
        builder.Append("    <WakeToRun>false</WakeToRun>\n");
        // PT0S is the scheduler's spelling of "no limit". A daemon supervised by a task with the
        // DEFAULT three-day execution limit is killed on day three, which is a supervision model
        // that stops supervising and says nothing.
        builder.Append("    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n");
        builder.Append("    <Priority>7</Priority>\n");
        builder.Append("    <RunOnlyIfIdle>false</RunOnlyIfIdle>\n");
        builder.Append("    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>\n");
        builder.Append("    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>\n");
        builder.Append("    <IdleSettings>\n");
        builder.Append("      <StopOnIdleEnd>false</StopOnIdleEnd>\n");
        builder.Append("      <RestartOnIdle>false</RestartOnIdle>\n");
        builder.Append("    </IdleSettings>\n");
        builder.Append("    <Enabled>true</Enabled>\n");
        builder.Append("    <Hidden>false</Hidden>\n");
        builder.Append("  </Settings>\n");
        builder.Append("  <Actions Context=\"Author\">\n");
        builder.Append("    <Exec>\n");
        builder.Append($"      <Command>{command}</Command>\n");
        builder.Append($"      <Arguments>{arguments}</Arguments>\n");
        builder.Append("    </Exec>\n");
        builder.Append("  </Actions>\n");
        builder.Append("</Task>\n");
        return builder.ToString();
    }

    public static string ArgumentsFor(DaemonLifecycleConfig config) =>
        "--port " + config.Port.ToString(CultureInfo.InvariantCulture);

    private static string Escape(string value) => SecurityElement.Escape(value) ?? string.Empty;

    // ------------------------------------------------------------------ the three operations

    /// <summary>Write the task, replacing any existing registration under the same name.</summary>
    /// <remarks>
    /// The XML goes through a file rather than stdin because schtasks /Create /XML takes a path and
    /// has no stdin form. It is written UTF-16LE WITH A BOM: schtasks reads the file with the same
    /// mark-sniffing rule everything else on Windows uses, and a BOM-less UTF-8 document containing
    /// any non-ASCII character - a user name with an accent, a path under a localised Program Files
    /// - is decoded as the ANSI code page and refused. That is the same cp1252 trap that cost this
    /// repository a scheduled-task run once already; scripts/windows/ps-parse-gate.py is the gate
    /// standing over the other half of it.
    /// </remarks>
    public TaskCliResult Register(DaemonLifecycleConfig config)
    {
        var xml = BuildTaskXml(config);
        var path = Path.Combine(Path.GetTempPath(),
            "mcprouter-logon-task-" + Guid.NewGuid().ToString("N") + ".xml");
        try
        {
            File.WriteAllText(path, xml, new UnicodeEncoding(false, true));
            return _cli.Run(new[] { "/Create", "/TN", _taskName, "/XML", path, "/F" });
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
                // A temp file outliving the call is not a failure of the registration, and
                // throwing here would turn a successful register into a reported failure.
            }
        }
    }

    public TaskCliResult Unregister() =>
        _cli.Run(new[] { "/Delete", "/TN", _taskName, "/F" });

    /// <summary>Read back what the SCHEDULER holds, parsed from its own XML.</summary>
    /// <remarks>
    /// A non-zero exit is reported as Absent ONLY when the scheduler says the task does not exist.
    /// Any other failure throws, because the alternative - treating an access-denied or a malformed
    /// response as "not registered" - makes every error look like the answer the caller was most
    /// likely hoping to act on, and the caller's next move is to register it again.
    /// </remarks>
    public LogonTaskState Query()
    {
        var result = _cli.Run(new[] { "/Query", "/TN", _taskName, "/XML", "ONE" });
        if (!result.Succeeded)
        {
            var text = result.StandardError + result.StandardOutput;
            if (SaysAbsent(text))
            {
                return LogonTaskState.Absent;
            }
            throw new InvalidOperationException(
                $"schtasks /Query for '{_taskName}' exited {result.ExitCode} and did not say the "
                + $"task was absent: {text.Trim()}");
        }
        return ParseState(result.StandardOutput);
    }

    /// <summary>Whether schtasks' refusal means "no such task" rather than something else.</summary>
    /// <remarks>
    /// Matched on the message because schtasks exits 1 for both "no such task" and "the XML is
    /// invalid", so the exit code cannot separate them. The phrases are the ones the English
    /// scheduler emits; on a localised Windows none of them match and the query THROWS rather than
    /// reporting absence, which is the correct direction to be wrong in - a caller that is told
    /// "this failed and here is what it said" can act, and one told "not registered" registers
    /// again.
    /// </remarks>
    internal static bool SaysAbsent(string text) =>
        text.IndexOf("cannot find the file", StringComparison.OrdinalIgnoreCase) >= 0
        || text.IndexOf("does not exist", StringComparison.OrdinalIgnoreCase) >= 0
        || text.IndexOf("The system cannot find", StringComparison.OrdinalIgnoreCase) >= 0;

    /// <summary>Parse the scheduler's task XML into the facts the mode's description claims.</summary>
    public static LogonTaskState ParseState(string xml)
    {
        if (string.IsNullOrWhiteSpace(xml))
        {
            return LogonTaskState.Absent;
        }

        XDocument document;
        try
        {
            document = XDocument.Parse(xml.TrimStart('﻿', ' ', '\r', '\n', '\t'));
        }
        catch (System.Xml.XmlException)
        {
            return LogonTaskState.Absent;
        }
        var root = document.Root;
        if (root is null)
        {
            return LogonTaskState.Absent;
        }
        var ns = root.Name.Namespace;

        string? Value(XElement? parent, string name) =>
            parent?.Element(ns + name)?.Value?.Trim();

        var exec = root.Element(ns + "Actions")?.Element(ns + "Exec");
        var principal = root.Element(ns + "Principals")?.Elements(ns + "Principal").FirstOrDefault();
        var settings = root.Element(ns + "Settings");
        var restart = settings?.Element(ns + "RestartOnFailure");
        var logonTrigger = root.Element(ns + "Triggers")?.Elements(ns + "LogonTrigger").FirstOrDefault();
        var hasLogon = logonTrigger is not null;
        var repetitionInterval = Value(logonTrigger?.Element(ns + "Repetition"), "Interval");

        var count = 0;
        var countText = Value(restart, "Count");
        if (countText is not null)
        {
            int.TryParse(countText, NumberStyles.Integer, CultureInfo.InvariantCulture, out count);
        }

        // A Settings/Enabled the scheduler omitted means enabled - the schema's default is true.
        // Reading a missing element as false would report every task written by a producer that
        // relies on the default as disabled, which is the safe-LOOKING direction and the wrong one:
        // it makes MatchesLogonTaskClaim false for a registration that is perfectly fine, and the
        // caller's remedy for that is to re-register a task that already exists.
        var enabledText = Value(settings, "Enabled");
        var enabled = enabledText is null
            || string.Equals(enabledText, "true", StringComparison.OrdinalIgnoreCase);

        return new LogonTaskState(
            Registered: true,
            Command: Value(exec, "Command"),
            Arguments: Value(exec, "Arguments"),
            HasLogonTrigger: hasLogon,
            RunLevel: Value(principal, "RunLevel"),
            LogonType: Value(principal, "LogonType"),
            RestartCount: count,
            RestartInterval: Value(restart, "Interval"),
            Enabled: enabled,
            RepetitionInterval: repetitionInterval);
    }
}
