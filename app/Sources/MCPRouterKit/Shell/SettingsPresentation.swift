import Foundation

/// What the Settings pane draws, computed from what the router serves and what this Mac stores.
///
/// In `MCPRouterKit` for the reason the menu bar's rules are: the pane's clauses are assertions
/// about values — that the endpoint carries the observed port, that no byte figure is rendered,
/// that the token never reaches a view — and a value a test cannot call is a clause with no
/// evidence lane.
public enum SettingsPresentation {
    // MARK: - The router's own facts

    /// The four rows of the Router card. Every one is served by `GET /servers`; none is writable.
    ///
    /// **There is no control-API endpoint that writes any of these.** `isControlPath` admits only
    /// `/servers`, `/usage` and `/registry`, and the sole mutation shape for an existing server is
    /// `ServerPatch`, which is per-server and carries no router setting. Writing
    /// `~/.claude/mcp-router/servers.json` from the app would be a second channel to the router,
    /// which this product's standing constraint forbids — so the pane shows the facts and says, in
    /// place, where they are configured.
    public struct RouterFacts: Equatable, Sendable {
        public let port: Int
        public let idleMs: Int
        public let since: String
        public let home: URL

        public init(port: Int, idleMs: Int, since: String, home: URL) {
            self.port = port
            self.idleMs = idleMs
            self.since = since
            self.home = home
        }

        /// Composed from the **observed** port, never a constant. A build that renders `8879` for a
        /// router listening on 9999 is telling the user to point their client at the wrong place.
        public var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

        /// The reap horizon in whole seconds, which is the unit the router's own configuration
        /// uses and the unit M3's row copy already speaks.
        public var reaper: String { "\(idleMs / 1000)s" }

        /// The home directory in the tilde form when it is under this user's home, and in full
        /// otherwise. A path is identified by its tail, so the overflow rule truncates it from the
        /// left; shortening it here is the better fix where it applies.
        public func homeDisplay(homeDirectory: String = NSHomeDirectory()) -> String {
            let path = home.path
            guard !homeDirectory.isEmpty, path.hasPrefix(homeDirectory) else { return path }
            return "~" + path.dropFirst(homeDirectory.count)
        }

        /// When the usage counter last opened — what every per-server total is measured against.
        ///
        /// Deliberately **not** "Started 3d 4h ago · pid 41208", which is what
        /// `design/mocks/prototype.html` draws. The router serves no start time and no pid on any
        /// endpoint, so that row would be two invented numbers (`DESIGN.md` §6).
        public func sinceDisplay(now: Date = Date()) -> String {
            guard let date = since.asControlAPIDate else { return "—" }
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM, HH:mm"
            return formatter.string(from: date)
        }
    }

    public static let routerHelp = """
    Read from the router, not set here. The app reaches the router over one loopback channel and \
    that channel has no endpoint that rewrites the router's own configuration — deliberately, \
    because an API that can rewrite a command line can run anything. Change these in \
    ~/.claude/mcp-router/servers.json and restart the router.
    """

    /// Shown in place of the Router card's values when the router has never answered.
    ///
    /// The headline and advice are **not written here** — they are `ControlAPIError`'s, approved in
    /// F3 and asserted verbatim by `ControlCopyTests`. One wording per state across both devices
    /// (`DESIGN.md` §6), so this type points at them rather than paraphrasing.
    public static let warmSetUnknown = "Not known while the router is down"

    // MARK: - The menu bar group

    public static let menuBarToggleLabel = "Show MCP Router in the menu bar"
    public static let menuBarHelp = """
    The item is a plain symbol and stays one. It takes a dot only while something wants a \
    decision — a held tool description, a server that needs authorising, one that failed to \
    index. An icon that changes constantly is one the eye learns to skip, and then it skips the \
    change that mattered.
    """

    /// Where the preference lives. `UserDefaults` is correct for it: `SWIFT_PRACTICES.md` §6 bars
    /// **secrets** from `UserDefaults`, and whether an icon is shown is not one.
    public static let menuBarVisibleKey = "shell.menuBarVisible"

    /// Shown by default. A menu-bar app whose item is hidden until you find the setting is an app
    /// whose main feature is undiscoverable.
    public static let menuBarVisibleDefault = true

    // MARK: - The warm set

    /// How many servers are kept resident, and which.
    ///
    /// **No megabyte figure, and the type has no field for one.** `residentMb()` exists in
    /// `src/pool.ts` and has zero callers: it never reaches `describe()` and never reaches the
    /// wire, so any memory number here would be invented. `DESIGN.md` §6 is explicit that there is
    /// no fabricated memory saving anywhere in this product.
    public struct WarmSet: Equatable, Sendable {
        public let names: [String]
        public let declared: Int

        public init(names: [String], declared: Int) {
            self.names = names
            self.declared = declared
        }

        public init(servers: [MCPServer]) {
            names = servers.filter(\.warm).map(\.name)
            declared = servers.count
        }

        public var isEmpty: Bool { names.isEmpty }

        public var summary: String {
            isEmpty
                ? "None of \(declared) \(declared == 1 ? "server" : "servers")"
                : "\(names.count) of \(declared) \(declared == 1 ? "server" : "servers")"
        }
    }

    public static let warmSetLabel = "Kept resident"
    public static let warmSetAction = "Show in Servers"

    public static let warmSetPopulatedHelp = """
    A warm server is not closed when it goes idle, so its next call is not a cold start. The \
    switch is on each server's own row, because that is where you can see what it costs you — \
    this pane counts the set, it does not edit it.
    """

    public static let warmSetEmptyHelp = """
    Every server is started when something first calls it and closed when the reaper reaches it. \
    Keep one warm from its row in Servers when its cold start is the thing you keep waiting on.
    """

    // MARK: - The control token

    /// What the pane says about the control token.
    ///
    /// **No case carries the token.** That is the enforcement rather than a convention: there is no
    /// field here a token could be placed in, so it cannot reach a view by being passed along —
    /// not in full, not redacted, not as a length. `SWIFT_PRACTICES.md` §6 bars logging a token,
    /// and rendering one is worse than logging it.
    public enum TokenStatus: Equatable, Sendable {
        /// Stored in this Mac's keychain and not known to be wrong.
        case stored
        /// Nothing stored yet — the ordinary state before the router has ever been reached.
        case absent
        /// Stored, and the router answered 401 with it.
        case rejected
        /// The keychain itself refused. Carries the OSStatus, which is the one detail a support
        /// conversation needs and is not a secret.
        case unavailable(status: Int32)

        public var value: String {
            switch self {
            case .stored: "Stored in this Mac's keychain"
            case .absent: "Not stored yet"
            case .rejected: "Stored, and the router rejected it"
            case .unavailable: "Not stored — this Mac's keychain refused"
            }
        }

        /// Whether `Forget the stored token` can do anything.
        public var canForget: Bool {
            switch self {
            case .stored, .rejected: true
            case .absent, .unavailable: false
            }
        }

        /// The one condition where forgetting is the fix rather than a maintenance chore, and so
        /// the one condition where it is the pane's prominent action. `DESIGN.md` §3.4 allows one
        /// prominent accent-filled action per view; this is it, and only while this holds.
        public var forgetIsProminent: Bool { self == .rejected }

        /// Adjacent to the group that failed, saying what happened, what still works, and what
        /// happens next. Non-blaming, and it does not emote (`DESIGN.md` §6).
        public var banner: String? {
            guard case let .unavailable(status) = self else { return nil }
            return """
            The keychain would not hand over the token (item not found, \(status)). The app is \
            still using the copy it read from the router's file, so nothing has stopped working; \
            it will read it again next time it starts.
            """
        }
    }

    public static let tokenLabel = "Token"
    public static let tokenSourceLabel = "Read from"
    public static let forgetAction = "Forget the stored token"
    public static let forgetDisabledReason = "There is no stored token to forget."

    public static let tokenStoredHelp = """
    The token is never shown, here or in a log. Forgetting it makes the app re-read the router's \
    file on its next request, which is the fix when the router has been reset and this app is \
    still sending the token it had before.
    """

    public static let tokenAbsentHelp = """
    The router writes a token to that file the first time it starts. The app reads it from there \
    and keeps it in the keychain.
    """

    public static let tokenRejectedHelp = """
    The router has a token this app does not. Forgetting the stored one makes the app read the \
    router's file again on its next request, which is usually the whole fix.
    """

    // MARK: - The pane

    public static let paneTitle = "Settings"
    public static let paneSubtitle = "What the router is, and what this Mac remembers about it"

    /// The four group headers, in order. Sentence case, and stored that way rather than
    /// upper-cased at render time — `DESIGN.md` §3.2 says the fix for tracked uppercase is to
    /// remove it, not to re-track it.
    public enum Group: String, CaseIterable, Sendable {
        case router = "Router"
        case menuBar = "Menu bar"
        case warmSet = "Warm set"
        case controlToken = "Control token"
    }

    /// The shared label-column width. One constant used by every group, which is what makes
    /// "label-left, control-right, on one axis across the whole pane" a property of the layout
    /// rather than a coincidence four cards happen to share.
    public static let labelColumnWidth: Double = 150
}
