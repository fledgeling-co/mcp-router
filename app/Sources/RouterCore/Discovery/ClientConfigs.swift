import Foundation

/// The agent clients this product manages MCP servers for.
public enum MCPClient: String, Sendable, Hashable, CaseIterable {
    case claudeCode
    case claudeDesktop
    case codexCLI
    case chatGPTCLI
    case cursor
    case geminiCLI
    case grokCLI
    case opencode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .codexCLI: "Codex CLI"
        case .chatGPTCLI: "ChatGPT CLI"
        case .cursor: "Cursor"
        case .geminiCLI: "Gemini CLI"
        case .grokCLI: "grok"
        case .opencode: "opencode"
        }
    }
}

public struct DiscoveredServer: Sendable, Hashable {
    public let name: String
    public let raw: JSONValue
}

/// What was found at one client's config path.
///
/// Four cases, because three of them are routinely confused and they want different handling: a
/// client that is not installed, a file that is broken, a file that is fine and declares nothing,
/// and a file with servers in it. **Absent is a normal answer** — most machines have three of six.
public enum ClientConfigResult: Sendable, Hashable {
    case absent
    case unreadable(reason: String)
    case declaresNone
    case servers([DiscoveredServer])
}

public struct ClientConfigReport: Sendable, Hashable {
    public let client: MCPClient
    public let path: String
    public let result: ClientConfigResult
}

/// Finds what each client declares. Discovery only — adopting, writing back or reconciling any of
/// it belongs to a later item.
public enum ClientConfigs {
    /// Fixed order, so two runs of discovery report the same list in the same sequence.
    public static func discover(
        homeDirectory: String = NSHomeDirectory(),
        projectDirectory: String? = nil,
        routerPort: Int = RouterHome.defaultPort,
        fileSystem: FileSystem = RealFileSystem()
    ) -> [ClientConfigReport] {
        MCPClient.allCases.compactMap { client in
            guard let path = resolvedPath(
                for: client,
                homeDirectory: homeDirectory,
                projectDirectory: projectDirectory,
                fileSystem: fileSystem
            )
            else { return nil }
            return ClientConfigReport(
                client: client,
                path: path,
                result: read(client: client, path: path, routerPort: routerPort, fileSystem: fileSystem)
            )
        }
    }

    /// The path this client's config is **declared** at — the first of
    /// ``candidatePaths(for:homeDirectory:projectDirectory:)``.
    ///
    /// Pure, and it asks the filesystem nothing, so it is the right answer for "where would this
    /// harness's config live" and the wrong one for "which file is this harness reading". A harness
    /// that has moved its config between releases has two answers, and only the disk knows which is
    /// live: see ``resolvedPath(for:homeDirectory:projectDirectory:fileSystem:)``.
    public static func path(
        for client: MCPClient,
        homeDirectory: String,
        projectDirectory: String?
    ) -> String? {
        candidatePaths(
            for: client, homeDirectory: homeDirectory, projectDirectory: projectDirectory
        ).first
    }

    /// Every path this client's config could live at, **most current first**.
    ///
    /// One entry for every harness but one, and the exception is the harness this item exists for.
    /// `agy` 1.1.17 moved its MCP configuration out of `~/.gemini/settings.json` and into
    /// `~/.gemini/config/mcp_config.json`, leaving the old file in place: on the machine R7 was
    /// measured on both exist and they disagree about the transport, about two of the servers, and
    /// about the entry count. Reading the older one is how the first pass came to report a harness
    /// as shimmed, count twelve duplicates over seventeen entries, and offer the user a migration
    /// they had already performed — while `agy mcp list` printed twenty rows with four of them
    /// typed `http`.
    ///
    /// **Resolved rather than swapped.** A straight path swap answers this machine and breaks a
    /// pre-migration install, which is the same shape of wrong answer one release earlier.
    public static func candidatePaths(
        for client: MCPClient,
        homeDirectory: String,
        projectDirectory: String?
    ) -> [String] {
        let home = homeDirectory as NSString
        switch client {
        case .claudeCode:
            return [home.appendingPathComponent(".claude.json")]
        case .claudeDesktop:
            return [home
                .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")]
        case .codexCLI:
            return [home.appendingPathComponent(".codex/config.toml")]
        case .chatGPTCLI:
            // Project-scoped rather than global: the ChatGPT CLI writes its config beside the
            // project it was run in.
            guard let projectDirectory else { return [] }
            return [(projectDirectory as NSString).appendingPathComponent(".chatgpt/config.toml")]
        case .cursor:
            // cursor-agent reads this file too — measured 2026-08-21 in the shipped 2026.08.11
            // bundle, which joins `.cursor/mcp.json` under both the home and the project. One
            // entry covers the IDE and the CLI because they share the file.
            return [home.appendingPathComponent(".cursor/mcp.json")]
        case .geminiCLI:
            // The Gemini / Antigravity CLI (`agy` on this machine), and R7's entire subject.
            //
            // Four independent lines from the shipped 1.1.17 binary say the FIRST of these is the
            // file it reads, and each is quotable rather than inferred: its changelog string — "for
            // managing MCP servers in your user-level `mcp_config.json`"; its help text — "`serverUrl`
            // (string, required)"; its error string — `MCP server %q must have either command or
            // serverUrl`; and the only MCP config paths in the binary at all, `.gemini/config/
            // mcp_config.json` and `config/mcp_config.json`. A fifth is on disk:
            // `~/.gemini/config/.migrated` dates the move. `agy mcp list` prints exactly that
            // file's contents.
            //
            // The second is kept because it is what an install that predates the migration still
            // reads, and it is the shape upstream `gemini-cli` writes.
            return [
                home.appendingPathComponent(".gemini/config/mcp_config.json"),
                home.appendingPathComponent(".gemini/settings.json")
            ]
        case .grokCLI:
            return [home.appendingPathComponent(".grok/config.toml")]
        case .opencode:
            return [home.appendingPathComponent(".config/opencode/opencode.json")]
        }
    }

    /// The path this client is **actually reading**: the first candidate that exists on disk.
    ///
    /// Falls back to the first candidate when none exists, so an absent harness is reported at the
    /// path the harness itself would create rather than at a legacy one — and `exists: false` says
    /// the rest.
    static func resolvedPath(
        for client: MCPClient,
        homeDirectory: String,
        projectDirectory: String?,
        fileSystem: FileSystem
    ) -> String? {
        let candidates = candidatePaths(
            for: client, homeDirectory: homeDirectory, projectDirectory: projectDirectory
        )
        return candidates.first { fileSystem.fileExists(atPath: $0) } ?? candidates.first
    }

    static func read(
        client: MCPClient,
        path: String,
        routerPort: Int,
        fileSystem: FileSystem,
        retainingRouterEntry: Bool = false
    ) -> ClientConfigResult {
        guard fileSystem.fileExists(atPath: path) else { return .absent }
        let data: Data
        do {
            data = try fileSystem.readFile(atPath: path)
        } catch {
            return .unreadable(reason: error.localizedDescription)
        }

        switch client {
        case .codexCLI, .chatGPTCLI, .grokCLI:
            // grok spells its table `[mcp_servers.*]`, which is already one of the two names
            // ``MiniTOML/serverTableNames`` carries. Measured on ~/.grok/config.toml, 2026-08-21.
            return readTOML(data, routerPort: routerPort, retainingRouterEntry: retainingRouterEntry)
        case .claudeCode, .claudeDesktop, .cursor, .geminiCLI:
            return readJSON(
                data, key: "mcpServers", routerPort: routerPort, retainingRouterEntry: retainingRouterEntry
            )
        case .opencode:
            return readJSON(
                data, key: "mcp", routerPort: routerPort, retainingRouterEntry: retainingRouterEntry
            )
        }
    }

    private static func readJSON(
        _ data: Data, key: String, routerPort: Int, retainingRouterEntry: Bool
    ) -> ClientConfigResult {
        let root: JSONValue
        do {
            root = try JSONParser.parse(data)
        } catch {
            return .unreadable(reason: "\(error)")
        }
        guard let declared = root.member(key) else { return .declaresNone }
        guard case let .object(members) = declared else {
            return .unreadable(reason: "\"\(key)\" is a \(declared.typeName), not an object of servers")
        }
        return finish(
            members.map { DiscoveredServer(name: $0.key.string, raw: $0.value) },
            routerPort: routerPort,
            retainingRouterEntry: retainingRouterEntry
        )
    }

    /// The brief's second named trap: the two CLIs spell the same table differently.
    ///
    /// A name declared under **both** spellings is reported as unreadable rather than resolved by
    /// picking one. The two tables mean the same thing, so disagreeing about one server is a config
    /// the user needs to fix — and quietly preferring whichever the parser reached first is how a
    /// tool ends up running a command the user thought they had replaced.
    private static func readTOML(
        _ data: Data, routerPort: Int, retainingRouterEntry: Bool
    ) -> ClientConfigResult {
        let document: MiniTOML.Document
        do {
            document = try MiniTOML.parse(String(bytes: data, encoding: .utf8) ?? "")
        } catch let problem as TOMLProblem {
            return .unreadable(reason: problem.description)
        } catch {
            return .unreadable(reason: "\(error)")
        }

        var found: [DiscoveredServer] = []
        var seen: Set<String> = []
        for tableName in MiniTOML.serverTableNames {
            for name in document.childNames(of: [tableName]) {
                guard let server = serverValue(document: document, table: tableName, name: name)
                else { continue }
                if seen.contains(name) {
                    return .unreadable(
                        reason: "\"\(name)\" is declared under both [mcp_servers] and [mcpServers]. "
                            + "Keep one and remove the other."
                    )
                }
                seen.insert(name)
                found.append(DiscoveredServer(name: name, raw: server))
            }
        }
        return finish(found, routerPort: routerPort, retainingRouterEntry: retainingRouterEntry)
    }

    private static func serverValue(document: MiniTOML.Document, table: String, name: String) -> JSONValue? {
        guard let pairs = document.table(matching: [table, name]) else { return nil }
        var members = pairs.map { JSONMember(key: JSString($0.key), value: $0.value.json) }
        // `env` and `headers` are their own sub-tables in TOML, so they are folded back in as
        // nested objects to give the shared server parser the shape it expects.
        for nested in ["env", "headers"] {
            guard let sub = document.table(matching: [table, name, nested]) else { continue }
            members.append(JSONMember(
                key: JSString(nested),
                value: .object(sub.map { JSONMember(key: JSString($0.key), value: $0.value.json) })
            ))
        }
        return .object(members)
    }

    /// Drops the router's own entry, which every client gains at install time. Anything that adopts
    /// it would make the router proxy to itself, and every `tools/list` would recurse.
    private static func finish(
        _ servers: [DiscoveredServer], routerPort: Int, retainingRouterEntry: Bool
    ) -> ClientConfigResult {
        // R7 asks the opposite question of the same file, so it keeps what adoption drops. The
        // router's own entry is the ONLY evidence that a harness is wired at all, and dropping it
        // here is why ``discover`` cannot tell "not wired" from "wired": the two are identical
        // once the entry is gone. The default is unchanged, so `import` and `watch` see exactly
        // what they saw before.
        let kept = retainingRouterEntry ? servers : servers.filter {
            !SelfReference.isSelfReference(name: $0.name, raw: $0.raw, port: routerPort)
        }
        return kept.isEmpty ? .declaresNone : .servers(kept)
    }

    /// Discovery for **R7**: every entry, including the one that points at this router.
    ///
    /// Separate from ``discover(homeDirectory:projectDirectory:routerPort:fileSystem:)`` rather
    /// than replacing it, because the two want opposite things from the same bytes. Adoption must
    /// never see the router's own entry or it proxies to itself; reconciliation must see it or it
    /// cannot answer the only question it was built for.
    public static func inventory(
        homeDirectory: String = NSHomeDirectory(),
        projectDirectory: String? = nil,
        routerPort: Int = RouterHome.defaultPort,
        fileSystem: FileSystem = RealFileSystem()
    ) -> [ClientConfigReport] {
        MCPClient.allCases.compactMap { client in
            guard let path = resolvedPath(
                for: client, homeDirectory: homeDirectory,
                projectDirectory: projectDirectory, fileSystem: fileSystem
            )
            else { return nil }
            return ClientConfigReport(
                client: client,
                path: path,
                result: read(
                    client: client, path: path, routerPort: routerPort,
                    fileSystem: fileSystem, retainingRouterEntry: true
                )
            )
        }
    }
}
