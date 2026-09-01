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
    /// Declared and not served — the third state, between adopted and removed.
    ///
    /// Distinct from `placard`, which keeps the tools listed and answering with a reason. A
    /// disabled server contributes nothing to `tools/list`, cannot be called by name, is never
    /// spawned to be warmed or indexed, and is reaped if it happens to be up — while its manifest
    /// row, digest and approved surface survive untouched, so re-enabling cannot launder an
    /// approval the user refused by disabling.
    ///
    /// Absent from `UpstreamHash` for the reason `projects`, `warm` and `placard` are: none of them
    /// changes what the upstream advertises.
    public var disabled: Bool?
    /// This server's `health` block, if it wrote one — R27.
    ///
    /// Absent from ``UpstreamHash`` for the reason `idleMs`, `projects`, `warm` and `placard` are:
    /// how often the router asks a server for its tools does not change which tools it advertises,
    /// so changing it must not cost a re-index.
    public var health: HealthOverride?

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
    /// The health defaults every upstream inherits unless it overrides them — R27. Defaulted here
    /// rather than required, so the twenty-six construction sites that predate health checking
    /// build a router with background probing off, which is what they described before this
    /// existed.
    public var health: HealthPolicy = .standard
    /// Top-level `health` values the loader would not take, carried so every server's report can
    /// say so. Empty for a file that configured nothing or configured it within range.
    public var healthRefusals: [HealthPolicyRefusal] = []
    /// When the router warns that a credential is running out, and how often it says so again —
    /// R26. Defaulted here rather than required for the reason ``health`` is, and with one of its
    /// own: unlike health probing this feature is **on** by default, because deriving an expiry
    /// from `authorizedAt + expires_in` reads two numbers already on disk and spawns nothing.
    public var authExpiry: AuthExpiryPolicy = .standard
    /// Top-level `authExpiry` values the loader would not take, carried out to the wire so a file
    /// that says one number and a router that uses another cannot disagree in silence.
    public var authExpiryRefusals: [AuthExpiryRefusal] = []
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

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) {
        if let override = environment["MCP_ROUTER_HOME"], !override.isEmpty {
            root = override
        } else {
            root = (homeDirectory as NSString).appendingPathComponent(".claude/mcp-router")
        }
    }

    /// The home directory the **reference** would use: `os.homedir()`, which reads `$HOME`.
    ///
    /// `NSHomeDirectory()` does not. Measured on 2026-08-15: under `HOME=/tmp/fakehome`, node's
    /// `os.homedir()` returns `/tmp/fakehome` and `NSHomeDirectory()` returns the real account's
    /// directory. Every path the reference derives from `homedir()` therefore has to be derived
    /// from this, or a run under a scratch `HOME` reads and writes the developer's own files —
    /// which is a safety property before it is a parity one (`WatchPaths`, X10/W-D2).
    ///
    /// One implementation rather than two: ``WatchPaths`` and ``ImportPaths`` both call it.
    public static func resolvedHomeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? homeDirectory
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
    /// Where the router holds skills, plugins and marketplaces — R28. Under the home like every
    /// other piece of router state, so `MCP_ROUTER_HOME` still moves all of it together, which is
    /// the invariant this type exists for.
    public var extensionsPath: String { path("extensions") }
    /// Where F5 writes what it observed. Three files, under the home for ``extensionsPath``'s
    /// reason — `MCP_ROUTER_HOME` moves all of the router's state together, which is the invariant
    /// this type exists for, and telemetry that escaped it would be the one kind of state a person
    /// most needs to be able to move or delete in one gesture.
    public var invocationsPath: String { path("invocations.jsonl") }
    /// The version boundary set — `spec-F5.md` §4.2.
    public var versionLedgerPath: String { path("versions.jsonl") }
    /// How far into each transcript file the last scan reached.
    public var invocationWatermarkPath: String { path("invocation-watermarks.json") }
    /// F8's profile store. A sibling of `extensions` rather than a directory inside it: a profile
    /// selects over the store and is not one of the things stored, and nesting it would put a name
    /// that is not an extension kind inside a directory whose every child is one.
    public var profilesPath: String { path("profiles") }

    public static let defaultPort = 8879
    public static let defaultHost = "127.0.0.1"
    public static let defaultIdleMs = 300_000
    public static let defaultStartupTimeoutMs = 60000
}

public extension JSONValue {
    /// JavaScript truthiness, which several of the reference's checks turn on: `if (!s.command)`
    /// rejects an empty string, and `s.url ? 'http' : 'stdio'` selects stdio for `url: ""`.
    var isTruthy: Bool {
        switch self {
        case .null: false
        case let .bool(flag): flag
        case let .number(value): value != 0 && !value.isNaN
        case let .string(text): !text.isEmpty
        case .array, .object: true
        }
    }

    /// `ToBoolean(value?.length)` — a **property read**, not an array test.
    ///
    /// The reference gates `projects` on `b.projects?.length`, which reads a `length` property off
    /// whatever arrived and takes its truthiness. A string has one (its UTF-16 code-unit count), so
    /// `projects: "x"` is stored **unchanged**; an object has one only if it declares the member;
    /// a number and a boolean have none, so both read `undefined` and are falsy. Testing `asArray`
    /// instead removes the member for every non-array, which is a silent divergence on the exact
    /// vector B42 names.
    var jsLengthIsTruthy: Bool {
        switch self {
        case let .string(text): !text.isEmpty
        case let .array(items): !items.isEmpty
        case let .object(members):
            // `{length: 3}` is truthy; an object without the member reads `undefined`.
            members.first { $0.key == JSString("length") }?.value.isTruthy ?? false
        // No `length` property exists on these, so the read yields `undefined`.
        case .null, .bool, .number: false
        }
    }

    /// How a template literal would render this value, used for the reason strings.
    var jsDisplayString: String {
        switch self {
        case .null: "null"
        case let .bool(flag): flag ? "true" : "false"
        case let .number(value): JSNumber.string(value)
        case let .string(text): text.string
        case .array, .object: JSStringify.compact(self)
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
