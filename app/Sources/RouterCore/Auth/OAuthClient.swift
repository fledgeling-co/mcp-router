import Foundation

/// The production ``AuthTransport``: a hand-written OAuth 2.1 public client.
///
/// **Why it is hand-written rather than the vendored SDK's.** `MCP swift-sdk 0.12.1` ships a whole
/// OAuth stack, and it cannot serve this route. Its `OAuthAuthorizationCodeFlow` emits the
/// authorization URL in a different member order and **always** includes `state`, while the
/// reference's TypeScript SDK omits `state` entirely for a provider that does not implement it —
/// and `extractCode(from:expectedRedirectURI:expectedState:)` hard-guards on `state`, so omitting
/// it to match the wire also rules the flow out. Neither configuration reaches agreement with the
/// reference, which is what `D-p1-a` recorded and what this type exists to answer.
///
/// The shape mirrors `authInternal` in the reference's SDK: probe, discover, register once, then
/// either exchange a code or begin a browser authorization. It is an actor because
/// `resourceMetadataURL` is written by `connect()` and read by `finishAuth(code:)`, which run on
/// different tasks — the callback lands on the listener, not on whoever began the flow.
public actor OAuthClient: AuthTransport {
    /// What one round of `authorize` decided.
    enum Outcome {
        case authorized
        case redirected
    }

    private let server: JSString
    private let serverURL: String
    private let requestHeaders: [JSStringPair]
    private let store: FileAuthStore
    private let http: any OAuthHTTPPerforming
    private let discovery: OAuthDiscovery
    private let clock: any RouterClock
    private let redirect: @Sendable (String) async -> Void
    private let makeVerifier: @Sendable () -> String
    /// The `resource_metadata` the 401 pointed at. Held across `connect()` and `finishAuth(code:)`
    /// exactly as the transport holds `_resourceMetadataUrl`, and the difference is visible: with
    /// it, protected-resource discovery is one request; without it, two.
    private var resourceMetadataURL: String?

    public init(
        server: JSString,
        serverURL: String,
        requestHeaders: [JSStringPair] = [],
        store: FileAuthStore,
        http: any OAuthHTTPPerforming = URLSessionOAuthHTTP(),
        clock: any RouterClock = SystemClock(),
        makeVerifier: @escaping @Sendable () -> String = { OAuthPKCE.verifier() },
        redirect: @escaping @Sendable (String) async -> Void
    ) {
        self.server = server
        self.serverURL = serverURL
        self.requestHeaders = requestHeaders
        self.store = store
        self.http = http
        discovery = OAuthDiscovery(http: http)
        self.clock = clock
        self.makeVerifier = makeVerifier
        self.redirect = redirect
    }

    /// `client.connect(transport)`.
    ///
    /// The reference sends the MCP `initialize` request, takes the 401, reads `resource_metadata`
    /// off the `WWW-Authenticate` challenge and runs the authorization from there — so the probe is
    /// part of the flow rather than a nicety, and a router that skipped it would ask the provider
    /// for a document the reference never requests.
    ///
    /// Expected to throw. The authorization URL is the real output and it leaves through
    /// ``redirect``; a provider that does **not** answer 401 produces no URL at all, which is the
    /// reference's behaviour too and which the route reports as a 502 once the 20-second URL race
    /// gives up.
    public func connect() async throws {
        let probe = try await probeMCPEndpoint()
        guard probe.status == 401 else { return }
        resourceMetadataURL = probe.header("WWW-Authenticate").flatMap {
            OAuthWire.wwwAuthenticateField("resource_metadata", in: $0)
        }
        let outcome = try await authorize(code: nil)
        switch outcome {
        case .redirected:
            throw AuthFailure("Unauthorized")
        case .authorized:
            // The reference retries the initialize once authorization reports success and takes the
            // second 401 as final. Same observable: no URL was produced, and the flow fails.
            throw AuthFailure("Server returned 401 after successful authentication")
        }
    }

    /// `transport.finishAuth(code)` — discovery again (the probe is not repeated), then the token
    /// exchange, then the credential file.
    public func finishAuth(code: String) async throws {
        guard try await authorize(code: code) == .authorized else {
            throw AuthFailure("Failed to authorize")
        }
    }

    /// `client.close()` then `transport.close()`. There is no socket and no subscription to drop:
    /// every request this client makes is a single round trip that has already completed.
    public func close() async {}

    // MARK: - The flow

    private func probeMCPEndpoint() async throws -> OAuthHTTPResponse {
        var headers = [
            (name: "content-type", value: "application/json"),
            (name: "accept", value: "application/json, text/event-stream")
        ]
        for header in requestHeaders {
            headers.append((name: header.key.string, value: header.value.string))
        }
        return try await http.perform(OAuthHTTPRequest(
            method: "POST",
            url: serverURL,
            headers: headers,
            body: Data(MCPInitializeProbe.body(protocolVersion: OAuthDiscovery.protocolVersion).utf8)
        ))
    }

    /// `authInternal`.
    func authorize(code: String?) async throws -> Outcome {
        let info = try await discovery.serverInfo(
            serverURL: serverURL, resourceMetadataURL: resourceMetadataURL
        )
        let resource = try selectResource(info)
        let client = try await clientInformation(info, exchangingCode: code != nil)

        if let code {
            let record = await store.read(server)
            guard let verifier = record.codeVerifier?.string, !verifier.isEmpty else {
                throw AuthFailure("no PKCE code verifier saved for \"\(server.string)\"")
            }
            let tokens = try await OAuthTokenRequest.exchange(
                OAuthTokenRequest.CodeExchange(
                    code: code, verifier: verifier, redirectURI: AuthPaths.redirectURI
                ),
                resource: resource, metadata: info.metadata, client: client, http: http
            )
            try await store.saveTokens(
                server, tokens: tokens, nowMilliseconds: clock.nowMilliseconds
            )
            return .authorized
        }

        if let refreshed = try await refreshIfPossible(info, resource: resource, client: client) {
            try await store.saveTokens(
                server, tokens: refreshed, nowMilliseconds: clock.nowMilliseconds
            )
            return .authorized
        }

        let verifier = makeVerifier()
        let url = try authorizationURL(info, resource: resource, client: client, verifier: verifier)
        try await store.merge(server, "codeVerifier", .string(JSString(verifier)))
        await redirect(url)
        return .redirected
    }

    /// `selectResourceURL`: the resource parameter exists only when the resource server published
    /// protected-resource metadata, and the value is **that document's** `resource` rather than the
    /// upstream URL — validated against it first, which is the check that refuses a document
    /// claiming authority over somewhere else.
    private func selectResource(_ info: OAuthDiscovery.ServerInfo) throws -> String? {
        guard let resource = info.resource?.resource else { return nil }
        let requested = serverURL.split(separator: "#", maxSplits: 1).first.map(String.init)
            ?? serverURL
        guard OAuthWire.resourceAllowed(requested: requested, configured: resource) else {
            throw AuthFailure(
                "Protected resource \(resource) does not match expected \(requested) (or origin)"
            )
        }
        return resource
    }

    /// The saved registration, or one dynamic registration that is then saved.
    private func clientInformation(
        _ info: OAuthDiscovery.ServerInfo, exchangingCode: Bool
    ) async throws -> JSONValue {
        if let saved = await store.read(server).member("clientInformation"), saved.isObject {
            return saved
        }
        guard !exchangingCode else {
            throw AuthFailure(
                "Existing OAuth client information is required when exchanging an authorization code"
            )
        }
        let registered = try await OAuthTokenRequest.register(
            metadata: info.metadata,
            body: OAuthClientMetadata.serialized(server: server, redirectURI: AuthPaths.redirectURI),
            http: http
        )
        try await store.merge(server, "clientInformation", registered)
        return registered
    }

    /// The refresh the reference attempts before it ever opens a browser. A stored refresh token
    /// that still works means **no authorization URL is produced at all**, which is the whole of
    /// the difference between re-authorizing an authorized server and authorizing a fresh one.
    private func refreshIfPossible(
        _ info: OAuthDiscovery.ServerInfo, resource: String?, client: JSONValue
    ) async throws -> JSONValue? {
        let record = await store.read(server)
        guard
            let refresh = record.member("tokens")?.member("refresh_token")?.asString,
            !refresh.isEmpty
        else { return nil }
        return try await OAuthTokenRequest.refresh(
            refreshToken: refresh.string, resource: resource, metadata: info.metadata,
            client: client, http: http
        )
    }

    /// `startAuthorization`. The member order is the reference's and is on the wire.
    private func authorizationURL(
        _ info: OAuthDiscovery.ServerInfo, resource: String?, client: JSONValue, verifier: String
    ) throws -> String {
        let metadata = info.metadata
        guard metadata.responseTypesSupported.contains("code") else {
            throw AuthFailure("Incompatible auth server: does not support response type code")
        }
        if let methods = metadata.codeChallengeMethodsSupported,
           !methods.contains(OAuthPKCE.challengeMethod)
        {
            throw AuthFailure(
                "Incompatible auth server: does not support code challenge method "
                    + OAuthPKCE.challengeMethod
            )
        }
        guard let clientID = client.member("client_id")?.asString else {
            throw AuthFailure("the authorization server returned no client_id")
        }
        var pairs: [(name: String, value: String)] = [
            (name: "response_type", value: "code"),
            (name: "client_id", value: clientID.string),
            (name: "code_challenge", value: OAuthPKCE.challenge(for: verifier)),
            (name: "code_challenge_method", value: OAuthPKCE.challengeMethod),
            (name: "redirect_uri", value: AuthPaths.redirectURI)
        ]
        if let resource { pairs.append((name: "resource", value: resource)) }
        return OAuthTokenRequest.url(metadata.authorizationEndpoint, adding: pairs)
    }
}

/// The MCP `initialize` request the probe carries.
///
/// The bytes of this body are **not** compared against the reference: it is the MCP handshake,
/// which the `mcp` parity rows own, and the fixture's authorization server refuses every request to
/// the resource endpoint whatever it says. What matters here is that the request is made at all,
/// because it is what produces the `WWW-Authenticate` challenge the cascade starts from.
enum MCPInitializeProbe {
    static func body(protocolVersion: String) -> String {
        JSStringify.compact(.object([
            JSONMember(key: "jsonrpc", value: .string("2.0")),
            JSONMember(key: "id", value: .number(0)),
            JSONMember(key: "method", value: .string("initialize")),
            JSONMember(key: "params", value: .object([
                JSONMember(key: "protocolVersion", value: .string(JSString(protocolVersion))),
                JSONMember(key: "capabilities", value: .object([])),
                JSONMember(key: "clientInfo", value: .object([
                    JSONMember(key: "name", value: .string("mcp-router")),
                    JSONMember(key: "version", value: .string("0.1.0"))
                ]))
            ]))
        ]))
    }
}
