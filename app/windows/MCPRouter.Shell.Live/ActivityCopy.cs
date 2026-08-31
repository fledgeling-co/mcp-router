namespace MCPRouter.Shell.Live;

/// <summary>
/// Every sentence the Activity board renders that is its own, held as data.
///
/// Two rules shape what is in here. DESIGN.md §5 requires real copy for the unhappy paths, so
/// these are the shipped strings and the tests compare against them rather than a paraphrase.
/// DESIGN.md §6 requires one name per state, so where the Mac authored a sentence first its
/// words carry across unchanged, and where this build had to re-author, the comment says why.
///
/// **What none of these sentences claims.** The wire carries no completeness watermark - the
/// newest record's timestamp proves a record arrived, never that none was missed - and
/// <c>UsageSnapshot.Since</c> is the moment the counting window opened, not the router's
/// uptime. The mock's "kept for 90 days" is a figure no field on this wire supports, so no
/// sentence here carries it (spec-WIN5 §6).
/// </summary>
public static class ActivityCopy
{
    // ------------------------------------------------------------------ the board's own words

    /// <summary>The design of record's mission line, drawn under the board title
    /// (design/mcp-router-console.html:2219). The one place the product says what this surface
    /// is for, so it stays the mock's own words.</summary>
    public const string Mission =
        "Every tool call every harness made, as it happens. This is the only place that can answer \"which of my agents did that\".";

    /// <summary>What the populated board says under the log. The mock's callout claims a
    /// 90-day retention this wire does not carry; these two sentences claim only what is true
    /// of it - a local store, a recent-call window, rotation (spec-WIN5 §6).</summary>
    public const string Foot =
        "Calls are recorded locally and never leave this PC. The list shows the router's recent-call window - older calls rotate out as new ones arrive.";

    public static readonly string[] Columns = ["Time", "Harness", "Tool", "Duration", "Result"];

    /// <summary>The four filter words, in the design of record's order and its own spelling
    /// of the slow threshold.</summary>
    public static readonly string[] Filters = ["All", "Errors", "Slow (> 2 s)", "Held"];

    public const string PauseLabel = "Pause";

    public const string ResumeLabel = "Resume";

    public const string ExportLabel = "Export…";

    public const string ExportDialogTitle = "Export the visible calls";

    /// <summary>What the export dialog says it will write. The visible slice is what is on
    /// screen at the moment, window-capped - a fact the reader can check against the rows
    /// (spec-WIN5 §3.5).</summary>
    public const string ExportDialogDetail =
        "Writes the calls on screen now, in the order shown, with every column. Nothing leaves the file you choose.";

    public const string ExportJson = "JSON lines";

    public const string ExportCsv = "CSV";

    public const string ExportConfirm = "Export";

    public const string ExportCancel = "Cancel";

    public static string CallsArrivedWhilePaused(int count) => count == 1
        ? "1 call arrived while paused."
        : $"{count.ToString(System.Globalization.CultureInfo.InvariantCulture)} calls arrived while paused.";

    // ------------------------------------------------------------------ the states (spec §4)

    /// <summary>The mock's empty state, word for word, with its action - which is real here:
    /// the shell can perform that navigation.</summary>
    public const string EmptyTitle = "Nothing has called a tool yet";

    public const string EmptyDetail =
        "Start a session in any wired harness and its calls appear here within a second. The log fills itself; there is nothing to set up.";

    public const string EmptyAction = "See which harnesses are wired";

    /// <summary>The loading status under the skeleton. Never a spinner over a blank pane.</summary>
    public const string LoadingStatus = "Attaching to the event stream…";

    /// <summary>The router is not answering on the loopback port. §6's one wording per state:
    /// the Mac's <c>routerNotRunning</c> sentence, carried verbatim. Its action differs, and
    /// spec-WIN5 §3.6 records why: "Start the router" names a capability this build does not
    /// have, so the board offers the thing it can really do.</summary>
    public const string OfflineTitle = "The router isn't running";

    public const string OfflineDetail =
        "Nothing is listening on the control port, so there is nothing to show yet. Starting it takes a moment and your servers stay exactly as you left them.";

    public const string ReconnectLabel = "Reconnect";

    /// <summary>The disconnected state's action, named as the thing it does: reconnecting
    /// reloads the history as well, so the action is doing more than re-subscribing (spec §4).</summary>
    public const string ReconnectNowLabel = "Reconnect now";

    /// <summary>The feed dropped and the ladder is mid-climb, over a history that did load.
    /// Mac wording, carried. No button: retrying is already happening.</summary>
    public const string PartialReconnectingTitle =
        "The live feed dropped. New calls won't appear until it reconnects.";

    /// <summary>The ladder was walked to its top. The one disconnected phase that earns a
    /// button, and the button's sentence promises what reconnecting really does.</summary>
    public const string DisconnectedTitle = "The live feed stopped retrying.";

    public const string NeverConnectedTitle = "The live feed hasn't connected.";

    public const string NeverConnectedDetail =
        "The history below loaded, but nothing is streaming, so new calls won't appear on their own.";

    /// <summary>Every filter is satisfiable on its own, so reaching this takes a combination -
    /// deliberately different words from the empty state, whose cause and fix are different
    /// (Mac wording, carried).</summary>
    public const string FilteredTitle = "No calls match these filters";

    public const string ClearFiltersLabel = "Clear filters";

    /// <summary>The held filter's own honest sentence. Nothing on this wire produces a held
    /// call; the tab exists because the design of record names it, and this is what it says
    /// when it matches nothing (spec-WIN5 §3.2's recorded deviation, drawn).</summary>
    public const string HeldNothingTitle = "No held calls";

    public const string HeldNothingDetail =
        "The router holds tool-surface changes for review, not calls, so nothing matches this filter yet.";

    // ------------------------------------------------------------------ composed sentences

    /// <summary>The board's subtitle. Worded as SHOWING, never as a total: the window is
    /// capped at <see cref="ActivityModel.Capacity"/>, and on a busy router "500 calls" read
    /// as a total would be wrong by any margin you like (Mac reasoning, carried).</summary>
    public static string Subtitle(int count, string feedLabel) =>
        $"Showing {count.ToString(System.Globalization.CultureInfo.InvariantCulture)} " +
        (count == 1 ? "call" : "calls") + $" · {feedLabel}";

    /// <summary>The only place a filtered board states what it is hiding.</summary>
    public static string FilteredCount(int visible, int total) =>
        $"{visible.ToString(System.Globalization.CultureInfo.InvariantCulture)} of " +
        $"{total.ToString(System.Globalization.CultureInfo.InvariantCulture)}";

    public static string NewestSentence(string? newestTs) => newestTs is null
        ? "Nothing has arrived yet."
        : $"The newest call here is from {newestTs}.";

    public static string DisconnectedDetail(string? newestTs) =>
        $"{NewestSentence(newestTs)} Reconnecting reloads the history as well, so anything that arrived while the feed was down comes back with it.";

    public static string FilteredDetail(int total) =>
        $"That combination has nothing in it. Clearing the filters shows all " +
        $"{total.ToString(System.Globalization.CultureInfo.InvariantCulture)} again.";

    /// <summary>What the feed is doing, in one phrase per phase, for the subtitle.</summary>
    public static string FeedLabel(StreamPhase? phase, bool paused) => paused
        ? "paused"
        : phase switch
        {
            StreamPhase.Live => "live",
            StreamPhase.Reconnecting => "reconnecting",
            StreamPhase.Disconnected => "no live feed",
            _ => "connecting",
        };
}
