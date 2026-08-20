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
            guard let path = path(
                for: client,
                homeDirectory: homeDirectory,
                projectDirectory: projectDirectory
            )
            else { return nil }
            return ClientConfigReport(
                client: client,
                path: path,
                result: read(client: client, path: path, routerPort: routerPort, fileSystem: fileSystem)
            )
        }
    }

    public static func path(
        for client: MCPClient,
        homeDirectory: String,
        projectDirectory: String?
    ) -> String? {
        let home = homeDirectory as NSString
        switch client {
        case .claudeCode:
            return home.appendingPathComponent(".claude.json")
        case .claudeDesktop:
            return home
                .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .codexCLI:
            return home.appendingPathComponent(".codex/config.toml")
        case .chatGPTCLI:
            // Project-scoped rather than global: the ChatGPT CLI writes its config beside the
            // project it was run in.
            guard let projectDirectory else { return nil }
            return (projectDirectory as NSString).appendingPathComponent(".chatgpt/config.toml")
        case .cursor:
            // cursor-agent reads this file too — measured 2026-08-21 in the shipped 2026.08.11
            // bundle, which joins `.cursor/mcp.json` under both the home and the project. One
            // entry covers the IDE and the CLI because they share the file.
            return home.appendingPathComponent(".cursor/mcp.json")
        case .geminiCLI:
            // The Gemini / Antigravity CLI (`agy` on this machine). It was absent from this enum
            // and it is R7's entire subject: it is the harness carrying a stdio shim to the router
            // alongside twelve servers the router already fronts.
            return home.appendingPathComponent(".gemini/settings.json")
        case .grokCLI:
            return home.appendingPathComponent(".grok/config.toml")
        case .opencode:
            return home.appendingPathComponent(".config/opencode/opencode.json")
        }
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
            guard let path = path(
                for: client, homeDirectory: homeDirectory, projectDirectory: projectDirectory
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
