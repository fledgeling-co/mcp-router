import Foundation
import Testing
@testable import RouterCore

/// The two routes, asserted against F3's **recorded fixtures** — the same bytes R4 diffs.
///
/// The fixtures are consumed, never altered.
@Suite("R5 auth — the two control routes")
struct AuthRoutesTests {
    /// Derived from `#filePath` rather than hardcoded: an absolute path would be worktree-specific
    /// and would break the moment this file merges anywhere else.
    private func fixture(_ name: String) throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let appRoot = thisFile
            .deletingLastPathComponent() // RouterCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // app
        let path = appRoot
            .appendingPathComponent("Sources/MCPRouterKit/Control/Fixtures/\(name).json")
        return try String(contentsOf: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: POST /servers/:name/auth

    @Test("B77 — a stdio server is refused 400 with the recorded string, and binds no port")
    func stdioIsRefusedBeforeAnyPortIsBound() async {
        let listener = FakeListener()
        let sink = RecordingCompletionSink()
        let (status, body) = await AuthRoutes.authStart(
            server: JSString("filesystem"),
            isStdio: true,
            sink: sink,
            begin: {
                Issue.record("begin() must not run for a stdio server")
                return LiveFlow(server: JSString("filesystem"), url: "")
            },
            awaitCompletion: {}
        )
        #expect(status == 400)
        #expect(JSStringify.compact(body)
            == #"{"error":"stdio servers do not authorize; their credentials are env vars"}"#)
        #expect(await listener.started == false, "no listener may bind on the stdio path")
    }

    @Test("B77 — success is 200 {server, authorizationUrl} matching the recorded fixture")
    func successMatchesFixture() async throws {
        let recorded = try fixture("auth-start")
        // The fixture's own server and URL, so this is the recorded byte shape rather than a
        // shape we invented that happens to serialize.
        let url = "http://127.0.0.1:8972/authorize?response_type=code&client_id=fixture-client"
            + "&code_challenge=Ouk77pSGXEpROYB-0ZKxoeYpZ6INgelJgpVL_gHeyPQ&code_challenge_method=S256"
            + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A8880%2Fcallback"
            + "&resource=http%3A%2F%2F127.0.0.1%3A8972%2Fmcp"
        let (status, body) = await AuthRoutes.authStart(
            server: JSString("fixture-oauth"),
            isStdio: false,
            sink: RecordingCompletionSink(),
            begin: { LiveFlow(server: JSString("fixture-oauth"), url: url) },
            awaitCompletion: {}
        )
        #expect(status == 200)
        #expect(JSStringify.compact(body) == recorded, "got: \(JSStringify.compact(body))")
    }

    @Test("B77 — a beginAuth failure is 502 carrying the thrown message")
    func beginFailureIs502() async {
        let (status, body) = await AuthRoutes.authStart(
            server: JSString("linear"),
            isStdio: false,
            sink: RecordingCompletionSink(),
            begin: { throw AuthFailure("listen EADDRINUSE 127.0.0.1:8880") },
            awaitCompletion: {}
        )
        #expect(status == 502)
        #expect(JSStringify.compact(body) == #"{"error":"listen EADDRINUSE 127.0.0.1:8880"}"#)
    }

    @Test("B79 + B95 — the side-effect runs only on success, through the injected sink")
    func completionSideEffectOnSuccess() async throws {
        let sink = RecordingCompletionSink()
        let (status, _) = await AuthRoutes.authStart(
            server: JSString("linear"), isStdio: false, sink: sink,
            begin: { LiveFlow(server: JSString("linear"), url: "https://x") },
            awaitCompletion: {}
        )
        #expect(status == 200)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(await sink.entries() == ["authorized:linear"])
    }

    @Test("B79 — a rejection warns and never changes the request outcome")
    func completionRejectionWarnsOnly() async throws {
        let sink = RecordingCompletionSink()
        let (status, body) = await AuthRoutes.authStart(
            server: JSString("linear"), isStdio: false, sink: sink,
            begin: { LiveFlow(server: JSString("linear"), url: "https://x") },
            awaitCompletion: { throw AuthFailure("authorization timed out") }
        )
        #expect(status == 200, "the 200 is already decided; a later failure cannot retract it")
        #expect(JSStringify.compact(body).contains("authorizationUrl"))
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(await sink.entries() == ["incomplete:linear:authorization timed out"])
    }

    @Test("B79 — a re-index rejection produces the SAME warn as a flow rejection")
    func reindexRejectionUsesTheSameWarn() async throws {
        // The reference chains .catch onto the whole .then, so a failure from indexOne is
        // indistinguishable from a failure of the flow. Two sources, one message.
        let sink = RecordingCompletionSink()
        _ = await AuthRoutes.authStart(
            server: JSString("linear"), isStdio: false, sink: sink,
            begin: { LiveFlow(server: JSString("linear"), url: "https://x") },
            awaitCompletion: { throw AuthFailure("index failed: spawn ENOENT") }
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(await sink.entries() == ["incomplete:linear:index failed: spawn ENOENT"])
    }

    // MARK: POST /servers/:name/approve

    private func manifest(with entry: String, server: String = "linear") -> (AuthTestFileSystem, String) {
        let fs = AuthTestFileSystem()
        let path = "/router/manifest.json"
        fs.memory.seed(
            "{\n  \"version\": 1,\n  \"servers\": {\n    \"\(server)\": \(entry)\n  }\n}",
            atPath: path
        )
        return (fs, path)
    }

    @Test("B78 — no pending change is 409 with the recorded message")
    func approveWithoutPendingIs409() async {
        let (fs, path) = manifest(with: #"{"tools":[],"digest":"d1","builtAt":"t1"}"#)
        let (status, body) = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs, nowMilliseconds: 0
        )
        #expect(status == 409)
        #expect(JSStringify.compact(body) == #"{"error":"no pending change for \"linear\""}"#)
    }

    @Test("B88 — a corrupt manifest degrades to 409 rather than throwing")
    func corruptManifestIs409() async {
        let fs = AuthTestFileSystem()
        fs.memory.seed("{not json", atPath: "/router/manifest.json")
        let (status, body) = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: "/router/manifest.json",
            fileSystem: fs, nowMilliseconds: 0
        )
        #expect(status == 409)
        #expect(JSStringify.compact(body) == #"{"error":"no pending change for \"linear\""}"#)
    }

    @Test("B78 — approving promotes the pending surface and answers {server, approved}")
    func approvePromotes() async {
        let (fs, path) = manifest(with: """
        {"tools":[{"name":"old"}],"digest":"d1","builtAt":"t1",\
        "pending":{"tools":[{"name":"a"},{"name":"b"}],"digest":"d2","seenAt":"s1"}}
        """)
        let (status, body) = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs,
            nowMilliseconds: 1_700_000_000_000
        )
        #expect(status == 200)
        #expect(
            JSStringify.compact(body) == #"{"server":"linear","approved":2}"#,
            "approved is pending.tools.length, counted before the write"
        )

        let written = fs.memory.contents(atPath: path) ?? ""
        #expect(written.contains(#""name": "a""#), "the pending tools were promoted")
        #expect(
            written.contains("pending") == false,
            "pending is REMOVED, not emitted as null — JSON.stringify drops undefined"
        )
        #expect(written.contains(#""digest": "d2""#))
        #expect(written.contains(#""builtAt": "2023-11-14T22:13:20.000Z""#))
    }

    @Test("B89 — the promoted entry keeps its ORIGINAL key order, not the literal's")
    func approvePreservesKeyOrder() async throws {
        // `builtAt` and `digest` come BEFORE `tools` here. JS spread keeps a key where it already
        // is and appends only genuinely-new keys, so the written order must be unchanged.
        let (fs, path) = manifest(with: """
        {"builtAt":"t1","digest":"d1","tools":[{"name":"old"}],\
        "pending":{"tools":[{"name":"a"}],"digest":"d2"}}
        """)
        _ = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs,
            nowMilliseconds: 1_700_000_000_000
        )
        let written = fs.memory.contents(atPath: path) ?? ""
        let builtAt = written.range(of: "builtAt")
        let digest = written.range(of: "digest")
        let tools = written.range(of: "\"tools\"")
        let builtAtAt = try #require(builtAt?.lowerBound)
        let digestAt = try #require(digest?.lowerBound)
        let toolsAt = try #require(tools?.lowerBound)
        #expect(builtAtAt < digestAt, "builtAt stays first")
        #expect(digestAt < toolsAt, "tools stays last, as it began")
    }

    @Test("B88 — the manifest is read FRESH from disk, not from a cache")
    func approveReadsFreshFromDisk() async {
        let (fs, path) = manifest(with: #"{"tools":[],"digest":"d1","builtAt":"t1"}"#)
        // First call: no pending, so 409.
        let first = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs, nowMilliseconds: 0
        )
        #expect(first.status == 409)

        // Someone else writes a pending change. A cached read would still answer 409.
        fs.memory.seed("""
        {
          "version": 1,
          "servers": {
            "linear": {"tools":[],"digest":"d1","builtAt":"t1",\
        "pending":{"tools":[{"name":"a"}],"digest":"d2"}}
          }
        }
        """, atPath: path)

        let second = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs,
            nowMilliseconds: 1_700_000_000_000
        )
        #expect(second.status == 200, "a cached manifest would have answered 409 again")
        #expect(JSStringify.compact(second.body) == #"{"server":"linear","approved":1}"#)
    }

    @Test("B94 — approving logs the reference's line verbatim")
    func approveLogsVerbatim() async {
        let (fs, path) = manifest(with: """
        {"tools":[],"digest":"d1","builtAt":"t1",\
        "pending":{"tools":[{"name":"a"},{"name":"b"},{"name":"c"}],"digest":"d2"}}
        """)
        let sink = RecordingSink()
        let log = RouterLog(sink: sink)
        _ = await AuthRoutes.approve(
            server: JSString("linear"), manifestPath: path, fileSystem: fs,
            nowMilliseconds: 0, log: log
        )
        #expect(
            sink.text.contains("approved \"linear\"'s new tool surface (3 tools)"),
            "got: \(sink.text)"
        )
    }
}
