import Foundation

/// Where the client's diagnostics go, and the seam a test can watch.
///
/// This exists so "no token is ever logged" is a claim something can *check*. A client that logs
/// through `print` gives a test nothing to assert against, so the rule survives only as an
/// intention — and the failure it guards against (a token in a log file, a support bundle, a
/// screen share) is silent and permanent. Here every line goes through one sink, and the test
/// installs its own.
public enum ControlLogLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

/// A destination for client diagnostics.
public protocol ControlLogSink: Sendable {
    func write(_ level: ControlLogLevel, _ message: String)
}

/// Discards everything. The default, because a library that logs to a shared destination without
/// being asked is a library that decides for its host.
public struct SilentLogSink: ControlLogSink {
    public init() {}
    public func write(_: ControlLogLevel, _: String) {}
}

/// Collects lines in memory so a test can assert on what was written.
public actor CollectingLogSink: ControlLogSink {
    private var lines: [String] = []

    public init() {}

    public nonisolated func write(_ level: ControlLogLevel, _ message: String) {
        Task { await self.append("[\(level.rawValue)] \(message)") }
    }

    private func append(_ line: String) {
        lines.append(line)
    }

    public func recorded() -> [String] {
        lines
    }

    /// Every line joined, for a containment assertion.
    public func joined() -> String {
        lines.joined(separator: "\n")
    }
}

/// The client's logger. Records the **shape** of a thing, never its value.
public struct ControlLog: Sendable {
    public let sink: any ControlLogSink

    public init(sink: any ControlLogSink = SilentLogSink()) {
        self.sink = sink
    }

    public func info(_ message: String) {
        sink.write(.info, message)
    }

    public func warning(_ message: String) {
        sink.write(.warning, message)
    }

    public func error(_ message: String) {
        sink.write(.error, message)
    }

    /// Describe a secret without disclosing it.
    ///
    /// The only sanctioned way to mention a token in a log line. A length is enough to tell
    /// "there is a token and it looks plausible" from "the token is empty", which is the entire
    /// diagnostic value a token has; the characters themselves add nothing a reader needs and
    /// everything an attacker does.
    public static func redacted(_ secret: String?) -> String {
        guard let secret, !secret.isEmpty else { return "<none>" }
        return "<\(secret.count) chars>"
    }
}

// MARK: - Storing the control token

public enum TokenStoreError: Error, Equatable, Sendable {
    /// The Keychain refused, with its own status code.
    case keychain(status: Int32)
    /// Something was stored but it was not text.
    case notText
}

/// Where the control token lives between launches.
///
/// A protocol with two implementations because the Keychain is a process boundary — the one place
/// this codebase's own testing rule says to substitute a double rather than reach for the real
/// thing. Everything else in the client is exercised for real.
public protocol ControlTokenStore: Sendable {
    func read() async throws -> String?
    func write(_ token: String) async throws
    func delete() async throws
}

/// The real store: a generic password in the system Keychain.
///
/// `UserDefaults`, a plist and a file beside the app are all excluded by the house rules, and for
/// the same reason: this token authorises everything the router can do, which includes starting a
/// process with the user's environment. `kSecAttrAccessibleAfterFirstUnlock` keeps it readable to
/// a menu-bar app that launches at login while still requiring the device to have been unlocked
/// once since boot.
public struct KeychainTokenStore: ControlTokenStore {
    public let service: String
    public let account: String

    public init(
        service: String = "app.fledgeling.mcprouter.control",
        account: String = "control-token"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    public func read() async throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status: status) }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw TokenStoreError.notText
        }
        return text
    }

    public func write(_ token: String) async throws {
        // Delete-then-add rather than update: an update on a missing item fails, and branching on
        // which case applies is one more state to get wrong for no gain.
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData] = Data(token.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status: status) }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status: status)
        }
    }
}

/// An in-memory store for tests. An actor rather than a locked class, so no `@unchecked Sendable`
/// promise has to be made and audited.
public actor InMemoryTokenStore: ControlTokenStore {
    private var token: String?

    public init(_ initial: String? = nil) {
        token = initial
    }

    public func read() async throws -> String? {
        token
    }

    public func write(_ token: String) async throws {
        self.token = token
    }

    public func delete() async throws {
        token = nil
    }
}

// MARK: - Where the router puts the token

/// Reads the token file the router writes.
///
/// The path is the router's own (`ROUTER_HOME/control.token`, mode 0600), and
/// `MCP_ROUTER_HOME` moves it — the same environment variable the router honours, so a second
/// router instance for a test does not collide with the real one. The Mac app can read it directly
/// because it is unsandboxed and the file belongs to the same user; that is the whole pairing
/// step on this machine.
///
/// **On iOS there is no such file, and that is the point rather than a gap.** The phone is
/// sandboxed and the router runs on the Mac, so there is no local daemon to hold a credential for
/// — the phone reaches the Mac by pairing, which the inbox items own. The default path resolves
/// inside the app's own container, where nothing will ever write one, so a read returns nil and
/// the client reports "the router is not running": on a phone, truthfully, it never is.
public struct RouterTokenFile: Sendable {
    public let url: URL

    public init(home: String? = ProcessInfo.processInfo.environment["MCP_ROUTER_HOME"]) {
        let base = home.map { URL(fileURLWithPath: $0) } ?? Self.defaultHome
        url = base.appendingPathComponent("control.token", isDirectory: false)
    }

    /// Where the router keeps its state when the environment does not say otherwise.
    private static var defaultHome: URL {
        #if os(macOS)
            // The user's real home. `homeDirectoryForCurrentUser` is macOS-only, which is the
            // compiler telling us the same thing the design does: this path only means something
            // on the machine the router runs on.
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("mcp-router", isDirectory: true)
        #else
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("mcp-router", isDirectory: true)
        #endif
    }

    public init(url: URL) {
        self.url = url
    }

    /// The token, or nil when the file is absent or empty.
    ///
    /// Absent is not an error here: it means the router has never run, and the caller turns that
    /// into `.routerNotRunning` — the condition the user actually has — rather than into
    /// `.unauthorized`, which would send them to re-pair something that was never paired.
    public func read() -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
