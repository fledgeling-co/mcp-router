import Foundation
import Synchronization

/// The composition root: one object that owns the listener, the pool, the manifest store, the usage
/// store, the control handler and the relay, and dispatches a request between them.
///
/// This is the piece R2 deferred and nobody owned. Everything under it existed and was tested; what
/// did not exist was a process that put them together and answered a socket.
///
/// **Dispatch order is `src/router.ts`'s and is not rearrangeable.** Identity is started at accept
/// time, `/health` and `/status` are answered before the control block — deliberately
/// unauthenticated, which is why they are dispatched first rather than gated and then excepted —
/// then control paths, then `/mcp`, then 404.
public actor RouterService {
    public struct Options: Sendable {
        public var configPath: String?
        public var port: Int?
        public var host: String?
        public var idleMs: Int?
        public var verbose: Bool

        public init(
            configPath: String? = nil,
            port: Int? = nil,
            host: String? = nil,
            idleMs: Int? = nil,
            verbose: Bool = false
        ) {
            self.configPath = configPath
            self.port = port
            self.host = host
            self.idleMs = idleMs
            self.verbose = verbose
        }
    }

    let config: RouterConfig
    let home: RouterHome
    let fileSystem: any FileSystem
    let clock: any RouterClock
    let log: RouterLog
    let manifest: ManifestStore
    let pool: UpstreamPool
    let usage: UsageStore
    let auth: FileAuthStore
    let token: String
    let tokenPath: String
    let configPath: String
    private let server = LoopbackHTTPServer()
    private let resolver: any PeerResolver
    private let identities = AttributionCache()
    private var stopping = false

    /// Build the whole graph from a loaded configuration.
    ///
    /// Not `throws` for anything that can be degraded: a manifest that will not parse serves the
    /// previous one and records why, and a usage log that cannot be read starts empty. The only
    /// failures that reach a caller are the ones that make serving impossible.
    public init(
        loaded: LoadedConfig,
        home: RouterHome,
        log: RouterLog,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        resolver: (any PeerResolver)? = nil
    ) {
        config = loaded.config
        self.home = home
        self.fileSystem = fileSystem
        self.clock = clock
        self.log = log
        self.resolver = resolver ?? LibProcPeerResolver()
        configPath = home.configPath
        manifest = ManifestStore(
            path: config.manifestPath, fileSystem: fileSystem, clock: clock, log: log
        )
        usage = UsageStore(
            logPath: config.usagePath, statsPath: config.statsPath, fileSystem: fileSystem
        )
        auth = FileAuthStore(authDir: config.authDir, log: log)
        pool = UpstreamPool(
            upstreams: config.upstreams,
            defaultIdleMilliseconds: config.idleMs,
            defaultStartupTimeoutMilliseconds: config.startupTimeoutMs,
            transporting: RoutingUpstreamTransport(log: log),
            clock: clock,
            log: log
        )
        // Whether the token already existed is read *before* loading it, because `load()` mints one
        // when it is missing and there is no way to ask afterwards which happened. The reference
        // logs "wrote a new control token" only on the minting path.
        let path = (home.root as NSString).appendingPathComponent("control.token")
        tokenPath = path
        wroteToken = !fileSystem.fileExists(atPath: path)
        token = (try? ControlToken(path: path, fileSystem: fileSystem).load()) ?? ""
    }

    private let wroteToken: Bool

    /// The port actually bound. Read after ``start()``; a test asks for port 0 and reads it back.
    public var boundPort: Int? {
        get async { await server.boundPort }
    }

    // MARK: - Lifecycle

    public func start() async throws {
        // The stale-manifest warning comes **before** the token line, because the reference emits it
        // in `cmdServe` while the token is minted later inside `startRouter`. Measured, and the
        // order is part of what `parity-log.sh` diffs — a log whose lines are individually correct
        // and collectively out of order is a log nobody can diff.
        let current = await manifest.current()
        let stale = config.upstreams.filter { ToolUnion.isStale(current, $0) }
        if !stale.isEmpty {
            await log.record(ServiceLogEvent.notInManifest(
                count: stale.count, names: stale.map(\.name)
            ))
        }
        if wroteToken {
            await log.record(ServiceLogEvent.wroteControlToken(path: tokenPath))
        }

        let handle = Handler(service: self)
        try await server.start(
            port: config.port,
            onAccept: { [identities, resolver] descriptor in
                // Identify at accept time, not when a call finishes. The lookup asks the OS who
                // holds the other end of this socket, so it can only answer while that process
                // exists — deferring it to the end of a tool call loses every short-lived client,
                // and the answer is cached so awaiting it later costs nothing.
                Task.detached {
                    guard let port = Self.peerPort(of: descriptor.peer) else { return }
                    let identity = resolver.identity(peerPort: port)
                    if let pid = identity.pid { identities.store(identity, for: pid) }
                    PeerIdentities.shared.store(identity, for: descriptor)
                }
            },
            handler: { request in await handle.respond(to: request) }
        )

        await log.record(ServiceLogEvent.listening(
            host: config.host, port: config.port, path: MCPEndpoint.path
        ))
        let tools = ToolUnion.unionTools(manifest: current, upstreams: config.upstreams).count
        await log.record(ServiceLogEvent.serving(
            tools: tools,
            upstreams: config.upstreams.count,
            open: 0,
            idleSeconds: Int((Double(config.idleMs) / 1000).rounded())
        ))

        // After listen(), so a slow warm server delays no client: the router is already answering
        // tools/list from cache while these open in the background.
        await pool.warmUp()
    }

    /// Graceful stop, in the reference's order: flush what was recorded, stop accepting, close every
    /// upstream. Idempotent, because two signals can arrive.
    public func stop(signal: String? = nil) async {
        guard !stopping else { return }
        stopping = true
        if let signal {
            await log.record(ServiceLogEvent.signalReceived(signal: signal))
        }
        usage.flush()
        await server.stop()
        await pool.shutdown()
    }

    // MARK: - Dispatch

    func respond(to request: HTTPWireRequest) async -> HTTPWireResponse {
        let (path, query) = request.pathAndQuery

        if path == "/health", request.method == "GET" {
            return .json(200, Data(JSStringify.compact(.object([
                JSONMember(key: JSString("ok"), value: .bool(true)),
                JSONMember(
                    key: JSString("upstreams"),
                    value: .number(Double(config.upstreams.count))
                )
            ])).utf8))
        }

        if path == "/status", request.method == "GET" {
            return await statusResponse()
        }

        if ControlPaths.isControlPath(path) {
            if let response = await controlResponse(request, path: path, query: query) {
                return response
            }
        }

        guard path == MCPEndpoint.path else {
            return .json(404, Data(JSStringify.compact(.object([
                JSONMember(
                    key: JSString("error"),
                    value: .string(JSString("not found; MCP endpoint is \(MCPEndpoint.path)"))
                )
            ])).utf8), reason: "Not Found")
        }

        let endpoint = MCPEndpoint(
            deps: MCPEndpoint.Deps(
                config: config,
                upstreams: config.upstreams,
                manifest: manifest,
                pool: pool,
                usage: usage,
                log: log,
                clock: clock
            ),
            identify: { descriptor in
                let identity = PeerIdentities.shared.identity(for: descriptor)
                return CallerIdentity(
                    pid: identity.pid.map(Int.init), cwd: identity.cwd, client: identity.client
                )
            }
        ).with(connection: request.connection)
        return await endpoint.respond(to: request)
    }

    private func statusResponse() async -> HTTPWireResponse {
        let live = await pool.status()
        let pending = await pool.pending()
        let current = await manifest.current()
        let children = live.map { row in
            JSONValue.object([
                JSONMember(key: JSString("name"), value: .string(JSString(row.name))),
                JSONMember(key: JSString("transport"), value: .string(JSString(row.transport))),
                JSONMember(key: JSString("state"), value: .string(JSString(row.state))),
                JSONMember(key: JSString("callsServed"), value: .number(Double(row.callsServed))),
                JSONMember(key: JSString("inFlight"), value: .number(Double(row.inFlight))),
                JSONMember(key: JSString("idleSec"), value: .number(Double(row.idleSec)))
            ])
        }
        let body = JSONValue.object([
            JSONMember(key: JSString("ok"), value: .bool(true)),
            JSONMember(key: JSString("port"), value: .number(Double(config.port))),
            JSONMember(key: JSString("idleMs"), value: .number(Double(config.idleMs))),
            JSONMember(key: JSString("children"), value: .array(children)),
            JSONMember(key: JSString("pendingAuth"), value: .array(pending.map { row in
                .object([
                    JSONMember(key: JSString("server"), value: .string(JSString(row.server)))
                ])
            })),
            JSONMember(
                key: JSString("tools"),
                value: .number(Double(ToolUnion.unionTools(
                    manifest: current, upstreams: config.upstreams
                ).count))
            )
        ])
        return .json(200, Data(JSStringify.compact(body).utf8))
    }

    /// The control API, adapted from the wire type to R3's own request type.
    ///
    /// Returns `nil` only when the handler declined the path, which cannot happen here because
    /// ``ControlPaths/isControlPath(_:)`` gated it — but the disposition travels with the response
    /// for a reason, and honouring it is what stops a mistyped control path falling through to the
    /// relay.
    private func controlResponse(
        _ request: HTTPWireRequest, path: String, query: String?
    ) async -> HTTPWireResponse? {
        var deps = ControlDeps(
            config: config,
            upstreams: config.upstreams.map { (name: JSString($0.name), upstream: $0) },
            pool: await PoolSnapshotPort(pool: pool),
            indexer: ManifestIndexer(pool: pool, manifestPath: config.manifestPath,
                                     fileSystem: fileSystem, clock: clock, log: log),
            auth: await SnapshotAuthStore(
                store: auth, servers: config.upstreams.map { JSString($0.name) }
            ),
            usage: usage,
            manifest: await manifest.current(),
            clock: clock,
            fileSystem: fileSystem,
            tokenPath: tokenPath,
            configPath: configPath
        )
        let handler = ControlHandler(token: token)
        let response = await handler.handle(
            ControlAPIRequest(
                method: request.method,
                encodedPath: path,
                query: Self.queryItems(query),
                headers: request.headers,
                body: request.body.isEmpty ? nil : request.body
            ),
            &deps
        )
        guard response.handled else { return nil }

        switch response.body {
        case let .bytes(bytes):
            return HTTPWireResponse(
                status: response.status,
                headers: response.headers.map { (name: $0.name, value: $0.value) },
                body: .bytes(Data(bytes))
            )
        case let .stream(description):
            return Self.usageStream(description, status: response.status,
                                    headers: response.headers, usage: usage)
        }
    }

    /// `/usage/stream`: the opening comment, then one frame per record, then a heartbeat every 25 s
    /// so a proxy or a sleeping Mac cannot make an idle stream look disconnected.
    private static func usageStream(
        _ description: ControlStream,
        status: Int,
        headers: [(name: String, value: String)],
        usage: UsageStore
    ) -> HTTPWireResponse {
        let stream = AsyncStream<Data> { continuation in
            continuation.yield(Data(description.openingFrame))
            // Boxed because the unsubscribe closure is not `Sendable` and `onTermination` is. The
            // box is the smallest honest synchronisation: one write at subscribe, one read at
            // termination, and nothing else touches it.
            let unsubscribe = UnsubscribeBox(usage.subscribe { record in
                continuation.yield(Data(ControlStream.frame(for: record.value)))
            })
            let heartbeat = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(
                        nanoseconds: UInt64(ControlStream.heartbeatMilliseconds) * 1_000_000
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(Data(description.heartbeatFrame))
                }
            }
            // The reader going away fires this, which is the only cancellation channel there is —
            // and the one that cannot be forgotten, because it is the stream's own.
            continuation.onTermination = { _ in
                unsubscribe.cancel()
                heartbeat.cancel()
            }
        }
        return HTTPWireResponse(
            status: status,
            headers: headers.map { (name: $0.name, value: $0.value) },
            body: .chunks(stream),
            keepAlive: false
        )
    }

    /// `URLSearchParams` semantics: `+` is a space, then percent decoding, and repeats are kept in
    /// arrival order so the handler's first-wins lookup can be honest.
    static func queryItems(_ raw: String?) -> [(name: String, value: String)] {
        guard let raw, !raw.isEmpty else { return [] }
        var items: [(name: String, value: String)] = []
        for pair in raw.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            let text = String(pair)
            guard let equals = text.firstIndex(of: "=") else {
                items.append((name: decode(text), value: ""))
                continue
            }
            items.append((
                name: decode(String(text[text.startIndex ..< equals])),
                value: decode(String(text[text.index(after: equals)...]))
            ))
        }
        return items
    }

    static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }

    /// The port half of a `host:port` peer description.
    static func peerPort(of peer: String) -> UInt16? {
        guard let colon = peer.lastIndex(of: ":") else { return nil }
        return UInt16(peer[peer.index(after: colon)...])
    }
}

/// A non-`Sendable`-crossing handle, so the listener's `@Sendable` handler can reach the actor.
struct Handler: Sendable {
    let service: RouterService

    func respond(to request: HTTPWireRequest) async -> HTTPWireResponse {
        await service.respond(to: request)
    }
}

/// Identities resolved at accept time, looked up again when a call is recorded.
///
/// A process-wide store rather than state on the service, because the lookup happens on a detached
/// task started by the listener's accept callback and has to be readable from whichever request
/// arrives on that connection afterwards.
final class PeerIdentities: Sendable {
    static let shared = PeerIdentities()
    static let capacity = 512

    private struct State {
        var byPeer: [String: ClientIdentity] = [:]
        var order: [String] = []
    }

    private let state = Mutex(State())

    func store(_ identity: ClientIdentity, for descriptor: ConnectionDescriptor) {
        state.withLock { current in
            if current.byPeer[descriptor.peer] == nil { current.order.append(descriptor.peer) }
            current.byPeer[descriptor.peer] = identity
            while current.order.count > Self.capacity {
                let oldest = current.order.removeFirst()
                current.byPeer[oldest] = nil
            }
        }
    }

    /// The identity for this connection, or `unknown`. An unattributed record is worth far more
    /// than a dropped one, so this is a value rather than an error.
    func identity(for descriptor: ConnectionDescriptor) -> ClientIdentity {
        state.withLock { $0.byPeer[descriptor.peer] ?? .unknown }
    }
}

/// Holds a non-`Sendable` unsubscribe closure so a `@Sendable` termination handler can call it.
///
/// `@unchecked Sendable` with the reason `SWIFT_PRACTICES.md` §1 asks for: the closure is written
/// once at construction and read once at termination, guarded by a mutex, and `AsyncStream`
/// guarantees `onTermination` runs at most once.
final class UnsubscribeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func cancel() {
        lock.lock()
        let handler = handler
        self.handler = nil
        lock.unlock()
        handler?()
    }
}
