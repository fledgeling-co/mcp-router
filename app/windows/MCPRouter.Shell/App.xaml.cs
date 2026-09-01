using System.Diagnostics;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Shell;
using Microsoft.UI.Xaml;

namespace MCPRouter.Shell;

public partial class App : Application
{
    private ShellWindow? _window;

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
        _window.Activate();
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
