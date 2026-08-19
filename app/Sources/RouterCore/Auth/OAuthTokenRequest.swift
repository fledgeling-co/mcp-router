import Foundation

/// The two requests that carry a body: dynamic client registration, and the token endpoint.
///
/// Split from ``OAuthClient`` because they are the half where the **bytes** are the contract —
/// member order in the registration body, parameter order in the form, and the client
/// authentication method chosen from what the server said it supports. Nothing here holds state.
public enum OAuthTokenRequest {
    /// `registerClient`. The body is ``OAuthClientMetadata``'s, which is already ordered for this
    /// reason; the response is projected through the SDK's schema before it is saved.
    static func register(
        metadata: AuthorizationServerMetadata,
        body: String,
        http: any OAuthHTTPPerforming
    ) async throws -> JSONValue {
        guard let target = metadata.registrationEndpoint else {
            throw AuthFailure(
                "Incompatible auth server: does not support dynamic client registration"
            )
        }
        let response = try await http.perform(OAuthHTTPRequest(
            method: "POST",
            url: target,
            headers: [(name: "Content-Type", value: "application/json")],
            body: Data(body.utf8)
        ))
        guard (200 ..< 300).contains(response.status) else {
            throw failure(from: response)
        }
        guard let json = response.json, let information = OAuthSchemas.clientInformation(json) else {
            throw AuthFailure("the authorization server returned no usable client registration")
        }
        return information
    }

    /// `exchangeAuthorization`: `grant_type`, `code`, `code_verifier`, `redirect_uri`, then
    /// `resource`, then whatever the client authentication method appends. That order is the
    /// reference's `URLSearchParams` construction order and it is what the provider receives.
    /// The authorization code and the two values it has to be presented with. One exchange rather
    /// than three loose arguments, which is also what keeps this call inside the parameter cap.
    struct CodeExchange: Sendable {
        let code: String
        let verifier: String
        let redirectURI: String
    }

    static func exchange(
        _ exchange: CodeExchange,
        resource: String?,
        metadata: AuthorizationServerMetadata,
        client: JSONValue,
        http: any OAuthHTTPPerforming
    ) async throws -> JSONValue {
        var params: [(name: String, value: String)] = [
            (name: "grant_type", value: "authorization_code"),
            (name: "code", value: exchange.code),
            (name: "code_verifier", value: exchange.verifier),
            (name: "redirect_uri", value: exchange.redirectURI)
        ]
        return try await execute(
            params: &params,
            resource: resource,
            metadata: metadata,
            client: client,
            http: http
        )
    }

    /// `refreshAuthorization`. The reference preserves the original refresh token when the server
    /// does not return a new one — `{ refresh_token: refreshToken, ...tokens }` — so a member the
    /// response *does* carry wins, and the preserved one lands in the schema's own position.
    static func refresh(
        refreshToken: String,
        resource: String?,
        metadata: AuthorizationServerMetadata,
        client: JSONValue,
        http: any OAuthHTTPPerforming
    ) async throws -> JSONValue {
        var params: [(name: String, value: String)] = [
            (name: "grant_type", value: "refresh_token"),
            (name: "refresh_token", value: refreshToken)
        ]
        let tokens = try await execute(
            params: &params,
            resource: resource,
            metadata: metadata,
            client: client,
            http: http
        )
        guard tokens.member("refresh_token") == nil else { return tokens }
        var members = tokens.asObjectMembers ?? []
        members.append(JSONMember(key: "refresh_token", value: .string(JSString(refreshToken))))
        return OAuthSchemas.project(.object(members), order: OAuthSchemas.tokensOrder)
    }

    private static func execute(
        params: inout [(name: String, value: String)],
        resource: String?,
        metadata: AuthorizationServerMetadata,
        client: JSONValue,
        http: any OAuthHTTPPerforming
    ) async throws -> JSONValue {
        if let resource { params.append((name: "resource", value: resource)) }
        var headers = [
            (name: "Content-Type", value: "application/x-www-form-urlencoded"),
            (name: "Accept", value: "application/json")
        ]
        applyClientAuthentication(&params, &headers, metadata: metadata, client: client)
        let response = try await http.perform(OAuthHTTPRequest(
            method: "POST",
            url: metadata.tokenEndpoint,
            headers: headers,
            body: Data(OAuthWire.query(params).utf8)
        ))
        guard (200 ..< 300).contains(response.status) else {
            throw failure(from: response)
        }
        guard let json = response.json, let tokens = OAuthSchemas.tokens(json) else {
            throw AuthFailure("the token endpoint returned no usable tokens")
        }
        return tokens
    }

    /// `selectClientAuthMethod` then `applyClientAuthentication`.
    ///
    /// The registration response's own `token_endpoint_auth_method` wins when the server either
    /// listed it as supported or published no list at all. Absent that, a client with a secret
    /// defaults to Basic — RFC 8414 §2 — and a public client to `none`, which appends `client_id`
    /// to the form rather than authenticating at all.
    private static func applyClientAuthentication(
        _ params: inout [(name: String, value: String)],
        _ headers: inout [(name: String, value: String)],
        metadata: AuthorizationServerMetadata,
        client: JSONValue
    ) {
        let clientID = client.member("client_id")?.asString?.string ?? ""
        let secret = client.member("client_secret")?.asString?.string
        switch method(metadata: metadata, client: client, hasSecret: secret != nil) {
        case "client_secret_basic":
            guard let secret else { break }
            let credentials = Data("\(clientID):\(secret)".utf8).base64EncodedString()
            headers.append((name: "Authorization", value: "Basic \(credentials)"))
        case "client_secret_post":
            params.append((name: "client_id", value: clientID))
            if let secret { params.append((name: "client_secret", value: secret)) }
        default:
            params.append((name: "client_id", value: clientID))
        }
    }

    private static func method(
        metadata: AuthorizationServerMetadata, client: JSONValue, hasSecret: Bool
    ) -> String {
        let known = ["client_secret_basic", "client_secret_post", "none"]
        let supported = metadata.tokenEndpointAuthMethodsSupported ?? []
        if let declared = client.member("token_endpoint_auth_method")?.asString?.string,
           known.contains(declared),
           supported.isEmpty || supported.contains(declared)
        {
            return declared
        }
        if supported.isEmpty { return hasSecret ? "client_secret_basic" : "none" }
        if hasSecret, supported.contains("client_secret_basic") { return "client_secret_basic" }
        if hasSecret, supported.contains("client_secret_post") { return "client_secret_post" }
        return "none"
    }

    /// `parseErrorResponse`: an OAuth error response carries `error_description` as the message,
    /// and the reference falls back to the **empty string** rather than to `error`. That empty
    /// message is what a failed callback renders, so it is reproduced rather than improved.
    private static func failure(from response: OAuthHTTPResponse) -> AuthFailure {
        guard
            let json = response.json,
            json.member("error")?.asString != nil
        else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            return AuthFailure(
                "HTTP \(response.status): Invalid OAuth error response. Raw body: \(body)"
            )
        }
        return AuthFailure(json.member("error_description")?.asString?.string ?? "")
    }

    /// `new URL(endpoint)` then `searchParams.set(…)` for each pair, in order.
    ///
    /// Parameters the endpoint already carries are kept ahead of the added ones, which is what
    /// `set` does for a name the URL does not already have. An authorization endpoint that itself
    /// carried `response_type` would order differently from the reference; no provider does, and
    /// this is recorded rather than silently assumed away.
    static func url(_ endpoint: String, adding pairs: [(name: String, value: String)]) -> String {
        var base = endpoint
        var existing = ""
        if let mark = endpoint.firstIndex(of: "?") {
            base = String(endpoint[endpoint.startIndex ..< mark])
            existing = String(endpoint[endpoint.index(after: mark)...])
        }
        let added = OAuthWire.query(pairs)
        let query = existing.isEmpty ? added : "\(existing)&\(added)"
        return "\(base)?\(query)"
    }
}
