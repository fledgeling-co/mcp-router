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
    /// Upstream health — R27. Held for the life of the process because health IS history: a
    /// monitor rebuilt per request would report every server `unprobed` forever.
    let health: UpstreamHealthMonitor
    /// Upstream credential expiry — R26. Held for the life of the process because the THROTTLE is
    /// history: a monitor rebuilt per request would have delivered nothing yet, so every call to
    /// `POST /upstreams/auth-expiry/notify` would re-issue every notice and
    /// ``AuthExpiryPolicy/renotifyAfterMs`` could never be reached. That failure is invisible to
    /// any test that makes one request. It holds no task and no timer — see ``AuthExpiryMonitor``.
    let authExpiry: AuthExpiryMonitor
    /// F5's invocation history, or nil when nothing pointed the router at a transcript corpus.
    ///
    /// **Optional at the service, not just at `ControlDeps`.** The reader opens a directory of
    /// somebody's agent sessions, so it exists only when a person named one — there is no default
    /// and no discovery. Absent, `GET /invocations` answers 503 saying so, which is a different
    /// claim from an empty window.
    let invocations: InvocationHistory?
    /// The session analyst — F7. Held for the life of the process for the reason ``health`` is, and
    /// for a second one: the thirty-day suppression window is state, and an engine rebuilt per
    /// request would re-read its file on every call and hold a `running` flag nothing could see.
    let analyst: AnalystEngine
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
        // F5. Built here rather than per request for the reason `health` is: the watermarks and the
        // ledger are read off disk at construction, and a history rebuilt per request would re-read
        // 19.5 GB of transcripts on every call to `GET /invocations`.
        //
        // **Supplied here and nowhere else**, which is the whole of why this line carries a comment
        // at all: `registry` and `authFlow` each existed, were unit-tested and were nil in the one
        // process that ships, so every route depending on them answered a refusal on the wire while
        // the suite stayed green (`D-p1-a`, and the `control-registry-search` row). This item's own
        // spec quotes that, so shipping it nil would have reproduced it knowingly.
        invocations = InvocationSources.history(
            environment: environment, home: home, fileSystem: fileSystem
        )
        health = UpstreamHealthMonitor(
            upstreams: config.upstreams,
            global: config.health,
            globalRefusals: config.healthRefusals,
            probing: PoolUpstreamProbe(pool: pool, clock: clock),
            clock: clock
        )
        // R26. `auth` rather than a second store built from the same arguments, for the reason
        // the `authFlow` line above gives. Built through a factory rather than inline because
        // this initializer sits at the 60-line body cap — the same pressure that split
        // `RouterServiceDispatch` off this type when M22 added two dependencies.
        authExpiry = Self.expiryMonitor(config: config, auth: auth)
        analyst = AnalystEngine(
            reader: SessionCorpusReader(
                fileSystem: fileSystem,
                homeDirectory: RouterHome.resolvedHomeDirectory(environment: environment)
            ),
            judge: CLIAnalystJudge(runner: AnalystProcessRunner(environment: environment)),
            candidateSource: RegistryCandidateSource(deps: RegistryDeps(
                http: RegistryHTTPClient(), fileSystem: fileSystem, routerHome: home.root,
                officialBase: environment["MCP_ROUTER_REGISTRY"],
                smitheryBase: environment["MCP_ROUTER_SMITHERY"],
                githubToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"],
                nowMs: clock.nowMilliseconds
            )),
            fileSystem: fileSystem,
            clock: clock,
            statePath: (home.root as NSString).appendingPathComponent("analyst.json")
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

    /// R26's monitor, built from the loaded configuration and the service's own credential store.
    ///
    /// A function rather than four lines inside `init`, and the seam is real rather than
    /// arithmetic: it is the whole of what this feature needs from configuration, so a later
    /// reader asking what the router does with `authExpiry` has one place to look.
    private static func expiryMonitor(config: RouterConfig, auth: FileAuthStore) -> AuthExpiryMonitor {
        AuthExpiryMonitor(
            upstreams: config.upstreams,
            policy: config.authExpiry,
            refusals: config.authExpiryRefusals,
            auth: auth
        )
    }

    private let wroteToken: Bool

    /// The port actually bound. Read after ``start()``; a test asks for port 0 and reads it back.
    public var boundPort: Int? {
        get async { await server.boundPort }
    }

    // MARK: - Lifecycle

    /// The startup warning about upstreams the manifest has no usable entry for, or `nil` when
    /// there are none.
    ///
    /// **A function rather than four lines inside `start()`, so the rule is reachable.** The clause
    /// it carries is M29's oracle line 5 — *the automatic index sweeps skip a disabled server* —
    /// and `start()` binds a port and spawns a server, so nothing in the Swift suite could state
    /// anything about the filter while it lived there: deleting the `disabled` term left every test
    /// passing.
    ///
    /// Disabled servers are excluded from the warning rather than from the manifest. Their tools
    /// are not "missing until index runs" — they are withheld on purpose, and naming them here
    /// would send the reader to run `mcp-router index`, which would change nothing.
    nonisolated static func staleManifestWarning(
        _ manifest: Manifest, upstreams: [UpstreamConfig]
    ) -> ServiceLogEvent? {
        let stale = upstreams.filter { $0.disabled != true && ToolUnion.isStale(manifest, $0) }
        guard !stale.isEmpty else { return nil }
        return .notInManifest(count: stale.count, names: stale.map(\.name))
    }

    public func start() async throws {
        // The stale-manifest warning comes **before** the token line, because the reference emits it
        // in `cmdServe` while the token is minted later inside `startRouter`. Measured, and the
        // order is part of what `parity-log.sh` diffs — a log whose lines are individually correct
        // and collectively out of order is a log nobody can diff.
        let current = await manifest.current()
        if let warning = Self.staleManifestWarning(current, upstreams: config.upstreams) {
            await log.record(warning)
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

        // R27. Arms nothing unless a server configured a positive `probeIntervalMs`, which no
        // server does by default — a background probe spawns a child, and `REQ-001` is that at
        // rest there are none. `start()` returning without a task is the ordinary case.
        await health.start()

        // F5. Detached and after listen() for `warmUp`'s reason and one of its own: a cold corpus
        // is 59,476 files and 19.5 GB (measured 2026-08-29), roughly 150 seconds of reading, and a
        // router that took that before answering would look hung. Every later pass is nearly free —
        // the watermark skips every file whose size and mtime are unchanged — but the first is not.
        //
        // `nil` unless somebody set `MCP_ROUTER_TRANSCRIPTS`, so this task does not exist on a
        // default install. It runs ONCE per start rather than on a timer, which is a real limit
        // rather than a plan: a long-lived daemon's window stops advancing until it restarts. A
        // periodic refresh is `D-f5-e`, and the honest reading in the meantime is that
        // `GET /invocations` answers for what had been read when the router last started.
        if let invocations {
            let register = InvocationSources.registerPath(environment: environment)
            let fileSystem = fileSystem
            Task.detached {
                // The boundaries FIRST, then the scan. Order is load-bearing rather than tidy: a
                // window folded before any boundary exists reports every run `unestablished`, which
                // is a correct answer to the wrong question and looks exactly like the honest
                // refusal this item is built to give.
                let seeded = InvocationSources.seed(at: register, fileSystem: fileSystem)
                invocations.observe(seeded.observations)
                invocations.refresh()
            }
        }
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
        await health.stop()
        await server.stop()
        await pool.shutdown()
    }
}
