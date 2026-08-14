import Foundation
import Testing
@testable import MCPRouterKit

/// The callable surface: that every endpoint the apps need can actually be *called*, with the
/// parameters the endpoint actually offers, and that a name needing encoding still lands on the
/// right route.
///
/// Split from `ControlClientTests` because it answers a different question. That suite asks what
/// the client does with an answer; this one asks whether the request could be made at all — which
/// is the failure A9 exists for, and the one that hides best, since a shape can be modelled
/// perfectly and still have no way to reach the router.
@Suite("Control client — the callable surface")
struct ControlSurfaceTests {
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

    /// `GET /usage` reads `limit`, `server` and `cwd` from the query string. A client that cannot
    /// send them can only ever fetch the last 200 rows unfiltered, so "show me this server's calls"
    /// is impossible through the one boundary the app is allowed to use. The out-of-family critic
    /// found this by diffing the endpoint's query parameters against the protocol.
    @Test("the usage filters reach the wire, and only the ones that were set")
    func usageFiltersReachTheWire() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/usage", .json(200, #"{"since":"2026-08-14T00:00:00.000Z","records":[]}"#))

        _ = try await client(stub).usage(limit: 5, server: "alpha", cwd: "/tmp/p")
        let filtered = try #require(stub.requests.first)
        #expect(filtered.contains("limit=5"))
        #expect(filtered.contains("server=alpha"))
        #expect(filtered.contains("cwd=/tmp/p") || filtered.contains("cwd=%2Ftmp%2Fp"))

        // An unset filter must be absent, not empty: the router reads the parameter's presence, so
        // `server=` asks for the calls of a server named "" rather than for no filter at all.
        _ = try await client(stub).usage()
        let unfiltered = try #require(stub.requests.last)
        #expect(!unfiltered.contains("server="), "an unset filter went out as empty: \(unfiltered)")
        #expect(!unfiltered.contains("cwd="))
        #expect(!unfiltered.contains("limit="))
    }

    /// Rotation is normal — the router rewrites its token file whenever it is asked to. Making the
    /// user re-pair for that would be a bug. Retrying forever would be a worse one.
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
