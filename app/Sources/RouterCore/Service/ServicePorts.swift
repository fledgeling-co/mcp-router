import Foundation
import MCP

/// The adapters between R3's synchronous control ports and R2's actors.
///
/// Both gaps are real and were found by building the process rather than by reading: `UpstreamPool`
/// is an actor while `UpstreamPoolPort` is synchronous, and `FileAuthStore`'s reads are `async`
/// while `AuthStore`'s are not. Neither seam was wrong — each was written for the item that owned it
/// — but nothing had ever had to hold both at once, because nothing had ever composed them.
///
/// The resolution is a **snapshot per request**, not a blocking wait. Every value the control
/// handler can read is fetched before the handler runs, so the handler stays what R3 built it to be:
/// a total function of its dependencies.

/// The pool's live state, read once per control request.
public struct PoolSnapshotPort: UpstreamPoolPort {
    let rows: [LiveUpstream]
    let pendingRows: [PendingAuthRow]
    let livenames: Set<String>
    let pool: UpstreamPool

    public init(pool: UpstreamPool) async {
        self.pool = pool
        let status = await pool.status()
        rows = status.map {
            LiveUpstream(
                name: JSString($0.name),
                state: $0.state,
                inFlight: $0.inFlight,
                callsServed: $0.callsServed,
                idleSec: $0.idleSec
            )
        }
        pendingRows = await pool.pending().map {
            PendingAuthRow(server: JSString($0.server), url: $0.url)
        }
        livenames = Set(status.filter { $0.state == "running" }.map(\.name))
    }

    public func status() -> [LiveUpstream] { rows }
    public func pending() -> [PendingAuthRow] { pendingRows }
    public func isLive(_ name: JSString) -> Bool { livenames.contains(name.string) }

    /// Requested, never awaited: a warming failure must not turn a 200 into an error.
    public func warmUp() {
        let pool = pool
        Task { await pool.warmUp() }
    }

    public func clearPending(_ name: JSString) {
        let pool = pool
        let server = name.string
        Task { await pool.clearPending(server) }
    }
}

/// The credential store, read once per control request.
///
/// `FileAuthStore.read` touches the filesystem, so this reads each configured server's record up
/// front rather than leaving the handler to await one mid-response. That is also what the reference
/// does — `describe()` reads a record per server while building `GET /servers`.
public struct SnapshotAuthStore: AuthStore {
    let authorized: Set<String>
    let stamps: [String: String]
    let store: FileAuthStore

    public init(store: FileAuthStore, servers: [JSString]) async {
        self.store = store
        var authorized: Set<String> = []
        // swift-wire-exempt: a local index, never serialised.
        var stamps: [String: String] = [:]
        for server in servers {
            if await store.hasTokens(server) { authorized.insert(server.string) }
            if let at = await store.authorizedAt(server) { stamps[server.string] = at.string }
        }
        self.authorized = authorized
        self.stamps = stamps
    }

    public func hasTokens(_ server: JSString) -> Bool { authorized.contains(server.string) }
    public func authorizedAt(_ server: JSString) -> String? { stamps[server.string] }

    @discardableResult public func clear(_ server: JSString) -> Bool { store.clear(server) }
}

/// Opens whichever transport an upstream declares.
///
/// `StdioUpstreamTransport` is R2's and unchanged. The HTTP half is what R2 deferred, and it is
/// here rather than in a second pool because the pool's whole contract — one live session per
/// upstream, leased and reaped — is transport-independent by design.
public struct RoutingUpstreamTransport: UpstreamTransporting {
    let stdio: StdioUpstreamTransport
    let http: HTTPUpstreamTransport

    public init(log: RouterLog? = nil, authorizing: any UpstreamAuthorizing = NoUpstreamAuthorizing()) {
        stdio = StdioUpstreamTransport(log: log)
        http = HTTPUpstreamTransport(log: log, authorizing: authorizing)
    }

    public func open(
        _ upstream: UpstreamConfig, timeoutMilliseconds: Int
    ) async throws -> any UpstreamSession {
        if upstream.isStdio {
            return try await stdio.open(upstream, timeoutMilliseconds: timeoutMilliseconds)
        }
        return try await http.open(upstream, timeoutMilliseconds: timeoutMilliseconds)
    }
}

/// An HTTP upstream: the pinned SDK's `HTTPClientTransport`, tapped for the same reason the stdio
/// one is.
///
/// There is no process here, so `processIdentifier` is `nil` rather than zero — `residentMb()`
/// omits upstreams with no process, and reporting a zero would be reporting a number nobody
/// measured.
public struct HTTPUpstreamTransport: UpstreamTransporting {
    let log: RouterLog?
    let authorizing: any UpstreamAuthorizing
    let clientName: String
    let clientVersion: String

    public init(
        log: RouterLog? = nil,
        authorizing: any UpstreamAuthorizing = NoUpstreamAuthorizing(),
        clientName: String = "mcp-router",
        clientVersion: String = "0.1.0"
    ) {
        self.log = log
        self.authorizing = authorizing
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    public func open(
        _ upstream: UpstreamConfig, timeoutMilliseconds: Int
    ) async throws -> any UpstreamSession {
        guard upstream.isHTTP, let raw = upstream.url, let url = URL(string: raw) else {
            throw PoolError.spawnFailed(name: upstream.name, reason: "no url configured")
        }
        // The legacy SSE transport is refused by the pool before it reaches here; asserted again
        // because a transport that silently downgraded would be worse than one that refuses.
        guard upstream.transport != .sse else {
            throw PoolError.legacySSEUnsupported(upstream.name)
        }

        let tap = ResponseTap()
        // `oauth: false` must suppress authorization entirely rather than merely fail it, which is
        // why this asks the seam for an authorizer rather than always attaching one.
        let transport = TappingTransport(
            wrapping: HTTPClientTransport(
                endpoint: url,
                streaming: false,
                authorizer: authorizing.authorizer(for: upstream.name)
            ),
            tap: tap
        )
        let client = Client(name: clientName, version: clientVersion)
        let session = HTTPUpstreamSession(client: client, tap: tap)

        do {
            _ = try await client.connect(transport: transport)
        } catch {
            await session.shutdown()
            let reason = "\(error)"
            // A 401 means the user has to authorize in a browser. The router runs under launchd
            // with no user attached, so the challenge is recorded rather than opened.
            if reason.lowercased().contains("401") || reason.lowercased().contains("unauthorized") {
                authorizing.challenge(upstreamName: upstream.name, url: raw)
                await log?.record(PoolLogEvent.needsAuthorization(server: upstream.name))
            }
            throw PoolError.spawnFailed(name: upstream.name, reason: reason)
        }
        return session
    }
}

/// One live HTTP upstream.
final class HTTPUpstreamSession: UpstreamSession, Sendable {
    let processIdentifier: Int32? = nil
    private let client: Client
    private let tap: ResponseTap
    private let ended = EndSignal()

    init(client: Client, tap: ResponseTap) {
        self.client = client
        self.tap = tap
    }

    /// An HTTP session ends when its client disconnects. There is no EOF to await and no process to
    /// reap, so this resolves only when ``shutdown()`` fires the signal — which is the honest
    /// answer: nothing else can tell us the far end has gone until a call fails.
    func waitUntilEnded() async {
        await ended.wait()
    }

    func shutdown() async {
        await client.disconnect()
        ended.fire()
    }

    func listTools() async throws -> JSONValue {
        try await RawRequest.perform(
            RawListTools.self, client: client, tap: tap, parameters: .object([])
        )
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try await RawRequest.perform(
            RawCallTool.self, client: client, tap: tap,
            parameters: .object([
                JSONMember(key: JSString("name"), value: .string(JSString(name))),
                JSONMember(key: JSString("arguments"), value: arguments)
            ])
        )
    }
}

/// `indexOne`: lease an upstream, ask it for its tools, and write the entry.
///
/// The seam R3 declared and nobody implemented. It is what `POST /servers/:name/reindex` and
/// `mcp-router index` both run, which is why it lives here rather than inside either.
public struct ManifestIndexer: UpstreamIndexerPort {
    let pool: UpstreamPool
    let manifestPath: String
    let fileSystem: any FileSystem
    let clock: any RouterClock
    let log: RouterLog?

    public init(
        pool: UpstreamPool,
        manifestPath: String,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        log: RouterLog? = nil
    ) {
        self.pool = pool
        self.manifestPath = manifestPath
        self.fileSystem = fileSystem
        self.clock = clock
        self.log = log
    }

    public func index(_ upstream: UpstreamConfig) async -> IndexOutcome {
        let tools: [CachedTool]
        do {
            let lease = try await pool.lease(upstream.name)
            defer { Task { [pool] in await pool.release(lease) } }
            let listed = try await lease.session.listTools()
            guard case let .object(members) = listed,
                  case let .array(items)? = members.first(where: { $0.key == JSString("tools") })?.value
            else {
                return IndexOutcome(tools: 0, error: "the upstream returned no tools array")
            }
            tools = items.compactMap(CachedTool.init)
        } catch {
            let reason = (error as? PoolError)?.message ?? "\(error)"
            await log?.record(LogEvent.serverIndexFailed(server: upstream.name, reason: reason))
            // The entry is still written, carrying the error — the reference records a failure
            // rather than leaving the previous tools looking current.
            record(upstream, tools: [], error: reason)
            return IndexOutcome(tools: 0, error: reason)
        }

        let outcome = record(upstream, tools: tools, error: nil)
        if case let .heldForApproval(changeCount) = outcome {
            await log?.record(LogEvent.serverSurfaceChanged(
                server: upstream.name, changeCount: changeCount
            ))
        } else {
            await log?.record(LogEvent.serverIndexed(server: upstream.name, toolCount: tools.count))
        }
        return IndexOutcome(tools: tools.count)
    }

    /// Write the entry through R1's bookkeeping, which owns the pending/approved rules — a second
    /// implementation here would be a second place for the surface-change semantics to drift.
    ///
    /// Returns the change count when the surface moved, so the caller can log the reference's
    /// "changed its tool surface" warning rather than reporting a silent success.
    @discardableResult
    private func record(
        _ upstream: UpstreamConfig, tools: [CachedTool], error: String?
    ) -> ManifestBookkeeping.Outcome {
        var manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest
        let step = ManifestBookkeeping.apply(
            previous: manifest.entry(named: upstream.name),
            observation: error.map { ManifestBookkeeping.Observation.failure(message: $0) }
                ?? .tools(tools),
            configHash: UpstreamHash.hash(upstream),
            nowMilliseconds: clock.nowMilliseconds
        )
        manifest.setEntry(upstream.name, step.entry)
        try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)
        return step.outcome
    }
}
