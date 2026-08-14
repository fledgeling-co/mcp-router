import Foundation
import RouterCore

/// `mcp-router`, in Swift.
///
/// The argv shell over ``RouterService``, and nothing more: every verb here is a thin translation of
/// one arm of `src/index.ts`, and every string it prints is the reference's — on the reference's
/// stream, with the reference's exit code. Those three travel together and getting any one of them
/// wrong is a parity failure that a combined capture would hide, which is why
/// `scripts/acceptance/parity-cli.sh` compares stdout, stderr and status separately.
///
/// `watch` is deliberately absent. It is `R2-W`'s, and `cli-watch` stays blocked with that owner
/// rather than being half-built here.
///
/// `auth` exists so the verb is not missing, but it is **not claimed as parity**: the Swift router
/// answers 405 on `POST /servers/:name/auth` where the reference answers 400, because `AuthRoutes`
/// is not wired into `ControlHandler`'s dispatch. That is defect `D-j`, and fixing it here would
/// make `control-differential.sh` record a stale-defect failure — see spec-R2R §8 A1.
@main
struct MCPRouterCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let verb = arguments.first ?? "serve"

        do {
            switch verb {
            case "serve": try await serve(arguments)
            case "index", "refresh": try await index(arguments)
            case "import": try await importServers(arguments)
            case "status": await status(arguments)
            case "tools": try tools(arguments)
            case "usage": try await usage(arguments)
            case "auth": try await auth(arguments)
            case "help", "--help", "-h": Out.print(Copy.usage(home: RouterHome()))
            default:
                Out.print(Copy.usage(home: RouterHome()))
                exit(1)
            }
        } catch {
            // `run().catch` — every thrown message reaches stderr with this prefix and exit 1.
            Out.error("mcp-router: \(Self.message(of: error))\n")
            exit(1)
        }
    }

    static func message(of error: Error) -> String {
        (error as? CLIError)?.message
            ?? (error as? RouterServiceError)?.description
            ?? (error as? PoolError)?.description
            ?? "\(error)"
    }

    // MARK: - serve

    static func serve(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        let (loaded, home) = try load(options)
        let log = RouterLog()
        await log.configure(file: loaded.config.logPath, verbose: options.has("verbose"))
        if !loaded.skipped.isEmpty {
            await log.record(ServiceLogEvent.notProxied(names: loaded.skipped))
        }

        let service = RouterService(loaded: loaded, home: home, log: log)
        do {
            try await service.start()
        } catch {
            // The one startup failure a user acts on, and the reason it is not just rethrown: the
            // reference's `listen EADDRINUSE: address already in use 127.0.0.1:8879` is the whole
            // message, with no `mcp-router: ` prefix and no added advice.
            Out.error(Self.message(of: error) + "\n")
            exit(1)
        }

        // Signals, handled through `DispatchSourceSignal` rather than `signal(2)`: a C handler may
        // only call async-signal-safe functions, and shutting the pool down is none of those. The
        // default disposition is ignored first, or the process dies before the source ever fires.
        let stopping = SignalWait()
        for (number, name) in [(SIGINT, "SIGINT"), (SIGTERM, "SIGTERM")] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { stopping.fire(name) }
            source.resume()
            stopping.hold(source)
        }
        let name = await stopping.wait()
        await service.stop(signal: name)
        exit(0)
    }

    // MARK: - index / refresh

    static func index(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        let (loaded, home) = try load(options)
        let log = RouterLog()
        await log.configure(file: loaded.config.logPath, verbose: options.has("verbose"))

        let indexer = ManifestIndexer(
            startupTimeoutMs: loaded.config.startupTimeoutMs,
            transporting: RoutingUpstreamTransport(log: log),
            manifestPath: loaded.config.manifestPath, log: log
        )
        let force = options.has("force")
        let manifest = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let stale = loaded.config.upstreams.filter { ToolUnion.isStale(manifest, $0) }
        Out.print(
            "\(loaded.config.upstreams.count) upstreams, \(stale.count) need indexing"
                + (force ? " (forced: all)" : "") + "\n"
        )

        var built: [String] = []
        var failed: [String] = []
        for upstream in loaded.config.upstreams where force || ToolUnion.isStale(manifest, upstream) {
            let outcome = await indexer.index(upstream)
            if let error = outcome.error, !error.isEmpty {
                failed.append("\(upstream.name): \(error)")
            } else {
                built.append("\(upstream.name) (\(outcome.tools) tools)")
            }
        }

        for line in built { Out.print("  ok    \(line)\n") }
        for line in failed { Out.print("  FAIL  \(line)\n") }
        let after = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let count = ToolUnion.unionTools(
            manifest: after, upstreams: loaded.config.upstreams
        ).count
        Out.print(
            "\n\(count) tools cached -> \(loaded.config.manifestPath)\n"
                + "All upstreams closed; none will open again until a tool is called.\n"
        )
        _ = home
    }

    // MARK: - status

    /// Offline goes to **stdout** with exit 1, not to stderr. Measured, and it differs from `usage`
    /// three lines below — `cmdStatus` catches and writes where `cmdUsage` throws.
    static func status(_ arguments: [String]) async {
        let port = (try? Flags(arguments).number("port") ?? RouterHome.defaultPort)
            ?? RouterHome.defaultPort
        guard let body = await Loopback.get(port: port, path: "/status") else {
            Out.print("no router answering on 127.0.0.1:\(port) (fetch failed)\n")
            exit(1)
        }
        guard case let .object(fields) = body else { exit(1) }
        func number(_ key: String) -> Double {
            fields.first { $0.key == JSString(key) }?.value.asNumber ?? 0
        }
        let children: [JSONValue] = {
            guard case let .array(rows)? = fields
                .first(where: { $0.key == JSString("children") })?.value else { return [] }
            return rows
        }()
        let running = children.filter { row in
            guard case let .object(fields) = row else { return false }
            return fields.first { $0.key == JSString("state") }?.value.asString == JSString("running")
        }
        Out.print(
            "router on :\(port) — \(Int(number("tools"))) tools, "
                + "\(running.count)/\(children.count) upstreams open, "
                + "idle window \(Int((number("idleMs") / 1000).rounded()))s\n\n"
        )
        for row in children {
            guard case let .object(fields) = row else { continue }
            func text(_ key: String) -> String {
                fields.first { $0.key == JSString(key) }?.value.asString?.string ?? ""
            }
            func count(_ key: String) -> Int {
                Int(fields.first { $0.key == JSString(key) }?.value.asNumber ?? 0)
            }
            let state = text("state")
            // `${c.calls} calls` — and `/status` emits `callsServed`, never `calls`, so a **running**
            // child prints the literal `undefined calls`. Measured on 2026-08-14:
            //   `running   stdio  probe                undefined calls, idle 2s`
            // Reproduced through the same mechanism rather than by hard-coding the word: this reads
            // the member the reference reads and interpolates an absent one the way a template
            // literal does, so if either router ever starts emitting `calls`, both change together
            // and the parity row keeps meaning something.
            let detail = state == "running"
                ? "\(Copy.interpolate(fields, "calls")) calls, idle \(count("idleSec"))s"
                : ""
            Out.print(
                "  \(Copy.pad(state, 9)) \(Copy.pad(text("transport"), 6)) "
                    + "\(Copy.pad(text("name"), 20)) \(detail)\n"
            )
        }
        if case let .array(pending)? = fields
            .first(where: { $0.key == JSString("pendingAuth") })?.value {
            for row in pending {
                guard case let .object(fields) = row,
                      let server = fields.first(where: { $0.key == JSString("server") })?
                          .value.asString
                else { continue }
                Out.print(
                    "\n  ! \(server.string) needs authorizing: mcp-router auth \(server.string)\n"
                )
            }
        }
    }

    // MARK: - tools

    static func tools(_ arguments: [String]) throws {
        let options = try Flags(arguments)
        let (loaded, _) = try load(options)
        let manifest = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let all = ToolUnion.unionTools(manifest: manifest, upstreams: loaded.config.upstreams)
        for tool in all {
            Out.print("\(tool.name?.string ?? "undefined")\n")
        }
        // No empty branch, deliberately: the reference has none, and adding one would be an
        // undeclared divergence on `cli-tools`. Raised as deferred child D-r2r-a instead.
        Out.print("\n\(all.count) tools from \(loaded.config.upstreams.count) upstreams\n")
    }

    // MARK: - usage

    /// Offline **throws**, so it lands on stderr with the `mcp-router: ` prefix. The difference from
    /// `status` is the reference's, not a tidy-up opportunity.
    static func usage(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        let port = try options.number("port") ?? RouterHome.defaultPort
        let limit = try options.number("limit") ?? 40
        guard let body = await Loopback.get(port: port, path: "/usage?limit=\(limit)") else {
            throw CLIError("no router answering on 127.0.0.1:\(port) (fetch failed)")
        }
        guard case let .object(fields) = body else { return }
        let since = fields.first { $0.key == JSString("since") }?.value.asString?.string ?? ""
        let records: [JSONValue] = {
            guard case let .array(rows)? = fields
                .first(where: { $0.key == JSString("records") })?.value else { return [] }
            return rows
        }()
        Out.print("last \(records.count) calls (history since \(since))\n\n")
        for row in records {
            guard case let .object(fields) = row else { continue }
            func text(_ key: String) -> String? {
                fields.first { $0.key == JSString(key) }?.value.asString?.string
            }
            let stamp = text("ts") ?? ""
            let when = stamp.count >= 19 ? String(Array(stamp)[11 ..< 19]) : stamp
            let pid = fields.first { $0.key == JSString("pid") }?.value.asNumber
            let project = text("project")
            let caller = project.map { "\($0)\(pid.map { ":\(Int($0))" } ?? "")" } ?? "unknown"
            let succeeded = fields.first { $0.key == JSString("ok") }?.value.isTruthy ?? false
            let elapsed = Int(fields.first { $0.key == JSString("ms") }?.value.asNumber ?? 0)
            let name = "\(text("server") ?? "")__\(text("tool") ?? "")"
            let cold = (fields.first { $0.key == JSString("cold") }?.value.isTruthy ?? false)
                ? "cold" : "    "
            Out.print(
                "  \(when)  \(succeeded ? " " : "!") \(Copy.pad(name, 38)) "
                    + "\(Copy.padStart(String(elapsed), 6))ms \(cold)  \(caller)\n"
            )
        }
    }

    // MARK: - auth

    static func auth(_ arguments: [String]) async throws {
        guard arguments.count > 1, !arguments[1].hasPrefix("--") else {
            throw CLIError("usage: mcp-router auth <server>")
        }
        let name = arguments[1]
        let options = try Flags(arguments)
        let port = try options.number("port") ?? RouterHome.defaultPort
        let home = RouterHome()
        let token = (try? ControlToken(
            path: (home.root as NSString).appendingPathComponent("control.token")
        ).load()) ?? ""

        guard let body = await Loopback.post(
            port: port,
            path: "/servers/\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name)/auth",
            token: token
        ) else {
            throw CLIError(
                "no router answering on 127.0.0.1:\(port) (fetch failed) — start it first"
            )
        }
        guard case let .object(fields) = body,
              let url = fields.first(where: { $0.key == JSString("authorizationUrl") })?
                  .value.asString
        else {
            let message = {
                guard case let .object(fields) = body,
                      let error = fields.first(where: { $0.key == JSString("error") })?.value.asString
                else { return "authorization could not start" }
                return error.string
            }()
            throw CLIError(message)
        }

        Out.print("opening your browser to authorize \"\(name)\"\n\(url.string)\n")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [url.string]
        try? open.run()

        // Polled rather than held: the exchange completes inside the router.
        let store = FileAuthStore(authDir: home.authDir)
        for _ in 0 ..< 150 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await store.hasTokens(JSString(name)) {
                Out.print("\n✓ \(name) is authorized\n")
                return
            }
        }
        Out.print("\ngave up waiting; run `mcp-router status` to check\n")
        exit(1)
    }

    // MARK: - Shared

    static func load(_ options: Flags) throws -> (LoadedConfig, RouterHome) {
        let home = RouterHome()
        let loaded = try ConfigLoader.load(
            options: ConfigLoader.Options(
                configPath: options.value("config"),
                port: try options.number("port"),
                host: options.value("host"),
                idleMs: try options.number("idle-ms")
            ),
            home: home,
            fileSystem: RealFileSystem()
        )
        return (loaded, home)
    }
}

/// An error whose message is printed verbatim after the `mcp-router: ` prefix.
struct CLIError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
