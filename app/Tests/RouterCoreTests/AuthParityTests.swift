import Foundation
import Testing
@testable import RouterCore

// MARK: - Doubles

/// Records the mode every write asked for, so B60 is asserted rather than trusted.
final class ModeRecordingFileSystem: FileModeWriting, @unchecked Sendable {
    let inner: MemoryFileSystem
    private let lock = NSLock()
    private var modes: [String: UInt16] = [:]

    init(_ inner: MemoryFileSystem) {
        self.inner = inner
    }

    func createDirectory(atPath path: String, mode: UInt16) throws {
        try inner.createDirectory(atPath: path)
        lock.lock(); modes[path] = mode; lock.unlock()
    }

    func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws {
        try inner.writeFile(data, atPath: path)
        lock.lock(); modes[path] = mode; lock.unlock()
    }

    func fileMode(atPath path: String) throws -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        guard let mode = modes[path] else {
            throw AuthFailure("no recorded mode for \(path)")
        }
        return mode
    }
}

/// A `FileSystem` + `FileModeWriting` pair the store can take.
final class AuthTestFileSystem: FileSystem, FileModeWriting, @unchecked Sendable {
    let memory: MemoryFileSystem
    let modes: ModeRecordingFileSystem

    init() {
        memory = MemoryFileSystem()
        modes = ModeRecordingFileSystem(memory)
    }

    func fileExists(atPath path: String) -> Bool {
        memory.fileExists(atPath: path)
    }

    func readFile(atPath path: String) throws -> Data {
        try memory.readFile(atPath: path)
    }

    func writeFile(_ data: Data, atPath path: String) throws {
        try memory.writeFile(data, atPath: path)
    }

    func appendFile(_ data: Data, atPath path: String) throws {
        try memory.appendFile(data, atPath: path)
    }

    func createDirectory(atPath path: String) throws {
        try memory.createDirectory(atPath: path)
    }

    func moveItem(atPath s: String, toPath d: String) throws {
        try memory.moveItem(atPath: s, toPath: d)
    }

    func copyItem(atPath s: String, toPath d: String) throws {
        try memory.copyItem(atPath: s, toPath: d)
    }

    func removeItem(atPath path: String) throws {
        try memory.removeItem(atPath: path)
    }

    func contentsOfDirectory(atPath p: String) throws -> [String] {
        try memory.contentsOfDirectory(atPath: p)
    }

    func attributes(atPath path: String) throws -> FileStamp {
        try memory.attributes(atPath: path)
    }

    func createDirectory(atPath path: String, mode: UInt16) throws {
        try modes.createDirectory(atPath: path, mode: mode)
    }

    func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws {
        try modes.writeFile(data, atPath: path, mode: mode)
    }

    func fileMode(atPath path: String) throws -> UInt16 {
        try modes.fileMode(atPath: path)
    }
}

actor FakeAuthTransport: AuthTransport {
    private(set) var closed = false
    private(set) var finishedWith: [String] = []
    private var finishAuthError: Error?

    func setFinishAuthError(_ error: Error?) {
        finishAuthError = error
    }

    func connect() async throws {
        throw AuthFailure("unauthorized")
    }

    func finishAuth(code: String) async throws {
        finishedWith.append(code)
        if let finishAuthError { throw finishAuthError }
    }

    func close() async {
        closed = true
    }
}

actor FakeListener: CallbackListening {
    private var handler: (@Sendable (String) async -> CallbackReply)?
    private(set) var started = false
    private(set) var stopped = false
    private var startError: Error?

    func setStartError(_ error: Error?) {
        startError = error
    }

    func start(port: Int, handler: @escaping @Sendable (String) async -> CallbackReply) async throws {
        if let startError { throw startError }
        self.handler = handler
        started = true
    }

    func stop() async {
        stopped = true
    }

    /// Drive a request as a browser would.
    func deliver(_ target: String) async -> CallbackReply {
        guard let handler else { return CallbackReply(status: 0, contentType: nil, body: "") }
        return await handler(target)
    }
}

actor RecordingCompletionSink: AuthRoutes.CompletionSink {
    private(set) var trace: [String] = []
    func onAuthorized(server: JSString) async {
        trace.append("authorized:\(server.string)")
    }

    func onIncomplete(server: JSString, reason: String) async {
        trace.append("incomplete:\(server.string):\(reason)")
    }

    func entries() -> [String] {
        trace
    }
}

// MARK: - The record and the store

@Suite("R5 auth — the record store")
struct AuthStoreTests {
    private func store() -> (FileAuthStore, AuthTestFileSystem) {
        let fs = AuthTestFileSystem()
        return (FileAuthStore(authDir: "/router/auth", fileSystem: fs), fs)
    }

    @Test("B60 — the directory is 0700 and the record 0600, both asserted from disk")
    func modes() async throws {
        let (store, fs) = store()
        try await store.merge(JSString("linear"), "codeVerifier", .string("v"))
        #expect(try fs.fileMode(atPath: "/router/auth") == 0o700)
        #expect(try fs.fileMode(atPath: "/router/auth/linear.json") == 0o600)
    }

    @Test("B60 — hasTokens is false without an access_token, in every shape")
    func hasTokensBranches() async {
        let (store, fs) = store()
        let name = JSString("linear")
        let path = "/router/auth/linear.json"

        #expect(await store.hasTokens(name) == false, "absent record")

        fs.memory.seed("{}", atPath: path)
        #expect(await store.hasTokens(name) == false, "no tokens member")

        fs.memory.seed(#"{"tokens":{}}"#, atPath: path)
        #expect(await store.hasTokens(name) == false, "tokens without access_token")

        fs.memory.seed(#"{"tokens":{"access_token":""}}"#, atPath: path)
        #expect(await store.hasTokens(name) == false, "!! coerces an empty token to false")

        fs.memory.seed(#"{"tokens":{"access_token":"abc"}}"#, atPath: path)
        #expect(await store.hasTokens(name) == true)
    }

    @Test("B61 + B100 — an unreadable record warns verbatim and reads unauthorized")
    func unreadableRecord() async {
        let fs = AuthTestFileSystem()
        let sink = RecordingSink()
        let log = RouterLog(sink: sink)
        let store = FileAuthStore(authDir: "/router/auth", fileSystem: fs, log: log)
        fs.memory.seed("{not json", atPath: "/router/auth/linear.json")

        #expect(await store.hasTokens(JSString("linear")) == false)
        let text = sink.text
        #expect(text.contains("auth record for \"linear\" unreadable ("), "got: \(text)")
        #expect(text.contains("); treating as unauthorized"), "got: \(text)")
    }

    @Test("B62 — clear reports whether a record existed")
    func clearReportsExistence() {
        let (store, fs) = store()
        #expect(store.clear(JSString("linear")) == false)
        fs.memory.seed("{}", atPath: "/router/auth/linear.json")
        #expect(store.clear(JSString("linear")) == true)
        #expect(store.clear(JSString("linear")) == false)
    }

    @Test("B91 — a merge keeps existing key positions and writes 2-space JSON")
    func mergePreservesKeyOrder() async throws {
        let (store, fs) = store()
        let name = JSString("linear")
        fs.memory.seed(
            "{\n  \"codeVerifier\": \"v1\",\n  \"authorizedAt\": \"t1\"\n}",
            atPath: "/router/auth/linear.json"
        )
        // Overwrite an EXISTING key. It must stay in position 1, not move to the end.
        try await store.merge(name, "codeVerifier", .string("v2"))
        let written = fs.memory.contents(atPath: "/router/auth/linear.json") ?? ""
        #expect(written == "{\n  \"codeVerifier\": \"v2\",\n  \"authorizedAt\": \"t1\"\n}", "got: \(written)")

        // A genuinely new key appends.
        try await store.merge(name, "tokens", .object([]))
        let second = fs.memory.contents(atPath: "/router/auth/linear.json") ?? ""
        #expect(second.hasSuffix("\"tokens\": {}\n}"), "got: \(second)")
    }

    @Test("B80 — names are keyed on code units, not canonical equivalence (key level only)")
    func codeUnitKeying() {
        // U+00E9 vs U+0065 U+0301. Swift String would call these equal; JSString must not.
        let precomposed = JSString("caf\u{00E9}")
        let decomposed = JSString("cafe\u{0301}")
        #expect("caf\u{00E9}" == "cafe\u{0301}", "Swift String equality IS canonical — the hazard")
        #expect(precomposed != decomposed, "JSString must compare by code unit")

        var map: [JSString: Int] = [:]
        map[precomposed] = 1
        map[decomposed] = 2
        #expect(map.count == 2, "two distinct keys")
        #expect(map[precomposed] == 1)
        #expect(map[decomposed] == 2)
        // Deliberately NOT asserted through the filesystem: APFS compares filenames
        // normalisation-insensitively, so a disk round-trip conflates these for BOTH routers.
    }
}

// MARK: - The pages and the callback

@Suite("R5 auth — the rendered pages and the callback")
struct CallbackTests {
    private func responder(
        server: String = "linear",
        log: RouterLog? = nil,
        exchange: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) -> CallbackResponder {
        CallbackResponder(server: JSString(server), log: log, exchange: exchange)
    }

    @Test("B65 + B99 — the success page is byte-exact")
    func successPage() async {
        let (reply, outcome) = await responder().respond(to: "/callback?code=abc")
        #expect(reply.status == 200)
        #expect(reply.contentType == "text/html")
        #expect(outcome == .succeeded)
        #expect(reply.body == "<!doctype html><meta charset=\"utf-8\"><title>linear is connected</title>"
            + "<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;"
            + "display:grid;place-items:center;height:100vh;margin:0;text-align:center}"
            + "h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>"
            +
            "<div><h1>linear is connected</h1><p>You can close this tab and return to mcp-router.</p></div>")
    }

    @Test("B65 — a provider error renders its value verbatim, at 400")
    func providerError() async {
        let (reply, outcome) = await responder().respond(to: "/callback?error=access_denied")
        #expect(reply.status == 400)
        #expect(reply.body.contains("<h1>Authorization failed</h1><p>access_denied</p>"))
        #expect(reply.body.contains("<title>Authorization failed</title>"), "B99: title AND h1")
        #expect(outcome == .failed(reason: "access_denied"))
    }

    @Test("B86 — the no-code page and its rejection are DIFFERENT strings")
    func noCodeUsesTwoStrings() async {
        let (reply, outcome) = await responder().respond(to: "/callback")
        #expect(reply.status == 400)
        #expect(reply.body.contains("<p>the provider returned no code</p>"), "the PAGE string")
        #expect(outcome == .failed(reason: "no authorization code returned"), "the REJECTION string")
    }

    @Test("nullish ?? — a present-but-empty error= yields an EMPTY detail, not the default")
    func emptyErrorIsNullishNotFalsy() async {
        let (reply, outcome) = await responder().respond(to: "/callback?error=")
        #expect(reply.status == 400)
        #expect(reply.body.contains("<p></p>"), "error ?? default is nullish; \"\" is not null")
        #expect(reply.body.contains("the provider returned no code") == false)
        #expect(outcome == .failed(reason: ""))
    }

    @Test("B65 — an exchange failure is 500 carrying the thrown message")
    func exchangeFailure() async {
        let responder = responder(exchange: { _ in
            throw AuthFailure("token endpoint returned 401 invalid_client")
        })
        let (reply, outcome) = await responder.respond(to: "/callback?code=abc")
        #expect(reply.status == 500)
        #expect(reply.body.contains("<p>token endpoint returned 401 invalid_client</p>"))
        #expect(outcome == .failed(reason: "token endpoint returned 401 invalid_client"))
    }

    @Test("B82 — any other path is 404, zero-length, no content-type, and NOT a termination")
    func strayRequestIsNotATermination() async {
        for target in ["/favicon.ico", "/", "/callbackx", "/callback/extra"] {
            let (reply, outcome) = await responder().respond(to: target)
            #expect(reply.status == 404, "\(target)")
            #expect(reply.contentType == nil, "\(target): no content-type")
            #expect(reply.body.isEmpty, "\(target): zero-length body")
            #expect(outcome == .ignored, "\(target): must not settle the flow")
        }
    }

    @Test("searchParams.get returns the FIRST value for a repeated parameter")
    func firstValueWins() async {
        let fake = FakeAuthTransport()
        let responder = responder(exchange: { code in try await fake.finishAuth(code: code) })
        _ = await responder.respond(to: "/callback?code=first&code=second")
        #expect(await fake.finishedWith == ["first"])
    }

    @Test("B94 + B66 — the success line is verbatim and no token reaches the log")
    func logsAreVerbatimAndSecretFree() async {
        let sink = RecordingSink()
        let log = RouterLog(sink: sink)
        let responder = responder(log: log, exchange: { _ in })
        _ = await responder.respond(to: "/callback?code=SUPER-SECRET-CODE")
        let text = sink.text
        #expect(text.contains("authorized upstream \"linear\""))
        #expect(text.contains("SUPER-SECRET-CODE") == false, "B66: no credential in the log")
    }
}

// MARK: - Client metadata, paths

@Suite("R5 auth — registration metadata and the fixed port")
struct AuthMetadataTests {
    @Test("B87 — the registration body is byte-exact and in the reference's key order")
    func clientMetadataBytes() {
        let serialized = OAuthClientMetadata.serialized(
            server: JSString("linear"), redirectURI: "http://127.0.0.1:8880/callback"
        )
        #expect(
            serialized ==
                #"{"client_name":"mcp-router (linear)","#
                + #""client_uri":"https://mcp-router.fledgeling.app","#
                + #""redirect_uris":["http://127.0.0.1:8880/callback"],"#
                + #""grant_types":["authorization_code","refresh_token"],"#
                + #""response_types":["code"],"token_endpoint_auth_method":"none"}"#,
            "got: \(serialized)"
        )
    }

    @Test("B90 — the port and redirect URI are resolved once and do not follow the environment")
    func portIsResolvedOnce() {
        let first = AuthPaths.redirectURI
        setenv("MCP_ROUTER_AUTH_PORT", "9999", 1)
        defer { unsetenv("MCP_ROUTER_AUTH_PORT") }
        #expect(
            AuthPaths.redirectURI == first,
            "a later mutation must not change the derived URI"
        )
        #expect(AuthPaths.redirectURI.hasSuffix("/callback"))
    }

    @Test("the record path is the server name under the auth directory")
    func recordPath() {
        #expect(AuthPaths.recordPath(authDir: "/r/auth", server: JSString("linear"))
            == "/r/auth/linear.json")
    }
}
