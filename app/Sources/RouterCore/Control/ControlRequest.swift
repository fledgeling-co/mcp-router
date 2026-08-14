import Foundation

/// One control-API request, as the handler sees it.
///
/// Deliberately not `URLRequest` or a Foundation type: the spec's S5 makes the **encoded** pathname
/// and the **first** value of a repeated query parameter part of the contract, and both are things
/// Foundation is helpfully willing to normalise away.
public struct ControlRequest: Sendable {
    /// The method exactly as it arrived. Comparison is case-sensitive, so `post` is not `POST`
    /// (B16), and `nil` interpolates as the literal `undefined` in the 405 message (B25).
    public let method: String?

    /// The **percent-encoded** pathname, with no decoding, slash collapsing or dot-segment
    /// normalisation — `/servers%2Fx` must not be classified as a control path (B15).
    public let encodedPath: String

    /// Query items in arrival order, so `first(named:)` can honour the reference's first-wins rule
    /// rather than a dictionary's arbitrary one (B28, B32).
    public let query: [(name: String, value: String)]

    /// Headers as Node's `req.headers` presents them: every name lowercased, and repeated names
    /// joined with `", "` in arrival order.
    ///
    /// An ordered array rather than a dictionary, and not only to satisfy the wire lint.
    /// `Dictionary.first(where:)` iterates in a **non-deterministic** order, so a request carrying
    /// both `Authorization` and `authorization` decided B17's bearer shadowing by coin flip — the
    /// same bytes could authorize on one run and 401 on the next. Normalising once, at
    /// construction, is also where Node does it, so no handler can see an unnormalised name.
    public let headers: [(name: String, value: String)]

    /// The raw body bytes. Parsed by ``JSONParser`` at the point of use, never by a decoder — a
    /// validating decoder rejects shapes the reference stores (B42).
    public let body: Data?

    public init(
        method: String?,
        encodedPath: String,
        query: [(name: String, value: String)] = [],
        headers: [(name: String, value: String)] = [],
        body: Data? = nil
    ) {
        self.method = method
        self.encodedPath = encodedPath
        self.query = query
        self.headers = Self.normalized(headers)
        self.body = body
    }

    /// Mirrors what Node has already done before any handler runs: lowercase every name, and join
    /// repeats with `", "`. `set-cookie` is the one header Node keeps as an array; it is not a
    /// request header and nothing here reads it, so it gets no special case.
    static func normalized(
        _ raw: [(name: String, value: String)]
    ) -> [(name: String, value: String)] {
        var order: [String] = []
        // swift-wire-exempt: a local accumulator for the join, never stored and never serialised.
        var joined: [String: String] = [:]
        for pair in raw {
            let key = pair.name.lowercased()
            if let existing = joined[key] {
                joined[key] = existing + ", " + pair.value
            } else {
                joined[key] = pair.value
                order.append(key)
            }
        }
        return order.map { (name: $0, value: joined[$0] ?? "") }
    }

    /// The first value for `name`, matching `URLSearchParams.get`. A later duplicate never wins.
    public func first(named name: String) -> String? {
        query.first { $0.name == name }?.value
    }

    /// Header lookup. Names are already lowercased at construction, so this is an exact match on a
    /// deterministically ordered list rather than a scan whose winner depends on hash order.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.name == wanted }?.value
    }

    /// `POST`, `DELETE` and `PATCH` exactly — every other spelling, and an absent method, is not
    /// mutating and is therefore not gated (B16).
    public var isMutating: Bool {
        guard let method else { return false }
        return method == "POST" || method == "DELETE" || method == "PATCH"
    }

    /// `body ?? {}` — a `null`, array or primitive body all coerce to an empty object, and a body
    /// that does not parse does too. The reference casts rather than validates, so nothing here
    /// rejects a shape (B44).
    public var bodyObject: [JSONMember] {
        guard let body, let parsed = try? JSONParser.parse(body) else { return [] }
        return parsed.asObjectMembers ?? []
    }
}

/// What the handler produces.
///
/// `handled` travels **with** the response rather than beside it, because S8 makes the disposition
/// part of the contract: a branch that answers correctly while reporting "not handled" lets the
/// caller answer a second time, and a `Bool` returned separately is the thing a refactor drops.
public struct ControlResponse: Sendable {
    public enum Body: Sendable {
        case bytes([UInt8])
        /// `/usage/stream`. The socket belongs to R2, so this describes the stream rather than
        /// writing one (D4).
        case stream(ControlStream)
    }

    public let status: Int
    public let headers: [(name: String, value: String)]
    public let body: Body
    public let handled: Bool

    public init(status: Int, headers: [(name: String, value: String)], body: Body, handled: Bool) {
        self.status = status
        self.headers = headers
        self.body = body
        self.handled = handled
    }

    /// The path this item does not own. No header is read and nothing is sent — an unauthenticated
    /// `POST /mcp` has to reach the MCP endpoint, not a 401 (B14).
    public static let notHandled = ControlResponse(
        status: 0, headers: [], body: .bytes([]), handled: false
    )

    /// The reference's `json()` helper: the three headers, in its order, and **no**
    /// `Access-Control-Allow-Origin` anywhere — a page may be able to send a simple request, but it
    /// must never read one back.
    public static func json(_ status: Int, _ value: JSONValue) -> ControlResponse {
        let bytes = Array(JSStringify.compact(value).utf8)
        return ControlResponse(
            status: status,
            headers: [
                ("content-type", "application/json"),
                // Byte length, not character count — `Buffer.byteLength`, not `String.count` (B11).
                ("content-length", String(bytes.count)),
                ("cache-control", "no-store")
            ],
            body: .bytes(bytes),
            handled: true
        )
    }

    /// Every error body is exactly `{"error": <string>}` — one member, never an extra, never a
    /// null-valued one (B12).
    public static func error(_ status: Int, _ message: String) -> ControlResponse {
        json(status, .object([JSONMember(key: JSString("error"), value: .string(JSString(message)))]))
    }
}

/// The server-sent-event stream `/usage/stream` describes.
///
/// Byte-exact: a `: connected` comment on open, one `data:` frame per record, and a `: ping`
/// comment every 25 s so a proxy or a sleeping Mac cannot make an idle stream look disconnected
/// (B49).
public struct ControlStream: Sendable {
    public static let heartbeatMilliseconds = 25000.0

    public let openingFrame: [UInt8]
    public let heartbeatFrame: [UInt8]

    public init(
        openingFrame: [UInt8] = Array(": connected\n\n".utf8),
        heartbeatFrame: [UInt8] = Array(": ping\n\n".utf8)
    ) {
        self.openingFrame = openingFrame
        self.heartbeatFrame = heartbeatFrame
    }

    /// One record's frame. Compact JSON, matching `JSON.stringify(r)`.
    public static func frame(for record: JSONValue) -> [UInt8] {
        Array("data: \(JSStringify.compact(record))\n\n".utf8)
    }
}
