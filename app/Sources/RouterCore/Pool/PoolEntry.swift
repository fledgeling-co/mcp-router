import Foundation

/// A live upstream, whatever it is made of.
///
/// The pool is written against this rather than against the MCP SDK, for two reasons. It keeps the
/// state machine testable without spawning anything — the races are in the bookkeeping, not in the
/// process — and it keeps the SDK's pre-1.0 surface at one edge, which is the containment argument
/// the package already makes for putting the SDK in this target at all.
public protocol UpstreamSession: Sendable {
    /// The child's pid, or `nil` when there is no local process.
    ///
    /// Optional rather than zero because `residentMb()` **omits** upstreams with no process, which
    /// is what the reference does; reporting a zero would be reporting a number nobody measured.
    var processIdentifier: Int32? { get }

    /// Returns when the session has ended **on its own** — EOF on the child's stdout, a send
    /// failure, a dropped HTTP session, or the process exiting. A healthy session never returns.
    ///
    /// A one-shot await rather than a callback because the pinned SDK exposes no close callback at
    /// all: `Transport` has none, `StdioTransport` merely finishes its private receive stream, and
    /// `Client` owns that loop privately. Awaiting once is also what stops the naive wrapper's hot
    /// loop, where re-requesting an already-finished stream returns immediately, forever.
    func waitUntilEnded() async

    /// Close the client and transport, then terminate **and await** any child process, closing
    /// every descriptor this session owns. Must be idempotent.
    func shutdown() async

    /// The tools this upstream declares, as the **raw** `result` object it sent.
    ///
    /// `JSONValue` rather than the SDK's `[Tool]` because the reference passes the upstream's own
    /// object through, and a typed decode drops any member the SDK does not model — and, worse,
    /// destroys member order, since `MCP.Value`'s object case is an unordered dictionary. The
    /// relay's output is diffed against the reference byte for byte, so order lost here would be
    /// order lost on the wire.
    func listTools() async throws -> JSONValue

    /// Call one tool, returning the raw `result` object the upstream sent, for the same reason.
    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue
}

/// Opens upstreams. The seam Phase 1 fakes and Phase 2 implements against real processes.
public protocol UpstreamTransporting: Sendable {
    /// Open one upstream, or throw. A throwing open must leave **nothing** behind — no half-open
    /// child, socket or descriptor.
    func open(_ upstream: UpstreamConfig, timeoutMilliseconds: Int) async throws -> any UpstreamSession
}

/// What the pool knows about one live upstream.
///
/// `Sendable` because it is the value a start flight's `Task` resolves to, and every waiter in a
/// cohort receives it from that task.
struct PoolHandle: Sendable {
    let id: HandleID
    let session: any UpstreamSession
    let startedAtMilliseconds: Double
    var lastUsedAtMilliseconds: Double
    /// The reference's `calls`: an **acquisition** counter, not a served-call counter. See the
    /// spec's D6 — it is reproduced exactly because R4 diffs the value.
    var acquisitions: Int
    /// The task awaiting `waitUntilEnded()`, cancelled when this handle is deliberately reaped so
    /// an intentional close cannot be mistaken for the upstream dying on its own.
    var endWatcher: Task<Void, Never>?
}

/// The idle countdown, and the epoch that makes cancelling it trustworthy.
///
/// The deadline is a `ContinuousClock` instant, deliberately **not** the injectable `RouterClock`.
/// That clock exists to make wall-clock timestamps and `idleSec` match the reference byte for byte,
/// and a wall clock is the wrong thing to measure an elapsed interval against: it jumps when the
/// system time is corrected, and a test that freezes it would freeze the deadline while the timer's
/// own `Task.sleep` kept running in real time. Elapsed time is measured monotonically; the wall
/// clock stays for the values that are reported.
struct ReapTimer {
    let epoch: ReapEpoch
    /// The window this arming resolved to, kept because it is the thing a test needs to CHECK.
    ///
    /// Comparing deadlines instead was weaker in two ways an out-of-family review caught: two
    /// deadlines taken minutes apart can order wrongly for a reason that is not the pool's, and a
    /// window of 599 seconds compares as smaller than a 600-second default while being just as
    /// wrong as 600. The integer is exact, is the same local that computes the deadline and drives
    /// the sleep, and involves no clock at all.
    let idleMilliseconds: Int
    let deadline: ContinuousClock.Instant
    let task: Task<Void, Never>
}

/// What an arming chose, without the machinery it chose it with.
///
/// The `Task` deliberately does not travel: it is live, unstructured and cancellable, and three
/// out-of-family reviewers independently named handing one to a test as the wrong seam — a caller
/// could cancel a production timer, or await one that has since been superseded. The pool awaits
/// its own tasks instead (`awaitReap`, `awaitSessionEnded`) and lets only this value out.
///
/// `idleMilliseconds` is the window the arming RESOLVED TO, which is the thing a test about idle
/// windows actually wants to check. It is exact, it is the same local that computes the deadline
/// and drives the sleep, and reading it involves no clock at all.
struct ReapArming: Sendable {
    let epoch: ReapEpoch
    let idleMilliseconds: Int
}

/// One attempt to open an upstream, shared by every caller that arrives while it is in flight.
struct StartFlight {
    let attempt: StartAttemptID
    let task: Task<PoolHandle, Error>
}

/// The pool's per-upstream state.
struct PoolEntry {
    var handle: PoolHandle?
    var starting: StartFlight?
    var reap: ReapTimer?
    /// Calls currently awaiting a response. Never reap above zero.
    var inFlight: Int = 0
    /// Live lease ids, so a release is honoured exactly once.
    var activeLeases: Set<LeaseID> = []
    /// Callers that have committed to taking a lease but are still awaiting the start. The reaper
    /// treats these exactly like work outstanding, because that is what they are about to become.
    var pendingWaiters: Int = 0
}

/// An upstream that answered 401 and wants the user to authorize in a browser.
public struct PendingAuth: Sendable, Hashable {
    public let server: String
    /// The browser URL to finish the flow, when there is one.
    ///
    /// Optional since 2026-08-20: an upstream that rejects a REFRESH never reaches the
    /// redirect callback, so there is no URL to offer and the server still needs
    /// authorizing. Requiring it is what forced the index path to record nothing at all,
    /// which is how a dead credential came to read as `idle` on every surface.
    public let url: String?
    public let at: String
    /// The failure text, when this came from a rejection rather than a redirect.
    public let reason: String?

    public init(server: String, url: String? = nil, at: String, reason: String? = nil) {
        self.server = server
        self.url = url
        self.at = at
        self.reason = reason
    }
}

/// One upstream's live state, as `/status` reports it.
public struct UpstreamStatus: Sendable, Hashable {
    public let name: String
    public let transport: String
    public let state: String
    /// The acquisition counter (D6). Named for the wire, whose field name F3's client is built
    /// against; its true semantics are in the spec, so no later runner "corrects" it into
    /// something R4 reads as a regression.
    public let callsServed: Int
    public let inFlight: Int
    public let idleSec: Int

    public init(
        name: String,
        transport: String,
        state: String,
        callsServed: Int,
        inFlight: Int,
        idleSec: Int
    ) {
        self.name = name
        self.transport = transport
        self.state = state
        self.callsServed = callsServed
        self.inFlight = inFlight
        self.idleSec = idleSec
    }
}

public enum PoolError: Error, Sendable, Equatable, CustomStringConvertible {
    case shuttingDown
    case unknownUpstream(String)
    case superseded(String)
    case startupTimeout(name: String, milliseconds: Int)
    case legacySSEUnsupported(String)
    case spawnFailed(name: String, reason: String)
    /// The command could not be resolved on the PATH the child would have been given.
    ///
    /// Its own case rather than a `spawnFailed` with a particular reason string, because it is the
    /// one spawn failure with a specific cause and a specific remedy, and a caller that wants to
    /// treat it differently should not have to match on prose. R6.
    case commandNotFound(name: String, command: String, searchedPath: String)

    /// What the **wire** carries for this failure, which is not always `description`.
    ///
    /// A spawn failure is the exception and it is measured: the reference's `indexOne` reports
    /// `err.message`, and Node's message for a command that does not exist is `spawn <cmd> ENOENT`
    /// with no wrapper of its own. Reporting `description` there would prefix it with
    /// `upstream "x" could not be started: `, which the reference never writes — so `mcp-router
    /// import` would disagree on every failing server.
    ///
    /// `commandNotFound` carries that same text for the same reason: it replaced a `spawnFailed`
    /// whose reason was already `spawn <cmd> ENOENT`, and the `cli-import` parity lane diffs it.
    /// The richer wording lives in `description`, which is not on the wire.
    public var message: String {
        switch self {
        case let .spawnFailed(_, reason): reason
        case let .commandNotFound(_, command, _): "spawn \(command) ENOENT"
        default: description
        }
    }

    public var description: String {
        switch self {
        case .shuttingDown:
            "router is shutting down"
        case let .unknownUpstream(name):
            "unknown upstream server \"\(name)\""
        case let .superseded(name):
            "upstream \"\(name)\" was superseded while starting"
        case let .startupTimeout(name, milliseconds):
            "upstream \"\(name)\" did not initialize within \(milliseconds)ms"
        case let .legacySSEUnsupported(name):
            "Upstream \"\(name)\" uses the legacy SSE transport, which the Swift router "
                + "cannot speak. Keep this server on the TypeScript router until it is migrated "
                + "to streamable HTTP."
        case let .spawnFailed(name, reason):
            "upstream \"\(name)\" could not be started: \(reason)"
        case let .commandNotFound(name, command, searchedPath):
            // The directory count is the length of the PATH actually searched, not an assertion
            // about the machine: DESIGN.md §6 forbids displaying a number the router did not
            // observe, and this one is observed at the moment the lookup fails.
            "upstream \"\(name)\" could not be started: spawn \(command) ENOENT — "
                + "\"\(command)\" is not in any of the "
                + "\(searchedPath.split(separator: ":", omittingEmptySubsequences: true).count) "
                + "directories on the router's PATH. Install it, or give this server an "
                + "absolute command."
        }
    }
}
