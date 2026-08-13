import Foundation

/// Why a server list could not be read.
///
/// These are separate cases rather than one error with a message because the surfaces that render
/// them need to tell them apart: "you have no servers yet" and "this file is a shape I do not
/// understand" are different screens, and a caller cannot choose between them by inspecting a
/// count. A config that parsed and genuinely declares no servers is not in this enum at all — it
/// is an ordinary ``LoadedConfig`` with no upstreams.
public enum ConfigProblem: Error, Sendable, Equatable, CustomStringConvertible {
    case missingFile(path: String)
    case unreadable(path: String, reason: String)
    case notJSON(path: String, reason: String)
    case unrecognisedShape(path: String, found: Found)
    case malformedServerEntry(path: String, name: String)

    public enum Found: Sendable, Equatable {
        /// No `mcpServers` key at all — the recorded trap, where the servers sit at the top level.
        case missingKey
        /// Present, but not an object of servers.
        case wrongType(String)
    }

    /// States what happened and what to do, names the file, and blames nobody.
    public var description: String {
        switch self {
        case let .missingFile(path):
            "No server list at \(path). Run `mcp-router import` to generate one from ~/.claude.json."
        case let .unreadable(path, reason):
            "\(path) could not be read (\(reason)). Nothing was loaded."
        case let .notJSON(path, reason):
            "\(path) is not valid JSON (\(reason)). Nothing was loaded."
        case let .unrecognisedShape(path, .missingKey):
            "\(path) has no \"mcpServers\" object. The servers look like they are at the "
                + "top level — wrap them in \"mcpServers\": { … }. Nothing was loaded."
        case let .unrecognisedShape(path, .wrongType(kind)):
            "\(path) has an \"mcpServers\" that is a \(kind), not an object of servers. "
                + "Nothing was loaded."
        case let .malformedServerEntry(path, name):
            "\(path) declares \"\(name)\" as null rather than as a server. Nothing was loaded."
        }
    }
}

/// A server list that was read successfully. No upstreams here is the legitimate empty case.
public struct LoadedConfig: Sendable {
    public let config: RouterConfig
    /// One `name (reason)` per entry that could not be adopted — the Partial state's data.
    public let skipped: [String]

    /// True when the file parsed and declared nothing, which is a first-run state rather than a
    /// failure.
    public var declaresNoServers: Bool { config.upstreams.isEmpty && skipped.isEmpty }
}

/// Reads the router's own server list.
///
/// The one deliberate departure from the reference is the whole point of this item: a file whose
/// shape is not recognised **fails loudly**. The reference reads `raw.mcpServers`, finds nothing,
/// and loads zero servers with no error at all — which a surface renders as "you have no servers",
/// the single worst failure available, because it is indistinguishable from the truth.
public enum ConfigLoader {
    public struct Options: Sendable {
        public var configPath: String?
        public var port: Int?
        public var host: String?
        public var idleMs: Int?

        public init(configPath: String? = nil, port: Int? = nil, host: String? = nil, idleMs: Int? = nil) {
            self.configPath = configPath
            self.port = port
            self.host = host
            self.idleMs = idleMs
        }
    }

    public static func load(
        options: Options = Options(),
        home: RouterHome = RouterHome(),
        fileSystem: FileSystem = RealFileSystem()
    ) throws -> LoadedConfig {
        let path = options.configPath ?? home.configPath
        guard fileSystem.fileExists(atPath: path) else {
            throw ConfigProblem.missingFile(path: path)
        }

        let data: Data
        do {
            data = try fileSystem.readFile(atPath: path)
        } catch {
            throw ConfigProblem.unreadable(path: path, reason: error.localizedDescription)
        }

        let raw: JSONValue
        do {
            raw = try JSONParser.parse(data)
        } catch let error as JSONParseError {
            throw ConfigProblem.notJSON(path: path, reason: error.description)
        }

        guard let servers = raw.member("mcpServers") else {
            throw ConfigProblem.unrecognisedShape(path: path, found: .missingKey)
        }
        // Present but not an object is the same defect wearing a different hat, and it is the one a
        // decoder that special-cased the recorded fixture would still get wrong.
        guard case let .object(entries) = servers else {
            throw ConfigProblem.unrecognisedShape(path: path, found: .wrongType(servers.typeName))
        }

        var upstreams: [UpstreamConfig] = []
        var skipped: [String] = []
        for entry in entries {
            let name = entry.key.string
            // The reference reads `s.type` off this value; a null entry throws a TypeError there
            // and takes the whole load with it rather than becoming one skipped server.
            guard entry.value != .null else {
                throw ConfigProblem.malformedServerEntry(path: path, name: name)
            }
            switch ServerParser.parse(name: name, raw: entry.value) {
            case let .upstream(upstream): upstreams.append(upstream)
            case let .skipped(reason): skipped.append("\(name) (\(reason))")
            }
        }

        // Nullish, not truthy: an explicit `0` or `""` in the file is honoured rather than
        // replaced by the default.
        let config = RouterConfig(
            port: options.port ?? intMember(raw, "port") ?? RouterHome.defaultPort,
            host: options.host ?? stringMember(raw, "host") ?? RouterHome.defaultHost,
            idleMs: options.idleMs ?? intMember(raw, "idleMs") ?? RouterHome.defaultIdleMs,
            // No option-level override exists for this one, matching the reference.
            startupTimeoutMs: intMember(raw, "startupTimeoutMs") ?? RouterHome.defaultStartupTimeoutMs,
            upstreams: upstreams,
            manifestPath: home.manifestPath,
            logPath: home.logPath,
            usagePath: home.usagePath,
            statsPath: home.statsPath,
            authDir: home.authDir
        )
        return LoadedConfig(config: config, skipped: skipped)
    }

    private static func intMember(_ raw: JSONValue, _ key: String) -> Int? {
        guard let value = raw.member(key), case let .number(number) = value,
              number.isFinite else { return nil }
        return Int(number)
    }

    private static func stringMember(_ raw: JSONValue, _ key: String) -> String? {
        guard let value = raw.member(key), case let .string(text) = value else { return nil }
        return text.string
    }
}
