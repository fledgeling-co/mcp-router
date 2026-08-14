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
        let from = options.value("from")
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude.json")
        let fileSystem = RealFileSystem()
        guard fileSystem.fileExists(atPath: from) else {
            throw CLIError("no such file: \(from)")
        }
        let port = try options.number("port") ?? RouterHome.defaultPort
        let home = RouterHome()

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
    static func writeAdopted(
        _ adopt: [JSONMember], port: Int, home: RouterHome, fileSystem: some FileSystem
    ) throws {
        try fileSystem.createDirectory(atPath: home.root)
        if fileSystem.fileExists(atPath: home.configPath) {
            let backup = "\(home.configPath).bak-\(Int(Date().timeIntervalSince1970 * 1000))"
            try fileSystem.writeFile(fileSystem.readFile(atPath: home.configPath), atPath: backup)
            Out.print("backed up existing config -> \(backup)\n")
        }
        let written = JSONValue.object([
            JSONMember(key: JSString("port"), value: .number(Double(port))),
            JSONMember(key: JSString("host"), value: .string(JSString("127.0.0.1"))),
            JSONMember(key: JSString("idleMs"), value: .number(300_000)),
            JSONMember(key: JSString("mcpServers"), value: .object(adopt))
        ])
        try fileSystem.writeFile(
            Data((JSStringify.prettyTwoSpace(written)).utf8), atPath: home.configPath
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
