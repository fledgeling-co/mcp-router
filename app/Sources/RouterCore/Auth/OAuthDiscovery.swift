import Foundation

/// The discovery cascade, RFC 9728 then RFC 8414, in the reference's order and with its fallbacks.
///
/// It is written as its own type because the objection recorded against `control-auth-post-http`
/// was precisely about this: a fixture that answers every conventional path cannot tell a real
/// cascade from a client that hardcodes `/authorize`, so the *sequence of requests* has to be the
/// thing under test rather than only the URL that comes out. `scripts/acceptance/parity-oauth.sh`
/// compares that sequence against the running reference's, over an authorization server whose
/// endpoints sit at a path nothing could guess.
public struct OAuthDiscovery: Sendable {
    /// `LATEST_PROTOCOL_VERSION`, sent as `MCP-Protocol-Version` on every metadata request.
    ///
    /// Pinned to the value the installed reference SDK carries, and it is on the wire, so a
    /// version bump in `node_modules` moves the reference and reddens the parity lane. That is the
    /// intended failure: the lane says which value each side sent, and the fix is one line here.
    public static let protocolVersion = "2025-11-25"

    let http: any OAuthHTTPPerforming

    public init(http: any OAuthHTTPPerforming) {
        self.http = http
    }

    /// What one round of discovery yields: where the authorization server is, its metadata, and
    /// the protected-resource metadata if the resource server published any.
    public struct ServerInfo: Sendable {
        public let authorizationServerURL: String
        public let metadata: AuthorizationServerMetadata
        public let resource: ProtectedResourceMetadata?
    }

    /// `discoverOAuthServerInfo`. A resource server with no RFC 9728 metadata is not an error —
    /// the MCP server's own origin is then treated as the authorization server.
    public func serverInfo(
        serverURL: String, resourceMetadataURL: String?
    ) async throws -> ServerInfo {
        var resource: ProtectedResourceMetadata?
        var authorizationServerURL: String?
        if let found = try? await protectedResourceMetadata(
            serverURL: serverURL, metadataURL: resourceMetadataURL
        ) {
            resource = found
            authorizationServerURL = found.authorizationServers.first
        }
        let base = authorizationServerURL
            ?? OAuthWire.resolve("/", against: serverURL)
            ?? serverURL
        guard let metadata = try await authorizationServerMetadata(base) else {
            throw AuthFailure("the authorization server published no usable metadata")
        }
        return ServerInfo(authorizationServerURL: base, metadata: metadata, resource: resource)
    }

    /// `discoverOAuthProtectedResourceMetadata`, including `discoverMetadataWithFallback`: the
    /// path-aware well-known URL first, then the root one when that answers 4xx and the resource
    /// server's own path is not already the root.
    ///
    /// When the 401 carried a `resource_metadata` challenge parameter that URL is used verbatim and
    /// **no fallback runs**, which is the single-request shape the reference produces against a
    /// server that advertises one.
    func protectedResourceMetadata(
        serverURL: String, metadataURL: String?
    ) async throws -> ProtectedResourceMetadata {
        let response = try await metadataWithFallback(
            serverURL: serverURL, wellKnown: "oauth-protected-resource", metadataURL: metadataURL
        )
        guard let response, response.status != 404 else {
            throw AuthFailure(
                "Resource server does not implement OAuth 2.0 Protected Resource Metadata."
            )
        }
        guard (200 ..< 300).contains(response.status) else {
            throw AuthFailure(
                "HTTP \(response.status) trying to load well-known OAuth protected resource metadata."
            )
        }
        guard let json = response.json, let parsed = ProtectedResourceMetadata(json) else {
            throw AuthFailure("the protected resource metadata could not be read")
        }
        return parsed
    }

    private func metadataWithFallback(
        serverURL: String, wellKnown: String, metadataURL: String?
    ) async throws -> OAuthHTTPResponse? {
        let path = OAuthWire.pathname(of: serverURL)
        let target: String
        if let metadataURL {
            target = metadataURL
        } else {
            let stripped = path.hasSuffix("/") ? String(path.dropLast()) : path
            guard
                let resolved = OAuthWire.resolve("/.well-known/\(wellKnown)\(stripped)", against: serverURL)
            else { return nil }
            target = resolved + OAuthWire.search(of: serverURL)
        }
        let response = try? await get(target, accept: nil)
        guard metadataURL == nil else { return response }
        let shouldFallback = response == nil
            || ((400 ..< 500).contains(response?.status ?? 0) && path != "/")
        guard shouldFallback else { return response }
        guard let root = OAuthWire.resolve("/.well-known/\(wellKnown)", against: serverURL) else {
            return response
        }
        return try? await get(root, accept: nil)
    }

    /// `discoverAuthorizationServerMetadata`: each candidate URL in `buildDiscoveryUrls` order,
    /// skipping a 4xx and stopping at the first document that parses.
    func authorizationServerMetadata(_ base: String) async throws -> AuthorizationServerMetadata? {
        for candidate in Self.discoveryURLs(base) {
            guard let response = try? await get(candidate, accept: "application/json") else {
                continue
            }
            guard (200 ..< 300).contains(response.status) else {
                if (400 ..< 500).contains(response.status) { continue }
                throw AuthFailure(
                    "HTTP \(response.status) trying to load OAuth metadata from \(candidate)"
                )
            }
            guard let json = response.json, let parsed = AuthorizationServerMetadata(json) else {
                throw AuthFailure("the authorization server metadata could not be read")
            }
            return parsed
        }
        return nil
    }

    /// `buildDiscoveryUrls`. A root authorization server offers two candidates; one with a path
    /// offers three, and the third is the OIDC Discovery 1.0 spelling that appends rather than
    /// inserts.
    static func discoveryURLs(_ base: String) -> [String] {
        guard let origin = OAuthWire.origin(of: base) else { return [] }
        let path = OAuthWire.pathname(of: base)
        guard path != "/" else {
            return [
                "\(origin)/.well-known/oauth-authorization-server",
                "\(origin)/.well-known/openid-configuration"
            ]
        }
        let stripped = path.hasSuffix("/") ? String(path.dropLast()) : path
        return [
            "\(origin)/.well-known/oauth-authorization-server\(stripped)",
            "\(origin)/.well-known/openid-configuration\(stripped)",
            "\(origin)\(stripped)/.well-known/openid-configuration"
        ]
    }

    private func get(_ url: String, accept: String?) async throws -> OAuthHTTPResponse {
        var headers = [(name: "MCP-Protocol-Version", value: Self.protocolVersion)]
        if let accept { headers.append((name: "Accept", value: accept)) }
        return try await http.perform(OAuthHTTPRequest(method: "GET", url: url, headers: headers))
    }
}
