using System.Diagnostics;
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
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        SelfTestDirectory = ReadSelfTestDirectory(Environment.GetCommandLineArgs());
        StartupLog.Write($"launched, selftest={SelfTestDirectory ?? "(no)"}");

        _window = new ShellWindow();
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
