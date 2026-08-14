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
            return await post(request)
        case "GET":
            // The reference opens an SSE stream and holds it. Nothing is ever written to it in
            // stateless mode, and it ends when the client leaves — reproduced rather than answered
            // with a 405, because a client that opens the standalone stream must not see an error.
            return HTTPWireResponse(
                status: 200,
                headers: Self.sseHeaders,
                body: .chunks(AsyncStream { _ in }),
                keepAlive: false
            )
        case "DELETE":
            // 200 with a chunked, empty body. Measured; the reference's transport has no session to
            // delete in stateless mode and says so by saying nothing.
            return HTTPWireResponse(
                status: 200, headers: [], body: .chunks(AsyncStream { $0.finish() })
            )
        default:
            return Self.rpcError(405, code: -32000, message: "Method Not Allowed")
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
        let messages: [JSONValue] = if case let .array(items) = message { items } else { [message] }
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

    /// The authorities a request may name. `cfg.host:port` first, then the three loopback spellings,
    /// de-duplicated — `src/router.ts:allowedHosts`.
    private var allowedHosts: [String] {
        var seen: [String] = []
        for candidate in [
            "\(deps.config.host):\(deps.config.port)",
            "127.0.0.1:\(deps.config.port)",
            "localhost:\(deps.config.port)",
            "[::1]:\(deps.config.port)"
        ] where !seen.contains(candidate) {
            seen.append(candidate)
        }
        return seen
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

    // MARK: - tools/call

    private func callTool(_ params: JSONValue?) async -> JSONValue {
        guard case let .object(members)? = params,
              let fullName = members.first(where: { $0.key == JSString("name") })?.value.asString
        else {
            return Self.toolError("Tool \"undefined\" is not namespaced <server>__<tool>.")
        }
        let arguments = members.first { $0.key == JSString("arguments") }?.value ?? .object([])

        guard let split = ToolUnion.splitToolName(fullName) else {
            return Self.toolError(
                "Tool \"\(fullName.string)\" is not namespaced <server>__<tool>."
            )
        }
        let serverName = split.server.string
        let tool = split.tool.string
        let upstream = deps.upstreams.first { $0.name == serverName }

        // A scoped server is not merely hidden from the list — it does not run for a caller outside
        // its projects. Hiding alone would leave it callable by any agent that learned the name.
        if let upstream {
            let identity = await currentIdentity()
            if !ToolUnion.visibleTo(upstream, cwd: identity.cwd) {
                let location = identity.cwd.map { " (\($0))" } ?? ""
                return Self.toolError(
                    "Upstream \"\(serverName)\" is not available in this project\(location)."
                )
            }
        }

        // A placarded server answers instead of running. The text is written for the model rather
        // than for a log: it names the fault and the substitute, so the assistant reroutes on this
        // attempt instead of spending the turn discovering that a tool cannot work.
        if let upstream {
            let entry = await deps.manifest.current().entry(named: serverName)
            if let placard = ToolUnion.placardFor(upstream, entry: entry) {
                var text = "Tool \"\(tool)\" is INOPERATIVE: \(placard.reason)."
                if let substitute = placard.substitute, !substitute.isEmpty {
                    text += " Use \(substitute) instead."
                }
                text += " Do not retry this tool; it will keep returning this."
                return Self.toolError(text)
            }
        }

        let startedAt = deps.clock.nowMilliseconds
        // Read before the call: afterwards the upstream is live either way, so this is the only
        // moment at which "did this call pay the start-up cost" is knowable.
        let cold = await !deps.pool.isLive(serverName)
        var ok = true
        var failure: String?
        var result: JSONValue

        do {
            // `lease`, not `acquire` then call: the pool has to know a request is outstanding or its
            // idle reaper closes the upstream mid-call.
            let lease = try await deps.pool.lease(serverName)
            // Released explicitly rather than through a `defer` that spawns a task: a fire-and-forget
            // release lands at an unspecified later moment, so the idle window would start counting
            // from whenever that task happened to run rather than from when the call ended.
            do {
                result = try await lease.session.callTool(name: tool, arguments: arguments)
            } catch {
                await deps.pool.release(lease)
                throw error
            }
            await deps.pool.release(lease)
            // A tool that reports its own failure is a failure in the record. Counting it as a
            // success would make the error rate a measure of transport health rather than of
            // whether the tool worked.
            if case let .object(fields) = result,
               fields.first(where: { $0.key == JSString("isError") })?.value.isTruthy == true {
                ok = false
                failure = "tool reported an error"
            }
        } catch {
            ok = false
            let reason = (error as? PoolError)?.message ?? "\(error)"
            failure = reason
            await deps.log?.record(
                ServiceLogEvent.callFailed(server: serverName, tool: tool, reason: reason)
            )
            // A dead upstream is a tool error, never a router crash: one broken server must not take
            // the other nine down with it.
            result = Self.toolError(
                "Upstream \"\(serverName)\" failed to handle \"\(tool)\": \(reason)"
            )
        }

        // Attribution runs after the result is on its way and swallows everything: it must never
        // delay or break a call.
        let elapsed = deps.clock.nowMilliseconds - startedAt
        let identity = await currentIdentity()
        deps.usage.record(UsageRecord(
            ts: JSDate.iso8601(milliseconds: startedAt),
            server: serverName,
            tool: tool,
            ok: ok,
            ms: elapsed,
            cold: cold,
            pid: identity.pid.map(Int32.init),
            cwd: identity.cwd,
            project: projectOf(identity.cwd),
            client: identity.client,
            err: failure
        ))
        return result
    }

    private func currentIdentity() async -> CallerIdentity {
        await identify(currentConnection)
    }

    /// Set by ``respond(to:)``'s caller through ``with(connection:)`` — the descriptor of the socket
    /// this request arrived on.
    var currentConnection: ConnectionDescriptor = ConnectionDescriptor(
        peer: "", acceptedAtMilliseconds: 0
    )

    public func with(connection: ConnectionDescriptor) -> MCPEndpoint {
        var copy = self
        copy.currentConnection = connection
        return copy
    }

    // MARK: - Framing

    /// The reference's SSE header set, in the reference's order. `Transfer-Encoding: chunked` and
    /// `Date` are added by ``HTTPWire``; `connection` is here rather than left to the listener
    /// because the reference sends it in this position, lowercased.
    static let sseHeaders: [(name: String, value: String)] = [
        (name: "cache-control", value: "no-cache, no-transform"),
        (name: "connection", value: "keep-alive"),
        (name: "content-type", value: "text/event-stream"),
        (name: "x-accel-buffering", value: "no")
    ]

    static func sse(_ frames: [JSONValue]) -> HTTPWireResponse {
        let stream = AsyncStream<Data> { continuation in
            for frame in frames {
                continuation.yield(Data("event: message\ndata: \(JSStringify.compact(frame))\n\n".utf8))
            }
            continuation.finish()
        }
        return HTTPWireResponse(status: 200, headers: sseHeaders, body: .chunks(stream))
    }

    /// A JSON-RPC error delivered as a plain JSON body — which is what the reference does for the
    /// framing refusals, in contrast to the SSE it uses for anything the transport actually handled.
    /// The member order is the reference's: `jsonrpc`, `error`, `id`.
    static func rpcError(_ status: Int, code: Int, message: String) -> HTTPWireResponse {
        let body = JSONValue.object([
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("error"), value: .object([
                JSONMember(key: JSString("code"), value: .number(Double(code))),
                JSONMember(key: JSString("message"), value: .string(JSString(message)))
            ])),
            JSONMember(key: JSString("id"), value: .null)
        ])
        return .json(status, Data(JSStringify.compact(body).utf8))
    }

    /// `result` first, then `jsonrpc`, then `id` — the reference's envelope order, measured.
    static func success(id: JSONValue, result: JSONValue) -> JSONValue {
        .object([
            JSONMember(key: JSString("result"), value: result),
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("id"), value: id)
        ])
    }

    /// `jsonrpc`, `id`, then `error` — a different order from the success envelope, and measured
    /// separately rather than assumed symmetric.
    static func failure(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("id"), value: id),
            JSONMember(key: JSString("error"), value: .object([
                JSONMember(key: JSString("code"), value: .number(Double(code))),
                JSONMember(key: JSString("message"), value: .string(JSString(message)))
            ]))
        ])
    }

    /// A `CallToolResult` reporting its own failure: one text content part and `isError: true`.
    static func toolError(_ text: String) -> JSONValue {
        .object([
            JSONMember(key: JSString("content"), value: .array([
                .object([
                    JSONMember(key: JSString("type"), value: .string(JSString("text"))),
                    JSONMember(key: JSString("text"), value: .string(JSString(text)))
                ])
            ])),
            JSONMember(key: JSString("isError"), value: .bool(true))
        ])
    }
}
