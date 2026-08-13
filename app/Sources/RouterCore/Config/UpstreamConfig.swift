import Foundation

/// An ordered key/value pair whose key is compared exactly.
///
/// `env` and `headers` are `[JSStringPair]` rather than a Swift dictionary for the same reason
/// JSON objects are ordered arrays: a dictionary keyed by `String` would merge two canonically
/// equivalent keys that JavaScript keeps apart, and both keys feed the config hash.
public struct JSStringPair: Sendable, Hashable {
    public let key: JSString
    public let value: JSString

    public init(key: JSString, value: JSString) {
        self.key = key
        self.value = value
    }
}

/// Why a server is inoperative, and what stands in for it meanwhile.
public struct Placard: Sendable, Hashable {
    public var reason: String
    public var substitute: String?
    public var until: String?

    public init(reason: String, substitute: String? = nil, until: String? = nil) {
        self.reason = reason
        self.substitute = substitute
        self.until = until
    }
}

/// The transport a server speaks. A closed set: an unrecognised value is a rejection with a
/// reason, never a silent fallback to stdio.
public enum ServerTransport: String, Sendable, Hashable, CaseIterable {
    case stdio
    case http
    case sse
}

/// One declared upstream.
///
/// The original parsed JSON is retained alongside the typed view because the config hash is taken
/// over the reference's own expressions — `u.args`, `u.env`, `u.cwd ?? null` — and those are
/// whatever the file contained, not a normalised form of it. Hashing the typed view would quietly
/// repair malformed input and produce a digest the reference never would.
public struct UpstreamConfig: Sendable, Hashable {
    public var name: String
    public var transport: ServerTransport
    public var raw: JSONValue

    // Common to both transports.
    public var idleMs: Int?
    public var startupTimeoutMs: Int?
    public var projects: [String]?
    public var warm: Bool?
    public var placard: Placard?

    // stdio.
    public var command: String?
    public var args: [String]
    public var env: [JSStringPair]
    public var cwd: String?

    // http / sse.
    public var url: String?
    public var headers: [JSStringPair]
    public var oauth: Bool?

    /// True for every non-stdio transport, matching the reference's `u.transport !== 'stdio'`
    /// rather than an explicit list — an `sse` upstream is an HTTP upstream here.
    public var isHTTP: Bool { transport != .stdio }
    public var isStdio: Bool { transport == .stdio }
}

/// Everything the router reads or writes, and where it lives.
public struct RouterConfig: Sendable, Hashable {
    public var port: Int
    public var host: String
    public var idleMs: Int
    public var startupTimeoutMs: Int
    public var upstreams: [UpstreamConfig]
    public var manifestPath: String
    public var logPath: String
    public var usagePath: String
    public var statsPath: String
    public var authDir: String
}

/// Where every piece of router state lives.
///
/// `MCP_ROUTER_HOME` moves all of it together, and that is the invariant: splitting the control
/// token from the config would let a second instance authenticate against the first one's control
/// API. Note the paths derive from the **home**, never from the directory an explicitly-supplied
/// config file happens to sit in.
public struct RouterHome: Sendable, Hashable {
    public let root: String

    public init(root: String) {
        self.root = root
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: String = NSHomeDirectory())
    {
        if let override = environment["MCP_ROUTER_HOME"], !override.isEmpty {
            root = override
        } else {
            root = (homeDirectory as NSString).appendingPathComponent(".claude/mcp-router")
        }
    }

    private func path(_ component: String) -> String {
        (root as NSString).appendingPathComponent(component)
    }

    public var configPath: String { path("servers.json") }
    public var manifestPath: String { path("manifest.json") }
    public var logPath: String { path("router.log") }
    public var usagePath: String { path("usage.jsonl") }
    public var statsPath: String { path("usage-stats.json") }
    public var authDir: String { path("auth") }

    public static let defaultPort = 8879
    public static let defaultHost = "127.0.0.1"
    public static let defaultIdleMs = 300_000
    public static let defaultStartupTimeoutMs = 60_000
}

public extension JSONValue {
    /// JavaScript truthiness, which several of the reference's checks turn on: `if (!s.command)`
    /// rejects an empty string, and `s.url ? 'http' : 'stdio'` selects stdio for `url: ""`.
    var isTruthy: Bool {
        switch self {
        case .null: return false
        case let .bool(flag): return flag
        case let .number(value): return value != 0 && !value.isNaN
        case let .string(text): return !text.isEmpty
        case .array, .object: return true
        }
    }

    /// How a template literal would render this value, used for the reason strings.
    var jsDisplayString: String {
        switch self {
        case .null: return "null"
        case let .bool(flag): return flag ? "true" : "false"
        case let .number(value): return JSNumber.string(value)
        case let .string(text): return text.string
        case .array, .object: return JSStringify.compact(self)
        }
    }

    /// `Object.entries(value)` for the object case, which is the only shape a real config uses.
    ///
    /// A non-object here — `env: "abc"`, which JavaScript would enumerate as indexed characters —
    /// yields no entries. Recorded as a stated limit rather than reproduced: the reference's own
    /// behaviour for that input is incoherent, and a config carrying it is malformed in a way the
    /// user needs to see rather than have hashed.
    var objectEntries: [JSStringPair] {
        guard case let .object(members) = self else { return [] }
        return members.compactMap { member in
            guard case let .string(text) = member.value else {
                return JSStringPair(key: member.key, value: JSString(member.value.jsDisplayString))
            }
            return JSStringPair(key: member.key, value: text)
        }
    }
}
