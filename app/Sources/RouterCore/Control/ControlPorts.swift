import Foundation

/// One upstream as the pool reports it live.
public struct LiveUpstream: Sendable, Hashable {
    public let name: String
    /// Nullish-defaulted at the point of use, so a live row reporting `0` stays `0` (B7).
    public let state: String?
    public let inFlight: Int?
    public let callsServed: Int?
    public let idleSec: Int?

    public init(
        name: String,
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
public struct PendingAuth: Sendable, Hashable {
    public let server: String
    public let url: String

    public init(server: String, url: String) {
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
    func pending() -> [PendingAuth]
    func isLive(_ name: String) -> Bool
    /// Requested, never awaited: a warming failure must not turn a 200 into an error (B43).
    func warmUp()
    func clearPending(_ name: String)
}

public extension UpstreamPoolPort {
    func firstStatus(_ name: String) -> LiveUpstream? {
        status().first { $0.name == name }
    }

    func firstPending(_ name: String) -> PendingAuth? {
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
public protocol AuthStore: Sendable {
    func hasTokens(_ server: String) -> Bool
    func authorizedAt(_ server: String) -> String?
    /// Reports whether a record existed, which is what `signedOut` carries (B62).
    @discardableResult func clear(_ server: String) -> Bool
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
    public var fileSystem: any FileSystem
    public var tokenPath: String
    public var configPath: String
    /// Absent until R2 wires a real HTTP client. `/registry/search` is the one endpoint that
    /// reaches the network, so it is the one dependency that can legitimately be missing.
    public var registry: RegistryDeps?

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
        fileSystem: any FileSystem = RealFileSystem(),
        tokenPath: String,
        configPath: String,
        registry: RegistryDeps? = nil
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
