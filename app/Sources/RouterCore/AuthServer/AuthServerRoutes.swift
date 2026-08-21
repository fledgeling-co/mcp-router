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
    static let codeTTLMilliseconds: Double = 60_000
    static let maxRedirectURIs = 10

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
        guard AuthServerPaths.isAuthServerPath(path) else { return nil }

        if path == AuthServerPaths.wellKnownResource
            || path.hasPrefix("\(AuthServerPaths.wellKnownResource)/")
        {
            guard request.method == "GET" else { return Self.methodNotAllowed() }
            return Self.json(200, .object([
                member("resource", "\(issuer)/mcp"),
                JSONMember(key: JSString("authorization_servers"), value: .array([
                    .string(JSString(issuer))
                ])),
                JSONMember(key: JSString("scopes_supported"), value: .array([
                    .string(JSString("mcp"))
                ])),
                JSONMember(key: JSString("bearer_methods_supported"), value: .array([
                    .string(JSString("header"))
                ]))
            ]))
        }

        if path == AuthServerPaths.wellKnownServer
            || path.hasPrefix("\(AuthServerPaths.wellKnownServer)/")
        {
            guard request.method == "GET" else { return Self.methodNotAllowed() }
            return Self.json(200, .object([
                member("issuer", issuer),
                member("authorization_endpoint", "\(issuer)\(AuthServerPaths.authorize)"),
                member("token_endpoint", "\(issuer)\(AuthServerPaths.token)"),
                member("registration_endpoint", "\(issuer)\(AuthServerPaths.register)"),
                strings("response_types_supported", ["code"]),
                strings("grant_types_supported", ["authorization_code", "refresh_token"]),
                strings("code_challenge_methods_supported", ["S256"]),
                strings("token_endpoint_auth_methods_supported", ["none"]),
                strings("scopes_supported", ["mcp"])
            ]))
        }

        if path == AuthServerPaths.register {
            guard request.method == "POST" else { return Self.methodNotAllowed() }
            if originIsForeign(request) { return Self.forbiddenOrigin() }
            return registerResponse(request)
        }

        if path == AuthServerPaths.authorize {
            switch request.method {
            case "GET":
                return await authorizeGet(query: query, report: report)
            case "POST":
                if originIsForeign(request) { return Self.forbiddenOrigin() }
                return authorizePost(Self.form(request))
            default:
                return Self.methodNotAllowed()
            }
        }

        if path == AuthServerPaths.token {
            guard request.method == "POST" else { return Self.methodNotAllowed() }
            if originIsForeign(request) { return Self.forbiddenOrigin() }
            return await tokenResponse(Self.form(request))
        }

        return nil
    }

    private func originIsForeign(_ request: HTTPWireRequest) -> Bool {
        AuthServerAuthority.originRefused(request, host: config.host, port: config.port)
    }

    // MARK: - Registration

    private func registerResponse(_ request: HTTPWireRequest) -> HTTPWireResponse {
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

    // MARK: - Authorize

    struct AuthorizeParams {
        var clientID: String
        var redirectURI: String
        var challenge: String
        var state: String?
        var scope: String?
    }

    /// Everything `/authorize` must agree about before anything is minted.
    ///
    /// The distinction the caller then draws is the one that matters: an error about the
    /// `redirect_uri` itself may never be *redirected* to it, because that is a hop to a
    /// destination we have just decided not to trust.
    /// The refusal reason, as its own type rather than `Result<_, String>` — `String` is not an
    /// `Error`, and a bare enum here also names the four ways this can fail in one place.
    enum AuthorizeCheck {
        case ok(AuthorizeParams)
        case refused(String)
    }

    func validate(_ items: [(name: String, value: String)]) -> AuthorizeCheck {
        let get = { (key: String) -> String? in items.first { $0.name == key }?.value }
        let clientID = get("client_id") ?? ""
        let redirectURI = get("redirect_uri") ?? ""
        guard let blob = seal.unseal(clientID),
              case let .array(registered) = blob.member("u") ?? .null
        else {
            return .refused("client_id is not one this router issued")
        }
        guard !redirectURI.isEmpty else { return .refused("redirect_uri is required") }
        // Both, in this order: registered, and loopback. The registration is signed, so the second
        // check is not redundant paranoia — it is what holds if a registration ever predates the rule.
        guard registered.contains(where: { $0.asString?.string == redirectURI }) else {
            return .refused("redirect_uri is not one this client registered")
        }
        guard AuthServerAuthority.isLoopbackRedirect(redirectURI) else {
            return .refused("redirect_uri must be an http loopback address")
        }
        return .ok(AuthorizeParams(
            clientID: clientID,
            redirectURI: redirectURI,
            challenge: get("code_challenge") ?? "",
            state: get("state"),
            scope: get("scope")
        ))
    }

    /// The interstitial. This is the one surface with guaranteed human eyes on it.
    ///
    /// The "you can close this window" page belongs to the *client's* loopback listener, not to
    /// us, so this is the only page the router owns in this flow — which is why the upstream
    /// report renders here rather than anywhere further along.
    private func authorizeGet(
        query: String?, report: @Sendable () async -> [UpstreamReport]
    ) async -> HTTPWireResponse {
        let items = RouterService.queryItems(query)
        let get = { (key: String) -> String? in items.first { $0.name == key }?.value }
        let checked: AuthorizeParams
        switch validate(items) {
        case let .refused(reason): return Self.fatalPage(reason)
        case let .ok(params): checked = params
        }
        guard (get("response_type") ?? "") == "code" else {
            return Self.redirectError(
                checked.redirectURI, "unsupported_response_type",
                "only response_type=code is supported", checked.state
            )
        }
        // PKCE S256 is required rather than merely supported. `plain` is a challenge that is its
        // own verifier, which on a machine where any local process can read a redirect is no
        // protection at all.
        guard (get("code_challenge_method") ?? "") == "S256", !checked.challenge.isEmpty else {
            return Self.redirectError(
                checked.redirectURI, "invalid_request",
                "code_challenge with code_challenge_method=S256 is required", checked.state
            )
        }
        var hidden: [(String, String)] = [
            ("client_id", checked.clientID),
            ("redirect_uri", checked.redirectURI),
            ("code_challenge", checked.challenge)
        ]
        if let state = checked.state { hidden.append(("state", state)) }
        if let scope = checked.scope { hidden.append(("scope", scope)) }
        return Self.htmlPage(
            200, AuthServerPage.consent(rows: await report(), hidden: hidden)
        )
    }

    /// The Continue button. Everything is re-validated; nothing is trusted for having been on the
    /// page we drew.
    private func authorizePost(_ form: [(name: String, value: String)]) -> HTTPWireResponse {
        let checked: AuthorizeParams
        switch validate(form) {
        case let .refused(reason): return Self.fatalPage(reason)
        case let .ok(params): checked = params
        }
        guard !checked.challenge.isEmpty else {
            return Self.redirectError(
                checked.redirectURI, "invalid_request", "code_challenge is required", checked.state
            )
        }
        var nonce = ""
        for _ in 0 ..< 12 {
            nonce.append("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                .randomElement() ?? "a")
        }
        let code = seal.seal(.object([
            member("c", checked.clientID),
            member("r", checked.redirectURI),
            member("h", checked.challenge),
            // Floored, because `Date.now()` is an integral number of milliseconds and this value
            // is serialised into the code. A fractional expiry is a number the reference cannot
            // produce, and the two would diverge inside a blob nothing else can see.
            JSONMember(
                key: JSString("x"),
                value: .number((clock.nowMilliseconds + Self.codeTTLMilliseconds).rounded(.down))
            ),
            member("j", nonce)
        ]))
        var target = "\(checked.redirectURI)\(checked.redirectURI.contains("?") ? "&" : "?")"
        target += "code=\(Self.percentEncode(code))"
        if let state = checked.state { target += "&state=\(Self.percentEncode(state))" }
        return Self.redirect(target)
    }

    // MARK: - Token

    private func tokenResponse(_ form: [(name: String, value: String)]) async -> HTTPWireResponse {
        let get = { (key: String) -> String? in form.first { $0.name == key }?.value }
        switch get("grant_type") ?? "" {
        case "authorization_code":
            guard let blob = seal.unseal(get("code") ?? "") else {
                return Self.oauthError(400, "invalid_grant", "the authorization code is not valid")
            }
            guard case let .number(expiry) = blob.member("x") ?? .null,
                  clock.nowMilliseconds <= expiry
            else {
                return Self.oauthError(400, "invalid_grant", "the authorization code has expired")
            }
            let issuedTo = blob.member("c")?.asString?.string ?? ""
            if let claimed = get("client_id"), claimed != issuedTo {
                return Self.oauthError(400, "invalid_grant", "the code was issued to a different client")
            }
            let issuedFor = blob.member("r")?.asString?.string ?? ""
            if let redirect = get("redirect_uri"), redirect != issuedFor {
                return Self.oauthError(
                    400, "invalid_grant",
                    "redirect_uri does not match the one the code was issued for"
                )
            }
            guard let verifier = get("code_verifier"), !verifier.isEmpty else {
                return Self.oauthError(400, "invalid_request", "code_verifier is required")
            }
            guard OAuthPKCE.challenge(for: verifier) == (blob.member("h")?.asString?.string ?? "")
            else {
                return Self.oauthError(400, "invalid_grant", "the PKCE verifier does not match")
            }
            let nonce = blob.member("j")?.asString?.string ?? ""
            guard await usedCodes.burn(nonce, expiresAt: expiry, now: clock.nowMilliseconds) else {
                return Self.oauthError(
                    400, "invalid_grant", "the authorization code has already been used"
                )
            }
            return issue(scope: get("scope"))

        case "refresh_token":
            // Validated rather than waved through. An issuer that mints a fresh token for any
            // refresh request is an issuer whose tokens mean nothing, and validating costs nothing
            // once they are signed — the signature is the whole check.
            guard let blob = seal.unseal(get("refresh_token") ?? ""),
                  blob.member("t")?.asString?.string == "refresh"
            else {
                return Self.oauthError(
                    400, "invalid_grant", "the refresh token is not one this router issued"
                )
            }
            return issue(scope: get("scope") ?? blob.member("s")?.asString?.string)

        default:
            return Self.oauthError(
                400, "unsupported_grant_type",
                "only authorization_code and refresh_token are supported"
            )
        }
    }

    private func issue(scope: String?) -> HTTPWireResponse {
        let now = (clock.nowMilliseconds / 1000).rounded(.down)
        var access: [JSONMember] = [
            member("t", "access"),
            JSONMember(key: JSString("iat"), value: .number(now)),
            JSONMember(key: JSString("exp"), value: .number(now + Double(Self.accessTTLSeconds)))
        ]
        var refresh: [JSONMember] = [
            member("t", "refresh"),
            JSONMember(key: JSString("iat"), value: .number(now))
        ]
        if let scope {
            access.append(member("s", scope))
            refresh.append(member("s", scope))
        }
        var body: [JSONMember] = [
            member("access_token", seal.seal(.object(access))),
            member("token_type", "Bearer"),
            JSONMember(key: JSString("expires_in"), value: .number(Double(Self.accessTTLSeconds))),
            // Deliberately NOT rotated on refresh. A rotating refresh token has to be paired with
            // a grace window, because clients crash between rotating and storing; a stable one has
            // no such window to get wrong, and rotation buys nothing for a credential that confers
            // no privilege.
            member("refresh_token", seal.seal(.object(refresh)))
        ]
        // Echoed rather than rejected: a client asking for a scope this router does not model is
        // not an error worth failing an otherwise complete flow over.
        if let scope, !scope.isEmpty { body.append(member("scope", scope)) }
        return Self.json(200, .object(body))
    }

    // MARK: - Wire helpers

    private func member(_ key: String, _ value: String) -> JSONMember {
        JSONMember(key: JSString(key), value: .string(JSString(value)))
    }

    private func strings(_ key: String, _ values: [String]) -> JSONMember {
        JSONMember(key: JSString(key), value: .array(values.map { .string(JSString($0)) }))
    }

    static func json(_ status: Int, _ value: JSONValue) -> HTTPWireResponse {
        let bytes = Data(JSStringify.compact(value).utf8)
        return HTTPWireResponse(
            status: status,
            headers: [
                (name: "content-type", value: "application/json"),
                (name: "content-length", value: String(bytes.count)),
                (name: "cache-control", value: "no-store")
            ],
            body: .bytes(bytes)
        )
    }

    static func oauthError(_ status: Int, _ error: String, _ description: String) -> HTTPWireResponse {
        json(status, .object([
            JSONMember(key: JSString("error"), value: .string(JSString(error))),
            JSONMember(key: JSString("error_description"), value: .string(JSString(description)))
        ]))
    }

    static func methodNotAllowed() -> HTTPWireResponse {
        oauthError(405, "invalid_request", "method not allowed")
    }

    /// A browser POST from an origin that is not this router.
    ///
    /// 403 rather than a CORS answer, because the point is that the request must not execute at
    /// all — a form-encoded POST is a CORS *simple request* and runs whether or not its response
    /// can be read.
    static func forbiddenOrigin() -> HTTPWireResponse {
        oauthError(
            403, "invalid_request", "cross-origin requests are not accepted on this endpoint"
        )
    }

    static func htmlPage(_ status: Int, _ body: String) -> HTTPWireResponse {
        let bytes = Data(body.utf8)
        return HTTPWireResponse(
            status: status,
            headers: [
                (name: "content-type", value: "text/html; charset=utf-8"),
                (name: "content-length", value: String(bytes.count)),
                (name: "cache-control", value: "no-store"),
                // So the page cannot be silently framed by a site the user is visiting, in either
                // the legacy header or the modern directive. It is a consent screen, and a framed
                // consent screen is a clickjacking target.
                (name: "x-frame-options", value: "DENY"),
                (name: "content-security-policy", value: "frame-ancestors 'none'; form-action 'self'"),
                (name: "referrer-policy", value: "no-referrer")
            ],
            body: .bytes(bytes)
        )
    }

    static func fatalPage(_ reason: String) -> HTTPWireResponse {
        htmlPage(400, AuthServerPage.fatal(reason: reason))
    }

    /// A 302 framed the way the reference frames it: **chunked**, with an immediately-terminated
    /// body.
    ///
    /// Measured 2026-08-21, and it is a hang rather than a cosmetic divergence. `res.end()` with no
    /// data makes Node emit `Transfer-Encoding: chunked` and the terminating zero-length chunk. An
    /// empty `.bytes` body here emits neither that nor a `content-length`, so with
    /// `Connection: keep-alive` the client has no way to know the body ended: curl waited the full
    /// 8s budget and gave up with 0 bytes, and a browser following the redirect would stall the
    /// same way. The `location` header is readable long before that, which is exactly why an
    /// assertion that only reads the header passes while the response never completes.
    ///
    /// `MCPEndpoint`'s DELETE answer uses this same shape for the same reason.
    static func redirect(_ location: String) -> HTTPWireResponse {
        HTTPWireResponse(
            status: 302,
            reason: "Found",
            headers: [
                (name: "location", value: location),
                (name: "cache-control", value: "no-store")
            ],
            body: .chunks(AsyncStream { $0.finish() })
        )
    }

    /// `error=` back to a redirect_uri already proven registered and loopback.
    static func redirectError(
        _ redirectURI: String, _ error: String, _ description: String, _ state: String?
    ) -> HTTPWireResponse {
        var target = "\(redirectURI)\(redirectURI.contains("?") ? "&" : "?")"
        target += "error=\(percentEncode(error))"
        target += "&error_description=\(percentEncode(description))"
        if let state { target += "&state=\(percentEncode(state))" }
        return redirect(target)
    }

    /// `URLSearchParams`' encoding: everything outside the unreserved set is percent-encoded and a
    /// space becomes `+`.
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text)
            .replacingOccurrences(of: "%20", with: "+")
    }

    /// `application/x-www-form-urlencoded`, and JSON for the clients that send it anyway.
    ///
    /// RFC 6749 specifies the form encoding and every standard library sends it, but some MCP
    /// clients post JSON to `/token`. Accepting both costs a branch and turns a class of
    /// "Authenticate failed" into a working flow; the security posture does not depend on the
    /// encoding, because the Origin check has already run either way.
    static func form(_ request: HTTPWireRequest) -> [(name: String, value: String)] {
        let raw = String(decoding: request.body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        if raw.hasPrefix("{") {
            guard let parsed = try? JSONParser.parse(raw),
                  case let .object(members) = parsed
            else { return [] }
            return members.compactMap { entry in
                entry.value.asString.map { (name: entry.key.string, value: $0.string) }
            }
        }
        return RouterService.queryItems(raw)
    }
}

/// The used-code set, as an actor because two token requests can arrive at once and "has this code
/// been burned" is a read-modify-write.
public actor UsedCodeSet {
    private var entries: [String: Double] = [:]

    public init() {}

    /// Record this code as used, or report that it already was.
    ///
    /// Pruned by expiry on every call rather than capped by count: an expired code is refused by
    /// its own `x` field, so remembering it any longer buys nothing.
    public func burn(_ nonce: String, expiresAt: Double, now: Double) -> Bool {
        entries = entries.filter { $0.value >= now }
        guard entries[nonce] == nil else { return false }
        entries[nonce] = expiresAt
        return true
    }
}
