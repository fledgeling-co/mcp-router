using System.Diagnostics;
using System.Runtime.CompilerServices;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Shell;
using Microsoft.UI.Xaml;

namespace MCPRouter.Shell;

public partial class App : Application
{
    private ShellWindow? _window;
    private Notifications.ToastNotifier? _toasts;

    /// <summary>
    /// Where the self-test writes, when <c>--selftest &lt;dir&gt;</c> was passed. Null for a
    /// normal launch.
    /// </summary>
    internal static string? SelfTestDirectory { get; private set; }

    /// <summary>
    /// Debug-only opt-in to the populated board fixture. The live client remains the default;
    /// the fixture is not a fallback, because a release build must never claim router data it did
    /// not read.
    /// </summary>
    internal static bool UseSkillsFixture { get; private set; }

    /// <summary>
    /// `--fault &lt;kind&gt;`: which escape route this launch is to take, or null for every launch
    /// that did not ask for one. Read once in the constructor because two handlers consult it.
    /// </summary>
    internal static string? FaultKind { get; private set; }

    /// <summary>
    /// `--fault-unregister &lt;handler&gt;`: the arming switch, and the ONLY thing in this file
    /// that can leave a top-level handler unregistered.
    /// </summary>
    /// <remarks>
    /// It exists so scripts/windows/win-shell-unhandled-witness.ps1 can plant a defect the product
    /// can genuinely have - one handler never attached - and require that handler's arm, and only
    /// that handler's arm, to break. Without it the three EFFECT arms could be reading lines some
    /// other handler wrote.
    /// </remarks>
    private static string? _suppressedHandler;

    public App()
    {
        InitializeComponent();

        // Read before any handler is attached: the arming switch decides which ones are.
        var bootArgv = Environment.GetCommandLineArgs();
        FaultKind = ValueAfter(bootArgv, FaultFlag);
#if DEBUG
        _suppressedHandler = ValueAfter(bootArgv, FaultUnregisterFlag);
#endif

        if (!IsSuppressed("xaml"))
        {
            UnhandledException += (_, e) =>
            {
                // A stowed exception with no record is how a WinUI process becomes "it just exits".
                // Writing it beside the executable costs nothing and is the only trace a session that
                // cannot see the desktop will ever have.
                StartupLog.Write($"unhandled: [xaml] {e.Message}\n{e.Exception}");
                if (SelfTestDirectory is not null)
                {
                    // In self-test the exception is the result, so fail loudly rather than limping on.
                    Environment.Exit(70);
                }
                ExitAfterInjectedFault(71);
            };
        }

        // The XAML handler above is NOT enough, and DEF-079 is the proof: sixteen launches on
        // 2026-09-02 wrote not one `unhandled:` line, including eight in which selecting Skills
        // terminated the process with exception code 0xC000027B - which is by definition an
        // unhandled exception. A stowed exception surfacing below the managed dispatch boundary,
        // and a fault on a thread-pool thread, both reach neither this event nor the log, so the
        // log's silence has been reading as "no exception occurred" when it meant "nothing was
        // recorded". These two cover the gap.
        if (!IsSuppressed("appdomain"))
        {
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            {
                StartupLog.Write($"unhandled: [appdomain terminating={e.IsTerminating}] {e.ExceptionObject}");
                ExitAfterInjectedFault(72);
            };
        }

        // An `async void` handler whose exception nobody observes faults its task and is collected
        // silently. SkillsBoard.OnLoaded is exactly that shape.
        if (!IsSuppressed("task"))
        {
            TaskScheduler.UnobservedTaskException += (_, e) =>
            {
                StartupLog.Write($"unhandled: [unobserved-task] {e.Exception}");
                e.SetObserved();
            };
        }

        // The writer's own account of which handlers it attached. It is NOT the witness's evidence
        // - the witness grades the lines the handlers wrote, read out of the log by another process
        // - but an arming run that suppressed nothing would otherwise be indistinguishable from one
        // that did.
        StartupLog.Write($"handlers: xaml={!IsSuppressed("xaml")}, appdomain={!IsSuppressed("appdomain")}, "
            + $"unobserved-task={!IsSuppressed("task")}, fault={FaultKind ?? "(none)"}");
    }

    private static bool IsSuppressed(string handler) =>
        string.Equals(_suppressedHandler, handler, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Ends a launch that asked for a fault, once its handler has written its line.
    /// </summary>
    /// <remarks>
    /// Only ever reached on a launch that passed <c>--fault</c>. A normal crash is left to behave
    /// exactly as it always has; this exists because the witness runs the shell through a scheduled
    /// task on a station nobody can see, and a Windows Error Reporting dialog behind an unhandled
    /// exception there would hang the lane on a window with no one to dismiss it.
    /// </remarks>
    private static void ExitAfterInjectedFault(int code)
    {
        if (FaultKind is not null)
        {
            Environment.Exit(code);
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var argv = Environment.GetCommandLineArgs();
        SelfTestDirectory = ReadSelfTestDirectory(argv);
#if DEBUG
        UseSkillsFixture = HasFlag(argv, "--fixture-skills");
#endif
        StartupLog.Write($"launched, selftest={SelfTestDirectory ?? "(no)"}, skills-fixture={UseSkillsFixture}");

        _window = new ShellWindow(UseSkillsFixture ? new FixtureSkillsControlClient() : null);

        // WIN22. Registered at launch rather than on first use, because the registration is what
        // makes a toast raised LATER able to activate this application at all - and because the
        // registration is the only part of the notification path an instrument on this host can
        // witness. A false here is logged and the window still opens: a shell that refused to run
        // because notifications could not be registered would trade a missing convenience for a
        // missing application.
        _toasts = new Notifications.ToastNotifier(OnToastInvoked);
        StartupLog.Write($"toast registration: {(_toasts.Register() ? "registered" : "FAILED")}");

        _window.Activate();

        if (HasFlag(argv, ToastProbeFlag))
        {
            RunToastProbe(argv);
        }

        // Last, and only when asked for by name. Everything above has already happened, so the
        // fault reaches a shell that is fully up rather than one still assembling itself.
        if (FaultKind is not null)
        {
            InjectFault(FaultKind);
        }
    }

    /// <summary>Where a toast click lands: the Inbox, which is the review sheet.</summary>
    /// <remarks>
    /// THIS METHOD IS THE CLAIM WIN22 MAKES. The toast says an item is waiting for review and
    /// offers a Review button; if pressing it did not select the destination that holds the item,
    /// the notification would be an announcement rather than a route. `Dismiss` deliberately does
    /// nothing here - the toast leaves the Action Center on activation, which IS the dismissal, and
    /// a Dismiss that also navigated would drag the operator into the app they just declined to
    /// open.
    /// </remarks>
    private void OnToastInvoked(MCPRouter.Shell.Model.Notifications.ToastInvocation invocation)
    {
        if (invocation.Action != MCPRouter.Shell.Model.Notifications.ToastActionKind.OpenReviewSheet)
        {
            return;
        }
        _window?.DispatcherQueue.TryEnqueue(() =>
        {
            _window.Activate();
            _window.SelectDestination(MCPRouter.Shell.Model.DestinationCatalog.InboxId);
        });
    }

    /// <summary>
    /// `--toast-probe &lt;dir&gt;`: raise one toast and write what the platform said about it.
    /// </summary>
    /// <remarks>
    /// Exists for scripts/windows/win22-toast-witness.ps1, which cannot press a button on a
    /// notification and must not pretend it did. What this writes is this side's account - "the
    /// platform accepted a Show" - and the witness treats it as exactly that: the file the WITNESS
    /// grades is the registry, written by the notification platform and read back by a different
    /// API, and this one is recorded beside it as the writer's own report rather than as evidence.
    /// </remarks>
    private void RunToastProbe(IReadOnlyList<string> argv)
    {
        var directory = ValueAfter(argv, ToastProbeFlag)
            ?? throw new ArgumentException($"{ToastProbeFlag} needs a directory to write to");
        Directory.CreateDirectory(directory);

        var payload = MCPRouter.Shell.Model.Notifications.NotificationPresentation.ForQueuedItem(
            "postgres-mcp", "win22-toast-witness", "postgres-mcp");
        var shown = _toasts is not null && _toasts.Show(payload);

        File.WriteAllText(Path.Combine(directory, "toast-probe.json"),
            "{\n"
            + $"  \"appUserModelId\": \"{Notifications.ToastNotifier.AppUserModelId}\",\n"
            + $"  \"executable\": {System.Text.Json.JsonSerializer.Serialize(Environment.ProcessPath ?? "")},\n"
            + $"  \"registered\": {(_toasts is not null).ToString().ToLowerInvariant()},\n"
            + $"  \"showAccepted\": {shown.ToString().ToLowerInvariant()},\n"
            + "  \"whatThisIs\": \"the writer's own account of raising one toast. It is NOT the "
            + "witness: nothing here reads the Action Center, and this process cannot see whether "
            + "the notification was drawn. The graded evidence is the registry the platform wrote.\"\n"
            + "}\n");
        StartupLog.Write($"toast probe: shown={shown}, wrote {directory}");
    }

    internal const string ToastProbeFlag = "--toast-probe";

    /// <summary>
    /// `--fault &lt;ui|appdomain|task&gt;`: take one deliberate escape route so the top-level
    /// handler that catches it writes its line, and a witness in another process can read that line
    /// back out of shell-startup.log.
    /// </summary>
    /// <remarks>
    /// WHY THIS EXISTS. DEF-079 is not a bug in a handler; it is a handler nobody has seen fire.
    /// Sixteen launches wrote no `unhandled:` line including eight that terminated at 0xC000027B,
    /// and the two handlers added in response were registered and then never observed catching
    /// anything, because every exception since has been caught at a site that logs it directly.
    /// A registered handler is a claim; a handler observed writing its line is a measurement, and
    /// closing DEF-079 on the first would repeat the error DEF-079 records.
    ///
    /// It is INERT unless `--fault` is passed with a kind, and it is compiled out entirely outside
    /// DEBUG, so no shipped launch can reach any of these paths however it is started.
    /// </remarks>
    internal const string FaultFlag = "--fault";

    /// <summary>`--fault-unregister &lt;xaml|appdomain|task&gt;`: see <see cref="_suppressedHandler"/>.</summary>
    internal const string FaultUnregisterFlag = "--fault-unregister";

    private void InjectFault(string kind)
    {
#if DEBUG
        StartupLog.Write($"fault: injecting {kind}");
        switch (kind.ToLowerInvariant())
        {
            case "ui":
                // Thrown on the UI thread, synchronously, inside XAML's own dispatch of
                // OnLaunched. That is the route Microsoft.UI.Xaml.Application.UnhandledException
                // exists for.
                throw new InvalidOperationException("DEF-079 fault injection: unhandled on the UI thread");

            case "dispatcher":
                // The same thread, reached a different way: a callback posted to the
                // DispatcherQueue and running after OnLaunched returned. Kept as its own kind
                // because it does NOT behave like the case above - see DEF-085.
                _window!.DispatcherQueue.TryEnqueue(
                    () => throw new InvalidOperationException("DEF-079 fault injection: unhandled in a DispatcherQueue callback"));
                break;

            case "appdomain":
                // A dedicated foreground thread rather than the pool: a pool thread's escape is a
                // faulted task, which is the OTHER handler's route.
                new Thread(() => throw new InvalidOperationException(
                    "DEF-079 fault injection: unhandled on a non-UI thread")).Start();
                break;

            case "task":
                new Thread(RaiseUnobservedTaskFault).Start();
                break;

            default:
                StartupLog.Write($"fault: unknown kind '{kind}' - nothing injected");
                break;
        }
#else
        // Said out loud rather than ignored: a witness that got silence here would read a build
        // without fault injection as a handler that failed to fire.
        StartupLog.Write($"fault: refused, this build has no fault injection compiled in (kind '{kind}')");
#endif
    }

#if DEBUG
    /// <summary>
    /// Faults a task nobody awaits and then drops every reference to it, off the UI thread so the
    /// sleeps below do not stall the message loop.
    /// </summary>
    private static void RaiseUnobservedTaskFault()
    {
        FaultATaskNobodyObserves();
        Thread.Sleep(500);
        // TaskScheduler.UnobservedTaskException is raised from the task's finalizer, so the
        // collection is the trigger and not a tidy-up after it.
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        Thread.Sleep(500);
        StartupLog.Write("fault: unobserved-task injection complete");
        // This route does not terminate the process the way the other two do, and the shell would
        // otherwise sit on an unwatched station until the lane's cleanup found it.
        Environment.Exit(73);
    }

    /// <summary>
    /// Its own method, not inlined: a Debug build keeps a local alive to the end of the frame that
    /// declared it, so a task faulted inline would still be rooted when the collection ran.
    /// </summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void FaultATaskNobodyObserves()
    {
        _ = Task.Run(() => throw new InvalidOperationException(
            "DEF-079 fault injection: faulted task nobody awaits"));
    }
#endif


    private static string? ValueAfter(IReadOnlyList<string> argv, string flag)
    {
        for (var i = 0; i < argv.Count; i++)
        {
            if (!string.Equals(argv[i], flag, StringComparison.OrdinalIgnoreCase)) continue;
            if (i + 1 >= argv.Count || argv[i + 1].StartsWith("--", StringComparison.Ordinal))
            {
                return null;
            }
            return argv[i + 1];
        }
        return null;
    }

    /// <summary>
    /// Parses <c>--selftest &lt;dir&gt;</c>. Returns null when the switch is absent, and throws
    /// when it is present without a directory - a self-test that quietly degrades into a normal
    /// launch would report a pass for a run that measured nothing.
    /// </summary>
    internal static string? ReadSelfTestDirectory(IReadOnlyList<string> argv)
    {
        for (var i = 0; i < argv.Count; i++)
        {
            if (!string.Equals(argv[i], "--selftest", StringComparison.OrdinalIgnoreCase)) continue;

            if (i + 1 >= argv.Count || argv[i + 1].StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException("--selftest needs a directory to write to");
            }

            return argv[i + 1];
        }

        return null;
    }

    private static bool HasFlag(IReadOnlyList<string> argv, string flag) =>
        argv.Any(argument => string.Equals(argument, flag, StringComparison.OrdinalIgnoreCase));
}

/// <summary>
/// A file beside the executable that records how far startup got.
///
/// This exists because of a measurement rather than a habit: on the reference machine the agent
/// session runs in Session 0 on a non-interactive window station, and a WinUI process started
/// from there dies at <c>0xC000027B</c> inside <c>Microsoft.UI.Xaml.dll</c> <b>before the App
/// constructor runs</b>. An exit code alone cannot tell that apart from a clean early exit, and
/// the difference is the whole question of whether the shell works.
/// </summary>
internal static class StartupLog
{
    private static readonly string Path =
        System.IO.Path.Combine(AppContext.BaseDirectory, "shell-startup.log");

    internal static void Write(string message)
    {
        try
        {
            File.AppendAllText(Path,
                $"{DateTime.Now:HH:mm:ss.fff} {message}{Environment.NewLine}");
        }
        catch (IOException)
        {
            Debug.WriteLine(message);
        }
    }
}
