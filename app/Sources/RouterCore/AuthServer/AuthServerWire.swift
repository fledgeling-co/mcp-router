import Foundation

/// The bytes this server writes: the JSON and HTML envelopes, the refusals, the redirect, and the
/// form decoding every POST goes through.
///
/// Pure functions from values to bytes, with no behaviour of their own — the same split
/// ``MCPEndpointFraming`` makes from ``MCPEndpoint``, and for the same reason: these are what the
/// parity lane diffs, so keeping the set that must not drift readable in one screen is worth a
/// file of its own.
extension AuthServerRoutes {
    // MARK: - Wire helpers

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
        // Failable rather than lossy: a body that is not UTF-8 is not a form, and substituting
        // replacement characters would turn it into one whose fields silently differ from what was
        // sent.
        guard let decoded = String(bytes: request.body, encoding: .utf8) else { return [] }
        let raw = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
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
