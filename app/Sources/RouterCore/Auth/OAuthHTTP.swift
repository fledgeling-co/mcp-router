import Foundation

/// One HTTP exchange the OAuth client makes, behind a protocol so the whole cascade is testable
/// without a network and so a mutation can be aimed at one request rather than at a socket.
public struct OAuthHTTPRequest: Sendable {
    public var method: String
    public var url: String
    public var headers: [(name: String, value: String)]
    public var body: Data?

    public init(
        method: String,
        url: String,
        headers: [(name: String, value: String)] = [],
        body: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct OAuthHTTPResponse: Sendable {
    public let status: Int
    public let headers: [(name: String, value: String)]
    public let body: Data

    public init(status: Int, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Header lookup is case-insensitive, as HTTP is. `WWW-Authenticate` arrives from URLSession
    /// canonicalised, and from a test double however the test wrote it.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    /// The body as `JSONValue`, or nil when it is not JSON. Parsed through ``JSONParser`` rather
    /// than `JSONSerialization`, which would reorder members and lose the code-unit identity the
    /// credential file depends on.
    public var json: JSONValue? {
        guard let text = String(data: body, encoding: .utf8) else { return nil }
        return try? JSONParser.parse(text)
    }
}

public protocol OAuthHTTPPerforming: Sendable {
    func perform(_ request: OAuthHTTPRequest) async throws -> OAuthHTTPResponse
}

/// The production client for the OAuth cascade.
///
/// Ephemeral for the reason ``RegistryHTTPClient`` is: `URLSession.shared` carries a process-wide
/// `URLCache` and cookie store, where node's `fetch` has neither. A cached metadata document would
/// make the two routers answer differently from the same provider, and redirects are **not**
/// followed — the reference's `fetch` follows them, but the authorization endpoint's 302 is never
/// requested by the router at all; every request this client makes is one the reference expects a
/// direct answer to, and following a redirect silently would hide a provider that moved.
public struct URLSessionOAuthHTTP: OAuthHTTPPerforming {
    private static let session = URLSession(configuration: .ephemeral)

    public init() {}

    public func perform(_ request: OAuthHTTPRequest) async throws -> OAuthHTTPResponse {
        guard let target = URL(string: request.url) else {
            throw AuthFailure("Invalid URL")
        }
        var urlRequest = URLRequest(url: target)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await Self.session.data(for: urlRequest)
        } catch {
            throw AuthFailure("fetch failed")
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthFailure("the response was not HTTP")
        }
        // Only the headers the cascade reads are carried across. `allHeaderFields` is
        // `[AnyHashable: Any]`, which is neither ordered nor typed, and nothing here needs a
        // header this list does not name.
        let names = ["WWW-Authenticate", "Content-Type", "Location"]
        let headers = names.compactMap { name -> (name: String, value: String)? in
            guard let value = http.value(forHTTPHeaderField: name) else { return nil }
            return (name: name, value: value)
        }
        return OAuthHTTPResponse(status: http.statusCode, headers: headers, body: body)
    }
}
