import Foundation

/// The two metadata documents the discovery cascade reads, and the two responses whose **member
/// order and membership** are decided by a schema rather than by the provider.
///
/// The second half is the one that is easy to get wrong and invisible when you do. The reference
/// parses the registration response and the token response through zod schemas that **reorder
/// members into the schema's own order and strip every member the schema does not name**, and it
/// is the parsed value — not the provider's bytes — that lands in the credential file on disk.
/// Measured against the running reference on 2026-08-19 with a fixture that answers in a
/// deliberately different order and carries an unknown member: the file came back in schema order
/// with the unknown member gone.
public enum OAuthSchemas {
    /// `OAuthClientInformationFullSchema`: the client-metadata shape, then the client-information
    /// shape, both `.strip()`.
    public static let clientInformationOrder = [
        "redirect_uris", "token_endpoint_auth_method", "grant_types", "response_types",
        "client_name", "client_uri", "logo_uri", "scope", "contacts", "tos_uri", "policy_uri",
        "jwks_uri", "jwks", "software_id", "software_version", "software_statement",
        "client_id", "client_secret", "client_id_issued_at", "client_secret_expires_at"
    ]

    /// `OAuthTokensSchema`, `.strip()`.
    public static let tokensOrder = [
        "access_token", "id_token", "token_type", "expires_in", "scope", "refresh_token"
    ]

    /// Reorder into `order` and drop everything else. A member that is absent stays absent — the
    /// schema's optional members are omitted rather than emitted as null, because `JSON.stringify`
    /// drops an undefined member and the credential file's bytes are the contract.
    public static func project(_ value: JSONValue, order: [String]) -> JSONValue {
        .object(order.compactMap { key in
            guard let member = value.member(key) else { return nil }
            return JSONMember(key: JSString(key), value: member)
        })
    }

    /// The registration response's two required members, checked before the projection so a
    /// provider that answers 201 with nothing usable fails here rather than writing a useless
    /// record.
    public static func clientInformation(_ value: JSONValue) -> JSONValue? {
        guard value.member("redirect_uris")?.asArray != nil else { return nil }
        guard let clientID = value.member("client_id")?.asString, !clientID.isEmpty else {
            return nil
        }
        return project(value, order: clientInformationOrder)
    }

    /// `access_token` and `token_type` are the schema's two required members.
    public static func tokens(_ value: JSONValue) -> JSONValue? {
        guard value.member("access_token")?.asString != nil else { return nil }
        guard value.member("token_type")?.asString != nil else { return nil }
        return project(value, order: tokensOrder)
    }
}

/// RFC 9728 protected-resource metadata, as much of it as the flow reads.
public struct ProtectedResourceMetadata: Sendable, Hashable {
    public let resource: String
    public let authorizationServers: [String]

    /// `resource` is the schema's one required member; a document without it is not this document.
    public init?(_ value: JSONValue) {
        guard let resource = value.member("resource")?.asString, !resource.isEmpty else {
            return nil
        }
        self.resource = resource.string
        authorizationServers = (value.member("authorization_servers")?.asArray ?? [])
            .compactMap { $0.asString?.string }
    }
}

/// RFC 8414 authorization-server metadata.
///
/// `issuer`, `authorization_endpoint`, `token_endpoint` and `response_types_supported` are the
/// schema's required members. A document missing one of them makes the reference's parse throw,
/// which aborts discovery rather than degrading it — so it does the same here.
public struct AuthorizationServerMetadata: Sendable, Hashable {
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let registrationEndpoint: String?
    public let responseTypesSupported: [String]
    public let codeChallengeMethodsSupported: [String]?
    public let tokenEndpointAuthMethodsSupported: [String]?

    public init?(_ value: JSONValue) {
        guard
            value.member("issuer")?.asString != nil,
            let authorization = value.member("authorization_endpoint")?.asString,
            let token = value.member("token_endpoint")?.asString,
            let responseTypes = value.member("response_types_supported")?.asArray
        else { return nil }
        authorizationEndpoint = authorization.string
        tokenEndpoint = token.string
        registrationEndpoint = value.member("registration_endpoint")?.asString?.string
        responseTypesSupported = responseTypes.compactMap { $0.asString?.string }
        codeChallengeMethodsSupported = value.member("code_challenge_methods_supported")?.asArray?
            .compactMap { $0.asString?.string }
        tokenEndpointAuthMethodsSupported = value
            .member("token_endpoint_auth_methods_supported")?.asArray?
            .compactMap { $0.asString?.string }
    }
}
