import Foundation

/// The Cleanup pane's decisions: who is a candidate, how much the router actually knows, and every
/// sentence the pane says about either.
///
/// **Two rules the brief learned the hard way, and neither is negotiable here.** There is no trash
/// metaphor — a never-used server was never deleted, so nothing here is "rubbish" and nothing is
/// tallied as reclaimed. And there is no automatic cull: an invocation count conflates "unused
/// because worthless" with "unused because rare but critical", so this pane proposes and the human
/// decides.
public enum CleanupPresentation {
    // MARK: - Candidacy

    /// Whether a subject belongs in the proposal, or whether the judgement is suspended.
    ///
    /// Three cases rather than a `Bool`, and the third is the whole of the Partial state. `heldOut`
    /// means the router could not read somewhere the subject might be, so proposing it would be a
    /// claim built on a lookup that never happened.
    public enum Candidacy: Equatable, Sendable {
        case candidate(reason: String)
        case notACandidate
        case heldOut(reason: String)

        public var isCandidate: Bool {
            if case .candidate = self { return true }
            return false
        }

        public var isHeldOut: Bool {
            if case .heldOut = self { return true }
            return false
        }
    }

    /// A server is proposed when nobody has called it over the recorded window, when the router
    /// cannot start it, or when it starts and offers nothing.
    ///
    /// **`usage.calls`, never `callsServed`.** `MCPServer` carries both: `callsServed` is this router
    /// process's lifetime tally, `usage.calls` is the resettable recorded window that `since`
    /// describes. Every sentence on this pane is scoped to that window, so it is the only field
    /// consistent with what the pane says — a server whose history was reset genuinely has no
    /// recorded calls over the window being described.
    ///
    /// **No time threshold anywhere.** "Last used a while ago" is not a fact the router reports; the
    /// prototype's `last > 3600` was an invented number and does not appear.
    public static func candidacy(for server: MCPServer) -> Candidacy {
        if let error = server.indexError, !error.isEmpty {
            return .candidate(reason: failedToIndex(error))
        }
        if server.neverUsed {
            return .candidate(reason: neverCalled)
        }
        if server.indexedAt != nil, server.tools == 0 {
            return .candidate(reason: offersNothing)
        }
        return .notACandidate
    }

    /// A skill is proposed only when every skills-capable client was **read** and none has it.
    ///
    /// **One unreadable client suspends the judgement for every skill, not just for that client's.**
    /// A skill absent everywhere readable may be installed in exactly the folder nobody could open,
    /// and there is no way to tell which skills those would be — so the whole proposal is held rather
    /// than a subset guessed at. The banner counts what was held out, so a suspended judgement is
    /// visible rather than looking like an empty result.
    public static func candidacy(for skill: Skill, clients: [SkillClient]) -> Candidacy {
        let capable = clients.filter(\.supportsSkills)
        let unreadable = capable.filter { client in
            client.status == .unreadable || skill.presence[client.id] == .unreadable
        }
        guard unreadable.isEmpty else {
            return .heldOut(reason: heldOutReason(clients: unreadable.map(\.displayName)))
        }
        guard !capable.isEmpty else { return .notACandidate }
        let installedSomewhere = capable.contains { skill.presence[$0.id] == .present }
        return installedSomewhere ? .notACandidate : .candidate(reason: installedNowhere)
    }

    // MARK: - Candidacy copy

    public static let neverCalled =
        "The router has recorded no calls to it over the window below."

    public static func failedToIndex(_ detail: String) -> String {
        "The router could not start it or read its tools — \(detail)"
    }

    public static let offersNothing =
        "It starts and indexes cleanly, and declares no tools, so it adds nothing to a session."

    public static let installedNowhere =
        "Every skills-capable client was read, and none of them has it installed."

    public static func heldOutReason(clients: [String]) -> String {
        let names = clients.sorted().joined(separator: ", ")
        return "\(names)'s skills directory could not be read, so whether this is installed there is unknown."
    }

    public static func heldOutBanner(count: Int, clients: [String]) -> String {
        let noun = count == 1 ? "skill is" : "skills are"
        let names = clients.sorted().joined(separator: ", ")
        return "\(count) \(noun) held out of this proposal: \(names) could not be read, and a skill "
            + "absent everywhere else may be installed exactly there."
    }

    // MARK: - The observation window

    /// How long the router has been recording, which is the number that decides what "never used"
    /// is worth.
    public struct Window: Equatable, Sendable {
        public let days: Int
        public let label: String
        /// Under seven days. Chosen so a fresh reset and a week away both trip it; the copy states
        /// the real elapsed time either way, so the threshold never stands in for a figure.
        public let isWeak: Bool
    }

    /// The window, or `nil` when `since` does not parse.
    ///
    /// **`UsageSummary.since`** — the type `usageSummary()` actually returns — parsed with
    /// `String.asControlAPIDate`. Returning `nil` rather than a fallback is the point: a wrong
    /// duration reads as real data, and the pane has an honest thing to say instead (the subtitle
    /// drops the clause, the banner does not fire, and no number is substituted).
    public static func window(since: String, now: Date = Date()) -> Window? {
        guard let start = since.asControlAPIDate else { return nil }
        let seconds = max(0, now.timeIntervalSince(start))
        let days = Int(seconds / 86400)
        return Window(days: days, label: shortAgo(start, from: now), isWeak: seconds < 7 * 86400)
    }

    /// How much of the track to fill, against a 30-day reference.
    ///
    /// Clamped, so a 400-day window pegs the bar full rather than drawing it thirteen times its own
    /// track. The real figure sits beside the bar in mono, so nothing depends on reading the drawing —
    /// the bar is the shape of the answer and the number is the answer.
    public static let referenceDays = 30

    public static func trackFraction(days: Int, reference: Int = referenceDays) -> Double {
        guard reference > 0 else { return 0 }
        return min(1, max(0, Double(days) / Double(reference)))
    }

    // MARK: - Pane copy

    public static let title = "Cleanup"

    /// Names the window from the router's own figure, and never a literal duration.
    public static func subtitle(window: Window?) -> String {
        guard let window else {
            return "Capabilities MCP Router has never seen used, over the calls it has recorded. "
                + "It proposes; you decide."
        }
        return "Capabilities MCP Router has never seen used, judged over the calls it has recorded "
            + "across the past \(window.label). It proposes; you decide."
    }

    public static func weakWindowBanner(window: Window) -> String {
        "Call history covers only the past \(window.label). Everything below reads as never-used "
            + "because there is almost nothing recorded yet, not because it is unused. Give it a few "
            + "days before acting on this."
    }

    /// States what the sidebar badge counts, because it counts a subset of what this pane lists.
    ///
    /// `Destination.badgeSource` binds `.cleanup` to `.serversNeverUsed` — `usage.calls == 0` — and M1
    /// already decided that. This pane also lists servers that failed to index or declared no tools,
    /// so a badge of 3 against a list of 9 would be left for the user to reconcile. Changing
    /// `BadgeSource` is a merged shared surface; saying what is true is not.
    public static func badgeNote(neverUsedCount: Int) -> String {
        let noun = neverUsedCount == 1 ? "server" : "servers"
        return "The sidebar badge counts the \(neverUsedCount) \(noun) nobody has called. This list "
            + "also includes servers that failed to index or declared no tools."
    }

    public static let footer =
        "These sit in every session's tool list, where a model reads them. Nothing here claims a "
            + "memory saving: MCP Router never runs the world in which every server is resident, so "
            + "it has no figure to subtract from. Nothing is removed unless you remove it, and what "
            + "you remove is not counted."

    public static let emptyTitle = "Everything here has been used"

    public static let emptyDetail =
        "Every server has served calls and every skill is installed in a client the router can read. "
            + "Nothing is being proposed."

    public static let emptyInFilterTitle = "Nothing matches this filter"

    public static let emptyInFilterDetail =
        "The proposal has entries, and none of them falls under this filter."

    // MARK: - Reset

    /// The header action, on both boards that carry one.
    ///
    /// `Reset history…` rather than `Reset call history…`, because that is what the design of record
    /// puts in a board header: `prototype.html:716` on Activity and `:930` on Cleanup. The longer
    /// wording belongs to a different slot — the Danger section of Settings at `:999`, which this
    /// app does not draw — and shipping it in the header was DEF-012, a rename in one direction with
    /// the design not followed.
    public static let resetLabel = "Reset history…"

    /// Why a removal dialog can offer nothing, said rather than shown as a gap.
    ///
    /// The consequence strings are computed from the candidate row — its tool count and its env and
    /// header key names. A poll that lands while the dialog is open can take that row away, and a
    /// dialog that then rendered its title, its toggle and a live Remove button with the two
    /// consequence paragraphs simply missing would be offering an irreversible act with its
    /// disclosure quietly deleted.
    public static let consequenceUnavailable =
        "This server is no longer in the list, so what removing it would take with it cannot be "
            + "stated. Close this and open it again from the Servers board."

    public static let resetTitle = "Reset the recorded call history?"

    /// The named consequence, because there is no restore endpoint for this.
    ///
    /// `POST /usage/reset` cannot be undone, and pressing it immediately makes every server read as
    /// never-used, repopulates this pane with false candidates and trips its own weak-window banner.
    /// `DESIGN.md` §9's escalation clause governs: the blast radius is the whole judgement surface
    /// this pane rests on, so it gets a named consequence and Cancel leads.
    /// `calls` is optional because the router may not have answered `usageSummary()` when the dialog
    /// opens, and a zero substituted for silence is the worst substitution available here: it turns
    /// the disclosure for an irreversible act into "0 calls are discarded", which reads as free. When
    /// the figure is unobserved the sentence drops the count and keeps every consequence — the reader
    /// still learns exactly what is lost and that it cannot come back, without being told a number
    /// nobody measured.
    ///
    /// **An observed zero is a third case, not the first one with a small number in it.** The Phase D
    /// critic found the sentence false for it: "0 calls are discarded, and there is no way to bring
    /// them back" warns of a loss that does not occur, and it is reachable on the *success* path —
    /// `usageSummary()` answering with an empty `servers` array folds to `.some(0)` through the
    /// `reduce` seed, so the optional that exists to prevent exactly this sentence was defeated one
    /// line upstream of it.
    ///
    /// Resetting is still not a no-op when nothing is recorded: `usage.reset()` moves `since` to now
    /// (`src/usage.ts:283`), restarting the observation window that every reading on this pane is
    /// measured against. So the zero case names *that* consequence rather than an imaginary one, and
    /// rather than claiming there is none.
    public static func resetConsequence(calls: Int?, window: Window?) -> String {
        let span = window.map { " recorded across the past \($0.label)" } ?? " recorded so far"
        guard let calls else {
            return "Every call\(span) is discarded — the router has not said how many — and there "
                + "is no way to bring them back. Every server will read as never-used until calls "
                + "are recorded again, so this list will propose things that are in daily use."
        }
        guard calls > 0 else {
            return "No calls have been recorded, so there is nothing to discard. Resetting still "
                + "restarts the observation window, which is what every reading on this pane is "
                + "measured against."
        }
        return "\(calls) \(calls == 1 ? "call" : "calls")\(span) are discarded, and there is no way "
            + "to bring them back. Every server will read as never-used until calls are recorded "
            + "again, so this list will propose things that are in daily use."
    }

    public static let resetConfirm = "Reset history"
}
