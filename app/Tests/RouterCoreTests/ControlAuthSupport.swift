import Foundation
import Testing
@testable import RouterCore

/// A spy the doubles below share. Top level rather than nested, because the repo caps nesting at one
/// level and a recorder inside a double inside a suite is otherwise three deep.
final class AuthDispatchCalls: @unchecked Sendable {
    private let lock = NSLock()
    /// Every side effect in arrival order, so an *ordering* assertion is possible rather than only
    /// a "both happened" one. `clearPending` before `index` is the whole of B?? on the success path.
    private var events: [String] = []
    private var indexedNames: [String] = []
    private var begins = 0

    func record(_ event: String) {
        lock.withLock { events.append(event) }
    }

    func recordIndex(_ name: String) {
        lock.withLock {
            events.append("index")
            indexedNames.append(name)
        }
    }

    func recordBegin() {
        lock.withLock {
            events.append("begin")
            begins += 1
        }
    }

    var order: [String] { lock.withLock { events } }
    var indexed: [String] { lock.withLock { indexedNames } }
    var beginCount: Int { lock.withLock { begins } }
}

/// Doubles, fixtures and request helpers shared by the two `ControlAuthDispatch` suites.
///
/// A separate type rather than a base class: the suites are `struct`s, and the repo's file-length
/// and type-body-length caps are met by splitting on this seam rather than by raising either.
enum ControlAuthSupport {
    // MARK: - Doubles

    struct RecordingPool: UpstreamPoolPort {
        let calls: AuthDispatchCalls

        func status() -> [LiveUpstream] {
            []
        }

        func pending() -> [PendingAuthRow] {
            []
        }

        func isLive(_: JSString) -> Bool {
            false
        }

        func warmUp() {}

        func clearPending(_: JSString) {
            calls.record("clearPending")
        }
    }

    struct RecordingIndexer: UpstreamIndexerPort {
        let calls: AuthDispatchCalls

        func index(_ upstream: UpstreamConfig) async -> IndexOutcome {
            calls.recordIndex(upstream.name)
            return IndexOutcome(tools: 1)
        }
    }

    struct NoAuth: AuthStore {
        func hasTokens(_: JSString) -> Bool {
            false
        }

        func authorizedAt(_: JSString) -> String? {
            nil
        }

        @discardableResult func clear(_: JSString) -> Bool {
            false
        }
    }

    struct FixedClock: RouterClock {
        let nowMilliseconds: Double
    }

    /// How the flow terminates, chosen per test.
    enum Termination: Sendable {
        case authorized
        case rejected(String)
        case abandoned
        case beginFails(String)
    }

    /// A flow starter that never touches a network.
    ///
    /// `Termination` chooses which of `authStart`'s four exits the flow takes, so each side effect
    /// is asserted against the exit that produces it rather than against one happy path.
    struct StubStarter: AuthFlowStarting {
        let calls: AuthDispatchCalls
        let termination: Termination
        var url = "https://auth.example.invalid/authorize?code_challenge=x"

        func begin(server: JSString, upstream _: UpstreamConfig) async throws -> LiveFlow {
            calls.recordBegin()
            if case let .beginFails(reason) = termination { throw AuthFailure(reason) }
            return LiveFlow(server: server, url: url)
        }

        func awaitCompletion(server _: JSString) async throws {
            switch termination {
            case .authorized: return
            case let .rejected(reason): throw AuthFailure(reason)
            case .abandoned: throw AuthAbandoned()
            case let .beginFails(reason): throw AuthFailure(reason)
            }
        }
    }

    // MARK: - Fixtures

    static let config = """
    {
      "mcpServers": {
        "p1-stdio": { "command": "/bin/echo", "args": ["hello"] },
        "p1-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": true }
      }
    }
    """

    /// A manifest on a memory filesystem, plus the path the config will point `manifestPath` at.
    static func seedManifest(_ entry: String, server: String = "p1-stdio") -> (AuthTestFileSystem, String) {
        let fileSystem = AuthTestFileSystem()
        let path = "/router/manifest.json"
        fileSystem.memory.seed(
            "{\n  \"version\": 1,\n  \"servers\": {\n    \"\(server)\": \(entry)\n  }\n}",
            atPath: path
        )
        return (fileSystem, path)
    }

    static func makeDeps(
        // `FileSystem & FileModeWriting`, not bare `FileSystem`: V1 tightened `ControlDeps`'s
        // member to the composition, and this parameter was the merge-only break — both
        // branches compiled alone and the merged tree did not.
        fileSystem: any FileSystem & FileModeWriting = AuthTestFileSystem(),
        manifestPath: String = "/router/manifest.json",
        calls: AuthDispatchCalls = AuthDispatchCalls(),
        starter: (any AuthFlowStarting)? = nil,
        log: RouterLog? = nil
    ) throws -> ControlDeps {
        let parsed = try JSONParser.parse(config)
        let entries = parsed.member("mcpServers")?.asObjectMembers ?? []
        var upstreams: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            upstreams.append((entry.key, upstream))
        }
        let clock = FixedClock(nowMilliseconds: 1_770_000_000_000)
        return ControlDeps(
            config: RouterConfig(
                port: 8971, host: "127.0.0.1", idleMs: 300_000, startupTimeoutMs: 60000,
                upstreams: upstreams.map(\.upstream), manifestPath: manifestPath,
                logPath: "/router/r.log", usagePath: "/router/none/usage.jsonl",
                statsPath: "/router/none/stats.json", authDir: "/router/auth"
            ),
            upstreams: upstreams,
            pool: RecordingPool(calls: calls),
            indexer: RecordingIndexer(calls: calls),
            auth: NoAuth(),
            usage: UsageStore(
                logPath: "/router/none/usage.jsonl", statsPath: "/router/none/stats.json",
                clock: clock
            ),
            manifest: .empty,
            clock: clock,
            fileSystem: fileSystem,
            tokenPath: "/router/control.token",
            configPath: "/router/servers.json",
            log: log,
            authFlow: starter
        )
    }

    static let token = "p1-token"

    static func post(_ path: String, authorized: Bool = true) -> ControlAPIRequest {
        var headers = [
            (name: "content-type", value: "application/json")
        ]
        if authorized { headers.append((name: "x-mcpr-token", value: token)) }
        return ControlAPIRequest(
            method: "POST", encodedPath: path, query: [], headers: headers, body: Data("{}".utf8)
        )
    }

    static func answer(
        _ path: String, _ deps: inout ControlDeps, authorized: Bool = true
    ) async -> (status: Int, body: String) {
        let response = await ControlHandler(token: token)
            .handle(post(path, authorized: authorized), &deps)
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    /// Polls until `condition` holds, rather than sleeping a fixed span and hoping.
    ///
    /// The side effects under test happen in a detached `Task` that `authStart` spawns before it
    /// returns, so they land *after* the response. A fixed sleep here is the pattern that gave this
    /// repo `pollingIsIdempotent` — 5/5 alone and ~4 failures in 5 under full-suite load.
    static func settle(
        within milliseconds: Int = 3000, _ condition: @Sendable () -> Bool
    ) async throws {
        for _ in 0 ..< (milliseconds / 10) {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("condition did not hold within \(milliseconds)ms")
    }
}
