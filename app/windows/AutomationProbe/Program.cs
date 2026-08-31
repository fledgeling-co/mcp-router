using System.Text;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace MCPRouter.AutomationProbe;

/// <summary>
/// The probe's own entry point, replacing the one the XAML compiler generates
/// (DISABLE_XAML_GENERATED_MAIN in the csproj).
///
/// The generated Main has no error handling, so a WinUI startup failure in an unpackaged app
/// leaves nothing but STATUS_STOWED_EXCEPTION (0xC000027B) in the event log — a code that names
/// the category of failure and nothing about the cause. That is the same "a not-run and a failure
/// look identical from outside" problem this repository's gates are built around, one layer down,
/// and the harness inherits it: a probe that dies at startup and a window on an unreachable window
/// station both present to the UIA lane as "no top-level window found".
///
/// So this Main catches, writes the exception, and exits with a code the lane can read.
/// </summary>
public static class Program
{
    /// <summary>Exit code for "the probe could not start" — distinct from a crash mid-run.</summary>
    private const int ExitStartupFailed = 70;

    [STAThread]
    public static int Main(string[] args)
    {
        App.Trace($"Program.Main entered, args=[{string.Join(" ", args)}]");

        try
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            App.Trace("ComWrappers initialised");

            Application.Start(p =>
            {
                var context = new DispatcherQueueSynchronizationContext(
                    DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App();
            });

            App.Trace("Application.Start returned");
            return 0;
        }
        catch (Exception ex)
        {
            App.Trace($"STARTUP FAILED {ex.GetType().FullName}: {ex.Message}");
            App.Trace(ex.ToString());

            if (ex is System.Runtime.InteropServices.COMException com)
            {
                App.Trace($"HRESULT 0x{com.HResult:X8}");
            }

            return ExitStartupFailed;
        }
    }
}
