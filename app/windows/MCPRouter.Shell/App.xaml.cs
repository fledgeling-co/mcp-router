using System.Diagnostics;
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

    public App()
    {
        InitializeComponent();

        UnhandledException += (_, e) =>
        {
            // A stowed exception with no record is how a WinUI process becomes "it just exits".
            // Writing it beside the executable costs nothing and is the only trace a session that
            // cannot see the desktop will ever have.
            StartupLog.Write($"unhandled: {e.Message}\n{e.Exception}");
            if (SelfTestDirectory is not null)
            {
                // In self-test the exception is the result, so fail loudly rather than limping on.
                Environment.Exit(70);
            }
        };

        // The XAML handler above is NOT enough, and DEF-079 is the proof: sixteen launches on
        // 2026-09-02 wrote not one `unhandled:` line, including eight in which selecting Skills
        // terminated the process with exception code 0xC000027B - which is by definition an
        // unhandled exception. A stowed exception surfacing below the managed dispatch boundary,
        // and a fault on a thread-pool thread, both reach neither this event nor the log, so the
        // log's silence has been reading as "no exception occurred" when it meant "nothing was
        // recorded". These two cover the gap.
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            StartupLog.Write($"unhandled (appdomain, terminating={e.IsTerminating}): {e.ExceptionObject}");

        // An `async void` handler whose exception nobody observes faults its task and is collected
        // silently. SkillsBoard.OnLoaded is exactly that shape.
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            StartupLog.Write($"unobserved task exception: {e.Exception}");
            e.SetObserved();
        };
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
