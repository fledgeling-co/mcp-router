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
    let deadline: ContinuousClock.Instant
    let task: Task<Void, Never>
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
    public let url: String
    public let at: String

    public init(server: String, url: String, at: String) {
        self.server = server
        self.url = url
        self.at = at
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
        }
    }
}
