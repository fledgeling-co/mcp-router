import Foundation
import MCPRouterKit

/// Every sentence the Activity board renders that is its own, held as data.
///
/// Two rules shape what is and is not in here. `DESIGN.md` §5 requires real copy for the unhappy
/// paths, because placeholder copy hides both layout and comprehension failures — so these are the
/// shipped strings and the tests compare against them rather than against a paraphrase. And §6
/// requires **one name per state**, which is why the offline, unauthorised and error wordings are
/// deliberately absent: those belong to `ControlAPIError`, which already authored them and which
/// `ControlCopyTests` already asserts. A second wording here would be a second thing to keep in
/// step, and the two would drift.
///
/// **What none of these sentences claims.** An early draft of this file said "The router has been up
/// since 09:12" and "the history below is complete up to 09:41". Neither is a fact the wire carries.
/// `UsageResponse.since` is `stats.since` in `src/usage.ts`, which `readStats()` *persists* — it
/// survives every restart and only moves when `reset()` zeroes the counter, so it is the moment the
/// counting window opened and says nothing about how long the process has been running. And there is
/// no watermark on the wire at all: the newest record's timestamp proves a record arrived, never
/// that none was missed, so a dropped stream can hide a two-minute hole the board cannot see. Every
/// sentence below is worded to claim only what those two fields actually mean.
public extension StateMessage {
    /// The same message with its offer removed.
    ///
    /// Used where the label names something a later item owns: the words stay (§6 — one wording per
    /// state, and `ControlAPIError` authored these), and the control beneath them is drawn disabled
    /// with its reason instead of enabled and inert.
    var withoutAction: StateMessage {
        StateMessage(title: title, detail: detail, actionLabel: nil)
    }
}

public enum ActivityCopy {
    /// The router answered and has recorded nothing in the current counting window.
    ///
    /// Not an error, and the brief says so explicitly. No tint, no warning icon, and **no action**.
    ///
    /// **The missing action is a recorded deviation from `DESIGN.md` §5**, which asks for "one
    /// action" on an empty state, not a rule this file is following. The reason is that the thing
    /// which fills this list is an agent making a tool call, and no control on this surface can do
    /// that: the honest options were a button that does nothing, a button that navigates to a
    /// surface which is still a placeholder in this build, or no button. `StateMessage.actionLabel`
    /// is optional for exactly this case — "nil where the state genuinely offers nothing — never a
    /// disabled placeholder button".
    public static func empty(since: String) -> StateMessage {
        StateMessage(
            title: "No calls yet",
            detail: """
            Nothing has called a tool since \(since). Servers stay asleep until an agent asks \
            for one — this list fills itself the moment that happens.
            """
        )
    }

    /// Every filter is satisfiable on its own, so this can only be reached by combining two.
    ///
    /// Deliberately different words from `empty`. "Nothing has been called yet" and "you filtered it
    /// all out" have different causes and different fixes, and one sentence for both sends the
    /// reader looking for a problem that is not there.
    ///
    /// It says what clearing the filters would restore, and nothing about what the router has ever
    /// recorded — the board holds one window of at most `ActivityRecords.capacity` records and has
    /// no way to know what fell off the end of the router's own ring before it asked.
    public static func filteredToNothing(total: Int) -> StateMessage {
        StateMessage(
            title: "No calls match these filters",
            detail: """
            That combination has nothing in it. \
            Clearing the filters shows all \(total) again.
            """,
            actionLabel: clearFilters
        )
    }

    public static let clearFilters = "Clear filters"

    /// The feed dropped and is retrying, over a history that did load.
    ///
    /// §5's partial is "say what arrived and what did not, with the reason", and this is that shape.
    /// The list stays on screen — replacing it would throw away the half that *did* arrive.
    ///
    /// **No button.** Retrying is already happening, and `ReconnectPolicy` is mid-ladder; offering
    /// "Reconnect now" here would either race the retry or do nothing. `disconnected` is the one
    /// that earns a control, which is the whole reason `StreamPhase` has three cases rather than a
    /// Bool.
    ///
    /// The timestamp is named as *the newest call here*, never as a completeness watermark.
    public static func partialReconnecting(newest: String?) -> StateMessage {
        StateMessage(
            title: "The live feed dropped. New calls won't appear until it reconnects.",
            detail: newestSentence(newest)
        )
    }

    /// The stream walked its whole retry ladder and stopped.
    ///
    /// The attempt count is deliberately absent. `ControlEventStream` yields `.phase(.disconnected)`
    /// and finishes; it never reports how many attempts it made, and the board did not construct the
    /// policy. A number here would be a default copied into a sentence, which is the same class of
    /// mistake as displaying a figure the router does not observe.
    public static func partialDisconnected(newest: String?) -> StateMessage {
        StateMessage(
            title: "The live feed stopped retrying.",
            detail: "\(newestSentence(newest)) Reconnecting reloads the history as well, "
                + "so anything that arrived while the feed was down comes back with it.",
            actionLabel: reconnect
        )
    }

    /// The feed never connected at all — the first subscription walked the ladder and gave up.
    ///
    /// Its own state rather than a reuse of `partialDisconnected`, because that sentence implies a
    /// feed that once ran. This one has nothing to have missed *yet*, and saying so is the
    /// difference between "you have a gap" and "you will not see new calls".
    public static func neverConnected() -> StateMessage {
        StateMessage(
            title: "The live feed hasn't connected.",
            detail: """
            The history below loaded, but nothing is streaming, so new calls won't appear \
            on their own.
            """,
            actionLabel: reconnect
        )
    }

    /// The backfill failed while the feed is delivering — the mirror of the partial above.
    ///
    /// A real condition with two independent sources, and one this board must not answer by
    /// replacing the pane with an error: a live subscription that is delivering rows is not nothing.
    public static func historyUnavailable(error: ControlAPIError) -> StateMessage {
        StateMessage(
            title: "Showing live calls only — the history didn't load.",
            detail: error.advice,
            actionLabel: reconnect
        )
    }

    public static let reconnect = "Reconnect now"

    /// One sentence under two controls, because they share one cause. Two copies of the same reason
    /// under two disabled controls is noise, and §3.4 asks for the reason to be discoverable rather
    /// than repeated.
    ///
    /// It says "yet" and not "since the router started": the trigger is an empty window, which after
    /// a reset or a log rotation says nothing about when the process began.
    public static let disabledFilters = """
    Filters need calls to filter. No calls have been recorded yet.
    """

    /// How a cold start is said in words, for the inspector and for a screen reader.
    ///
    /// Colour and a glyph are never the only carriers (§7's `differentiateWithoutColor`), and "cold"
    /// on its own is jargon that means nothing to someone who has not read the router's source.
    public static func startDescription(cold: Bool) -> String {
        cold
            ? "cold — this call is what started the server"
            : "warm — the server was already running"
    }

    /// The board's subtitle.
    ///
    /// Worded as **showing**, not as a total. The count is the size of the loaded window, which is
    /// capped at `ActivityRecords.capacity`; on a busy router "500 calls since 09:12" read as a
    /// total would be wrong by any margin you like. It is also deliberately *unfiltered* — the
    /// filtered pair is `filteredCount`'s `N of M`, and one number that silently changed meaning
    /// when a filter was set would put the two in an undefined relation.
    public static func subtitle(count: Int, since: String, feed: String) -> String {
        "Showing \(count) call\(count == 1 ? "" : "s") · since \(since) · \(feed)"
    }

    /// What the feed is doing, in one phrase per condition.
    public static func feedLabel(_ phase: StreamPhase?) -> String {
        switch phase {
        case .live: "live"
        case .reconnecting: "reconnecting"
        case .disconnected: "no live feed"
        case nil: "connecting"
        }
    }

    /// `9 of 28` — the only place a filtered board states what it is hiding.
    public static func filteredCount(visible: Int, total: Int) -> String {
        "\(visible) of \(total)"
    }

    /// The column headers, sentence case (§3.2), in order.
    ///
    /// Six, because the brief names six things a row shows — "session, working directory, server,
    /// tool, duration and outcome". Outcome is the mark in the gutter; the other five are columns.
    public static let columns = ["when", "server", "tool", "project", "session", "took"]

    /// A duration as the row and the inspector both write it. Milliseconds, because that is the
    /// unit the router measures in — `UsageRecord.ms` — and rounding it to seconds would discard
    /// the difference between a 14ms warm call and a 1840ms cold one, which is the comparison this
    /// column exists to make.
    public static func duration(ms: Int) -> String {
        "\(ms)ms"
    }

    /// The session, in the width a column has. The client name and the full pid are in the
    /// inspector; this is what distinguishes one agent window from another at a glance.
    public static func sessionColumn(pid: Int?) -> String {
        guard let pid else { return "—" }
        return "\(pid)"
    }

    /// The session as the inspector and the accessibility label write it, in full.
    public static func sessionFull(pid: Int?, client: String?) -> String {
        guard let pid else { return unattributed }
        guard let client, !client.isEmpty else { return "pid \(pid)" }
        return "\(client) · pid \(pid)"
    }

    /// What a record the router could not attribute is called. Read from the kit's own constant so
    /// the filter menu, the inspector and this file cannot say it three ways (§6).
    public static let unattributed = ActivityNaming.unattributed

    private static func newestSentence(_ newest: String?) -> String {
        guard let newest else { return "Nothing has arrived yet." }
        return "The newest call here is from \(newest)."
    }
}
