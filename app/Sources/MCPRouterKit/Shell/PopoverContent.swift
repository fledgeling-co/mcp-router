import Foundation

/// Everything the popover draws, as one value.
///
/// The popover is a view over this and decides nothing, which is what lets the clauses about it be
/// unit tests rather than screenshots. Two shapes here exist specifically because the first draft of
/// the spec could not be checked without them:
///
/// - **`band` is `[AttentionRow]?` and is `nil`, never `[]`, when nothing wants a decision.**
///   `DESIGN.md`'s rule is that the band is *absent* rather than empty — a permanent "all clear" row
///   is something to read every time that says nothing, and its presence would stop meaning
///   anything. A view-level test cannot tell a hidden band from a band rendering zero rows: both
///   produce no output. A nil-versus-empty assertion can, so the distinction lives in the type.
///
/// - **`stale` is a sibling of the band, not a modifier on it.** A failed refresh is not the servers
///   failing, and recolouring their rows `--fail` would assert that it was — which §2's exclusivity
///   forbids, since `--fail` means "failed or tripped" and nothing else.
public struct PopoverContent: Equatable, Sendable {
    /// The header's counts, or `nil` when nothing has ever loaded.
    ///
    /// Absent rather than zeroed, for the reason the readout is: nobody answered, and zero is an
    /// answer.
    public let counts: MenuBarPresentation.Counts?

    /// Shown as its own row above the band when the last refresh failed but the servers are still
    /// real — the tracker's `.stale` case.
    public let stale: StaleNotice?

    /// `nil` when no server wants a decision. Never an empty array.
    public let band: [MenuBarPresentation.AttentionRow]?

    /// The most recent calls, newest first, capped at `MenuBarPresentation.recentCallLimit`.
    public let calls: [CallRow]

    /// A whole-popover message that replaces the log — offline, or an empty call log.
    public let message: Message?

    public init(
        counts: MenuBarPresentation.Counts?,
        stale: StaleNotice? = nil,
        band: [MenuBarPresentation.AttentionRow]?,
        calls: [CallRow] = [],
        message: Message? = nil
    ) {
        self.counts = counts
        self.stale = stale
        self.band = band
        self.calls = calls
        self.message = message
    }

    public struct StaleNotice: Equatable, Sendable {
        public let title: String
        public let detail: String

        public init(secondsAgo: Int) {
            title = MenuBarPresentation.staleTitle
            detail = MenuBarPresentation.staleDetail(secondsAgo: secondsAgo)
        }
    }

    /// One call row, already formatted. The view places these; it does not compute them.
    public struct CallRow: Equatable, Sendable, Identifiable {
        public let id: String
        public let age: String
        public let server: String
        public let tool: String
        public let duration: String
        public let failed: Bool
        public let cold: Bool

        public init(record: CallRecord, now: Date) {
            id = record.id
            age = MenuBarPresentation.age(of: record, now: now)
            server = record.server
            tool = record.tool
            duration = MenuBarPresentation.duration(of: record)
            failed = !record.ok
            cold = record.cold
        }
    }

    public struct Message: Equatable, Sendable {
        public let title: String
        public let detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }

        /// The router is not running. Verbatim from `ControlAPIError`, which F3 approved and
        /// `ControlCopyTests` asserts — one wording per state across every surface and both
        /// devices, so this composes rather than paraphrases.
        ///
        /// **No action.** `ControlAPIError.actionLabel` offers "Start the router" and nothing in
        /// this tree can start one; a button that cannot act teaches the user that the app's
        /// buttons do not work. Recorded as a deviation from `DESIGN.md` §5 in `spec-M8.md`,
        /// consistent with M3's banners.
        public static let offline = Message(
            title: ControlAPIError.routerNotRunning.headline,
            detail: ControlAPIError.routerNotRunning.advice
        )

        public static let emptyLog = Message(
            title: MenuBarPresentation.emptyLogTitle,
            detail: MenuBarPresentation.emptyLogDetail
        )
    }

    // MARK: - Building one

    /// Compose the popover's content from what the tracker holds and the calls that were fetched.
    ///
    /// One function so the popover cannot be assembled two different ways by two different views,
    /// and so every state clause is a call to it with constructed inputs rather than a live router.
    public static func make(
        trackerState: ServerStateTracker.TrackerState?,
        records: [CallRecord],
        now: Date
    ) -> PopoverContent {
        guard let trackerState else {
            return PopoverContent(counts: nil, band: nil)
        }

        switch trackerState.load {
        case .loading:
            // Nothing has answered yet. No counts, and no message either — the view draws its
            // skeleton, which is not the same as telling the user something.
            return PopoverContent(counts: nil, band: nil)

        case .failed:
            // Nothing has ever loaded and the router did not answer. The counts are absent rather
            // than zero, and the offline message replaces the log.
            return PopoverContent(counts: nil, band: nil, message: .offline)

        case let .loaded(servers):
            return populated(servers: servers, stale: nil, records: records, now: now)

        case let .stale(servers, _):
            // The servers are real and keep their rows; the counts are a claim about *now*, so the
            // notice says when they were true. M1's rule, applied to a second surface.
            let age = Int(max(0, now.timeIntervalSince(lastAnswer(before: now, records: records) ?? now)))
            return populated(
                servers: servers,
                stale: StaleNotice(secondsAgo: age),
                records: records,
                now: now
            )
        }
    }

    private static func populated(
        servers: [MCPServer],
        stale: StaleNotice?,
        records: [CallRecord],
        now: Date
    ) -> PopoverContent {
        let rows = MenuBarPresentation.attentionRows(from: servers)
        let calls = records
            .prefix(MenuBarPresentation.recentCallLimit)
            .map { CallRow(record: $0, now: now) }

        return PopoverContent(
            counts: MenuBarPresentation.counts(from: servers),
            stale: stale,
            // The nil-versus-empty distinction, in the one place it is decided.
            band: rows.isEmpty ? nil : rows,
            calls: Array(calls),
            message: calls.isEmpty ? .emptyLog : nil
        )
    }

    /// The newest call's timestamp, used to age the stale notice. `nil` when there are no calls to
    /// date it from, in which case the notice reports zero rather than inventing an age.
    private static func lastAnswer(before _: Date, records: [CallRecord]) -> Date? {
        records.compactMap(\.ts.asControlAPIDate).max()
    }
}
