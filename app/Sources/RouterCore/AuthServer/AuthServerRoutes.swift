import Foundation

/// The authorization-server routes: metadata, dynamic client registration, `/authorize`, `/token`.
///
/// WHY THIS EXISTS. A client's "Authenticate" action against `http://127.0.0.1:8879/mcp` could not
/// succeed. The router served no metadata, so the client ran discovery, 404'd on every path, fell
/// back to `POST <origin>/register` and reported the router's catch-all 404. A better-worded 404
/// is not a fix: OAuth defines exactly two terminal states for a flow a user has started — a token
/// or an error — and there is no compliant way to say "this resource needs no authorization" that
/// a client treats as success.
///
/// WHAT THE TOKEN MEANS. It authenticates nobody. The router is loopback-bound, protects no
/// client-facing secret, and `/mcp` treats a bearer request and a bare one identically — so a
/// token issued here is worth exactly what unauthenticated loopback access is already worth. It
/// asserts one thing and it is true: a local user completed a loopback flow against this router.
///
/// THE DEVIATION, RECORDED. Advertising an authorization server while leaving `/mcp` unprotected
/// is knowingly outside the letter of the MCP spec, which says a server advertising an AS MUST
/// validate tokens. The alternative is protecting `/mcp`, which breaks every already-connected
/// client until it re-authenticates. That is the owner's decision, taken deliberately. The
/// invariant that pays for it: **`/mcp` never returns 401.**
public struct AuthServerRoutes: Sendable {
    /// An access token lives a year. It confers nothing, and a client that never has to re-run the
    /// browser leg is a client that never opens a tab on reconnect.
    static let accessTTLSeconds = 365 * 24 * 60 * 60
    /// An authorization code lives 60 seconds and is used within one.
    static let codeTTLMilliseconds: Double = 60000
    static let maxRedirectURIs = 10
    /// How long the consent ticket below stays good: long enough to read the upstream report,
    /// short enough that one found in a browser history is useless.
    static let consentTTLMilliseconds: Double = 10 * 60000

    let seal: AuthServerSeal
    let config: RouterConfig
    let clock: any RouterClock
    /// The used-code set. Codes are single-use, and that is the one thing here that cannot be
    /// stateless — so it is the one piece of memory, bounded by the 60-second lifetime rather than
    /// by a cap on entries. A restart forgets at most 60 seconds of codes, and the worst that
    /// costs is one retry of a flow that takes a second.
    let usedCodes: UsedCodeSet

    public init(
        seal: AuthServerSeal,
        config: RouterConfig,
        clock: any RouterClock,
        usedCodes: UsedCodeSet
    ) {
        self.seal = seal
        self.config = config
        self.clock = clock
        self.usedCodes = usedCodes
    }

    /// `http://127.0.0.1:<the port actually bound>`, never a constant: a user who moved the port
    /// would otherwise be handed endpoint URLs pointing at a router that is not there.
    var issuer: String { "http://127.0.0.1:\(config.port)" }

    // MARK: - Dispatch

    /// Which endpoint a path names. Resolved once so ``respond(to:path:query:report:)`` is a
    /// switch over five cases rather than a ladder of string tests.
    enum Route {
        case resourceMetadata
        case serverMetadata
        case register
        case authorize
        case token
    }

    static func route(for path: String) -> Route? {
        if path == AuthServerPaths.wellKnownResource
            || path.hasPrefix("\(AuthServerPaths.wellKnownResource)/") { return .resourceMetadata }
        if path == AuthServerPaths.wellKnownServer
            || path.hasPrefix("\(AuthServerPaths.wellKnownServer)/") { return .serverMetadata }
        if path == AuthServerPaths.register { return .register }
        if path == AuthServerPaths.authorize { return .authorize }
        if path == AuthServerPaths.token { return .token }
        return nil
    }

    /// Answer one authorization-server request, or `nil` when the path is not ours.
    ///
    /// Nothing here sets `Access-Control-Allow-Origin`, answers an `OPTIONS` preflight, sends
    /// `Access-Control-Allow-Private-Network`, or puts a token in a cookie. A page may be able to
    /// *send* some of these requests; it must never be able to read one back. Nor is a
    /// client-metadata `client_id` URL ever fetched — that would be an SSRF the router performs on
    /// request.
    public func respond(
        to request: HTTPWireRequest,
        path: String,
        query: String?,
        report: @Sendable () async -> [UpstreamReport]
    ) async -> HTTPWireResponse? {
        guard let route = Self.route(for: path) else { return nil }
        switch route {
        case .resourceMetadata:
            return get(request) { Self.json(200, resourceMetadata) }
        case .serverMetadata:
            return get(request) { Self.json(200, serverMetadata) }
        case .register:
            return postGuarded(request) { registerGuarded(request) }
        case .authorize:
            switch request.method {
            case "GET": return await authorizeGet(query: query, report: report)
            case "POST": return postGuarded(request) { authorizePost(Self.form(request)) }
            default: return Self.methodNotAllowed()
            }
        case .token:
            return await postGuardedAsync(request) { await tokenResponse(Self.form(request)) }
        }
    }

    /// A GET-only endpoint.
    private func get(
        _ request: HTTPWireRequest, _ body: () -> HTTPWireResponse
    ) -> HTTPWireResponse {
        guard request.method == "GET" else { return Self.methodNotAllowed() }
        return body()
    }

    /// A POST-only endpoint behind the Origin check, so no route can forget it.
    private func postGuarded(
        _ request: HTTPWireRequest, _ body: () -> HTTPWireResponse
    ) -> HTTPWireResponse {
        guard request.method == "POST" else { return Self.methodNotAllowed() }
        if originIsForeign(request) { return Self.forbiddenOrigin() }
        return body()
    }

    private func postGuardedAsync(
        _ request: HTTPWireRequest, _ body: () async -> HTTPWireResponse
    ) async -> HTTPWireResponse {
        guard request.method == "POST" else { return Self.methodNotAllowed() }
        if originIsForeign(request) { return Self.forbiddenOrigin() }
        return await body()
    }

    var resourceMetadata: JSONValue {
        .object([
            member("resource", "\(issuer)/mcp"),
            strings("authorization_servers", [issuer]),
            strings("scopes_supported", ["mcp"]),
            strings("bearer_methods_supported", ["header"])
        ])
    }

    var serverMetadata: JSONValue {
        .object([
            member("issuer", issuer),
            member("authorization_endpoint", "\(issuer)\(AuthServerPaths.authorize)"),
            member("token_endpoint", "\(issuer)\(AuthServerPaths.token)"),
            member("registration_endpoint", "\(issuer)\(AuthServerPaths.register)"),
            strings("response_types_supported", ["code"]),
            strings("grant_types_supported", ["authorization_code", "refresh_token"]),
            strings("code_challenge_methods_supported", ["S256"]),
            strings("token_endpoint_auth_methods_supported", ["none"]),
            strings("scopes_supported", ["mcp"])
        ])
    }

    /// The declared content type is required, not merely tolerated, and it is a second control
    /// rather than a formality. A `<form enctype="text/plain">` can be crafted so its body parses
    /// as valid JSON, and a form POST is a CORS *simple request*: no preflight stands in the way.
    /// Insisting on `application/json` puts the preflight back — and this router answers none — so
    /// the Origin check is no longer the only thing standing here. The control API applies the
    /// same rule for the same reason.
    private func registerGuarded(_ request: HTTPWireRequest) -> HTTPWireResponse {
        guard (request.first("content-type") ?? "").hasPrefix("application/json") else {
            return Self.oauthError(415, "invalid_request", "expected content-type: application/json")
        }
        return registerResponse(request)
    }

    private func originIsForeign(_ request: HTTPWireRequest) -> Bool {
        AuthServerAuthority.originRefused(request, host: config.host, port: config.port)
    }

    // MARK: - Registration

    func registerResponse(_ request: HTTPWireRequest) -> HTTPWireResponse {
        // A body that is not JSON is an empty registration, which fails the redirect_uris check
        // below with the message that names the real problem.
        let parsed = (try? JSONParser.parse(request.body)) ?? .null
        let uris: [JSONValue] = {
            if case let .array(items) = parsed.member("redirect_uris") ?? .null { return items }
            return []
        }()
        guard !uris.isEmpty, uris.count <= Self.maxRedirectURIs else {
            return Self.oauthError(
                400, "invalid_redirect_uri",
                "redirect_uris must name between 1 and \(Self.maxRedirectURIs) URIs"
            )
        }
        var accepted: [String] = []
        for uri in uris {
            guard let text = uri.asString?.string,
                  AuthServerAuthority.isLoopbackRedirect(text)
            else {
                return Self.oauthError(
                    400, "invalid_redirect_uri",
                    "every redirect_uri must be an http loopback address "
                        + "(127.0.0.1, localhost or [::1]); this router never redirects off the machine"
                )
            }
            accepted.append(text)
        }
        let name = parsed.member("client_name")?.asString.map { String($0.string.prefix(200)) }
        var blob: [JSONMember] = [
            JSONMember(key: JSString("u"), value: .array(accepted.map { .string(JSString($0)) }))
        ]
        if let name { blob.append(member("n", name)) }

        var body: [JSONMember] = [
            member("client_id", seal.seal(.object(blob))),
            JSONMember(
                key: JSString("client_id_issued_at"),
                value: .number((clock.nowMilliseconds / 1000).rounded(.down))
            ),
            JSONMember(key: JSString("redirect_uris"), value: .array(
                accepted.map { .string(JSString($0)) }
            )),
            strings("grant_types", ["authorization_code", "refresh_token"]),
            strings("response_types", ["code"]),
            member("token_endpoint_auth_method", "none")
        ]
        if let name { body.append(member("client_name", name)) }
        return Self.json(201, .object(body))
    }

    func member(_ key: String, _ value: String) -> JSONMember {
        JSONMember(key: JSString(key), value: .string(JSString(value)))
    }

    func strings(_ key: String, _ values: [String]) -> JSONMember {
        JSONMember(key: JSString(key), value: .array(values.map { .string(JSString($0)) }))
    }
}
