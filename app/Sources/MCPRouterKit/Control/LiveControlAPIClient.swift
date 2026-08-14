import Foundation

/// The client that actually talks to the router.
///
/// An `actor` because it owns one mutable thing — the cached token — and several surfaces will
/// call it concurrently the moment the app has more than one pane. The alternative, a struct
/// re-reading the Keychain on every request, turns every list refresh into a Keychain hit.
///
/// Everything here goes over loopback HTTP and nothing else. That is the product constraint this
/// whole item exists to serve: one boundary, so the router underneath can be replaced without the
/// app noticing.
public actor LiveControlAPIClient: ControlAPIClient {
    public let baseURL: URL
    private let session: URLSession
    private let store: any ControlTokenStore
    private let tokenFile: RouterTokenFile
    private let log: ControlLog

    /// The token as last read. Nil means "not looked up yet", not "absent".
    private var cachedToken: String?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8879")!,
        session: URLSession = .shared,
        store: any ControlTokenStore = KeychainTokenStore(),
        tokenFile: RouterTokenFile = RouterTokenFile(),
        log: ControlLog = ControlLog()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
        self.tokenFile = tokenFile
        self.log = log
    }

    // MARK: - Token handling

    /// The token to send, preferring what is stored and falling back to the router's file.
    private func currentToken() async -> String? {
        if let cachedToken { return cachedToken }
        if let stored = try? await store.read(), !stored.isEmpty {
            cachedToken = stored
            return stored
        }
        guard let fromFile = tokenFile.read() else { return nil }
        try? await store.write(fromFile)
        cachedToken = fromFile
        log.info("read the control token from the router's file (\(ControlLog.redacted(fromFile)))")
        return fromFile
    }

    /// Re-read the router's file after a rejection. Returns the new token only when it differs
    /// from **the one that was actually sent** — an unchanged token means the credential is simply
    /// wrong, and retrying with it would be a loop that never terminates.
    ///
    /// Comparing against the token that failed rather than against `cachedToken` is what makes
    /// this correct under concurrency, and the difference is observable. Two panes refresh at the
    /// same moment, both send token A, the router rotates to B, and both get a 401. The first call
    /// re-reads, sees B, and stores it. Compared against `cachedToken` the second call would then
    /// find B == B, conclude nothing had rotated, and report "not authorised" to a user whose
    /// credential is fine — a spurious re-pair prompt that disappears on the next refresh, which is
    /// the worst kind of bug to be told about. Compared against the token it sent, it sees B != A
    /// and retries once, like the first.
    private func rotatedToken(replacing sent: String?) async -> String? {
        guard let fresh = tokenFile.read(), fresh != sent else { return nil }
        try? await store.write(fresh)
        cachedToken = fresh
        log.info("the control token rotated; stored the new one (\(ControlLog.redacted(fresh)))")
        return fresh
    }

    // MARK: - The one request path

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"

        /// The router requires a token and a JSON content type on exactly these.
        var isMutating: Bool { self != .get }
    }

    /// Build the request URL from a path whose segments are **already** percent-encoded.
    ///
    /// Deliberately not `appendingPathComponent`: that treats its argument as a literal component
    /// and encodes it again, so a name we correctly encoded to `a%2Fb` goes out as `a%252Fb` and
    /// reaches a route that does not exist. Setting `percentEncodedPath` is what keeps one round
    /// of encoding at one round.
    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = components?.percentEncodedPath ?? ""
        let prefix = base.hasSuffix("/") ? String(base.dropLast()) : base
        components?.percentEncodedPath = prefix + "/" + path
        if !query.isEmpty { components?.queryItems = query }
        return components?.url ?? baseURL.appendingPathComponent(path)
    }

    /// Percent-encode one path segment. A server may legitimately be named with a character that
    /// would otherwise split the path; the router decodes the segment on the way in.
    private func segment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~")))
            ?? raw
    }

    private func send<Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        typedFailureStatuses: Set<Int> = [],
        as _: Response.Type
    ) async throws(ControlAPIError) -> Response {
        let data = try await perform(
            method, path,
            query: query, body: body,
            typedFailureStatuses: typedFailureStatuses,
            allowRetry: true
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // Never `try?` with a default here. A decode failure that fell back to an empty value
            // would render as "you have no servers", which is the exact silent-empty failure the
            // TypeScript router shipped once and this codebase now forbids by name.
            throw ControlAPIError.malformedResponse(detail: "\(Response.self): \(error)")
        }
    }

    private func perform(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        body: Data?,
        typedFailureStatuses: Set<Int> = [],
        allowRetry: Bool
    ) async throws(ControlAPIError) -> Data {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method.rawValue

        let token = await currentToken()
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if method.isMutating, body != nil || method != .delete {
            // A JSON content type is what forces a cross-origin preflight the router never
            // answers — it is a security control, not a formality.
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // Measured on this machine: a refused loopback connection is exactly
            // `cannotConnectToHost` (-1004). Nothing is listening, which for a loopback daemon
            // means it is not running — a state with its own surface and its own one action.
            if error.code == .cannotConnectToHost || error.code == .cannotFindHost {
                throw ControlAPIError.routerNotRunning
            }
            throw ControlAPIError.transport(detail: error.localizedDescription)
        } catch {
            throw ControlAPIError.transport(detail: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ControlAPIError.malformedResponse(detail: "not an HTTP response")
        }

        if http.statusCode == 401 {
            guard allowRetry, await rotatedToken(replacing: token) != nil else {
                throw ControlAPIError.unauthorized
            }
            // Exactly one retry, tracked by this parameter rather than by any stored flag — two
            // concurrent calls each get their own single retry and cannot compound into a loop.
            return try await perform(
                method, path,
                query: query, body: body,
                typedFailureStatuses: typedFailureStatuses,
                allowRetry: false
            )
        }

        // A status this endpoint documents as carrying its own typed body.
        //
        // Only re-index uses it, and the reason is specific: `POST /servers/:name/reindex` answers
        // `422 {name, tools, error}` when indexing fails (`src/control.ts` ~line 326) — the same
        // shape as its success, with `error` filled in. Routing that through the generic
        // `{error, hint}` path throws away `name` and `tools`, so the surface loses the count of
        // what *did* index and the row it belongs to, and can only say "something went wrong".
        //
        // This is an allowlist per call site rather than a blanket "422 is fine": a 422 from `add`
        // is a genuine refusal carrying `{error, hint}` and must stay an error, or the advice that
        // tells the user how to proceed would be swallowed by an empty typed decode.
        if !typedFailureStatuses.contains(http.statusCode) {
            guard (200 ..< 300).contains(http.statusCode) else {
                let failure = try? JSONDecoder().decode(RouterErrorBody.self, from: data)
                throw ControlAPIError.server(
                    status: http.statusCode,
                    message: failure?.error ?? "the router did not explain the failure",
                    hint: failure?.hint
                )
            }
        }

        return data
    }

    private func encode(_ value: some Encodable) throws(ControlAPIError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw ControlAPIError.malformedResponse(detail: "could not encode the request: \(error)")
        }
    }

    // MARK: - Reading

    public func servers() async throws(ControlAPIError) -> ServersResponse {
        try await send(.get, "servers", as: ServersResponse.self)
    }

    public func server(named name: String) async throws(ControlAPIError) -> MCPServer {
        try await send(.get, "servers/\(segment(name))", as: MCPServer.self)
    }

    public func usage(
        limit: Int?,
        server: String?,
        cwd: String?
    ) async throws(ControlAPIError) -> UsageResponse {
        // Only the filters the caller actually set go on the wire. Sending `server=` empty would
        // not mean "no filter" to the router — it reads the parameter's presence, so an empty one
        // asks for the calls of a server named "".
        var query: [URLQueryItem] = []
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let server { query.append(.init(name: "server", value: server)) }
        if let cwd { query.append(.init(name: "cwd", value: cwd)) }
        return try await send(.get, "usage", query: query, as: UsageResponse.self)
    }

    public func usageSummary() async throws(ControlAPIError) -> UsageSummary {
        try await send(.get, "usage/summary", as: UsageSummary.self)
    }

    public func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
        try await send(.get, "servers/\(segment(name))/changes", as: HeldChanges.self)
    }

    public func searchRegistry(
        query: String,
        limit: Int
    ) async throws(ControlAPIError) -> RegistrySearchResponse {
        try await send(
            .get,
            "registry/search",
            query: [.init(name: "q", value: query), .init(name: "limit", value: String(limit))],
            as: RegistrySearchResponse.self
        )
    }

    // MARK: - Writing

    public func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
        try await send(
            .post,
            "servers",
            query: force ? [.init(name: "force", value: "1")] : [],
            body: encode(server),
            as: AddedServer.self
        )
    }

    public func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
        try await send(
            .delete,
            "servers/\(segment(name))",
            query: keepHistory ? [.init(name: "keepHistory", value: "1")] : [],
            as: RemovedServer.self
        )
    }

    public func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
        try await send(
            .post,
            "servers/\(segment(name))/reindex",
            body: Data("{}".utf8),
            // The router reports a failed index as `422` carrying the *same* shape as a success.
            // It is an outcome, not a transport failure, and it is the only place that is true.
            typedFailureStatuses: [422],
            as: ReindexResult.self
        )
    }

    public func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
        let body: Data
        do {
            // Deliberately `encodedBody()` rather than a local encoder: that is the one path that
            // re-checks the wire keys, and it is what makes "a patch can never carry a command
            // line" a runtime guarantee rather than a code-review convention.
            body = try patch.encodedBody()
        } catch {
            throw ControlAPIError.malformedResponse(detail: "could not encode the patch: \(error)")
        }
        return try await send(.patch, "servers/\(segment(name))", body: body, as: MCPServer.self)
    }

    public func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
        try await send(
            .post,
            "servers/\(segment(name))/approve",
            body: Data("{}".utf8),
            as: ApprovalResult.self
        )
    }

    public func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
        try await send(
            .post,
            "servers/\(segment(name))/auth",
            body: Data("{}".utf8),
            as: AuthorizationStart.self
        )
    }

    public func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
        try await send(.delete, "servers/\(segment(name))/auth", as: SignedOut.self)
    }

    public func resetUsage() async throws(ControlAPIError) -> UsageReset {
        try await send(.post, "usage/reset", body: Data("{}".utf8), as: UsageReset.self)
    }
}
