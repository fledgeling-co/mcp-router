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
    /// `idleMs` is the router's own reap horizon from `ServersResponse`, and it is **optional**.
    ///
    /// The board briefly wrote `state.idleMs ?? 300_000` — the prototype's hardcoded horizon wearing
    /// a parameter's clothes, counting a row down against a number the router never sent. There is
    /// no default now; see `runningSubtitle` for what an unknown horizon renders instead.
    public static func forServer(_ server: MCPServer, idleMs: Int?) -> ServerSubtitle {
        // **First, above everything, and the position is the rule rather than a convenience.** A
        // disabled server can simultaneously be holding a schema change, be unauthorised, carry an
        // index error and be marked warm — the held-change sheet's own action is *disable this
        // server*, so `disabled` and `pendingChange` together is the ordinary case rather than a
        // corner. Every one of those lines describes something about a server that is serving
        // nobody, and the line a person needs first is the one that says so.
        //
        // `--t3`, not `--t4`: `DESIGN.md`:138 reserves `--t4` for disabled *controls* and never for
        // live text, and this is a subtitle a reader is meant to read. The row-level dim the mock
        // draws is the view's job, not this value's.
        if server.disabled {
            return ServerSubtitle(text: "disabled by you", tint: .t3)
        }
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
        return restingSubtitle(server, idleMs: idleMs)
    }

    /// What a server says once nothing above it has claimed the line: its transport state, then its
    /// scope, then the plain fact that it is not running.
    ///
    /// Split from `forServer` to bring that chain back under the complexity limit when M29 added a
    /// branch to it. The cut is where the chain stops asking *is something wrong or waiting* and
    /// starts describing an ordinary server, so the two halves are separately readable rather than
    /// one list broken at an arbitrary point.
    private static func restingSubtitle(_ server: MCPServer, idleMs: Int?) -> ServerSubtitle {
        switch server.state {
        case .running:
            return runningSubtitle(server, idleMs: idleMs)
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

    /// What a running server says, which depends on whether the router has told us its horizon.
    ///
    /// An **unknown** horizon renders `running` with no countdown, because "how long until it is
    /// reaped" is a question nothing has answered. Extracted rather than inlined as a `guard`: the
    /// extra branch took `forServer` to a cyclomatic complexity of 11 against a limit of 10.
    private static func runningSubtitle(_ server: MCPServer, idleMs: Int?) -> ServerSubtitle {
        guard let idleMs else { return ServerSubtitle(text: "running", tint: .t2) }
        return ServerSubtitle(text: "reaps in \(reapSeconds(server, idleMs: idleMs))s", tint: .t2)
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
    /// Start serving this server again.
    ///
    /// The design of record draws the disable — a destructive text button on the held-change sheet
    /// — and draws no way back. Shipping it that way would make the only reversal hand-editing
    /// `servers.json`, which is a defect rather than a design decision, so this is an addition to
    /// the mock recorded as one (`spec-M29.md` D8) rather than a reading of it. It takes the row's
    /// existing action slot, in the same shape as `reset`.
    case enable
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
        case .enable: "Enable"
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
        // First, for the reason the subtitle is: every action below asks the user to do something
        // about a server that is not serving anyone, and each would send a different request than
        // the one they want. `Review…` on a disabled server opens a sheet whose own destructive
        // action is *disable this server*, which is already done.
        if server.disabled { return .enable }
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
        // `needsAttention` already carries its own `!disabled` term, but the `placard` limb sits
        // outside it, so this filter needs the guard as well: a user who marks a server inoperative
        // and then switches it off has made both decisions and is being asked about neither.
        case .needsYou: !server.disabled && (server.needsAttention || server.placard != nil)
        }
    }

    /// Whether this filter's count is a claim about **now** rather than about what is declared.
    ///
    /// `running` and `idle` both describe what a child process is doing at this instant, so neither
    /// can be supported by a router that has stopped answering. `all` counts declared servers, which
    /// is configuration and survives a failed refresh; `needsYou` counts conditions the router
    /// reported — held descriptions, placards, failed indexes, waiting authorisations — which are
    /// the same kind of fact as the header's unindexed count and do not evaporate either.
    ///
    /// Used by `ServersBoardModel.counts(from:)` to withhold a figure rather than show a stale one
    /// as current.
    public var isPresentTense: Bool {
        switch self {
        case .running, .idle: true
        case .all, .needsYou: false
        }
    }

    /// What an empty result under this filter says.
    ///
    /// Worded per filter rather than once. The prototype uses one string — *"Every server is
    /// behaving. Switch to All to see the rest."* — which is simply false under `Running`, where the
    /// truth is that nothing is up. Placeholder or reused copy hides comprehension failures, which
    /// is the reason `DESIGN.md` §5 asks for real wording in the unhappy paths.
    ///
    /// **`reading` is not decoration.** These sentences are in the present tense — *"No server has a
    /// child process up right now"*, *"Everything is running"* — and this message is reachable from
    /// the stale branch, so a router that had gone quiet was asserting what was true at some
    /// unknown earlier moment as though it were true now. `.idle` was the worst of them: it attached
    /// an observed count to a present-tense verb, which is §6's defect in its literal form.
    ///
    /// A reading that is not current therefore gets one honest message instead of four confident
    /// ones. It says what is actually known — that this is the last reading, that it is not current,
    /// and what matched in it — and claims nothing about now.
    public func emptyMessage(
        totalServers: Int,
        reading: ServersBoardHeader.Reading = .current
    ) -> (title: String, detail: String) {
        guard reading == .current else {
            return (
                title: "Nothing matched, in the last reading",
                detail: """
                The router has stopped answering, so this is what it last said — and nothing in it \
                was \(staleNoun). What is true now is not something this can see.
                """
            )
        }
        return currentEmptyMessage(totalServers: totalServers)
    }

    /// How the stale message names this filter, as a plain noun phrase rather than a claim.
    private var staleNoun: String {
        switch self {
        case .all: "declared"
        case .running: "running"
        case .idle: "idle"
        case .needsYou: "waiting on you"
        }
    }

    private func currentEmptyMessage(totalServers: Int) -> (title: String, detail: String) {
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
