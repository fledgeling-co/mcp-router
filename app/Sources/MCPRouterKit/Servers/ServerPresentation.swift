import Foundation

// The Servers board's rules, as values rather than as a view.
//
// **Why this is in the UI-free target.** The brief names state correctness as the thing that failed
// twice in the prototype — a warm server told it was about to be reaped, a lever raised for a
// process that was not running. Those are not styling defects; they are wrong answers from a
// branch, and a branch that only a running app can exercise is a branch that ships wrong. Every
// rule below is a pure function of what the router reported, so all of it is testable with a
// constructed `MCPServer` and none of it needs a host.
//
// Nothing here derives a figure the router did not send. `DESIGN.md` §6 forbids it, and the two
// places `design/mocks/prototype.html` breaks that rule are both absent by construction: there is
// no eval on any server in the control API, so no eval is rendered; and the reap horizon is taken
// from `ServersResponse.idleMs` rather than from the prototype's literal 300 seconds, which is why
// `idleMs` is a parameter here with no default.

// MARK: - The subtitle

/// The one line under a server's name, and the tint it carries.
public struct ServerSubtitle: Equatable, Sendable {
    public let text: String
    /// Only ever `--t2`, `--t3`, `--attn` or `--fail`. An indicator colour appears here exactly when
    /// it means what it means (`DESIGN.md` §2), and never decoratively.
    public let tint: ColorToken

    public init(text: String, tint: ColorToken) {
        self.text = text
        self.tint = tint
    }

    /// The precedence table from `planning/specs/spec-M3.md`, in order.
    ///
    /// **Warm sits above running, and that ordering is the feature.** The brief states the rule
    /// three ways — warm implies running, the reaper skips warm, a warm server never shows a reap
    /// countdown — and the prototype implements it as the conjunction `warm && running`, which is
    /// not a precedence at all: a warm server the router has not brought up yet falls past both
    /// branches and reads `dormant`, telling the user that a server the reaper will never touch is
    /// idle and reapable. Written as an ordered chain with `warm` first, there is no input that
    /// reaches the countdown with `warm == true` — which is what `ServerPresentationTests` asserts
    /// over the whole cross product rather than over examples.
    ///
    /// Failure and decision outrank lifecycle because they are what a person can act on. Within
    /// lifecycle, warm outranks running.
    ///
    /// `idleMs` is the router's own reap horizon from `ServersResponse`. It has no default: a
    /// default would be a number this app invented, and the countdown is the one figure on this row
    /// that is arithmetic rather than a field.
    public static func forServer(_ server: MCPServer, idleMs: Int) -> ServerSubtitle {
        if server.inFlight > 0 {
            return ServerSubtitle(text: "\(server.inFlight) in flight", tint: .t2)
        }
        if let placard = server.placard {
            return ServerSubtitle(text: "tripped · \(placard.reason)", tint: .fail)
        }
        if let pending = server.pendingChange {
            let noun = pending.count == 1 ? "description" : "descriptions"
            return ServerSubtitle(text: "\(pending.count) \(noun) held", tint: .attention)
        }
        if server.auth.supported, !server.auth.authorized {
            return ServerSubtitle(text: "needs authorising", tint: .attention)
        }
        // Above `.running`, deliberately. See the note above.
        if server.warm {
            return ServerSubtitle(text: "warm · never reaped", tint: .t2)
        }
        switch server.state {
        case .running:
            return ServerSubtitle(text: "reaps in \(reapSeconds(server, idleMs: idleMs))s", tint: .t2)
        case .starting:
            return ServerSubtitle(text: "starting", tint: .t2)
        case .stopping:
            return ServerSubtitle(text: "stopping", tint: .t2)
        case .idle:
            break
        }
        if !server.projects.isEmpty {
            let noun = server.projects.count == 1 ? "project" : "projects"
            return ServerSubtitle(text: "scoped to \(server.projects.count) \(noun)", tint: .t2)
        }
        return ServerSubtitle(text: "dormant", tint: .t3)
    }

    /// Seconds until the reaper would close this server, floored at zero.
    ///
    /// `idleMs` is a whole-router setting the response carries; `idleSec` is how long this server
    /// has already been idle. Both are the router's. A server past its horizon reads `0s` rather
    /// than a negative number — the reaper runs on its own schedule, so "overdue" is a real moment
    /// and not an error.
    static func reapSeconds(_ server: MCPServer, idleMs: Int) -> Int {
        max(0, idleMs / 1000 - server.idleSec)
    }
}

// MARK: - The breaker

public extension BreakerState {
    /// Which lever a server shows.
    ///
    /// **Running is checked first, and that is the invariant.** The lever's whole meaning is "a
    /// child process is up" — `isRaised` is `self == .running` — so raising it for a server that is
    /// not running, or lowering it for one that is, is the only way this control can tell a lie.
    /// Attention therefore loses to running rather than the reverse: a running server that is also
    /// holding a tool description shows green, and its attention is carried by the subtitle, by the
    /// row's action and by the *Needs you* count. Colour is never the only signal (`DESIGN.md` §3
    /// rule 10), so nothing is lost that only colour was carrying.
    ///
    /// The state this cannot express is "running **and** wants a decision", because `BreakerState`
    /// is one enum and the lamp is not separable from the lever. That is recorded as a wanted
    /// shared-surface change in `spec-M3.md` rather than made here — `BreakerState` is a merged base
    /// element that F2's gallery also draws.
    static func forServer(_ server: MCPServer) -> BreakerState {
        if server.state == .running { return .running }
        if server.placard != nil { return .tripped }
        if server.needsAttention { return .wantsYou }
        return .dormant
    }
}

// MARK: - The row's action

/// What `Reset` has to do, which depends on where the placard came from.
///
/// `placardFor()` in `src/manifest.ts` returns the user's own placard first and the index error
/// second, so the two are not interchangeable: clearing the `placard` field on a server whose mark
/// came from a failed index changes nothing, because the router recomputes it from the same error on
/// the next describe. `indexError` is reported separately on `MCPServer`, which is what makes the
/// distinction observable rather than guessed.
public enum ResetKind: Equatable, Sendable {
    /// The mark came from a failed index: re-read the tool surface.
    case reindex
    /// The mark is the user's own: send an explicit `null` placard.
    case clearPlacard
}

/// The one action a row offers, or none.
public enum ServerRowAction: Equatable, Sendable {
    case reset(ResetKind)
    case reviewHeldChange
    case beginAuthorization
    /// An OAuth page the router already has open. Distinct from `beginAuthorization` because
    /// offering to start a flow that is already running opens a second browser tab and abandons the
    /// first — which is exactly why `PendingAuth` is modelled rather than dropped.
    case reopenAuthorizationPage(String)

    /// Verb-first, and naming the action (`DESIGN.md` §6). `…` means it opens a further view.
    public var label: String {
        switch self {
        case .reset: "Reset"
        case .reviewHeldChange: "Review…"
        case .beginAuthorization: "Sign in…"
        case .reopenAuthorizationPage: "Reopen the page"
        }
    }

    /// The row's action, or `nil` where there is genuinely nothing to do.
    ///
    /// `nil` renders an **empty cell**. The prototype fills it with an eval chip reading `passed` or
    /// `not evaluated`; there is no eval field on a server anywhere in the control API and no `eval`
    /// in `src/control.ts`, so that chip has nothing behind it and §6 rules it out. Evals are M7's.
    public static func forServer(_ server: MCPServer, pendingAuth: PendingAuth?) -> ServerRowAction? {
        if server.placard != nil {
            return .reset(server.indexError != nil ? .reindex : .clearPlacard)
        }
        if server.pendingChange != nil {
            return .reviewHeldChange
        }
        if server.auth.supported, !server.auth.authorized {
            // **The per-server field is checked first, and the order matters.** `PendingAuth` on the
            // response is a single `{server, url}`, so it can only ever describe one flow: with two
            // upstreams mid-authorisation it names one of them, and the other would be offered
            // `Sign in…` and start a duplicate flow — the exact failure `PendingAuth` was modelled
            // to prevent. `ServerAuth.pendingURL` is reported per server and has no such ceiling.
            if let url = server.auth.pendingURL {
                return .reopenAuthorizationPage(url)
            }
            if let pendingAuth, pendingAuth.server == server.name {
                return .reopenAuthorizationPage(pendingAuth.url)
            }
            return .beginAuthorization
        }
        return nil
    }
}

// MARK: - The filter

/// The segmented control's four views. It switches the view in place and is never navigation
/// (`DESIGN.md` §3.6).
public enum ServerFilter: String, CaseIterable, Sendable, Identifiable {
    case all, running, idle, needsYou

    public var id: String { rawValue }

    /// Sentence case (`DESIGN.md` §3.2).
    public var title: String {
        switch self {
        case .all: "All"
        case .running: "Running"
        case .idle: "Idle"
        case .needsYou: "Needs you"
        }
    }

    /// `needsYou` is `needsAttention` **plus a placard**.
    ///
    /// `MCPServer.needsAttention` already covers a held change, an unauthorised upstream and an
    /// index error. A placard set by the user is none of those and still makes the server
    /// inoperative and its breaker red — and a filter that means "not fine" while skipping the red
    /// rows is the wrong filter.
    public func matches(_ server: MCPServer) -> Bool {
        switch self {
        case .all: true
        case .running: server.state == .running
        case .idle: server.state != .running
        case .needsYou: server.needsAttention || server.placard != nil
        }
    }

    /// What an empty result under this filter says.
    ///
    /// Worded per filter rather than once. The prototype uses one string — *"Every server is
    /// behaving. Switch to All to see the rest."* — which is simply false under `Running`, where the
    /// truth is that nothing is up. Placeholder or reused copy hides comprehension failures, which
    /// is the reason `DESIGN.md` §5 asks for real wording in the unhappy paths.
    public func emptyMessage(totalServers: Int) -> (title: String, detail: String) {
        switch self {
        case .all:
            (
                title: "No servers declared yet",
                detail: """
                MCP Router reads the servers your agents already have configured. \
                Point it at a config, or declare one by hand.
                """
            )
        case .running:
            (
                title: "Nothing is running",
                detail: """
                No server has a child process up right now. \
                The router starts one the moment an agent calls it.
                """
            )
        case .idle:
            (
                title: "Everything is running",
                detail: "All \(totalServers) declared servers have a child process up."
            )
        case .needsYou:
            (
                title: "Nothing needs you",
                detail: """
                No held descriptions, nothing tripped, nothing that failed to index, \
                and nothing waiting to be authorised.
                """
            )
        }
    }
}

/// Matching a server against the search field.
///
/// `DESIGN.md` §8 binds `⌘F` to *focus search*; the prototype has no search field at all, and where
/// the document and the prototype disagree the prototype is stale. Tool names are searched as well
/// as the server name because a tool name is what a person actually hunts for — they remember
/// `search_screens`, not which server carries it.
public enum ServerSearch {
    public static func matches(_ server: MCPServer, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if contains(server.name, trimmed) { return true }
        return server.toolNames.contains { contains($0, trimmed) }
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - The row

/// One row of the board, fully resolved.
///
/// Identity is the server's **name**, never its index. This product's list reorders constantly as
/// servers start and stop, and index identity bleeds state between rows when it does
/// (`SWIFT_PRACTICES.md` §4).
public struct ServerRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let subtitle: ServerSubtitle
    public let breaker: BreakerState
    public let transport: String
    public let tools: Int
    /// Lifetime calls from the usage log — **not** `callsServed`, which is the current child
    /// process's own counter and resets to zero every time the reaper closes it. A column that
    /// dropped to zero whenever a server went idle would read as "this has never been used".
    public let calls: Int
    public let errors: Int
    public let lastUsed: Date?
    public let action: ServerRowAction?

    public init(server: MCPServer, idleMs: Int, pendingAuth: PendingAuth?) {
        id = server.name
        name = server.name
        subtitle = ServerSubtitle.forServer(server, idleMs: idleMs)
        breaker = BreakerState.forServer(server)
        transport = server.transport.rawValue
        tools = server.tools
        calls = server.usage.calls
        errors = server.usage.errors
        lastUsed = server.usage.lastUsed?.asControlAPIDate
        action = ServerRowAction.forServer(server, pendingAuth: pendingAuth)
    }
}

// MARK: - The header

/// The three figures under the board's title, and the one that goes absent.
public struct ServersBoardHeader: Equatable, Sendable {
    public let tools: Int
    public let servers: Int
    /// **`nil` on a stale load, and that is the point.** "1 running" is a present-tense claim about
    /// a router that is not currently answering. Showing the last known figure as though it were
    /// current is a quieter lie than showing a zero, and the same kind — M1 draws this line for the
    /// readout and this is the same line on the board. Optional rather than a flag beside an `Int`,
    /// so the absent case cannot be rendered by accident.
    public let running: Int?
    /// Servers whose index failed, so their tools are missing from `tools`.
    ///
    /// The router reports `tools: 0` and `toolNames: []` for a server with an `indexError`
    /// (`src/control.ts` — `entry?.error ? 0 : …`), so the total genuinely understates. `DESIGN.md`
    /// §5's Partial state is "say what arrived and what did not, with the reason", and this is the
    /// count that makes that sentence sayable.
    public let unindexed: Int

    public init(servers list: [MCPServer], isCurrent: Bool) {
        tools = list.reduce(0) { $0 + $1.tools }
        servers = list.count
        running = isCurrent ? list.filter { $0.state == .running }.count : nil
        unindexed = list.filter { $0.indexError != nil }.count
    }

    /// The subtitle line.
    ///
    /// **There is no timestamp here, and its absence is deliberate.** A phrase like "as of 14:32" or
    /// "last read 2m ago" needs the moment the poll answered, and nothing observes it: `LoadState`
    /// carries servers and an error, and no `apply` entry point records a time. An earlier draft
    /// derived one from the newest `lastUsed` across the servers, which is when a *tool was called* —
    /// a different fact wearing the same clothes, and precisely the invention §6 exists to stop.
    ///
    /// So the stale form claims no precision. It says the reading is not current, which is the whole
    /// of what is actually known.
    public func subtitle() -> String {
        let noun = servers == 1 ? "server" : "servers"
        let head = "\(tools) tools from \(servers) \(noun)"
        if let running {
            return "\(head) · \(running) running"
        }
        return "\(head) · last reading, not current"
    }

    /// The Partial note, or nil when everything indexed.
    public var partialNote: String? {
        guard unindexed > 0 else { return nil }
        let subject = unindexed == 1 ? "One server" : "\(unindexed) servers"
        let verb = unindexed == 1 ? "its" : "their"
        return """
        \(subject) could not be indexed, so \(verb) tools are missing from this count. \
        Those rows say why.
        """
    }
}
