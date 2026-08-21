import Foundation

/// The two legs that mint credentials: the consent page and the code, then the token.
///
/// Split from ``AuthServerRoutes`` because that file is the dispatch and the metadata — what the
/// server *advertises* — and this is what it *grants*. They change for different reasons: a new
/// endpoint is a change there, a change to what a code or a token means is a change here.
extension AuthServerRoutes {
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
    func authorizeGet(
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
        // Proof that this page was rendered, carried in a hidden field and required by the POST.
        //
        // Without it `POST /authorize` mints a code for anyone who can shape the form — the
        // interstitial is decorative, and an auto-submitting page skips it entirely. The Origin
        // check already refuses a cross-origin POST, so this is defence in depth rather than the
        // only control; it is here because "the human saw the screen" is the one thing this flow
        // claims and nothing was making it true.
        let consent = seal.seal(.object([
            member("t", "consent"),
            member("c", checked.clientID),
            member("r", checked.redirectURI),
            member("h", checked.challenge),
            JSONMember(
                key: JSString("x"),
                value: .number(
                    (clock.nowMilliseconds + Self.consentTTLMilliseconds).rounded(.down)
                )
            )
        ]))
        var hidden: [(String, String)] = [
            ("client_id", checked.clientID),
            ("redirect_uri", checked.redirectURI),
            ("code_challenge", checked.challenge),
            ("consent", consent)
        ]
        if let state = checked.state { hidden.append(("state", state)) }
        if let scope = checked.scope { hidden.append(("scope", scope)) }
        return await Self.htmlPage(
            200, AuthServerPage.consent(rows: report(), hidden: hidden)
        )
    }

    /// The Continue button. Everything is re-validated; nothing is trusted for having been on the
    /// page we drew.
    func authorizePost(_ form: [(name: String, value: String)]) -> HTTPWireResponse {
        let checked: AuthorizeParams
        switch validate(form) {
        case let .refused(reason): return Self.fatalPage(reason)
        case let .ok(params): checked = params
        }
        // The ticket the GET issued, re-checked against what this POST claims. A ticket for a
        // different client, redirect or challenge is not consent to this request.
        let ticketBlob = seal.unseal(form.first { $0.name == "consent" }?.value ?? "")
        let ticketOk: Bool = {
            guard let ticket = ticketBlob,
                  ticket.member("t")?.asString?.string == "consent",
                  case let .number(expiry) = ticket.member("x") ?? .null,
                  clock.nowMilliseconds <= expiry,
                  ticket.member("c")?.asString?.string == checked.clientID,
                  ticket.member("r")?.asString?.string == checked.redirectURI,
                  ticket.member("h")?.asString?.string == checked.challenge
            else { return false }
            return true
        }()
        guard ticketOk else {
            return Self.fatalPage(
                "this authorization did not come from the consent page, or it has expired. Start again."
            )
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
        // The `t` tag is load-bearing rather than decorative. Without it a CONSENT TICKET is
        // redeemable as a code: the two blobs share `c`, `r`, `h` and `x`, which is everything
        // `/token` checks, and the missing `j` degrades to burning the empty string. The
        // out-of-family review redeemed a ticket lifted from the consent page and got a working
        // access and refresh token — a ten-minute value standing in for a sixty-second one, with
        // the single-use check defeated because every such redemption burns the same empty nonce.
        let code = seal.seal(.object([
            member("t", "code"),
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

    func tokenResponse(_ form: [(name: String, value: String)]) async -> HTTPWireResponse {
        let get = { (key: String) -> String? in form.first { $0.name == key }?.value }
        switch get("grant_type") ?? "" {
        case "authorization_code":
            return await codeGrant(form)
        case "refresh_token":
            return refreshGrant(form)
        default:
            return Self.oauthError(
                400, "unsupported_grant_type",
                "only authorization_code and refresh_token are supported"
            )
        }
    }

    /// The authorization-code grant: the code must be ours, unexpired, unredeemed, and bound to
    /// the client, the redirect and the PKCE challenge it was issued for.
    private func codeGrant(_ form: [(name: String, value: String)]) async -> HTTPWireResponse {
        let get = { (key: String) -> String? in form.first { $0.name == key }?.value }
        // The tag AND a real nonce. A blob of another kind, or one carrying no `j`, is not a code
        // however well its other members line up.
        guard let blob = seal.unseal(get("code") ?? ""),
              blob.member("t")?.asString?.string == "code",
              let nonceValue = blob.member("j")?.asString?.string, !nonceValue.isEmpty
        else {
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
        guard await usedCodes.burn(nonceValue, expiresAt: expiry, now: clock.nowMilliseconds) else {
            return Self.oauthError(
                400, "invalid_grant", "the authorization code has already been used"
            )
        }
        return issue(scope: get("scope"))
    }

    /// The refresh grant. Validated rather than waved through: an issuer that mints a fresh token
    /// for any refresh request is an issuer whose tokens mean nothing, and validating costs
    /// nothing once they are signed — the signature is the whole check.
    private func refreshGrant(_ form: [(name: String, value: String)]) -> HTTPWireResponse {
        let get = { (key: String) -> String? in form.first { $0.name == key }?.value }
        guard let blob = seal.unseal(get("refresh_token") ?? ""),
              blob.member("t")?.asString?.string == "refresh"
        else {
            return Self.oauthError(
                400, "invalid_grant", "the refresh token is not one this router issued"
            )
        }
        return issue(scope: get("scope") ?? blob.member("s")?.asString?.string)
    }

    func issue(scope: String?) -> HTTPWireResponse {
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
}
