using MCPRouter.Shell.Model.Diagnostics;
using Microsoft.UI.Dispatching;

namespace MCPRouter.Shell.Shell;

/// <summary>
/// The one way this shell posts work to a DispatcherQueue - DEF-085.
///
/// <c>DispatcherQueue.TryEnqueue</c> is not banned by anything the compiler enforces, so this type
/// is a convention rather than a wall; what it buys is that every posting site names itself and
/// routes its failure to the startup log instead of taking the process down without a line.
/// <see cref="DispatcherGuard"/> holds the part with no WinUI in it, and the tests exercise that.
/// </summary>
internal static class GuardedDispatch
{
    /// <summary>
    /// Post <paramref name="work"/>, with a failure inside it reported against
    /// <paramref name="site"/> rather than escaping into the queue.
    /// </summary>
    /// <returns>What <c>TryEnqueue</c> returned: false means the queue refused the work, which is
    /// a different failure from the work throwing and is left to the caller.</returns>
    internal static bool TryEnqueueGuarded(this DispatcherQueue queue, string site, Action work) =>
        queue.TryEnqueue(new DispatcherQueueHandler(
            DispatcherGuard.Guard(site, work, App.ReportDispatcherFailure)));

    /// <summary>The awaiting form, for a handler that would otherwise be <c>async void</c>.</summary>
    internal static Func<Task> GuardedAsync(string site, Func<Task> work) =>
        DispatcherGuard.GuardAsync(site, work, App.ReportDispatcherFailure);
}
