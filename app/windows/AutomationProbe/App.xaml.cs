using System.Text;
using Microsoft.UI.Xaml;

namespace MCPRouter.AutomationProbe;

/// <summary>
/// WIN20's probe application.
///
/// The one thing here that is not boilerplate is that the window is shown WITHOUT activation.
/// WIN20's acceptance says the campaign must be able to enumerate a Windows surface "without
/// activating or foregrounding the window", and a probe that calls Window.Activate() at startup
/// makes that claim untestable for the first seconds of its life — the harness would be reading a
/// window that had just been given the foreground by the thing measuring it.
///
/// AppWindow.Show(activateWindow: false) maps to ShowWindow(SW_SHOWNOACTIVATE). The window is
/// mapped, laid out and drawn — which is what the tree needs — and never takes the foreground.
///
/// The startup log is not decoration. A WinExe has no console, so a probe that dies during launch
/// leaves the harness with "no top-level window found" — which is the SAME symptom as a window
/// that exists on a window station this session cannot enumerate. Those are opposite problems and
/// the log is what tells them apart.
/// </summary>
public partial class App : Application
{
    private Window? _window;

    /// <summary>
    /// Where the startup trace goes. WIN20_PROBE_LOG overrides it; otherwise it is always written,
    /// to a fixed path. An opt-in log is no use for the failure it exists to explain, because the
    /// run that crashes is usually the one nobody remembered to instrument.
    /// </summary>
    private static readonly string LogPath =
        Environment.GetEnvironmentVariable("WIN20_PROBE_LOG")
        ?? Path.Combine(Path.GetTempPath(), "win20-probe.log");

    internal static void Trace(string line)
    {
        try
        {
            File.AppendAllText(
                LogPath,
                $"{DateTime.UtcNow:O} pid={Environment.ProcessId} {line}{Environment.NewLine}",
                Encoding.UTF8);
        }
        catch
        {
            // A probe must not die because its own logging failed.
        }
    }

    public App()
    {
        UnhandledException += (_, e) =>
        {
            Trace($"UNHANDLED {e.Exception.GetType().FullName}: {e.Exception.Message}");
            Trace(e.Exception.ToString());
        };

        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            Trace($"DOMAIN-UNHANDLED {e.ExceptionObject}");
        };

        Trace("App ctor: before InitializeComponent");
        InitializeComponent();
        Trace("App ctor: after InitializeComponent");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            Trace("OnLaunched: constructing MainWindow");
            _window = new MainWindow();
            Trace("OnLaunched: MainWindow constructed");

            // Deliberately NOT _window.Activate(). See the class comment: activation is the thing
            // under test, so the probe must not perform it on its own behalf.
            _window.AppWindow.Show(activateWindow: false);
            Trace($"OnLaunched: shown without activation, hwnd={_window.AppWindow.Id.Value}");
        }
        catch (Exception ex)
        {
            Trace($"OnLaunched FAILED {ex.GetType().FullName}: {ex.Message}");
            Trace(ex.ToString());
            throw;
        }
    }
}
