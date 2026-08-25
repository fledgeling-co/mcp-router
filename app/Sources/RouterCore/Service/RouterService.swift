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
    let fileSystem: any FileSystem & FileModeWriting
    let clock: any RouterClock
    /// The process environment, captured once at construction because that is when the reference
    /// reads it: `const OFFICIAL = process.env.MCP_ROUTER_REGISTRY ?? …` is a module-level `const`
    /// (`src/registry.ts:18`), evaluated on import and fixed for the life of the process.
    /// Injectable so a test can drive the registry bases without mutating the real environment.
    let environment: [String: String]
    let log: RouterLog
    let manifest: ManifestStore
    let pool: UpstreamPool
    let usage: UsageStore
    let auth: FileAuthStore
    /// The one browser authorization that can be in flight, and the thing that begins it.
    ///
    /// Held by the service rather than built per request, because "a second flow supersedes the
    /// first" is a property of the process: a coordinator constructed inside `controlResponse`
    /// would be a fresh one every request and two authorizations would fight over :8880 instead.
    let authFlow: OAuthFlowStarter
    /// The authorization server's signing key and its used-code set.
    ///
    /// Held by the service rather than built per request, for the reason `authFlow` is: "a code is
    /// single-use" is a property of the process, and a set constructed inside the dispatcher would
    /// be a fresh empty one every request, which is the same as not checking at all.
    ///
    /// Optional because a home whose auth directory cannot be written is a router that still
    /// serves /mcp perfectly well. The routes then answer nothing and the dispatcher falls through
    /// — degraded honestly rather than refusing to start.
    let authServerSeal: AuthServerSeal?
    let usedCodes = UsedCodeSet()
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
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        resolver: (any PeerResolver)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        config = loaded.config
        self.home = home
        self.fileSystem = fileSystem
        self.clock = clock
        self.log = log
        self.environment = environment
        self.resolver = resolver ?? LibProcPeerResolver()
        configPath = home.configPath
        manifest = ManifestStore(
            path: config.manifestPath, fileSystem: fileSystem, clock: clock, log: log
        )
        usage = UsageStore(
            logPath: config.usagePath, statsPath: config.statsPath, fileSystem: fileSystem
        )
        auth = FileAuthStore(authDir: config.authDir, log: log)
        // `auth` rather than a second store built from the same arguments: two of them is two
        // places for a later change to the credential store to be applied once.
        authFlow = OAuthFlowStarter(
            coordinator: AuthFlowCoordinator(log: log), store: auth, clock: clock
        )
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
        authServerSeal = try? AuthServerSeal(authDir: config.authDir, fileSystem: fileSystem)
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
        // Disabled servers are excluded from this warning rather than from the manifest. Their
        // tools are not "missing until index runs" — they are withheld on purpose, and naming them
        // here would send the reader to run a command that would change nothing.
        let stale = config.upstreams.filter { $0.disabled != true && ToolUnion.isStale(current, $0) }
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
}
