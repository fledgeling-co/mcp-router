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

    /// Rotation is normal — the router rewrites its token file whenever it is asked to. Making the
    /// user re-pair for that would be a bug. Retrying forever would be a worse one.
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

    /// A1's stand-in at unit level: every operation is reachable and round-trips. The real-router
    /// version of this lives in `scripts/acceptance/control-client.sh`.
    @Test("every operation on the protocol is callable and decodes")
    func everyOperationIsCallable() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        let server = try String(
            data: FixtureControlAPIClient.fixtureData("server-stdio"),
            encoding: .utf8
        ) ?? "{}"

        try stub.on("GET", "/servers", .json(200, fixtureText("servers")))
        stub.on("GET", "/servers/a", .json(200, server))
        try stub.on("GET", "/usage", .json(200, fixtureText("usage")))
        try stub.on("GET", "/usage/summary", .json(200, fixtureText("usage-summary")))
        try stub.on("GET", "/servers/a/changes", .json(200, fixtureText("changes-none")))
        try stub.on("GET", "/registry/search", .json(200, fixtureText("registry-search")))
        try stub.on("POST", "/servers", .json(201, fixtureText("added")))
        stub.on("DELETE", "/servers/a", .json(200, #"{"removed":"a"}"#))
        stub.on("POST", "/servers/a/reindex", .json(200, #"{"name":"a","tools":3}"#))
        stub.on("PATCH", "/servers/a", .json(200, server))
        stub.on("POST", "/servers/a/approve", .json(200, #"{"server":"a","approved":4}"#))
        stub.on(
            "POST",
            "/servers/a/auth",
            .json(200, #"{"server":"a","authorizationUrl":"https://e.invalid/x"}"#)
        )
        stub.on("DELETE", "/servers/a/auth", .json(200, #"{"server":"a","signedOut":true}"#))
        stub.on("POST", "/usage/reset", .json(200, #"{"ok":true,"since":"2026-08-14T00:00:00.000Z"}"#))

        let subject = client(stub)

        _ = try await subject.servers()
        _ = try await subject.server(named: "a")
        _ = try await subject.usage()
        _ = try await subject.usageSummary()
        _ = try await subject.heldChanges(for: "a")
        _ = try await subject.searchRegistry(query: "github", limit: 3)
        _ = try await subject.add(NewServer(name: "b", command: "/bin/echo"), force: true)
        _ = try await subject.remove("a", keepHistory: false)
        _ = try await subject.reindex("a")
        _ = try await subject.patch(server: "a", ServerPatch(warm: true))
        let approval = try await subject.approvePendingChange(server: "a")
        let auth = try await subject.beginAuthorization(for: "a")
        _ = try await subject.signOut("a")
        _ = try await subject.resetUsage()

        // The correction F1's protocol needed: approve answers with a count, not a server.
        #expect(approval.approved == 4)
        #expect(auth.authorizationURL == "https://e.invalid/x")
        #expect(stub.connections == 14, "one connection per operation; got \(stub.connections)")
    }

    @Test("a server name needing encoding still reaches the right route")
    func namesArePercentEncoded() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        try stub.on("GET", "/servers/a%2Fb", .json(200, fixtureText("server-stdio")))

        _ = try await client(stub).server(named: "a/b")
        let head = try #require(stub.requests.first)
        #expect(head.contains("/servers/a%2Fb"))
    }

    private func fixtureText(_ name: String) throws -> String {
        let data = try FixtureControlAPIClient.fixtureData(name)
        return try #require(String(data: data, encoding: .utf8))
    }
}
