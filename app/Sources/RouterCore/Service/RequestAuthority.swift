import Foundation

/// Which authorities a request may name, and the refusal for one that names another.
///
/// This used to live inside ``MCPEndpoint``, which the dispatch ladder reaches only after
/// `/health`, `/status` and the whole control block have already answered. Measured on
/// 2026-08-21 against both routers: `/health`, `/status`, `/servers` and `/usage` answered **200**
/// to `Host: evil.example` while `/mcp` answered 403. A page on a domain whose DNS re-resolves to
/// `127.0.0.1` is same-origin with the router by the browser's reckoning, so it could read the
/// usage history, the project list and the full command line of every configured server. Not a
/// credential leak — `envKeys` carries variable *names* — but a reconnaissance surface nobody
/// chose to publish.
///
/// So it lives here and ``guarding(_:allowedHosts:dispatch:)`` wraps the whole ladder. A route
/// added later inherits the check rather than opting into it, which is the property
/// `RequestAuthorityTests` arms with a throwaway route that has no authority code of its own.
public enum RequestAuthority {
    /// `cfg.host:port` first, then the three loopback spellings, de-duplicated —
    /// `src/router.ts:allowedHosts`.
    ///
    /// `[::1]` is in the set deliberately: a client that resolves `localhost` to IPv6 sends
    /// `Host: [::1]:<port>`, and leaving it out would refuse a real local client while blocking
    /// nothing a hostile page can do.
    public static func allowedHosts(host: String, port: Int) -> [String] {
        var seen: [String] = []
        for candidate in [
            "\(host):\(port)",
            "127.0.0.1:\(port)",
            "localhost:\(port)",
            "[::1]:\(port)"
        ] where !seen.contains(candidate) {
            seen.append(candidate)
        }
        return seen
    }

    /// The refusal for a request naming an authority this router does not answer for, or `nil`
    /// when it may proceed.
    ///
    /// `/mcp`'s body is the reference transport's own, byte for byte — status `403 Forbidden`,
    /// `content-type: application/json`, and the JSON-RPC envelope in the member order
    /// `jsonrpc, error, id`. That wording is pinned by the `mcp-endpoint` parity row, so it is
    /// reproduced rather than unified with the ordinary refusal beside it. Every other route gets
    /// the plain error envelope the 404 already uses.
    ///
    /// A request carrying **no** Host header is left alone, matching the reference: Node answers
    /// 400 to an HTTP/1.1 request without one, so the reference cannot produce a refusal here and
    /// inventing one would be a divergence rather than a fix.
    public static func refusal(
        for request: HTTPWireRequest, path: String, allowedHosts: [String]
    ) -> HTTPWireResponse? {
        guard let host = request.first("host"), !allowedHosts.contains(host) else { return nil }
        if path == MCPEndpoint.path {
            return MCPEndpoint.rpcError(403, code: -32000, message: "Invalid Host header: \(host)")
        }
        return .json(403, Data(JSStringify.compact(.object([
            JSONMember(
                key: JSString("error"),
                value: .string(JSString("Invalid Host header: \(host)"))
            )
        ])).utf8))
    }

    /// Run `dispatch` only for a request whose authority this router answers for.
    ///
    /// The seam exists so the guard is provably *ahead of* the ladder rather than inside it: the
    /// arming test hands this a throwaway route and asserts the route never runs, which is a claim
    /// no per-route assertion can make.
    public static func guarding(
        _ request: HTTPWireRequest,
        allowedHosts: [String],
        dispatch: @Sendable (HTTPWireRequest) async -> HTTPWireResponse
    ) async -> HTTPWireResponse {
        let (path, _) = request.pathAndQuery
        if let refusal = refusal(for: request, path: path, allowedHosts: allowedHosts) {
            return refusal
        }
        return await dispatch(request)
    }
}
