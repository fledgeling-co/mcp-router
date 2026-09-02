namespace MCPRouter.Shell.Model.Diagnostics;

/// <summary>
/// Wraps a callback that will run on a DispatcherQueue so that an exception escaping it is
/// RECORDED rather than lost.
///
/// WHY THIS EXISTS - DEF-085. A callback posted with <c>DispatcherQueue.TryEnqueue</c> runs below
/// the XAML framework's own dispatch, so an exception escaping it reaches neither
/// <c>Microsoft.UI.Xaml.Application.UnhandledException</c> (the throw is not inside XAML's
/// dispatch) nor <c>AppDomain.CurrentDomain.UnhandledException</c> in a way that leaves a line
/// (the process is gone), nor <c>TaskScheduler.UnobservedTaskException</c> (there is no task).
/// Measured: scripts/windows/win-shell-unhandled-witness.ps1 ran the same binary, in the same run,
/// through all four routes; three wrote the line naming their handler and this one wrote nothing
/// at all. The shell simply vanished, leaving a log indistinguishable from a clean run - which is
/// the exact inversion DEF-079 was raised about, arriving by a route DEF-079's fix does not cover.
///
/// WHAT IT DOES ABOUT IT. The failure is caught at the site that owns it, reported through the
/// caller's sink with a marker no other line carries, and then DELIBERATELY SWALLOWED. That choice
/// is the argument, so it is written down rather than assumed: every call this shell posts to a
/// DispatcherQueue is a continuation marshalling work back to the UI thread - a toast activation
/// routing to a destination, a stream record landing in a list, a backfill applying to a model.
/// Letting one of those take the whole window down is what the unguarded code already did, and it
/// did it silently. Reporting and continuing keeps the window, and the report is what makes the
/// failure visible to a session that cannot see the desktop. A caller that genuinely cannot
/// continue past its callback's failure should say so in the callback rather than by throwing out
/// of it.
///
/// This type is deliberately in the WinUI-free model assembly and takes no DispatcherQueue: it is
/// the part that a test with no display can run, and MCPRouter.Shell.Tests does.
/// </summary>
public static class DispatcherGuard
{
    /// <summary>
    /// The prefix every reported line carries. It shares <c>unhandled:</c> with the three
    /// top-level handlers so one search finds all four routes, and adds <c>[dispatcher</c> so this
    /// route is distinguishable from them - the witness lane greps for exactly this.
    /// </summary>
    public const string Marker = "unhandled: [dispatcher";

    /// <summary>
    /// The line a failed callback produces: the marker, the site that owns the callback, and the
    /// exception with its stack. The site is in the line because a bare stack from a dispatcher
    /// callback names the queue rather than the code that posted to it.
    /// </summary>
    public static string Format(string site, Exception error)
    {
        ArgumentNullException.ThrowIfNull(error);
        return $"{Marker} site={site}] {error.GetType().FullName}: {error.Message}"
            + $"{Environment.NewLine}{error}";
    }

    /// <summary>
    /// The callback to post, with the reporting wrapped around it.
    /// </summary>
    /// <param name="site">Who posted it - a stable name, not a message.</param>
    /// <param name="work">The callback.</param>
    /// <param name="report">Where the line goes. In the shell this is the startup log.</param>
    public static Action Guard(string site, Action work, Action<string> report)
    {
        ArgumentNullException.ThrowIfNull(work);
        ArgumentNullException.ThrowIfNull(report);
        return () =>
        {
            try
            {
                work();
            }
            catch (Exception error)
            {
                Report(site, error, report);
            }
        };
    }

    /// <summary>
    /// The same for a callback that awaits. An <c>async void</c> handler on a dispatcher timer
    /// faults a task nobody awaits, so its exception surfaces - if at all - only when a collection
    /// runs the finalizer, which is a second way for a failure to arrive too late to mean
    /// anything. Wrapping it reports at the moment it happens.
    /// </summary>
    public static Func<Task> GuardAsync(string site, Func<Task> work, Action<string> report)
    {
        ArgumentNullException.ThrowIfNull(work);
        ArgumentNullException.ThrowIfNull(report);
        return async () =>
        {
            try
            {
                await work().ConfigureAwait(true);
            }
            catch (Exception error)
            {
                Report(site, error, report);
            }
        };
    }

    /// <summary>
    /// A sink that itself throws must not replace the failure it was handed with its own. The
    /// original is what the reader needs, and a logging fault is not worth the window.
    /// </summary>
    private static void Report(string site, Exception error, Action<string> report)
    {
        try
        {
            report(Format(site, error));
        }
        catch (Exception)
        {
            // Nothing to fall back to: the sink IS the fallback.
        }
    }
}
