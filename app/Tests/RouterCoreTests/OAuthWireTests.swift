import Foundation
import Testing
@testable import RouterCore

/// The pieces the OAuth client is built from, each asserted against the reference's own behaviour
/// rather than against a plausible-looking Swift default.
struct OAuthWireTests {
    /// Every vector here was taken from the running reference on 2026-08-19, not from memory: the
    /// authorization URL it emits carries `redirect_uri=http%3A%2F%2F127.0.0.1%3A8993%2Fcallback`
    /// and its token body carries `code_verifier=…%7E…`, which is what pins `:`, `/` and `~`.
    @Test("encode is URLSearchParams' serializer, not Foundation's")
    func encodeMatchesURLSearchParams() {
        #expect(OAuthWire.encode("http://127.0.0.1:8880/callback")
            == "http%3A%2F%2F127.0.0.1%3A8880%2Fcallback")
        // The four characters the urlencoded set leaves alone, and the one that looks like it
        // should be in that list and is not.
        #expect(OAuthWire.encode("*-._") == "*-._")
        #expect(OAuthWire.encode("~") == "%7E")
        // A space is `+`, never `%20`.
        #expect(OAuthWire.encode("a b") == "a+b")
        // Percent-encoding is upper-case hex and UTF-8 by byte.
        #expect(OAuthWire.encode("é") == "%C3%A9")
        #expect(OAuthWire.encode("").isEmpty)
    }

    @Test("query keeps the order it is given")
    func queryOrder() {
        let query = OAuthWire.query([
            (name: "response_type", value: "code"),
            (name: "client_id", value: "a b"),
            (name: "resource", value: "http://x/y")
        ])
        #expect(query == "response_type=code&client_id=a+b&resource=http%3A%2F%2Fx%2Fy")
    }

    @Test("pathname reports / for a bare origin, which is what decides path-aware discovery")
    func pathnameOfBareOrigin() {
        #expect(OAuthWire.pathname(of: "http://127.0.0.1:9911") == "/")
        #expect(OAuthWire.pathname(of: "http://127.0.0.1:9911/") == "/")
        #expect(OAuthWire.pathname(of: "http://127.0.0.1:9911/mcp") == "/mcp")
        #expect(OAuthWire.origin(of: "http://127.0.0.1:9911/mcp?x=1") == "http://127.0.0.1:9911")
        #expect(OAuthWire.origin(of: "https://example.com/mcp") == "https://example.com")
        #expect(OAuthWire.search(of: "http://x/y?a=1&b=2") == "?a=1&b=2")
        #expect(OAuthWire.search(of: "http://x/y").isEmpty)
    }

    @Test("resourceAllowed refuses a neighbour that merely shares a prefix")
    func resourceAllowedBoundaries() {
        #expect(OAuthWire.resourceAllowed(requested: "http://a/api/users", configured: "http://a/api"))
        #expect(OAuthWire.resourceAllowed(requested: "http://a/api", configured: "http://a/api"))
        // `/api123` is not a subpath of `/api`, and comparing raw prefixes would say it is.
        #expect(!OAuthWire.resourceAllowed(requested: "http://a/api123", configured: "http://a/api"))
        #expect(!OAuthWire.resourceAllowed(requested: "http://a/x", configured: "http://b/x"))
        #expect(!OAuthWire.resourceAllowed(requested: "http://a/", configured: "http://a/deep"))
    }

    @Test("the WWW-Authenticate challenge is read the way the reference reads it")
    func wwwAuthenticate() {
        let quoted = #"Bearer resource_metadata="http://x/.well-known/oauth-protected-resource""#
        #expect(OAuthWire.wwwAuthenticateField("resource_metadata", in: quoted)
            == "http://x/.well-known/oauth-protected-resource")
        #expect(OAuthWire.wwwAuthenticateField("resource_metadata", in: "Bearer resource_metadata=http://x")
            == "http://x")
        // Not a Bearer challenge, and a Bearer with no scheme after it: both are nothing.
        #expect(OAuthWire.wwwAuthenticateField("resource_metadata", in: #"Basic realm="x""#) == nil)
        #expect(OAuthWire.wwwAuthenticateField("resource_metadata", in: "Bearer") == nil)
        #expect(OAuthWire.wwwAuthenticateField("scope", in: quoted) == nil)
    }
}

struct OAuthPKCETests {
    @Test("the verifier is 43 characters of pkce-challenge's own mask")
    func verifierShape() {
        let verifier = OAuthPKCE.verifier()
        #expect(verifier.count == OAuthPKCE.verifierLength)
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { OAuthPKCE.alphabet.contains($0) })
        #expect(OAuthPKCE.alphabet.count == 66)
        // Two calls do not agree, or the "code verifier" is a constant.
        #expect(OAuthPKCE.verifier() != OAuthPKCE.verifier())
    }

    @Test("the challenge is unpadded base64url of SHA-256, against a pinned vector")
    func challengeVector() {
        // RFC 7636 Appendix B's own worked example.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(OAuthPKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let challenge = OAuthPKCE.challenge(for: OAuthPKCE.verifier())
        #expect(challenge.count == 43)
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }
}

struct OAuthSchemaTests {
    @Test("the token response is reordered into the schema's order and stripped")
    func tokensAreProjected() throws {
        let parsed = try JSONParser.parse("""
        {"scope":"s","refresh_token":"r","fixture_extra":"x","expires_in":3600,\
        "access_token":"a","token_type":"Bearer"}
        """)
        let tokens = try #require(OAuthSchemas.tokens(parsed))
        #expect(JSStringify.compact(tokens)
            == #"{"access_token":"a","token_type":"Bearer","expires_in":3600,"scope":"s","#
            + #""refresh_token":"r"}"#)
    }

    @Test("a token response missing a required member is not tokens at all")
    func tokensRequireTheirRequiredMembers() throws {
        #expect(try OAuthSchemas.tokens(JSONParser.parse(#"{"token_type":"Bearer"}"#)) == nil)
        #expect(try OAuthSchemas.tokens(JSONParser.parse(#"{"access_token":"a"}"#)) == nil)
        #expect(try OAuthSchemas.tokens(JSONParser.parse(#"{"access_token":1,"token_type":"B"}"#))
            == nil)
    }

    @Test("client information is reordered and stripped the same way")
    func clientInformationIsProjected() throws {
        let parsed = try JSONParser.parse("""
        {"token_endpoint_auth_method":"none","fixture_unknown":"x","client_id_issued_at":1,\
        "redirect_uris":["http://r"],"client_id":"c"}
        """)
        let information = try #require(OAuthSchemas.clientInformation(parsed))
        #expect(JSStringify.compact(information)
            == #"{"redirect_uris":["http://r"],"token_endpoint_auth_method":"none","#
            + #""client_id":"c","client_id_issued_at":1}"#)
        #expect(try OAuthSchemas.clientInformation(JSONParser.parse(#"{"client_id":"c"}"#)) == nil)
        #expect(try OAuthSchemas.clientInformation(JSONParser.parse(#"{"redirect_uris":[]}"#)) == nil)
    }

    @Test("authorization-server metadata without a required member is refused, not degraded")
    func metadataRequiresItsRequiredMembers() throws {
        let complete = "{\"issuer\":\"i\",\"authorization_endpoint\":\"a\","
            + "\"token_endpoint\":\"t\",\"response_types_supported\":[\"code\"]}"
        #expect(try AuthorizationServerMetadata(JSONParser.parse(complete)) != nil)
        for missing in ["issuer", "authorization_endpoint", "token_endpoint",
                        "response_types_supported"]
        {
            let text = complete.replacingOccurrences(of: "\"\(missing)\"", with: "\"other\"")
            #expect(
                try AuthorizationServerMetadata(JSONParser.parse(text)) == nil,
                "a document with no \(missing) must not parse"
            )
        }
    }
}

struct OAuthDiscoveryURLTests {
    @Test("a root authorization server offers two candidates, in the reference's order")
    func rootCandidates() {
        #expect(OAuthDiscovery.discoveryURLs("http://a:1") == [
            "http://a:1/.well-known/oauth-authorization-server",
            "http://a:1/.well-known/openid-configuration"
        ])
    }

    @Test("one with a path offers three, and the third appends rather than inserts")
    func pathCandidates() {
        #expect(OAuthDiscovery.discoveryURLs("http://a:1/tenant/") == [
            "http://a:1/.well-known/oauth-authorization-server/tenant",
            "http://a:1/.well-known/openid-configuration/tenant",
            "http://a:1/tenant/.well-known/openid-configuration"
        ])
    }

    /// The challenge's `resource_metadata` is used verbatim and the path-aware/root fallback pair
    /// does **not** run — one request rather than two, which is visible in the provider's own log
    /// and is what `parity-oauth.sh` compares.
    @Test("a challenge that names the metadata URL produces exactly one discovery request")
    func challengeSuppressesTheFallback() async throws {
        let http = ScriptedOAuthHTTP([
            ("named-metadata", OAuthClientFixture.protectedResource),
            (".well-known/oauth-authorization-server", OAuthClientFixture.authorizationServer)
        ])
        let discovery = OAuthDiscovery(http: http)
        _ = try await discovery.serverInfo(
            serverURL: "\(OAuthClientFixture.base)/mcp",
            resourceMetadataURL: "\(OAuthClientFixture.base)/named-metadata"
        )
        #expect(await http.trace == [
            "GET \(OAuthClientFixture.base)/named-metadata",
            "GET \(OAuthClientFixture.base)/.well-known/oauth-authorization-server"
        ])
    }

    @Test("with no challenge, path-aware discovery runs first and falls back to the root")
    func fallbackRunsWhenPathAwareIs404() async throws {
        let http = ScriptedOAuthHTTP([
            ("/.well-known/oauth-protected-resource/mcp", OAuthHTTPResponse(status: 404)),
            (".well-known/oauth-protected-resource", OAuthClientFixture.protectedResource),
            (".well-known/oauth-authorization-server", OAuthClientFixture.authorizationServer)
        ])
        let discovery = OAuthDiscovery(http: http)
        _ = try await discovery.serverInfo(
            serverURL: "\(OAuthClientFixture.base)/mcp", resourceMetadataURL: nil
        )
        #expect(await http.trace == [
            "GET \(OAuthClientFixture.base)/.well-known/oauth-protected-resource/mcp",
            "GET \(OAuthClientFixture.base)/.well-known/oauth-protected-resource",
            "GET \(OAuthClientFixture.base)/.well-known/oauth-authorization-server"
        ])
    }
}

/// One bit, set from inside a task and read from outside it.
actor FinishedFlag {
    private(set) var value = false
    func set() {
        value = true
    }
}

struct AuthorizationURLBoxTests {
    @Test("a URL delivered before anybody waits is still readable")
    func deliveredFirst() async throws {
        let box = AuthorizationURLBox()
        await box.deliver("http://one")
        #expect(try await box.value() == "http://one")
        // The first delivery wins; a second cannot rewrite an authorization already handed out.
        await box.deliver("http://two")
        #expect(try await box.value() == "http://one")
    }

    @Test("a waiter is resumed when the URL arrives")
    func waiterIsResumed() async throws {
        let box = AuthorizationURLBox()
        async let waited = box.value()
        try await Task.sleep(nanoseconds: 20_000_000)
        await box.deliver("http://late")
        #expect(try await waited == "http://late")
    }

    /// The regression this suite exists for. `AuthFlowCoordinator` races the box against a
    /// 20-second sleep inside a `withThrowingTaskGroup`; when the sleep wins, the group cancels the
    /// remaining child and then **awaits** it. The first version of the box could not be resumed by
    /// cancellation, so the group never returned — measured at 91 seconds against a 20-second
    /// budget, on every path where the provider produces no URL.
    ///
    /// It is written as "did the group finish inside a budget", not as "how long did it take",
    /// because against the defect it does not finish at all: an elapsed-time assertion after the
    /// group would never be reached, and the test would HANG rather than fail. Seen both ways —
    /// with the pre-fix box this reports a failed expectation in about three seconds, and with the
    /// fix it passes in about one tenth of one.
    @Test("a waiter that is cancelled is resumed rather than stranded")
    func cancellationResumesTheWaiter() async throws {
        let finished = FinishedFlag()
        let box = AuthorizationURLBox()
        let work = Task {
            _ = try? await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await box.value() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    throw AuthFailure("the server never produced an authorization URL")
                }
                guard let first = try await group.next() else { throw AuthFailure("empty") }
                group.cancelAll()
                return first
            }
            await finished.set()
        }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        work.cancel()
        #expect(
            await finished.value,
            "the group's 50ms budget expired and it had still not returned: the cancelled child"
        )
    }
}
