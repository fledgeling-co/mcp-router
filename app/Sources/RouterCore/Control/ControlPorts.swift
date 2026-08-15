import Foundation

/// One upstream as the pool reports it live.
///
/// `name` is a ``JSString`` rather than a Swift `String` deliberately. Swift compares strings by
/// **canonical equivalence**, so a composed `"é"` and a decomposed `"e\u{0301}"` are equal; the
/// reference compares UTF-16 code units, where they are two distinct servers. Typing the port
/// surface closes that by construction — a later `$0.name == name` cannot silently reintroduce it,
/// which a comparison helper over `String` would have allowed (S5, B24).
public struct LiveUpstream: Sendable, Hashable {
    public let name: JSString
    /// Nullish-defaulted at the point of use, so a live row reporting `0` stays `0` (B7).
    public let state: String?
    public let inFlight: Int?
    public let callsServed: Int?
    public let idleSec: Int?

    public init(
        name: JSString,
        state: String? = nil,
        inFlight: Int? = nil,
        callsServed: Int? = nil,
        idleSec: Int? = nil
    ) {
        self.name = name
        self.state = state
        self.inFlight = inFlight
        self.callsServed = callsServed
        self.idleSec = idleSec
    }
}

/// An authorization the pool is waiting on, discovered when an upstream refused a call.
///
/// Distinct from ``AuthFlowSummary``: this is the pool noticing a 401 mid-call, that is the router
/// driving a browser flow. The recorded fixtures carry a top-level `pendingAuth` from the second
/// while the server row's `pendingUrl` is absent, which is only explicable if they are two things.
public struct PendingAuthRow: Sendable, Hashable {
    public let server: JSString
    public let url: String

    public init(server: JSString, url: String) {
        self.server = server
        self.url = url
    }
}

/// The pool, as the control API needs it.
///
/// A protocol because the pool is R2's, running concurrently rather than merged. Every lookup
/// through it is **first-match**, matching `Array.prototype.find` — a `last(where:)` passes any
/// single-row fixture and is wrong (B6, B7).
public protocol UpstreamPoolPort: Sendable {
    func status() -> [LiveUpstream]
    func pending() -> [PendingAuthRow]
    func isLive(_ name: JSString) -> Bool
    /// Requested, never awaited: a warming failure must not turn a 200 into an error (B43).
    func warmUp()
    func clearPending(_ name: JSString)
}

public extension UpstreamPoolPort {
    func firstStatus(_ name: JSString) -> LiveUpstream? {
        status().first { $0.name == name }
    }

    func firstPending(_ name: JSString) -> PendingAuthRow? {
        pending().first { $0.server == name }
    }
}

/// What indexing one candidate produced.
public struct IndexOutcome: Sendable, Hashable {
    public let tools: Int
    /// `undefined` when the index succeeded. An **empty string** is a distinct, ported case: the
    /// reference's `error ? 422 : 200` is a truthiness test, so `""` yields 200 while
    /// `JSON.stringify` still emits `"error":""` (B33, S1, S3).
    public let error: String?

    public init(tools: Int, error: String? = nil) {
        self.tools = tools
        self.error = error
    }

    /// The reference's test for "expected to refuse a first connection". An OAuth server is
    /// *supposed* to fail here, and refusing it would make one impossible to add at all.
    public var isAuthorizationPending: Bool {
        guard let error, !error.isEmpty else { return false }
        let lowered = error.lowercased()
        return lowered.contains("not authorized")
            || lowered.contains("unauthorized")
            || lowered.contains("401")
    }
}

/// Spawning a candidate to record its tools — `indexOne`'s seam. R2 owns the spawning.
public protocol UpstreamIndexerPort: Sendable {
    func index(_ upstream: UpstreamConfig) async -> IndexOutcome
}

/// The credential store, behind a protocol so a test can enter states the real filesystem will not
/// enter on request — an unreadable record, a record with no access token (B60, B61).
///
/// Typed in ``JSString`` for the same reason ``UpstreamPoolPort`` is: the server name reaching this
/// store comes from a request path, and a composed name must not find a decomposed record (S5,
/// B24). **R5 implements this protocol** — the seam is typed here so that item inherits the
/// constraint rather than having to rediscover it.
public protocol AuthStore: Sendable {
    func hasTokens(_ server: JSString) -> Bool
    func authorizedAt(_ server: JSString) -> String?
    /// Reports whether a record existed, which is what `signedOut` carries (B62).
    @discardableResult func clear(_ server: JSString) -> Bool
}

/// The browser authorization currently in flight, if any. At most one: the callback port is fixed,
/// so a second flow cancels the first rather than failing to bind (B64).
public struct AuthFlowSummary: Sendable, Hashable {
    public let server: String
    public let url: String

    public init(server: String, url: String) {
        self.server = server
        self.url = url
    }
}

/// Beginning a browser authorization — the reference's `beginAuth(name, authTransportFor(u))`.
///
/// **Optional on ``ControlDeps``**, because the collaborator behind it does not exist yet: no type
/// conforms to ``AuthTransport``, so nothing can drive an OAuth exchange (`D-p1-a`). A handler that
/// constructed the coordinator itself could not be told that, and would have to invent an answer
/// for a flow it cannot drive. With this absent, a non-stdio `POST /servers/:name/auth` falls
/// through to the 405 it has always answered rather than claiming a failure that never happened.
public protocol AuthFlowStarting: Sendable {
    /// Returns once the authorization URL is known. Throws on either pre-flow failure (B84), which
    /// the route turns into a 502.
    func begin(server: JSString, upstream: UpstreamConfig) async throws -> LiveFlow

    /// Resolves when the flow terminates: returns on success, throws the rejection on failure, and
    /// throws ``AuthAbandoned`` when the flow was superseded (B85).
    ///
    /// **``begin(server:upstream:)`` must arm this channel before it returns.** A flow that settles
    /// between the two calls must still be reported here as authorized.
    /// ``AuthFlowCoordinator/awaitCompletion(server:)`` now meets that: it records the outcome of a
    /// settled flow per server and answers from that record when nothing is in flight (`D-p1-c`,
    /// closed). Before that it threw `no authorization is in flight` once the flow had settled,
    /// which turned a *successful* authorization into an `onIncomplete` warn with no `clearPending`
    /// and no re-index — the tokens landed on disk and the tools never appeared.
    ///
    /// Note that `AuthFlowCoordinator` does not *conform* to this protocol: nothing does yet, which
    /// is `D-p1-a` and why `control-auth-post-http` is a blocked parity row. The requirement stays
    /// stated here because whatever conforms will have to meet it in its own right, and the
    /// coordinator's behaviour is the worked example rather than the inherited implementation.
    func awaitCompletion(server: JSString) async throws
}

/// Everything the handler reads. Assembled by R2's router; every member is injectable, which is
/// what makes S6 — the handler as a total function of its dependencies — testable rather than
/// aspirational.
public struct ControlDeps: Sendable {
    public var config: RouterConfig
    /// The live upstream map, in insertion order. An array of pairs rather than a dictionary:
    /// `GET /servers` serialises in map order (B13) and lookup is by JavaScript string identity
    /// with no normalisation (B24), neither of which a Swift `Dictionary` gives.
    public var upstreams: [(name: JSString, upstream: UpstreamConfig)]
    public var pool: any UpstreamPoolPort
    public var indexer: any UpstreamIndexerPort
    public var auth: any AuthStore
    public var usage: UsageStore
    public var manifest: Manifest
    public var currentFlow: AuthFlowSummary?
    public var clock: any RouterClock
    public var fileSystem: any FileSystem & FileModeWriting
    public var tokenPath: String
    public var configPath: String
    /// `/registry/search` is the one endpoint that reaches the network, so it is the one
    /// dependency that can legitimately be missing — and it was missing in the daemon until P3,
    /// which is why the route answered 502 in the only process that ships. `RouterService` now
    /// supplies ``RegistryHTTPClient``. It stays OPTIONAL because `ControlDiff`, the in-process
    /// differential oracle, deliberately does not supply one: giving that harness a live client
    /// would put a real registry call inside every control-lane run, unpinned and rate-limited.
    public var registry: RegistryDeps?
    /// The router's log. Optional because the in-process differential oracle has none, and because
    /// every line the control API emits is a side effect rather than part of a response — a nil log
    /// changes no status and no byte on the wire. `POST /servers/:name/approve` is the one route
    /// that logs (B94).
    public var log: RouterLog?
    /// Starting a browser authorization. Nil until something conforms to ``AuthTransport``
    /// (`D-p1-a`); see ``AuthFlowStarting`` for what its absence means on the wire.
    public var authFlow: (any AuthFlowStarting)?

    public init(
        config: RouterConfig,
        upstreams: [(name: JSString, upstream: UpstreamConfig)],
        pool: any UpstreamPoolPort,
        indexer: any UpstreamIndexerPort,
        auth: any AuthStore,
        usage: UsageStore,
        manifest: Manifest,
        currentFlow: AuthFlowSummary? = nil,
        clock: any RouterClock = SystemClock(),
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem(),
        tokenPath: String,
        configPath: String,
        registry: RegistryDeps? = nil,
        log: RouterLog? = nil,
        authFlow: (any AuthFlowStarting)? = nil
    ) {
        self.config = config
        self.upstreams = upstreams
        self.pool = pool
        self.indexer = indexer
        self.auth = auth
        self.usage = usage
        self.manifest = manifest
        self.currentFlow = currentFlow
        self.clock = clock
        self.fileSystem = fileSystem
        self.tokenPath = tokenPath
        self.configPath = configPath
        self.registry = registry
        self.log = log
        self.authFlow = authFlow
    }

    /// Lookup by JavaScript string identity — a composed key does not match a decomposed request,
    /// which a Swift `[String: …]` would happily conflate (B24).
    public func upstream(named name: JSString) -> UpstreamConfig? {
        upstreams.first { $0.name == name }?.upstream
    }

    public func hasUpstream(named name: JSString) -> Bool {
        upstreams.contains { $0.name == name }
    }
}
