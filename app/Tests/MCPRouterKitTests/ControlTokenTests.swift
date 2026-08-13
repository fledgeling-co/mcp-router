import Foundation
import Testing
@testable import MCPRouterKit

/// Where the control token lives, and what is allowed to be said about it out loud.
///
/// This token authorises everything the router can do, which includes starting a process with the
/// user's environment. So the two properties worth a test are that it goes somewhere the system
/// protects, and that it never appears anywhere it might be read back — a log file, a support
/// bundle, a screen share.
@Suite("The control token")
struct ControlTokenTests {
    /// A service name unique to the run, so a test can never read, overwrite or delete the token
    /// belonging to an actual installed app on this machine.
    private static func uniqueStore() -> KeychainTokenStore {
        KeychainTokenStore(
            service: "app.fledgeling.mcprouter.test.\(UUID().uuidString)",
            account: "control-token"
        )
    }

    // MARK: - A5: the Keychain, and nowhere else

    @Test("the token round-trips through the real Keychain")
    func keychainRoundTrips() async throws {
        let store = Self.uniqueStore()
        defer { Task { try? await store.delete() } }

        #expect(try await store.read() == nil, "a fresh service starts empty")

        try await store.write("fixture-token-value")
        #expect(try await store.read() == "fixture-token-value")

        // Writing again replaces rather than duplicating — a second item under one service is an
        // ambiguous read forever after.
        try await store.write("rotated-token-value")
        #expect(try await store.read() == "rotated-token-value")

        try await store.delete()
        #expect(try await store.read() == nil)
    }

    @Test("deleting a token that was never stored is not an error")
    func deletingNothingIsFine() async throws {
        let store = Self.uniqueStore()
        await #expect(throws: Never.self) { try await store.delete() }
    }

    /// The negative half of A5. A round-trip through the Keychain proves the token *can* live
    /// there; it does not prove a copy was not also left somewhere unprotected on the way.
    ///
    /// It drives **both** stores, and the second one is the reason this test is worth having. An
    /// earlier version exercised only the in-memory double, so `KeychainTokenStore.write` — the
    /// implementation that actually ships — was never called: the red-green pass added a
    /// `UserDefaults.standard.set(token, …)` line to it and the whole suite stayed green. A
    /// negative assertion that never runs the code it is negating is worse than no assertion,
    /// because it reports having checked.
    @Test("no token-shaped value is ever written to UserDefaults")
    func nothingReachesUserDefaults() async throws {
        let secret = "token-\(UUID().uuidString)"
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/servers", .json(200, #"{"port":1,"idleMs":1,"since":"x","servers":[]}"#))

        let client = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore(secret),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token"))
        )
        _ = try await client.servers()

        // The store the app ships with, driven through every method that handles the value.
        let keychainSecret = "token-\(UUID().uuidString)"
        let store = Self.uniqueStore()
        try await store.write(keychainSecret)
        _ = try await store.read()
        try await store.delete()

        UserDefaults.standard.synchronize()
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        for (key, value) in defaults {
            if let text = value as? String {
                #expect(text != secret, "the token was written to UserDefaults under \(key)")
                #expect(
                    text != keychainSecret,
                    "the Keychain store left a copy of the token in UserDefaults under \(key)"
                )
            }
            #expect(
                !key.lowercased().contains("controltoken"),
                "a key named for the control token exists in UserDefaults: \(key)"
            )
            #expect(
                !key.lowercased().replacingOccurrences(of: "-", with: "").contains("controltoken"),
                "a key named for the control token exists in UserDefaults: \(key)"
            )
        }
    }

    // MARK: - A7: the shape may be logged, the value never

    @Test("the log records that a token exists and its length, never the token itself")
    func loggingRedactsTheToken() async throws {
        let secret = "super-secret-token-value"
        let sink = CollectingLogSink()

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f3-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("control.token")
        try "\(secret)\n".write(to: tokenURL, atomically: true, encoding: .utf8)

        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/servers", .json(200, #"{"port":1,"idleMs":1,"since":"x","servers":[]}"#))

        // No stored token, so the client reads the router's file — the one path that logs anything
        // about the credential at all.
        let client = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore(nil),
            tokenFile: RouterTokenFile(url: tokenURL),
            log: ControlLog(sink: sink)
        )
        _ = try await client.servers()

        let written = await Self.settledLog(sink)
        #expect(!written.isEmpty, "the client logged nothing at all, so this proves nothing")

        // The three separate ways a credential leaks into a log, per the house rules: the value
        // itself, the header carrying it, and a dump of the whole request or config object. A test
        // that greps only for the token passes a client that logs the entire request.
        #expect(!written.contains(secret), "the token's value reached the log")
        #expect(!written.lowercased().contains("authorization"), "an Authorization header reached the log")
        #expect(!written.lowercased().contains("bearer"), "a bearer header reached the log")
        #expect(!written.contains("URLRequest"), "a whole request object was dumped to the log")

        // What it *is* allowed to say: that there is one, and how long it is.
        #expect(
            written.contains("<\(secret.count) chars>"),
            "the log should describe the token's shape: \(written)"
        )
    }

    @Test("redaction describes an absent token as absent rather than as an empty one")
    func redactionHandlesNothing() {
        #expect(ControlLog.redacted(nil) == "<none>")
        #expect(ControlLog.redacted("") == "<none>")
        #expect(ControlLog.redacted("abcd") == "<4 chars>")
    }

    /// The sink appends asynchronously, so a read taken immediately can see nothing and pass a
    /// test that should have failed. This waits for it to settle, and gives up rather than hanging.
    private static func settledLog(_ sink: CollectingLogSink) async -> String {
        for _ in 0 ..< 100 {
            let text = await sink.joined()
            if !text.isEmpty { return text }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await sink.joined()
    }

    // MARK: - The router's own token file

    @Test("the token file is read as the router writes it, trailing newline and all")
    func tokenFileTrims() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f3-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("control.token")
        try "  abc123\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(RouterTokenFile(url: url).read() == "abc123")

        try "   \n".write(to: url, atomically: true, encoding: .utf8)
        #expect(RouterTokenFile(url: url).read() == nil, "whitespace is not a token")

        try FileManager.default.removeItem(at: url)
        #expect(
            RouterTokenFile(url: url).read() == nil,
            "an absent file is not an error — it means the router has never run"
        )
    }

    @Test("MCP_ROUTER_HOME moves the token file, as it does for the router")
    func honoursRouterHome() {
        let file = RouterTokenFile(home: "/tmp/some-router-home")
        #expect(file.url.path == "/tmp/some-router-home/control.token")

        let standard = RouterTokenFile(home: nil)
        #expect(standard.url.path.hasSuffix(".claude/mcp-router/control.token"))
    }
}
