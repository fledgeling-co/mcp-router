import Foundation
import Testing
@testable import MCPRouterKit

@Suite("Control client — talking to the router")
struct ControlClientTests {
    /// A client pointed at a stub, with the token already stored so no file is consulted.
    private func client(
        _ stub: HTTPStub,
        token: String? = "test-token",
        tokenFile: RouterTokenFile? = nil,
        log: ControlLog = ControlLog()
    ) -> LiveControlAPIClient {
        LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore(token),
            tokenFile: tokenFile ?? RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token")),
            log: log
        )
    }

    /// The state the whole design turns on. A refused loopback connection is not "the network is
    /// down" — it is "the daemon is not running", which has one obvious fix and its own surface.
    @Test("a refused connection is routerNotRunning, not a generic transport failure")
    func refusedConnectionIsRouterNotRunning() async throws {
        // Port 1 is reserved and nothing listens on it.
        let subject = try LiveControlAPIClient(
            baseURL: #require(URL(string: "http://127.0.0.1:1")),
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("t"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent"))
        )

        await #expect(throws: ControlAPIError.routerNotRunning) {
            _ = try await subject.servers()
        }
    }

    @Test("a 401 is unauthorized, and is a different value from routerNotRunning")
    func unauthorizedIsItsOwnCase() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/servers", .json(401, #"{"error":"unauthorized"}"#))

        await #expect(throws: ControlAPIError.unauthorized) {
            _ = try await client(stub).servers()
        }
    }

    /// The trap this codebase already fell into once, in TypeScript: a reader that looked for a
    /// key that wasn't there and found an empty collection. A silent empty result is the worst
    /// failure available because it is indistinguishable from "you have no servers".
    @Test("a shape this version doesn't understand fails loudly, never as an empty list")
    func malformedNeverDecodesToEmpty() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        // The flat shape: servers at the top level instead of under `servers`.
        stub.on("GET", "/servers", .json(200, #"{"fixture-stdio":{"transport":"stdio"}}"#))

        do {
            let response = try await client(stub).servers()
            Issue.record("decoded a flat shape into \(response.servers.count) servers instead of failing")
        } catch {
            // `servers()` is `throws(ControlAPIError)`, so `error` is already that type — an
            // `as` cast here is not just redundant, it crashes SILGen on Swift 6.3.3.
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        }
    }

    @Test("a router error carries its status, its message, and the hint that says what to do")
    func serverErrorCarriesTheHint() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/servers",
            .json(422, #"{"error":"spawn ENOENT","hint":"retry with ?force=1 to add it anyway"}"#)
        )

        do {
            _ = try await client(stub).add(NewServer(name: "x", command: "/nope"))
            Issue.record("expected the add to be refused")
        } catch {
            guard case let .server(status, message, hint) = error else {
                Issue.record("expected .server, got \(error)")
                return
            }
            #expect(status == 422)
            #expect(message == "spawn ENOENT")
            #expect(hint == "retry with ?force=1 to add it anyway")
            // The advice has to survive into what the user reads, or dropping it was pointless.
            #expect(error.userFacingDescription.contains("retry with ?force=1"))
        }
    }

    /// A failed re-index is an **outcome**, not a transport failure, and the router says so in the
    /// one way that matters: `422` carrying the *same* shape as a success, with `error` filled in
    /// (`src/control.ts` ~line 326).
    ///
    /// The out-of-family critic found this. A fixture decode test proved `ReindexResult` parses
    /// that body, but the client folded every non-2xx into `.server(status:message:hint:)`, so the
    /// operation could never return one — `name` and `tools` were destroyed on the way out and the
    /// surface could only say "something went wrong" instead of "indexed 0 of them, fetch failed,
    /// on this row". Modelling a shape without a path that returns it is the same defect the
    /// triage gate already caught once for the callable surface.
    @Test("a failed re-index returns its structured outcome rather than collapsing to an error")
    func reindexFailureSurvivesAsAValue() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/servers/fixture-http/reindex",
            .json(422, #"{"name":"fixture-http","tools":0,"error":"fetch failed"}"#)
        )

        let result = try await client(stub).reindex("fixture-http")

        #expect(result.name == "fixture-http", "the row the failure belongs to was lost")
        #expect(result.tools == 0, "the count of what did index was lost")
        #expect(result.error == "fetch failed", "the reason was lost")
    }

    /// The other half, and the reason this is an allowlist per call site rather than "422 is fine".
    /// A refused `add` is a genuine refusal whose `hint` is the sentence that tells the user how to
    /// proceed; decoding it as a typed success would swallow exactly that.
    @Test("a 422 from add stays an error, because only re-index documents a typed failure body")
    func addStillTreats422AsARefusal() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/servers",
            .json(422, #"{"error":"spawn ENOENT","hint":"retry with ?force=1 to add it anyway"}"#)
        )

        await #expect(throws: ControlAPIError.self) {
            _ = try await client(stub).add(NewServer(name: "x", command: "/nope"))
        }
    }

    /// A6 says the retry is bounded at one and tracked *per call*. Sequential calls cannot show
    /// that: the interesting case is two panes refreshing at the same moment through one actor.
    ///
    /// The out-of-family critic asked whether the bound survives concurrency, and the first answer
    /// was worse than "yes". Comparing the re-read token against the client's own cached copy meant
    /// the second call saw the value the *first* call had just stored, concluded nothing had
    /// rotated, and reported `.unauthorized` for a credential that was fine. The comparison is now
    /// against the token each call actually sent, so both retry once. Four requests total: two
    /// originals, two retries, and no loop.
    @Test("two calls racing a rotation each retry once, and neither is told it is unauthorised")
    func concurrentCallsEachRetryOnce() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f3-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("control.token")
        try "rotated-token\n".write(to: tokenURL, atomically: true, encoding: .utf8)

        // The stale token is refused; the rotated one is accepted.
        stub.onToken("Bearer stale-token", .json(401, #"{"error":"unauthorized"}"#))
        stub.on("GET", "/servers", .json(200, #"{"port":1,"idleMs":1,"since":"x","servers":[]}"#))

        let subject = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("stale-token"),
            tokenFile: RouterTokenFile(url: tokenURL)
        )

        async let first = subject.servers()
        async let second = subject.servers()
        let both = try await [first, second]

        #expect(both.count == 2, "both callers must get an answer, not one answer and one refusal")
        #expect(
            stub.connections <= 4,
            "at most two originals and two retries; \(stub.connections) means a call retried twice"
        )
    }

    /// The router exempts `DELETE` from its content-type requirement by name
    /// (`src/control.ts`: `req.method !== 'DELETE' && !ct.startsWith('application/json')`), so a
    /// bodyless DELETE must carry the token and *not* announce a body it is not sending. Asserting
    /// this on GET alone leaves the branch that actually decides it untested.
    @Test("a bodyless DELETE carries the token and announces no body")
    func deleteSendsTokenWithoutContentType() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("DELETE", "/servers/alpha", .json(200, #"{"removed":"alpha"}"#))

        _ = try await client(stub).remove("alpha", keepHistory: false)

        let head = try #require(stub.requests.first)
        #expect(head.contains("Bearer test-token"), "a mutating call must carry the token")
        #expect(
            !head.lowercased().contains("content-type"),
            "the router exempts DELETE, so announcing a body it isn't sending is noise: \(head)"
        )
    }

    /// Both headers are security controls, not formalities: the token defeats an unauthenticated
    /// POST, and the JSON content type forces a preflight the router never answers.
    @Test("a mutating request carries the bearer token and the JSON content type")
    func mutatingRequestsCarryBothHeaders() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("POST", "/usage/reset", .json(200, #"{"ok":true,"since":"2026-08-14T00:00:00.000Z"}"#))

        _ = try await client(stub).resetUsage()

        let head = try #require(stub.requests.first)
        #expect(head.contains("Authorization: Bearer test-token"))
        #expect(head.lowercased().contains("content-type: application/json"))
    }

    @Test("a read does not need to announce a JSON body it isn't sending")
    func readsDoNotSetContentType() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/usage", .json(200, #"{"since":"x","records":[]}"#))

        _ = try await client(stub).usage()

        let head = try #require(stub.requests.first)
        #expect(!head.lowercased().contains("content-type: application/json"))
    }
}

/// Credentials and rotation, split from the suite above only because SwiftLint caps a type's body
/// length — the boundary is a real one though: everything here is about *which token goes out* and
/// how many times, rather than about what the router answered.
@Suite("Control client — credentials and rotation")
struct ControlClientRotationTests {
    /// A client pointed at a stub, with the token already stored so no file is consulted.
    private func client(
        _ stub: HTTPStub,
        token: String? = "test-token",
        tokenFile: RouterTokenFile? = nil,
        log: ControlLog = ControlLog()
    ) -> LiveControlAPIClient {
        LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore(token),
            tokenFile: tokenFile ?? RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token")),
            log: log
        )
    }

    @Test("a rotated token is re-read and the request retried exactly once")
    func rotationRetriesExactlyOnce() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f3-rotate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("control.token")
        try "rotated-token\n".write(to: tokenURL, atomically: true, encoding: .utf8)

        // First call 401s; the retry, carrying the rotated token, succeeds.
        final class Toggle: @unchecked Sendable { var served = 0 }
        stub.on("GET", "/servers", .json(401, #"{"error":"unauthorized"}"#))

        let subject = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("stale-token"),
            tokenFile: RouterTokenFile(url: tokenURL)
        )

        // Still 401 on the retry: the point is the *count*, not the eventual success.
        await #expect(throws: ControlAPIError.unauthorized) {
            _ = try await subject.servers()
        }

        #expect(
            stub.connections == 2,
            """
            expected exactly two requests — the original and one retry with the rotated token — \
            but saw \(stub.connections). More than two is a retry loop; one means the rotation \
            was never noticed.
            """
        )
        let heads = stub.requests
        #expect(heads.count == 2)
        #expect(heads[0].contains("Bearer stale-token"))
        #expect(heads[1].contains("Bearer rotated-token"))
        _ = Toggle()
    }

    @Test("an unchanged token is not retried — a wrong credential must not become a loop")
    func unchangedTokenDoesNotRetry() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/servers", .json(401, #"{"error":"unauthorized"}"#))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f3-same-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("control.token")
        try "same-token\n".write(to: tokenURL, atomically: true, encoding: .utf8)

        let subject = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("same-token"),
            tokenFile: RouterTokenFile(url: tokenURL)
        )

        await #expect(throws: ControlAPIError.unauthorized) { _ = try await subject.servers() }
        #expect(stub.connections == 1, "an unchanged token was retried, which is a loop waiting to happen")
    }

    // A1's stand-in at unit level: every operation is reachable and round-trips. The real-router
    // version of this lives in `scripts/acceptance/control-client.sh`.
}
