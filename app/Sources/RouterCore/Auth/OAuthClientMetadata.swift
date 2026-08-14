import Foundation

/// The dynamic-registration request body.
///
/// This is **bytes on the wire** — the authorization server receives it verbatim at registration —
/// so the member order is part of the contract, not a style choice (B87). Built as ordered
/// `[JSONMember]` for that reason; a Swift dictionary would reorder it and a `Codable` struct would
/// pin the order to a declaration that nothing stops a later edit from rearranging.
public enum OAuthClientMetadata {
    /// The reference's `clientMetadata` getter, member for member and in its order.
    ///
    /// `token_endpoint_auth_method: "none"` is deliberate and is the reference's own reasoning: the
    /// router is a **public client**. It runs on the user's own machine, so it has nowhere to keep a
    /// client secret the user could not already read.
    public static func value(server: JSString, redirectURI: String) -> JSONValue {
        .object([
            JSONMember(key: "client_name", value: .string(JSString("mcp-router (\(server.string))"))),
            JSONMember(key: "client_uri", value: .string("https://mcp-router.fledgeling.app")),
            JSONMember(key: "redirect_uris", value: .array([.string(JSString(redirectURI))])),
            JSONMember(key: "grant_types", value: .array([
                .string("authorization_code"),
                .string("refresh_token")
            ])),
            JSONMember(key: "response_types", value: .array([.string("code")])),
            JSONMember(key: "token_endpoint_auth_method", value: .string("none"))
        ])
    }

    public static func serialized(server: JSString, redirectURI: String) -> String {
        JSStringify.compact(value(server: server, redirectURI: redirectURI))
    }
}
