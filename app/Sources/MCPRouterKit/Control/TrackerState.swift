import Foundation

/// The reading a surface renders, lifted out of `ServerStateTracker.swift` to keep that file under
/// the 400-line limit rather than raising the limit. A nested type declared in an extension is the
/// same type; nothing about the API moves.
public extension ServerStateTracker {
    /// What a surface renders.
    ///
    /// `load` and `stream` are two independent facts because they fail independently — a healthy
    /// poll with a dropped stream is ordinary, and folding them into one value would force a
    /// surface to lie about one of them. Both are `let`: a state handed to a surface is a reading,
    /// and a reading a caller can edit is not a reading.
    struct TrackerState: Equatable, Sendable {
        public let load: LoadState
        public let stream: StreamCondition

        /// The router's own reap horizon, in milliseconds, from the last poll that answered.
        ///
        /// Retained because a surface that renders "reaps in 200s" has to get that number from
        /// somewhere, and the only honest somewhere is the router. Without it the servers board
        /// would have to assume a horizon — the prototype assumes 300 seconds — and an assumed
        /// number displayed as an observation is exactly what `DESIGN.md` §6 forbids.
        ///
        /// `nil` until a poll has succeeded. It is deliberately **not** cleared by a failure, for
        /// the same reason the servers are not: a failure to refresh is not evidence that the
        /// router's configuration changed.
        public let idleMs: Int?

        /// An OAuth flow the router already has open, from the last poll that answered.
        ///
        /// The difference between "this server needs authorising" and "a browser window is already
        /// open waiting for you" — a surface that cannot tell those apart offers the button twice,
        /// and the second press abandons the first flow.
        public let pendingAuth: PendingAuth?

        /// The port the router answered on, from the last poll that answered.
        ///
        /// Settings composes its endpoint row from this rather than from a constant, so a router
        /// moved to another port is described correctly instead of plausibly. `nil` until a poll
        /// has succeeded, and — like `idleMs` — **not cleared by a failure**: a refresh that did
        /// not complete is not evidence that the router changed its port.
        public let port: Int?

        /// When the router's usage counter last opened, from the last poll that answered.
        ///
        /// Every per-server total is measured from this instant, so a surface reporting totals
        /// without it is reporting a rate with no window. Retained across failure for the same
        /// reason as the two above.
        public let since: String?

        /// The servers to show, whatever the load state — empty when nothing has ever loaded.
        ///
        /// Derived rather than stored, so it cannot disagree with `load`.
        public var servers: [MCPServer] {
            switch load {
            case .loading, .failed: []
            case let .loaded(servers): servers
            case let .stale(servers, _): servers
            }
        }

        public init(
            load: LoadState,
            stream: StreamCondition,
            idleMs: Int? = nil,
            pendingAuth: PendingAuth? = nil,
            port: Int? = nil,
            since: String? = nil
        ) {
            self.load = load
            self.stream = stream
            self.idleMs = idleMs
            self.pendingAuth = pendingAuth
            self.port = port
            self.since = since
        }
    }
}
