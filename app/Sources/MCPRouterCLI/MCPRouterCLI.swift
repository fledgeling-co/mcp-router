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
/// `watch` is the config watcher — `R2-W`. It shares `servers.json` with the running daemon, so its
/// write goes through the same `ConfigMutationLock` the control API takes, and it issues the router
/// restart the reference loses (divergence W-D1).
///
/// `auth` exists so the verb is not missing, and it is **still not claimed as parity** — but
/// `D-j` is no longer the reason. P1 wired both auth routes into `ControlHandler`'s dispatch, and
/// the control lane now compares them against the running reference (409 and 400, agreeing).
///
/// What blocks the *verb* is this lane's harness: `auth` POSTs to a **running** router and then
/// polls the auth dir, and `parity-cli.sh`'s `run_both` starts no router, so comparing it today
/// would compare two connection failures agreeing with each other. Tracked as `D-p1-d`; the lane
/// already has `serve_side` to build the row on. `D-p1-a` is closed — the router serves the http
/// half now — but this VERB still cannot be compared here for a reason of its own: a successful
/// start binds the fixed callback port for the flow's lifetime and shells out to `/usr/bin/open`,
/// putting a browser window in front of whoever runs the gate. `parity-oauth.sh` compares the route
/// instead, which is the same flow without the browser.
@main
struct MCPRouterCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try await dispatch(arguments)
        } catch {
            // `run().catch` — every thrown message reaches stderr with this prefix and exit 1.
            Out.error("mcp-router: \(Self.message(of: error))\n")
            exit(1)
        }
    }

    /// The whole verb surface: the reference's, plus **one verb it does not have**.
    ///
    /// `install-entry` (**P2-D1**) is handled here rather than as an eleventh arm inside
    /// ``dispatchReferenceVerb(_:)``, so that function stays one-to-one with `src/index.ts` and can
    /// still be read against it line by line. The reference performs that step inline in
    /// `docs/install.sh` through a `node -e` script, and R4-C removes Node from the installer, so
    /// the capability has to live in the binary. It is absent from `Copy.usage` for the reason
    /// ``InstallEntryVerb`` records, which is what keeps `cli-help` — a proven parity row comparing
    /// all four help arms — green.
    ///
    /// The split is also what keeps the reference's arm list inside the complexity budget: adding
    /// an eleventh branch to it put the function at 11, and the honest seam is between "what the
    /// reference dispatches" and "what this binary adds", not an arbitrary halving of the switch.
    static func dispatch(_ arguments: [String]) async throws {
        if arguments.first == "install-entry" {
            try InstallEntryVerb.run(arguments)
            return
        }
        // `harnesses` (**R7**) sits beside `install-entry`: a capability this binary adds with no
        // arm in the reference, out of `Copy.usage` so `cli-help` compares four identical arms.
        if arguments.first == "harnesses" {
            try HarnessesVerb.run(arguments)
            return
        }
        // `desktop-entry` (**R32**) is the third of those, and the only one that refuses to write
        // by default. `install-entry` points Claude Code at the router; this points Claude Desktop,
        // whose config takes a command rather than a url and which re-reads nothing while it runs.
        if arguments.first == "desktop-entry" {
            try DesktopEntryVerb.run(arguments)
            return
        }
        try await dispatchReferenceVerb(arguments)
    }

    /// One arm per verb `src/index.ts` dispatches, and nothing else — separate from `main` so the
    /// error handling around it stays legible as the two lines it is.
    static func dispatchReferenceVerb(_ arguments: [String]) async throws {
        switch arguments.first ?? "serve" {
        case "serve": try await serve(arguments)
        case "index", "refresh": try await index(arguments)
        case "import": try await importServers(arguments)
        case "status": await status(arguments)
        case "tools": try tools(arguments)
        case "usage": try await usage(arguments)
        case "watch": try await WatchVerb.run(arguments)
        case "auth": try await auth(arguments)
        case "help", "--help", "-h": Out.print(Copy.usage(home: RouterHome()))
        default:
            Out.print(Copy.usage(home: RouterHome()))
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
            .first(where: { $0.key == JSString("pendingAuth") })?.value
        {
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

    // MARK: - Shared

    static func load(_ options: Flags) throws -> (LoadedConfig, RouterHome) {
        let home = RouterHome()
        let loaded = try ConfigLoader.load(
            options: ConfigLoader.Options(
                configPath: options.value("config"),
                port: options.number("port"),
                host: options.value("host"),
                idleMs: options.number("idle-ms")
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

/// What one `index` run has to say about its upstreams, accumulated as it walks them.
///
/// A type of its own rather than three arrays and a branch inside the verb, because the three lines
/// are not exclusive. `lost` is independent of the pass/fail pair rather than a third arm of it: a
/// server can fail to start AND fail to have that failure recorded, and the second is exactly as
/// invisible as the first was — the unwritten error row leaves the entry non-stale, so the next
/// unforced `index` skips a server that never indexed.
/// Internal rather than private: the `index` verb moved to `MCPRouterCLIIndex.swift` when this
/// file outgrew the length limit, and Swift's `private` does not reach across files.
struct IndexReport {
    private(set) var built: [String] = []
    private(set) var failed: [String] = []
    private(set) var lost: [String] = []

    mutating func add(_ upstream: UpstreamConfig, _ outcome: IndexOutcome) {
        // `error ? … : …` — an empty string is not a failure, which is the ported truthiness test
        // rather than a nil check.
        let upstreamFailure = outcome.error.flatMap { $0.isEmpty ? nil : $0 }
        if let error = upstreamFailure {
            failed.append("\(upstream.name): \(error)")
        } else if outcome.cached {
            // A held surface reports its CHANGE count, not its tool count. The tools it just listed
            // are pending; the manifest still serves the approved set, which is what the closing
            // line counts — so printing `(2 tools)` here against `1 tools cached` was the same
            // two-numbers-disagree defect on a home with nothing wrong with it. Both strings are
            // the reference's, and their twin is `ManifestBookkeeping.build`.
            let held = outcome.heldChanges.map {
                "\(upstream.name) (\($0) change(s) held for approval)"
            }
            built.append(held ?? "\(upstream.name) (\(outcome.tools) tools)")
        }
        guard let reason = outcome.cacheFailure else { return }
        lost.append(upstreamFailure == nil
            ? "\(upstream.name) (\(outcome.tools) tools indexed): \(reason)"
            : "\(upstream.name) (the failure was not recorded either): \(reason)")
    }
}
