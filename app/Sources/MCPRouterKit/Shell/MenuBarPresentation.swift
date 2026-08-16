import Foundation

/// What the menu-bar status item and its popover draw, computed once and rendered by two views
/// that decide nothing.
///
/// This type is in `MCPRouterKit` rather than beside the views for the reason every presentation
/// rule in this repo is: `app/MCPRouter` is not a SwiftPM target, so a decision written next to the
/// `MenuBarExtra` scene is a decision `swift test` cannot reach, and a clause with no evidence lane
/// is a clause that is never checked. Every assertion M8's spec makes about the bar — that the dot
/// appears exactly when something wants a decision, that it is never `--fail`, that it carries no
/// count, that no skills figure is rendered — is an assertion about a value, so the value is
/// computed here.
public enum MenuBarPresentation {
    // MARK: - Why a server is in the band

    /// The three conditions `MCPServer.needsAttention` is actually made of.
    ///
    /// `needsAttention` is one boolean and the band needs a sentence, so it is decomposed here
    /// rather than in a view. **Declaration order is precedence order** — a server matching more
    /// than one reports the first — and `heldChange` leads deliberately: it is the only one of the
    /// three that is a security decision the router is actively holding bytes back for, and the
    /// other two are conditions a server is merely in.
    public enum AttentionCause: String, Sendable, CaseIterable, Hashable {
        /// The server started advertising a tool description that differs from the approved one.
        case heldChange
        /// An HTTP upstream that supports authorisation and has not been authorised.
        case needsAuthorization
        /// The last index attempt failed, and the router will not retry on its own.
        case indexFailed

        /// The sentence the band row shows. One place, so no later surface can word it differently
        /// — `DESIGN.md` §6 asks for one name per state across both devices.
        public var sentence: String {
            switch self {
            case .heldChange: "changed a tool description — held, not served"
            case .needsAuthorization: "needs authorising before it can answer"
            case .indexFailed: "failed to index — will not retry on its own"
            }
        }

        /// The raw value of the `Icon` case this row draws. A string rather than the type itself
        /// because `Icon` lives in `MCPRouterUI` and this module stays free of UI frameworks
        /// (`SWIFT_PRACTICES.md` §8).
        public var iconName: String {
            switch self {
            case .heldChange, .needsAuthorization: "shield"
            case .indexFailed: "warn"
            }
        }

        /// The tint of the **row's** glyph, which may be `--fail`.
        ///
        /// A row has a sentence beside it, so two glyph colours there are a distinction the reader
        /// can actually resolve. The status item's dot is a **separate** value
        /// (``statusItemDotToken``) and is always `--attn`. These are deliberately two properties
        /// rather than one shared value: collapsing them is the tidy-looking edit that would put a
        /// red dot in the menu bar, and `MenuBarPresentationTests` fails if it happens.
        public var tintToken: ColorToken {
            switch self {
            case .heldChange, .needsAuthorization: .attention
            case .indexFailed: .fail
            }
        }

        /// Whether pressing this row should open the held-change sheet.
        ///
        /// Only the held change does. A server that needs authorising and one that failed to index
        /// both land on Servers with the row selected and no sheet, because their next action is in
        /// the inspector — and putting a modal in front of a decision the user has not asked to make
        /// is how a surface starts being dismissed without being read.
        public var opensHeldChangeSheet: Bool { self == .heldChange }

        /// The causes this server is in, in precedence order. Empty when it wants nothing.
        public static func causes(for server: MCPServer) -> [AttentionCause] {
            var found: [AttentionCause] = []
            if server.pendingChange != nil { found.append(.heldChange) }
            if server.auth.supported, !server.auth.authorized { found.append(.needsAuthorization) }
            if server.indexError != nil { found.append(.indexFailed) }
            return found
        }
    }

    /// One row of the attention band.
    public struct AttentionRow: Equatable, Sendable, Identifiable {
        public let server: String
        public let cause: AttentionCause

        public init(server: String, cause: AttentionCause) {
            self.server = server
            self.cause = cause
        }

        public var id: String { "\(server)|\(cause.rawValue)" }
        public var sentence: String { cause.sentence }
        public var opensHeldChangeSheet: Bool { cause.opensHeldChangeSheet }
    }

    // MARK: - The band

    /// One row per server that wants a decision, reporting its highest-precedence cause.
    ///
    /// A server with both a held change and a failed index is **one** row, not two: the band is a
    /// list of things to look at, and the same server twice is one thing listed twice.
    public static func attentionRows(from servers: [MCPServer]) -> [AttentionRow] {
        servers.compactMap { server in
            AttentionCause.causes(for: server).first.map { AttentionRow(server: server.name, cause: $0) }
        }
    }

    // MARK: - The status item

    /// The token the status item's dot is drawn in. **Always `--attn`, in every case.**
    ///
    /// Including when the only cause is a failed index, which `AttentionCause.tintToken` reports as
    /// `--fail`. Two dot colours in a 16pt glyph are a code nobody learns, and both conditions
    /// resolve the same way — a human decides something. The distinction is drawn in the popover,
    /// where there is a sentence to carry it.
    public static let statusItemDotToken: ColorToken = .attention

    /// Whether the status item shows its dot at all.
    ///
    /// Sourced from `MCPServer.needsAttention`, which is also the Servers sidebar badge's source, so
    /// the menu bar and the sidebar cannot disagree about whether something is wrong — **and** from
    /// the number of items a paired phone has queued, which is the second thing in this app that
    /// ends in a human deciding something.
    ///
    /// The queued half is an addition rather than an exception to the three rules the bar obeys.
    /// There is still no count in the bar, still one dot colour, and `--live` still never appears; a
    /// queued item is a second reason for the same dot with the same meaning, so there is nothing
    /// new to learn. The alternative — a queue filling while the menu bar says nothing — is the
    /// failure the poller section of `spec-M8.md` names: a glanceable instrument that silently stops
    /// being true.
    ///
    /// `waiting` defaults to zero so every call site and assertion written before the inbox reached
    /// this surface still says what it said.
    public static func statusItemNeedsAttention(_ servers: [MCPServer], waiting: Int = 0) -> Bool {
        waiting > 0 || servers.contains(where: \.needsAttention)
    }

    /// What VoiceOver reads.
    ///
    /// A template symbol with no label is announced as "button", so the information the dot carries
    /// visually has to be carried here too — the same requirement
    /// `accessibilityDifferentiateWithoutColor` states for the dot itself.
    ///
    /// The count is of **things to look at**, not of causes: a server with two problems is one item,
    /// and a queued item is one item. The existing vocabulary already generalises, so one queued
    /// item alone reads `MCP Router, 1 item needs a decision` with no new wording.
    public static func statusItemLabel(_ servers: [MCPServer], waiting: Int = 0) -> String {
        let wanting = servers.filter(\.needsAttention).count + waiting
        guard wanting > 0 else { return "MCP Router" }
        return "MCP Router, \(wanting) \(wanting == 1 ? "item needs" : "items need") a decision"
    }

    // MARK: - The header

    /// The popover header's three counts.
    ///
    /// **There is no skills field on this type, and that absence is the enforcement.** The
    /// prototype's popover reads "… · 6 skills"; `ControlAPIClient` has no skills endpoint, so a
    /// skills count would be a number the router does not observe, which `DESIGN.md` §6 forbids.
    /// A structural absence survives an edit that a comment does not.
    public struct Counts: Equatable, Sendable {
        public let running: Int
        public let idle: Int
        public let tools: Int

        public init(running: Int, idle: Int, tools: Int) {
            self.running = running
            self.idle = idle
            self.tools = tools
        }
    }

    /// Running is derived exactly as `ReadoutModel` derives it — `state == .running` — so the
    /// popover and the window report the same number for one list of servers.
    public static func counts(from servers: [MCPServer]) -> Counts {
        let running = servers.filter(\.isRunning).count
        return Counts(
            running: running,
            idle: servers.count - running,
            tools: servers.reduce(0) { $0 + $1.tools }
        )
    }

    // MARK: - The call log

    /// How many call rows the popover asks for and shows.
    ///
    /// A glanceable instrument, not a log viewer: the whole log is Activity's surface. Named here
    /// so the request limit and the render cap cannot drift apart.
    public static let recentCallLimit = 6

    /// How many queued items the popover's inbox band draws before it defers to the board.
    ///
    /// Half the call log's cap, and the reason is that the rows are not comparable: a call row is
    /// read-only and an inbox row carries a decision and two controls. Past three the popover has
    /// stopped being a glance and started being the board, which is what `⌘5` is for. The band's
    /// header line states the true total, so the cap never hides a count.
    public static let inboxBandLimit = 3

    /// The relative age of a call, in the popover's compact form.
    ///
    /// Delegates to `shortAgo` and `asControlAPIDate` rather than parsing and formatting again:
    /// M2's Activity board shows the same column from the same field, and two formatters would let
    /// the popover and the board disagree about what "now" looks like. `—` for an unparseable
    /// timestamp, never a fallback date — a wrong time reads as real data.
    public static func age(of record: CallRecord, now: Date) -> String {
        guard let timestamp = record.ts.asControlAPIDate else { return "—" }
        return shortAgo(timestamp, from: now)
    }

    /// The duration column. Sub-second in milliseconds, then seconds to one decimal — the boundary
    /// where four digits of milliseconds stop being readable at a glance.
    public static func duration(of record: CallRecord) -> String {
        record.ms < 1000 ? "\(record.ms)ms" : String(format: "%.1fs", Double(record.ms) / 1000)
    }

    // MARK: - Copy

    /// The empty log. Counts stay real; only the log is empty.
    public static let emptyLogTitle = "No calls yet"
    public static let emptyLogDetail = """
    Tool calls appear here as your sessions make them. Nothing is running until something asks.
    """

    /// The stale header, when the last refresh failed but the servers are still real.
    public static let staleTitle = "Last refresh failed"
    public static func staleDetail(secondsAgo: Int) -> String {
        "showing what the router said \(secondsAgo)s ago"
    }

    public static let openWindowLabel = "Open MCP Router"
    public static let quitLabel = "Quit"

    /// Quit's help tag. The one thing a user might reasonably fear when quitting an app whose whole
    /// subject is a daemon is that the daemon goes with it. It does not.
    public static let quitHelp = "Quits MCP Router. The router keeps running and your sessions keep working."
}
