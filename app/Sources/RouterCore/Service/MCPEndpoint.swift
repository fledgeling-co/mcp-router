import Foundation

/// The relay: `POST /mcp`, answered over R1's JSON value layer rather than through the SDK's server
/// type.
///
/// That choice was forced by measurement, not preference. The reference answers a POST with
/// **Server-Sent Events** — `content-type: text/event-stream`, chunked, `event: message` — where the
/// SDK's `StatelessHTTPServerTransport` returns `application/json`; and its envelope member order is
/// `result, jsonrpc, id`, which no `Codable` encoder produces by accident. Serialising through
/// ``JSStringify`` from values parsed by ``JSONParser`` puts member order, number rendering, unicode
/// escaping and exponent form under this router's control, which is what makes a **byte** diff
/// against the reference possible instead of a key-sorted one that would hide exactly the
/// divergence most likely to occur.
///
/// The three framing refusals are **hand-written here rather than taken from the SDK's validator
/// pipeline**, and that too was measured: `OriginValidator` answers `421 Misdirected Request: Host
/// header not allowed` where the reference answers `403 Invalid Host header: <host>`. The Accept and
/// Content-Type strings do agree with the SDK's, because both implement the same spec sentence.
/// Every string below is asserted against the live reference by `scripts/acceptance/parity-mcp.sh`
/// on each run, so a hand-copied string that goes stale fails the gate rather than rotting.
public struct MCPEndpoint: Sendable {
    public static let path = "/mcp"

    /// What the relay reads. A value rather than a long parameter list, and every member is
    /// injectable so the endpoint is a function of its dependencies.
    public struct Deps: Sendable {
        public var config: RouterConfig
        public var upstreams: [UpstreamConfig]
        public var manifest: ManifestStore
        public var pool: UpstreamPool
        public var usage: UsageStore
        public var log: RouterLog?
        public var clock: any RouterClock

        public init(
            config: RouterConfig,
            upstreams: [UpstreamConfig],
            manifest: ManifestStore,
            pool: UpstreamPool,
            usage: UsageStore,
            log: RouterLog? = nil,
            clock: any RouterClock = SystemClock()
        ) {
            self.config = config
            self.upstreams = upstreams
            self.manifest = manifest
            self.pool = pool
            self.usage = usage
            self.log = log
            self.clock = clock
        }
    }

    let deps: Deps
    /// Resolves who is on the other end of the socket. Called at accept time by the service, and
    /// awaited here — by which point the answer is cached, so a tool call pays nothing for it.
    let identify: @Sendable (ConnectionDescriptor) async -> CallerIdentity

    public init(
        deps: Deps,
        identify: @escaping @Sendable (ConnectionDescriptor) async -> CallerIdentity
    ) {
        self.deps = deps
        self.identify = identify
    }

    // MARK: - Dispatch

    public func respond(to request: HTTPWireRequest) async -> HTTPWireResponse {
        switch request.method {
        case "POST":
            await post(request)
        case "GET":
            // The reference opens an SSE stream and holds it. Nothing is ever written to it in
            // stateless mode, and it ends when the client leaves — reproduced rather than answered
            // with a 405, because a client that opens the standalone stream must not see an error.
            HTTPWireResponse(
                status: 200,
                headers: Self.sseHeaders,
                body: .chunks(AsyncStream { _ in }),
                keepAlive: false
            )
        case "DELETE":
            // 200 with a chunked, empty body. Measured; the reference's transport has no session to
            // delete in stateless mode and says so by saying nothing.
            HTTPWireResponse(
                status: 200, headers: [], body: .chunks(AsyncStream { $0.finish() })
            )
        default:
            Self.rpcError(405, code: -32000, message: "Method Not Allowed")
        }
    }

    /// The POST path, in the reference's own order.
    ///
    /// The body is parsed **first**, before any header check, because `src/router.ts` calls
    /// `readBody` before `transport.handleRequest` — so a request that is both unparseable and
    /// wrongly addressed gets the parse answer. Getting this order wrong would put a 403 where the
    /// reference puts a 500 and vice versa, on requests a hostile page can send.
    private func post(_ request: HTTPWireRequest) async -> HTTPWireResponse {
        let message: JSONValue?
        if request.body.isEmpty {
            message = nil
        } else {
            do {
                message = try JSONParser.parse(request.body)
            } catch {
                // Divergence `div-r2r-d8`: the status, the code and the `invalid JSON body: ` prefix
                // are the reference's; only the parser text after the prefix differs, because the
                // reference's is V8's own. Reproducing V8's wording would mean shipping a
                // hand-copied string that goes stale the next time Node changes it.
                await deps.log?.record(
                    ServiceLogEvent.requestFailed(reason: "invalid JSON body: \(error)")
                )
                return Self.rpcError(
                    500, code: -32603, message: "invalid JSON body: \(error)"
                )
            }
        }

        if let refusal = framingRefusal(request) { return refusal }

        guard let message else {
            return Self.rpcError(400, code: -32700, message: "Parse error: Invalid JSON")
        }

        // A batch is an array of messages. Each request in it produces its own `event: message`
        // frame on the one stream, in order; a batch of nothing but notifications is 202, exactly as
        // a single notification is.
        let messages: [JSONValue] = if case let .array(items) = message {
            items
        } else { [message] }
        var frames: [JSONValue] = []
        for item in messages {
            if let answer = await answer(to: item) { frames.append(answer) }
        }
        guard !frames.isEmpty else {
            return HTTPWireResponse(status: 202, headers: [], body: .bytes(Data()))
        }
        return Self.sse(frames)
    }

    /// The three framing checks, in the reference's order: Host, then Accept, then Content-Type.
    private func framingRefusal(_ request: HTTPWireRequest) -> HTTPWireResponse? {
        // Binding to loopback is not on its own enough to keep a browser out: a page the user
        // visits can point a hostname it controls at 127.0.0.1, and the request is then same-origin
        // by the browser's reckoning, so no preflight stands in the way and a plain POST reaches an
        // endpoint that runs every MCP server the user owns with the user's environment. The Host
        // header is what distinguishes that request from a real local client.
        if let host = request.first("host"), !allowedHosts.contains(host) {
            return Self.rpcError(403, code: -32000, message: "Invalid Host header: \(host)")
        }

        let accept = request.first("accept") ?? ""
        let types = accept.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let acceptsJSON = types.contains { $0.hasPrefix("application/json") }
        let acceptsSSE = types.contains { $0.hasPrefix("text/event-stream") }
        guard acceptsJSON, acceptsSSE else {
            return Self.rpcError(
                406, code: -32000,
                message: "Not Acceptable: Client must accept both application/json and text/event-stream"
            )
        }

        let contentType = request.first("content-type") ?? ""
        guard contentType.split(separator: ";").first.map({
            $0.trimmingCharacters(in: .whitespaces) == "application/json"
        }) == true else {
            return Self.rpcError(
                415, code: -32000,
                message: "Unsupported Media Type: Content-Type must be application/json"
            )
        }
        return nil
    }

    /// The authorities a request may name.
    ///
    /// The list is ``RequestAuthority``'s, not a second copy: since R15 the dispatcher refuses a
    /// foreign Host ahead of this endpoint, and this check is the reference's transport-level
    /// `enableDnsRebindingProtection`, kept as defence in depth. Two lists could disagree about
    /// what the bound authority is; one cannot.
    private var allowedHosts: [String] {
        RequestAuthority.allowedHosts(host: deps.config.host, port: deps.config.port)
    }

    // MARK: - One JSON-RPC message

    /// The answer to one message, or `nil` when it is a notification and gets none.
    private func answer(to message: JSONValue) async -> JSONValue? {
        guard case let .object(members) = message else { return nil }
        let method = members.first { $0.key == JSString("method") }?.value.asString?.string
        let id = members.first { $0.key == JSString("id") }?.value

        // A notification has no id. It is acknowledged with 202 and never answered.
        guard let id else { return nil }
        guard let method else {
            return Self.failure(id: id, code: -32600, message: "Invalid Request")
        }

        let params = members.first { $0.key == JSString("params") }?.value

        switch method {
        case "initialize":
            return Self.success(id: id, result: .object([
                JSONMember(key: JSString("protocolVersion"), value: .string(JSString("2025-06-18"))),
                JSONMember(key: JSString("capabilities"), value: .object([
                    JSONMember(key: JSString("tools"), value: .object([]))
                ])),
                JSONMember(key: JSString("serverInfo"), value: .object([
                    JSONMember(key: JSString("name"), value: .string(JSString("mcp-router"))),
                    JSONMember(key: JSString("version"), value: .string(JSString("0.1.0")))
                ]))
            ]))
        case "ping":
            return Self.success(id: id, result: .object([]))
        case "tools/list":
            return await Self.success(id: id, result: listTools())
        case "tools/call":
            return await Self.success(id: id, result: callTool(params))
        default:
            return Self.failure(id: id, code: -32601, message: "Method not found")
        }
    }

    /// Read through the **store**, never a snapshot: an `mcp-router index` run while this process is
    /// up must reach the next client that lists tools. The caller's own directory is part of the
    /// answer, because a scoped server is served to some projects and not others.
    private func listTools() async -> JSONValue {
        let identity = await currentIdentity()
        let manifest = await deps.manifest.current()
        let tools = ToolUnion.unionTools(
            manifest: manifest, upstreams: deps.upstreams, cwd: identity.cwd
        )
        return .object([
            JSONMember(key: JSString("tools"), value: .array(tools.map(\.value)))
        ])
    }

    /// Set by ``respond(to:)``'s caller through ``with(connection:)`` — the descriptor of the socket
    /// this request arrived on.
    ///
    /// Stays here rather than moving with `tools/call`: a stored property cannot be declared in an
    /// extension, so this is the one member of that group the split could not carry across.
    var currentConnection: ConnectionDescriptor = .init(
        peer: "", acceptedAtMilliseconds: 0
    )
}
