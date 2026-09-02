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
    bool Enabled)
{
    public static LogonTaskState Absent { get; } =
        new(false, null, null, false, null, null, 0, null, false);

    /// <summary>Whether the scheduler holds what DaemonSupervisionKind.LogonTask claims.</summary>
    /// <remarks>
    /// The claim being checked is the one LifecyclePresentation.ModeDescription prints to the
    /// operator - "Scheduled Task at user logon (restarts on crash, un-elevated)" - broken into
    /// the facts it asserts. Any of them false and the sentence is a lie the UI is telling, so all
    /// of them are read rather than the presence of the task alone. A task that exists and runs
    /// elevated on a schedule satisfies "registered" and satisfies none of what the operator was
    /// told.
    /// </remarks>
    public bool MatchesLogonTaskClaim =>
        Registered
        && HasLogonTrigger
        && string.Equals(RunLevel, "LeastPrivilege", StringComparison.Ordinal)
        && RestartCount > 0
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
///   "restarts on crash"  -> RestartOnFailure with an interval and a count. This is the one that
///                           cannot be expressed through schtasks' flag form at all, and it is why
///                           registration goes through /XML rather than /SC ONLOGON. A flag-form
///                           registration would have shipped a task that starts the daemon once and
///                           never notices it died, under a description promising the opposite.
///   "un-elevated"        -> RunLevel LeastPrivilege, with LogonType InteractiveToken. The default
///                           for a task created by an elevated caller is HighestAvailable, so this
///                           is a thing to set and not a thing to leave alone.
///
/// WHAT THIS CLASS CANNOT ESTABLISH. That the scheduler accepted the XML, that the trigger fires,
/// or that a killed daemon comes back. The first is measured by the effect-witness lane
/// (scripts/windows/win23-logon-task-witness.ps1), which registers for real and reads the result
/// back through the Task Scheduler WMI provider rather than through schtasks. The second and third
/// are not measured anywhere yet, and DEF-074 stays open against them rather than being closed on
/// the strength of this file existing.
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
        var user = Escape(_userId);
        var command = Escape(config.ExecutablePath);
        var arguments = Escape(ArgumentsFor(config));

        // RestartOnFailure is emitted only when the config asks for it, so a config declaring
        // RestartOnCrash false produces a task that genuinely does not restart. The alternative -
        // always emitting it - would make the flag decorative, and a decorative flag on a
        // supervision setting is the same defect one layer down.
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
        var hasLogon = root.Element(ns + "Triggers")?.Elements(ns + "LogonTrigger").Any() == true;

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
            Enabled: enabled);
    }
}
