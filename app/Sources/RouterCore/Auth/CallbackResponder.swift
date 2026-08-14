import Foundation

/// What the callback listener sends back for one request.
public struct CallbackReply: Sendable, Equatable {
    public let status: Int
    /// `nil` for the 404, which the reference sends with **no** `content-type` and a zero-length
    /// body (B82).
    public let contentType: String?
    public let body: String

    public init(status: Int, contentType: String?, body: String) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }
}

/// How a request affected the flow.
///
/// `ignored` is the case that earns this type: a request to any path other than `/callback` answers
/// 404 and is **not** a termination — the flow stays unsettled, the timer stays armed and the
/// listener stays bound (B82). Collapsing it into a failure would make a stray `GET /favicon.ico`
/// end the user's authorization.
public enum CallbackOutcome: Sendable, Equatable {
    case succeeded
    case failed(reason: String)
    case ignored
}

/// The callback's request→response semantics, with **no** socket in sight.
///
/// Separated from the listener so all five terminations and the non-termination are exercised by
/// tests that bind no port. The reference's own handler mixes the two; keeping them apart here is
/// divergence in structure only — the bytes and the ordering are identical, and the ordering is
/// asserted.
public struct CallbackResponder: Sendable {
    private let server: JSString
    private let exchange: @Sendable (String) async throws -> Void
    private let log: RouterLog?

    public init(
        server: JSString,
        log: RouterLog? = nil,
        exchange: @escaping @Sendable (String) async throws -> Void
    ) {
        self.server = server
        self.exchange = exchange
        self.log = log
    }

    /// `requestTarget` is the raw request target, e.g. `/callback?code=abc&state=xyz`.
    ///
    /// The reference parses it with `new URL(req.url ?? '/', AUTH_REDIRECT_URI)` and reads
    /// `searchParams.get`, which returns the **first** value for a repeated parameter — matched
    /// here by `first(where:)`.
    public func respond(to requestTarget: String) async -> (CallbackReply, CallbackOutcome) {
        let (path, query) = Self.split(requestTarget)
        guard path == "/callback" else {
            // `res.writeHead(404).end()` — no content-type, no body, and crucially no settle and no
            // cleanup. B82.
            return (CallbackReply(status: 404, contentType: nil, body: ""), .ignored)
        }

        let code = Self.firstValue(of: "code", in: query)
        let error = Self.firstValue(of: "error", in: query)

        // `if (error || !code)` — JS truthiness, so a present-but-EMPTY `error=` does not take the
        // branch on its own account, and an empty `code=` does.
        let errorIsTruthy = !(error ?? "").isEmpty
        let codeIsFalsy = (code ?? "").isEmpty
        if errorIsTruthy || codeIsFalsy {
            // `error ?? '…'` is NULLISH coalescing, not `||`. A present-but-empty `error=` with no
            // code therefore renders an EMPTY detail and rejects with an EMPTY message — it does
            // not fall back to the default sentence. Getting this wrong is invisible until a
            // provider sends `?error=`, which is exactly when it matters.
            let detail = error ?? AuthPages.noCodePageDetail
            let reason = error ?? AuthPages.noCodeRejection
            return (
                CallbackReply(
                    status: 400,
                    contentType: "text/html",
                    body: AuthPages.failed(detail: detail)
                ),
                .failed(reason: reason)
            )
        }
        // Falsiness is settled above, so the code is present and non-empty here.
        let authorizationCode = code ?? ""

        do {
            try await exchange(authorizationCode)
            // The reference logs *between* writing the page and settling. Order asserted by B94.
            await log?.log(.upstreamAuthorized(server: server.string))
            return (
                CallbackReply(
                    status: 200,
                    contentType: "text/html",
                    body: AuthPages.connected(server: server)
                ),
                .succeeded
            )
        } catch {
            let reason = (error as? AuthFailure)?.message ?? error.localizedDescription
            return (
                CallbackReply(
                    status: 500,
                    contentType: "text/html",
                    body: AuthPages.failed(detail: reason)
                ),
                .failed(reason: reason)
            )
        }
    }

    /// `new URL(target, base)` for the two parts this needs.
    static func split(_ target: String) -> (path: String, query: [(name: String, value: String)]) {
        let withoutFragment = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        guard let mark = withoutFragment.firstIndex(of: "?") else {
            return (withoutFragment.isEmpty ? "/" : withoutFragment, [])
        }
        let path = String(withoutFragment[withoutFragment.startIndex ..< mark])
        let rest = String(withoutFragment[withoutFragment.index(after: mark)...])
        var items: [(name: String, value: String)] = []
        for pair in rest.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = Self.decode(String(parts[0]))
            let value = parts.count > 1 ? Self.decode(String(parts[1])) : ""
            items.append((name: name, value: value))
        }
        return (path.isEmpty ? "/" : path, items)
    }

    /// `URLSearchParams` decodes `+` as a space as well as percent-escapes.
    static func decode(_ raw: String) -> String {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            ?? raw.replacingOccurrences(of: "+", with: " ")
    }

    /// `searchParams.get` — the **first** occurrence wins.
    static func firstValue(
        of name: String, in query: [(name: String, value: String)]
    ) -> String? {
        query.first { $0.name == name }?.value
    }
}

/// A failure carrying the reference's own message text.
///
/// A typed error rather than a status/message pair assembled at the call site — R1's D5 — so a
/// surface can tell *refused* from *timed out* without parsing a string, while the emitted bytes
/// stay identical.
public struct AuthFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}
