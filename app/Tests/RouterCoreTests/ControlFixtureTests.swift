import Foundation
import Testing
@testable import RouterCore

/// A spy for the pool double. Top level rather than nested, because the repo caps nesting at one
/// level and a double's recorder is otherwise three deep.
final class PoolCalls: @unchecked Sendable {
    var warmUps = 0
    var cleared: [String] = []
}

/// The control API against F3's recorded responses.
///
/// These are **byte** comparisons against files captured from the running TypeScript router, and
/// the values are built from the same `servers.json` the capture script wrote — committed at
/// `scripts/capture-control-fixtures.sh`. That matters more than it looks: the row carries a
/// config-identity hash over the env *values*, so reproducing the recorded bytes is only possible
/// from the real config and not from a plausible one.
///
/// Per spec S6, nothing here recognises a state and returns recorded bytes. Every response is
/// constructed from injected dependencies, which is the property a review defeated nine of this
/// item's first-draft clauses for lacking.
struct ControlFixtureTests {
    // MARK: - Doubles

    struct IdlePool: UpstreamPoolPort {
        var live: [LiveUpstream] = []
        var pendingAuths: [PendingAuthRow] = []
        let calls = PoolCalls()

        func status() -> [LiveUpstream] {
            live
        }

        func pending() -> [PendingAuthRow] {
            pendingAuths
        }

        func isLive(_: JSString) -> Bool {
            false
        }

        func warmUp() {
            calls.warmUps += 1
        }

        func clearPending(_ name: JSString) {
            calls.cleared.append(name.string)
        }
    }

    struct StubIndexer: UpstreamIndexerPort {
        var outcome = IndexOutcome(tools: 0)
        func index(_: UpstreamConfig) async -> IndexOutcome {
            outcome
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

    /// The exact `servers.json` the capture script wrote.
    static let captureConfig = """
    {
      "mcpServers": {
        "fixture-stdio": { "command": "/bin/echo", "args": ["hello"], "env": { "FIXTURE_KEY": "x" } },
        "fixture-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": false },
        "fixture-oauth": { "url": "http://127.0.0.1:8972/mcp", "type": "http", "oauth": true }
      }
    }
    """

    static func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MCPRouterKit/Control/Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
    }

    static func makeDeps(
        pool: IdlePool = IdlePool(),
        indexer: StubIndexer = StubIndexer(),
        manifest: Manifest = .empty,
        usageLog: String = "/tmp/mcprouter-tests-does-not-exist/usage.jsonl"
    ) throws -> ControlDeps {
        let parsed = try JSONParser.parse(captureConfig)
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
                upstreams: upstreams.map(\.upstream), manifestPath: "/tmp/m.json",
                logPath: "/tmp/r.log", usagePath: usageLog, statsPath: "/tmp/s.json",
                authDir: "/tmp/auth"
            ),
            upstreams: upstreams,
            pool: pool,
            indexer: indexer,
            auth: NoAuth(),
            usage: UsageStore(
                logPath: usageLog, statsPath: "/tmp/mcprouter-tests-none/stats.json",
                clock: clock
            ),
            manifest: manifest,
            clock: clock,
            tokenPath: "/tmp/control.token",
            configPath: "/tmp/servers.json"
        )
    }

    static func body(_ response: ControlAPIResponse) -> String {
        guard case let .bytes(bytes) = response.body else { return "" }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - B1, B3: the recorded rows, byte for byte

    @Test("a stdio row reproduces server-stdio.json byte for byte")
    func stdioRow() throws {
        var deps = try Self.makeDeps()
        let upstream = try #require(deps.upstream(named: JSString("fixture-stdio")))
        let produced = JSStringify.compact(Describe.row(upstream, deps))
        #expect(try produced == (Self.fixture("server-stdio.json")))
        _ = deps
    }

    @Test("an http row reproduces server-http.json byte for byte")
    func httpRow() throws {
        var deps = try Self.makeDeps()
        let upstream = try #require(deps.upstream(named: JSString("fixture-http")))
        let produced = JSStringify.compact(Describe.row(upstream, deps))
        #expect(try produced == (Self.fixture("server-http.json")))
        _ = deps
    }

    /// The oauth row is the one that proves B6's `oauth !== false` branch and B7's omission of
    /// `authorizedAt`/`pendingUrl` — a supported, unauthorized server carrying neither key.
    @Test("an oauth row reports auth supported and omits the absent members")
    func oauthRow() throws {
        var deps = try Self.makeDeps()
        let upstream = try #require(deps.upstream(named: JSString("fixture-oauth")))
        let produced = JSStringify.compact(Describe.row(upstream, deps))
        #expect(produced.contains(#""auth":{"supported":true,"authorized":false}"#))
        #expect(!produced.contains("authorizedAt"))
        #expect(!produced.contains("pendingUrl"))
        _ = deps
    }

    // MARK: - B2, S3: undefined is absent, not null

    @Test("absent members are omitted rather than emitted as null")
    func omitsUndefined() throws {
        var deps = try Self.makeDeps()
        let upstream = try #require(deps.upstream(named: JSString("fixture-stdio")))
        let produced = JSStringify.compact(Describe.row(upstream, deps))
        // The config declares no cwd, the manifest has no entry, there is no placard and nothing
        // pending — four members the reference omits entirely.
        for absent in ["cwd", "indexedAt", "indexError", "placard", "pendingChange"] {
            #expect(!produced.contains("\"\(absent)\""), "\(absent) should be absent, not null")
        }
        _ = deps
    }

    // MARK: - B5, S1: JavaScript truthiness on entry.error

    /// The invariant that a Swift `!= nil` gets wrong while passing every recorded fixture.
    ///
    /// The reference writes `entry?.error ? 0 : entry.tools.length`. An **empty** error string is
    /// falsy, so the cached tools survive. A port testing `error != nil` reports zero tools here.
    @Test("an empty error string is falsy, so the cached tools survive")
    func emptyErrorRetainsTools() throws {
        let tool = CachedTool(members: [
            JSONMember(key: "name", value: .string(JSString("ping"))),
            JSONMember(key: "description", value: .string(JSString("Answer with pong.")))
        ])
        let entry = CachedServer(members: [
            JSONMember(key: "tools", value: .array([tool.value])),
            JSONMember(key: "error", value: .string(JSString("")))
        ])
        var manifest = Manifest.empty
        manifest.setEntry("fixture-stdio", entry)

        var deps = try Self.makeDeps(manifest: manifest)
        let upstream = try #require(deps.upstream(named: JSString("fixture-stdio")))
        let produced = JSStringify.compact(Describe.row(upstream, deps))

        #expect(produced.contains(#""tools":1"#), "an error:\"\" must not zero the tool count")
        #expect(produced.contains(#""toolNames":["ping"]"#))
        // And the empty error is still reported, because it is defined.
        #expect(produced.contains(#""indexError":"""#))
        _ = deps
    }
}

/// Dispatch, the token gate and the JavaScript-semantics invariants.
///
/// A second suite rather than a longer one: the repo caps a type body at 250 lines, and these are a
/// different subject from the recorded-row comparisons above.
struct ControlDispatchTests {
    typealias Fixtures = ControlFixtureTests

    // MARK: - B14, B22: the dispatch order the review corrected

    @Test("a non-control path is not handled, and no token is demanded of it")
    func mcpPathFallsThrough() async throws {
        var deps = try Fixtures.makeDeps()
        let handler = ControlHandler(token: "secret")
        let response = await handler.handle(
            ControlAPIRequest(method: "POST", encodedPath: "/mcp"), &deps
        )
        // Gating before ownership would answer 401 here and break the MCP endpoint outright.
        #expect(response.handled == false)
        #expect(response.status == 0)
    }

    @Test("an unknown server without a token is 401, not 404")
    func tokenPrecedesLookup() async throws {
        var deps = try Fixtures.makeDeps()
        let handler = ControlHandler(token: "secret")
        let response = await handler.handle(
            ControlAPIRequest(method: "DELETE", encodedPath: "/servers/ghost"), &deps
        )
        #expect(response.status == 401)
        #expect(Fixtures.body(response).contains("unauthorized; the token is in"))
    }

    @Test("a claimed path that matches no route is 405, not 404")
    func trailingSlashIs405() async throws {
        var deps = try Fixtures.makeDeps()
        let handler = ControlHandler(token: "secret")
        let response = await handler.handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers/"), &deps
        )
        #expect(response.status == 405)
        #expect(Fixtures.body(response) == #"{"error":"GET not allowed on /servers/"}"#)
    }

    // MARK: - B15: ownership over the encoded path

    @Test("path ownership is decided on the encoded path")
    func ownershipNegatives() {
        #expect(ControlPaths.isControlPath("/servers"))
        #expect(ControlPaths.isControlPath("/usage/summary"))
        #expect(ControlPaths.isControlPath("/registry/search"))
        // Prefix-sharing paths this item does not own — a `hasPrefix("/servers")` gets these wrong.
        #expect(!ControlPaths.isControlPath("/servershim"))
        #expect(!ControlPaths.isControlPath("/usagexyz"))
        #expect(!ControlPaths.isControlPath("/registry"))
        // Decoding before classifying would claim this one.
        #expect(!ControlPaths.isControlPath("/servers%2Fx"))
    }

    // MARK: - B17, B21: the token gate's awkward cases

    @Test("a Bearer prefix shadows x-mcpr-token even when the bearer value is wrong")
    func bearerShadowsHeader() {
        let request = ControlAPIRequest(
            method: "POST", encodedPath: "/servers",
            headers: [(name: "Authorization", value: "Bearer wrong"),
                      (name: "x-mcpr-token", value: "secret")]
        )
        // Trying both and accepting either would authorise a request the reference rejects.
        #expect(ControlToken.isAuthorized(request, expected: "secret") == false)
    }

    @Test("x-mcpr-token is consulted only when no Bearer prefix is present")
    func headerUsedWithoutBearer() {
        let request = ControlAPIRequest(
            method: "POST", encodedPath: "/servers",
            headers: [(name: "x-mcpr-token", value: "secret")]
        )
        #expect(ControlToken.isAuthorized(request, expected: "secret"))
    }

    @Test("the content-type gate tests a prefix, so application/jsonp is accepted")
    func contentTypePrefix() {
        func request(_ value: String) -> ControlAPIRequest {
            ControlAPIRequest(
                method: "POST", encodedPath: "/servers",
                headers: [(name: "content-type", value: value)]
            )
        }
        #expect(ControlToken.hasJSONContentType(request("application/json")))
        #expect(ControlToken.hasJSONContentType(request("application/json; charset=utf-8")))
        // The reference tests `startsWith`, so this passes — tightening to equality diverges.
        #expect(ControlToken.hasJSONContentType(request("application/jsonp")))
        #expect(!ControlToken.hasJSONContentType(request("Application/JSON")))
        #expect(!ControlToken.hasJSONContentType(request(" application/json")))
    }

    // MARK: - B19: ECMAScript trim, not Foundation's

    @Test("token trimming follows ECMAScript, which differs from Foundation in both directions")
    func ecmaScriptTrim() {
        // JavaScript trims U+FEFF; Foundation's whitespacesAndNewlines does not.
        #expect(ControlToken.jsTrim("\u{FEFF}abc\u{FEFF}") == "abc")
        // JavaScript does NOT trim U+0085; Foundation's set does. A token file holding only this
        // is non-empty to the reference, so the two would disagree about minting a new token.
        #expect(ControlToken.jsTrim("\u{0085}") == "\u{0085}")
        #expect(ControlToken.jsTrim("  \n\tabc \r\n") == "abc")
    }

    // MARK: - S4: ECMAScript key ordering

    @Test("array-index keys serialise first in ascending numeric order")
    func ecmaKeyOrder() {
        let ordered = JSONMember.ecmaOrdered([
            JSONMember(key: "10", value: .number(1)),
            JSONMember(key: "b", value: .number(2)),
            JSONMember(key: "2", value: .number(3)),
            JSONMember(key: "a", value: .number(4))
        ])
        // JavaScript emits 2, 10, then b, a — insertion order only among the non-index keys.
        #expect(JSStringify.compact(.object(ordered)) == #"{"2":3,"10":1,"b":2,"a":4}"#)
    }

    // MARK: - B4, S5: code-unit key sorting

    @Test("env keys sort by UTF-16 code unit, where Swift's default disagrees")
    func envKeySortOrder() throws {
        let raw = try JSONParser.parse(#"""
        {"command":"/bin/echo","env":{"😀":"a","":"b"}}
        """#)
        guard case let .upstream(upstream) = ServerParser.parse(name: "s", raw: raw) else {
            Issue.record("the fixture config should parse"); return
        }
        var deps = try Fixtures.makeDeps()
        deps.upstreams = [(JSString("s"), upstream)]
        let produced = JSStringify.compact(Describe.row(upstream, deps))
        // The emoji's lead surrogate D83D sorts BEFORE E000 in UTF-16 code-unit order. Swift's
        // default `<` on String compares by scalar and puts it last.
        let emojiFirst = produced.range(of: #""envKeys":["😀""#) != nil
            || produced.contains("\u{1F600}\",\"\u{E000}")
        #expect(emojiFirst, "produced: \(produced)")
    }
}
