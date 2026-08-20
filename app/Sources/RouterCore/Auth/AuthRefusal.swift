/// Does a failure message mean the upstream refused our credentials?
///
/// One predicate rather than three, because the router had three and they disagreed
/// invisibly. `UpstreamPool.open` caught a transport-level refusal; the `import` verb
/// matched `not authorized|unauthorized|401` against the recorded index error; and the
/// indexer matched nothing at all.
///
/// Measured against a live upstream on 2026-08-20, which is where the first alternative
/// comes from verbatim: the server answered `[-32603] Internal error: Authentication
/// required`, a JSON-RPC error raised AFTER the transport connected and the MCP handshake
/// completed, containing none of "not authorized", "unauthorized" or "401". All three
/// detectors missed it, the upstream contributed zero tools for six hours, and every
/// surface reported it `idle`.
///
/// `invalid_grant` and `invalid_token` are RFC 6749 §5.2 and RFC 6750 §3.1 error codes and
/// arrive verbatim in the body a server rejects a refresh with.
///
/// 403 is deliberately absent. Forbidden means the credential was understood and the
/// account is not permitted; re-authorizing does not fix it, so offering `mcp-router auth`
/// would send the user round a loop that cannot succeed. That case wants its own reporting
/// and does not have it.
/// Named `AuthRefusal` rather than `AuthFailure` because `AuthFailure` is already the
/// OAuth error type thrown by `OAuthTokenRequest`. Two meanings for one name in one module
/// is how the three disagreeing detectors below got written in the first place.
public enum AuthRefusal {
    private static let needles = [
        "authentication required",
        "unauthorized",
        "not authorized",
        "invalid_grant",
        "invalid_token"
    ]

    public static func isRefusal(_ message: String) -> Bool {
        let lowered = message.lowercased()
        if needles.contains(where: { lowered.contains($0) }) { return true }
        // Word-bounded, so a port number or a byte count containing 401 is not a refusal.
        return lowered.split(whereSeparator: { !$0.isNumber }).contains("401")
    }
}
