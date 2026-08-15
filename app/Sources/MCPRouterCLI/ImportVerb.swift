import Foundation
import RouterCore

/// `mcp-router import`, in its own file.
///
/// Split out of `MCPRouterCLI.swift` for length, not for cohesion: it is the same type, extended.
/// The CLI is deliberately one struct — every verb shares the same argument parsing, the same two
/// output streams and the same error contract — and breaking it into unrelated types to satisfy a
/// line count would hide that.
extension MCPRouterCLI {
    // MARK: - import

    /// Adopt the servers in `~/.claude.json`, **indexing each one before adopting it**.
    ///
    /// The order is the contract, not an implementation detail: a server that cannot start is left
    /// where the user typed it rather than disappearing into the router's config to fail there
    /// invisibly. The reference's own comment records what happened when it did not — a server with
    /// an unbuilt `dist/` ended up in both files and was retried every five minutes forever.
    static func importServers(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        // `~/.claude.json` AND the router home come from ONE resolved `$HOME` (`D-w2`). The
        // reference derives both from a single `homedir()` call, so two homes in one run is not a
        // shape it can produce — and `docs/install.sh:77` runs this verb with neither `--from` nor
        // `MCP_ROUTER_HOME`, so both defaults are on the installer's own path.
        let paths = ImportPaths()
        let from = options.value("from") ?? paths.claudeJSON
        let fileSystem = RealFileSystem()
        guard fileSystem.fileExists(atPath: from) else {
            throw CLIError("no such file: \(from)")
        }
        let port = try options.number("port") ?? RouterHome.defaultPort
        let home = paths.routerHome

        let reading = try Self.readCandidates(from: from, port: port, fileSystem: fileSystem)

        let log = RouterLog()
        await log.configure(file: home.logPath, verbose: options.has("verbose"))
        Out.print("checking \(reading.candidates.count) server(s) before adopting any\n")

        let probed = await Self.probe(reading.candidates, home: home, log: log)

        try Self.writeAdopted(probed.adopt, port: port, home: home, fileSystem: fileSystem)
        Self.report(
            adopted: probed.adopt.count,
            at: home.configPath,
            failed: probed.failed,
            skipped: reading.skipped
        )
    }

    /// What `~/.claude.json` declares, partitioned into what can be adopted and what cannot.
    ///
    /// The router's own entry is dropped rather than skipped-with-a-reason: adopting it would point
    /// the router at itself, and the user never asked for it in the first place.
    static func readCandidates(
        from path: String, port: Int, fileSystem: some FileSystem
    ) throws -> (candidates: [(raw: JSONMember, upstream: UpstreamConfig)], skipped: [String]) {
        let source = try JSONParser.parse(fileSystem.readFile(atPath: path))
        let declared: [JSONMember] = {
            guard case let .object(members) = source,
                  case let .object(servers)? = members
                  .first(where: { $0.key == JSString("mcpServers") })?.value
            else { return [] }
            return servers
        }()

        var candidates: [(raw: JSONMember, upstream: UpstreamConfig)] = []
        var skipped: [String] = []
        for member in declared {
            if SelfReference.isSelfReference(name: member.key.string, raw: member.value, port: port) {
                continue
            }
            switch ServerParser.parse(name: member.key.string, raw: member.value) {
            case let .upstream(upstream): candidates.append((member, upstream))
            case let .skipped(reason): skipped.append("\(member.key.string) (\(reason))")
            }
        }
        return (candidates, skipped)
    }

    /// Start every candidate before adopting any of it, and report each outcome as it lands.
    ///
    /// A server pending authorization is adopted: it did not fail, it is waiting for the user, and
    /// leaving it behind would make `mcp-router auth` unreachable for the one server that needs it.
    static func probe(
        _ candidates: [(raw: JSONMember, upstream: UpstreamConfig)],
        home: RouterHome,
        log: RouterLog
    ) async -> (adopt: [JSONMember], failed: [String]) {
        let indexer = ManifestIndexer(
            startupTimeoutMs: 60000,
            transporting: RoutingUpstreamTransport(log: log),
            manifestPath: home.manifestPath, log: log
        )

        var adopt: [JSONMember] = []
        var failed: [String] = []
        for candidate in candidates {
            let outcome = await indexer.index(candidate.upstream)
            let name = candidate.upstream.name
            if outcome.isAuthorizationPending {
                adopt.append(JSONMember(key: JSString(name), value: Self.withoutName(candidate.raw.value)))
                Out.print("  auth  \(name) — adopted, needs `mcp-router auth \(name)`\n")
            } else if let error = outcome.error, !error.isEmpty {
                failed.append("\(name): \(error)")
                Out.print("  SKIP  \(name) — \(error)\n")
            } else {
                adopt.append(JSONMember(key: JSString(name), value: Self.withoutName(candidate.raw.value)))
                Out.print("  ok    \(name) (\(outcome.tools) tools)\n")
            }
        }
        return (adopt, failed)
    }

    /// Write the router's config, backing up whatever was there. The backup is timestamped rather
    /// than a single `.bak`, so a second import cannot destroy the first one's copy.
    ///
    /// **The backup stays here, outside the lock, on purpose.** Its path goes to stdout, and
    /// `RouterCore` does not write to stdout — it is linked into the MCP process, where a stray
    /// line corrupts the protocol stream. The reference also copies outside any mutual exclusion.
    /// The consequence, stated rather than left to be found: under contention the backup is a
    /// snapshot from before the lock, so it can differ from the pre-image the merge saw. That
    /// matches the reference and is not worsened here.
    ///
    /// The write itself is ``ImportConfigWriter``, which is where R1's D3 (atomic, preserving) and
    /// the create-only `0600` live.
    static func writeAdopted(
        _ adopt: [JSONMember],
        port: Int,
        home: RouterHome,
        fileSystem: any FileSystem & FileModeWriting
    ) throws {
        try fileSystem.createDirectory(atPath: home.root)
        if fileSystem.fileExists(atPath: home.configPath) {
            let backup = "\(home.configPath).bak-\(Int(Date().timeIntervalSince1970 * 1000))"
            try fileSystem.writeFile(fileSystem.readFile(atPath: home.configPath), atPath: backup)
            Out.print("backed up existing config -> \(backup)\n")
        }
        // The watcher's bound, not the daemon's: `import` is a one-shot with nothing waiting on it,
        // and failing an import the user sat through a 60 s indexing pass for — because a PATCH
        // held the lock for 100 ms — is the worse of the two available failures.
        let destination = ImportConfigWriter.Destination(
            path: home.configPath,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            lockTimeoutMs: ConfigMutationLock.timeoutMilliseconds(
                default: ConfigMutationLock.watcherTimeoutMs
            )
        )
        try ImportConfigWriter.write(
            adopted: adopt, port: port, to: destination, fileSystem: fileSystem
        )
    }

    /// The closing summary. Each group is named for what the user has to do about it, not for what
    /// the importer did — "left where you declared it" is actionable, "failed" is not.
    static func report(adopted: Int, at configPath: String, failed: [String], skipped: [String]) {
        Out.print("\nadopted \(adopted) server(s) -> \(configPath)\n")
        if !failed.isEmpty {
            Out.print(
                "left \(failed.count) where you declared it, because it did not start:\n  "
                    + failed.joined(separator: "\n  ") + "\n"
            )
        }
        if !skipped.isEmpty {
            Out.print("not adoptable:\n  " + skipped.joined(separator: "\n  ") + "\n")
        }
    }

    /// `const { name: _drop, ...rest } = raw` — the adopted entry drops a `name` member if the
    /// source carried one, and keeps every other member in its original order.
    static func withoutName(_ value: JSONValue) -> JSONValue {
        guard case let .object(members) = value else { return value }
        return .object(members.filter { $0.key != JSString("name") })
    }
}
