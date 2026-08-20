import Foundation
import Testing
@testable import RouterCore

/// A recording ``OAuthHTTPPerforming`` that answers from a script.
///
/// Every case below drives the real ``OAuthClient`` through this rather than a network, so what is
/// asserted is the bytes it *would* send. `scripts/acceptance/parity-oauth.sh` is what proves those
/// bytes agree with the running reference; this suite is what says which byte broke when they stop.
actor ScriptedOAuthHTTP: OAuthHTTPPerforming {
    struct Call: Sendable {
        let method: String
        let url: String
        let headers: [(name: String, value: String)]
        let body: String
    }

    private var script: [(match: String, response: OAuthHTTPResponse)]
    private(set) var calls: [Call] = []

    init(_ script: [(match: String, response: OAuthHTTPResponse)]) {
        self.script = script
    }

    func perform(_ request: OAuthHTTPRequest) async throws -> OAuthHTTPResponse {
        calls.append(Call(
            method: request.method, url: request.url, headers: request.headers,
            body: request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
        for entry in script where request.url.contains(entry.match) {
            return entry.response
        }
        return OAuthHTTPResponse(status: 404)
    }

    var trace: [String] { calls.map { "\($0.method) \($0.url)" } }
}

enum OAuthClientFixture {
    static let base = "http://127.0.0.1:9911"
    static let serverURL = "\(base)/mcp"
    static let prefix = "/as-unguessable"

    static func json(_ status: Int, _ text: String) -> OAuthHTTPResponse {
        OAuthHTTPResponse(
            status: status,
            headers: [(name: "Content-Type", value: "application/json")],
            body: Data(text.utf8)
        )
    }

    static let unauthorized = OAuthHTTPResponse(
        status: 401,
        headers: [(
            name: "WWW-Authenticate",
            value: #"Bearer resource_metadata="\#(base)/.well-known/oauth-protected-resource""#
        )],
        body: Data(#"{"error":"unauthorized"}"#.utf8)
    )

    static let protectedResource = json(200, """
    {"resource":"\(base)/mcp","authorization_servers":["\(base)"]}
    """)

    static let authorizationServer = json(200, """
    {"issuer":"\(base)","authorization_endpoint":"\(base)\(prefix)/authorize",\
    "token_endpoint":"\(base)\(prefix)/token","registration_endpoint":"\(base)\(prefix)/register",\
    "response_types_supported":["code"],"code_challenge_methods_supported":["S256"]}
    """)

    /// Deliberately in a different member order from the SDK's schema, and carrying a member the
    /// schema does not name — the same shape the parity fixture answers with.
    static let registration = json(201, """
    {"token_endpoint_auth_method":"none","fixture_unknown":"must not be saved",\
    "client_id_issued_at":1755648000,"redirect_uris":["\(AuthPaths.redirectURI)"],\
    "client_id":"fixture-client"}
    """)

    static let tokens = json(200, """
    {"scope":"fixture.read","refresh_token":"fixture-refresh-token",\
    "fixture_extra":"must not be saved","expires_in":3600,\
    "access_token":"fixture-access-token","token_type":"Bearer"}
    """)

    static func script() -> [(match: String, response: OAuthHTTPResponse)] {
        [
            (".well-known/oauth-protected-resource", protectedResource),
            (".well-known/oauth-authorization-server", authorizationServer),
            ("\(prefix)/register", registration),
            ("\(prefix)/token", tokens),
            ("/mcp", unauthorized)
        ]
    }

    /// A store over an in-memory filesystem, so a test can read back exactly the bytes that would
    /// have been written.
    static func store() -> (store: FileAuthStore, files: AuthTestFileSystem) {
        let files = AuthTestFileSystem()
        return (FileAuthStore(authDir: "/auth", fileSystem: files), files)
    }
}

/// A clock this suite owns. `ControlAuthSupport.FixedClock` is nested inside another type, and a
/// second top-level one keeps the two suites from having to agree about a helper.
struct PinnedClock: RouterClock {
    let nowMilliseconds: Double
}

struct OAuthClientTests {
    /// A pinned verifier so the challenge — and therefore the whole URL — is a fixed byte string.
    static let verifier = "abcdefghijklmnopqrstuvwxyz0123456789-._~ABCD"

    private func makeClient(
        http: ScriptedOAuthHTTP, store: FileAuthStore, box: AuthorizationURLBox
    ) -> OAuthClient {
        OAuthClient(
            server: JSString("fx"),
            serverURL: OAuthClientFixture.serverURL,
            store: store,
            http: http,
            clock: PinnedClock(nowMilliseconds: 1_755_648_000_000),
            makeVerifier: { Self.verifier },
            redirect: { await box.deliver($0) }
        )
    }

    @Test("the authorization URL is the reference's byte string, member for member")
    func authorizationURLBytes() async throws {
        let http = ScriptedOAuthHTTP(OAuthClientFixture.script())
        let (store, _) = OAuthClientFixture.store()
        let box = AuthorizationURLBox()
        let client = makeClient(http: http, store: store, box: box)

        await #expect(throws: AuthFailure.self) { try await client.connect() }
        let url = try await box.value()

        let challenge = OAuthPKCE.challenge(for: Self.verifier)
        let redirect = OAuthWire.encode(AuthPaths.redirectURI)
        let resource = OAuthWire.encode("\(OAuthClientFixture.base)/mcp")
        #expect(url == "\(OAuthClientFixture.base)\(OAuthClientFixture.prefix)/authorize"
            + "?response_type=code&client_id=fixture-client"
            + "&code_challenge=\(challenge)&code_challenge_method=S256"
            + "&redirect_uri=\(redirect)&resource=\(resource)")
        // `state` is absent, and that is the whole reason the vendored Swift SDK cannot serve this
        // route: it emits one unconditionally.
        #expect(!url.contains("state="))
    }

    @Test("the discovery cascade is the reference's, and the endpoints are never guessed")
    func discoveryCascade() async throws {
        let http = ScriptedOAuthHTTP(OAuthClientFixture.script())
        let (store, _) = OAuthClientFixture.store()
        let box = AuthorizationURLBox()
        let client = makeClient(http: http, store: store, box: box)

        await #expect(throws: AuthFailure.self) { try await client.connect() }

        let base = OAuthClientFixture.base
        #expect(await http.trace == [
            "POST \(base)/mcp",
            "GET \(base)/.well-known/oauth-protected-resource",
            "GET \(base)/.well-known/oauth-authorization-server",
            "POST \(base)\(OAuthClientFixture.prefix)/register"
        ])
    }

    @Test("the registration body is the reference's bytes, and its response is reordered on disk")
    func registrationBytes() async throws {
        let http = ScriptedOAuthHTTP(OAuthClientFixture.script())
        let (store, _) = OAuthClientFixture.store()
        let box = AuthorizationURLBox()
        let client = makeClient(http: http, store: store, box: box)

        await #expect(throws: AuthFailure.self) { try await client.connect() }

        let registration = try #require(
            await http.calls.first { $0.url.hasSuffix("/register") }
        )
        let expectedBody = #"{"client_name":"mcp-router (fx)","client_uri":"#
            + #""https://mcp-router.fledgeling.app","redirect_uris":["\#(AuthPaths.redirectURI)"],"#
            + #""grant_types":["authorization_code","refresh_token"],"response_types":["code"],"#
            + #""token_endpoint_auth_method":"none"}"#
        #expect(registration.body == expectedBody)

        let saved = try #require(await store.read(JSString("fx")).member("clientInformation"))
        let expectedSaved = #"{"redirect_uris":["\#(AuthPaths.redirectURI)"],"#
            + #""token_endpoint_auth_method":"none","client_id":"fixture-client","#
            + #""client_id_issued_at":1755648000}"#
        #expect(JSStringify.compact(saved) == expectedSaved)
    }

    @Test("the token exchange sends the reference's form, and the record is schema-shaped")
    func tokenExchangeAndRecord() async throws {
        let http = ScriptedOAuthHTTP(OAuthClientFixture.script())
        let (store, files) = OAuthClientFixture.store()
        let box = AuthorizationURLBox()
        let client = makeClient(http: http, store: store, box: box)

        await #expect(throws: AuthFailure.self) { try await client.connect() }
        try await client.finishAuth(code: "fixture-code-1")

        let token = try #require(await http.calls.last { $0.url.hasSuffix("/token") })
        #expect(token.body == "grant_type=authorization_code&code=fixture-code-1"
            + "&code_verifier=\(OAuthWire.encode(Self.verifier))"
            + "&redirect_uri=\(OAuthWire.encode(AuthPaths.redirectURI))"
            + "&resource=\(OAuthWire.encode("\(OAuthClientFixture.base)/mcp"))"
            + "&client_id=fixture-client")

        let written = try String(
            data: files.memory.readFile(atPath: "/auth/fx.json"), encoding: .utf8
        ) ?? ""
        let record = try #require(try AuthRecord(JSONParser.parse(written)))
        let tokens = try #require(record.member("tokens"))
        #expect(JSStringify.compact(tokens) == #"{"access_token":"fixture-access-token","#
            + #""token_type":"Bearer","expires_in":3600,"scope":"fixture.read","#
            + #""refresh_token":"fixture-refresh-token"}"#)
        // The members the provider sent that the schema does not name never reach disk.
        #expect(!written.contains("fixture_extra"))
        #expect(!written.contains("fixture_unknown"))
        // The record's own member order, asserted as an order rather than by eye.
        #expect(record.members.map(\.key.string)
            == ["clientInformation", "codeVerifier", "tokens", "authorizedAt"])
        #expect(record.authorizedAt?.string == "2025-08-20T00:00:00.000Z")
    }

    @Test("a second authorization refreshes instead of opening a browser")
    func refreshRatherThanRedirect() async throws {
        let http = ScriptedOAuthHTTP(OAuthClientFixture.script())
        let (store, _) = OAuthClientFixture.store()
        let box = AuthorizationURLBox()
        let client = makeClient(http: http, store: store, box: box)

        await #expect(throws: AuthFailure.self) { try await client.connect() }
        try await client.finishAuth(code: "fixture-code-1")

        // A fresh client over the same store is a fresh flow against an authorized server.
        let second = AuthorizationURLBox()
        let again = makeClient(http: http, store: store, box: second)
        await #expect(throws: AuthFailure.self) { try await again.connect() }

        let refresh = try #require(await http.calls.last { $0.body.hasPrefix("grant_type=refresh") })
        #expect(refresh.body == "grant_type=refresh_token&refresh_token=fixture-refresh-token"
            + "&resource=\(OAuthWire.encode("\(OAuthClientFixture.base)/mcp"))"
            + "&client_id=fixture-client")
        // No URL was produced, which is what makes the route answer 502 rather than 200.
        #expect(await http.calls.allSatisfy { !$0.url.contains("/authorize") })
    }
}
