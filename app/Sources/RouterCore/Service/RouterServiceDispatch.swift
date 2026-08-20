import Foundation

/// How a request becomes a response: the dispatch ladder, the two unauthenticated status answers,
/// the control block and the usage stream, plus the query-string parsing they share.
///
/// Split from `RouterService.swift` so that file is only the composition root — what the service
/// owns and how it starts and stops. The two change for different reasons: a new route is a change
/// here, a new collaborator is a change there. Everything below stays actor-isolated, and the
/// `private` helpers stay private because they and their only callers moved together.
///
/// **Dispatch order is `src/router.ts`'s and is not rearrangeable** — see the type's own
/// documentation for why `/health` and `/status` are answered ahead of the control block.
extension RouterService {
    func respond(to request: HTTPWireRequest) async -> HTTPWireResponse {
        let (path, query) = request.pathAndQuery

        if path == "/health", request.method == "GET" {
            return .json(200, Data(JSStringify.compact(.object([
                JSONMember(key: JSString("ok"), value: .bool(true)),
                JSONMember(
                    key: JSString("upstreams"),
                    value: .number(Double(config.upstreams.count))
                )
            ])).utf8))
        }

        if path == "/status", request.method == "GET" {
            return await statusResponse()
        }

        if ControlPaths.isControlPath(path) {
            if let response = await controlResponse(request, path: path, query: query) {
                return response
            }
        }

        guard path == MCPEndpoint.path else {
            return .json(404, Data(JSStringify.compact(.object([
                JSONMember(
                    key: JSString("error"),
                    value: .string(JSString("not found; MCP endpoint is \(MCPEndpoint.path)"))
                )
            ])).utf8), reason: "Not Found")
        }

        let endpoint = MCPEndpoint(
            deps: MCPEndpoint.Deps(
                config: config,
                upstreams: config.upstreams,
                manifest: manifest,
                pool: pool,
                usage: usage,
                log: log,
                clock: clock
            ),
            identify: { descriptor in
                let identity = PeerIdentities.shared.identity(for: descriptor)
                return CallerIdentity(
                    pid: identity.pid.map(Int.init), cwd: identity.cwd, client: identity.client
                )
            }
        ).with(connection: request.connection)
        return await endpoint.respond(to: request)
    }

    private func statusResponse() async -> HTTPWireResponse {
        let live = await pool.status()
        let pending = await pool.pending()
        let current = await manifest.current()
        let children = live.map { row in
            JSONValue.object([
                JSONMember(key: JSString("name"), value: .string(JSString(row.name))),
                JSONMember(key: JSString("transport"), value: .string(JSString(row.transport))),
                JSONMember(key: JSString("state"), value: .string(JSString(row.state))),
                JSONMember(key: JSString("callsServed"), value: .number(Double(row.callsServed))),
                JSONMember(key: JSString("inFlight"), value: .number(Double(row.inFlight))),
                JSONMember(key: JSString("idleSec"), value: .number(Double(row.idleSec)))
            ])
        }
        let body = JSONValue.object([
            JSONMember(key: JSString("ok"), value: .bool(true)),
            JSONMember(key: JSString("port"), value: .number(Double(config.port))),
            JSONMember(key: JSString("idleMs"), value: .number(Double(config.idleMs))),
            JSONMember(key: JSString("children"), value: .array(children)),
            JSONMember(key: JSString("pendingAuth"), value: .array(pending.map { row in
                .object([
                    JSONMember(key: JSString("server"), value: .string(JSString(row.server)))
                ])
            })),
            JSONMember(
                key: JSString("tools"),
                value: .number(Double(ToolUnion.unionTools(
                    manifest: current, upstreams: config.upstreams
                ).count))
            )
        ])
        return .json(200, Data(JSStringify.compact(body).utf8))
    }

    /// The control API, adapted from the wire type to R3's own request type.
    ///
    /// Returns `nil` only when the handler declined the path, which cannot happen here because
    /// ``ControlPaths/isControlPath(_:)`` gated it — but the disposition travels with the response
    /// for a reason, and honouring it is what stops a mistyped control path falling through to the
    /// relay.
    private func controlResponse(
        _ request: HTTPWireRequest, path: String, query: String?
    ) async -> HTTPWireResponse? {
        var deps = await ControlDeps(
            config: config,
            upstreams: config.upstreams.map { (name: JSString($0.name), upstream: $0) },
            pool: PoolSnapshotPort(pool: pool),
            indexer: ManifestIndexer(
                startupTimeoutMs: config.startupTimeoutMs,
                transporting: RoutingUpstreamTransport(log: log),
                manifestPath: config.manifestPath,
                fileSystem: fileSystem,
                clock: clock,
                log: log
            ),
            auth: SnapshotAuthStore(
                store: auth, servers: config.upstreams.map { JSString($0.name) }
            ),
            usage: usage,
            manifest: manifest.current(),
            clock: clock,
            fileSystem: fileSystem,
            tokenPath: tokenPath,
            configPath: configPath,
            // Until P3 this was left at nil, and `GET /registry/search` answered
            // `502 registry search is unavailable: no HTTP client is configured` in the one
            // process that ships — measured on the wire against a reference answering 200. The
            // whole search pipeline existed and was unit-tested; nothing conformed to
            // ``HTTPFetching`` outside the test targets, so none of it could run here.
            //
            // The two bases are read with `??` and nothing else, because the reference's
            // `process.env.MCP_ROUTER_REGISTRY ?? 'https://…'` is NULLISH: a variable that is set
            // and empty survives to `new URL('/v0/servers', '')`, which throws, and the search
            // reports `official registry unreachable: Invalid URL`. Filtering the empty string out
            // here — the natural-looking Swift — would silently pick the default instead and
            // diverge on that input (B59).
            registry: RegistryDeps(
                http: RegistryHTTPClient(),
                fileSystem: fileSystem,
                routerHome: home.root,
                officialBase: environment["MCP_ROUTER_REGISTRY"],
                smitheryBase: environment["MCP_ROUTER_SMITHERY"],
                githubToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"],
                nowMs: clock.nowMilliseconds
            ),
            // B94's `approved "<name>"'s new tool surface (N tools)` is emitted by
            // `AuthRoutes.approve`, which takes the log as a parameter. Without this the daemon
            // passed nil and the line was unemittable in the one process that ships — the route
            // would answer correctly and log nothing, which no response assertion can see.
            log: log,
            // P7. This was nil until an `AuthTransport` existed outside the test target, and the
            // route answered 405 to the half of `POST /servers/:name/auth` the reference answers
            // 200 to (`D-p1-a`, the `control-auth-post-http` row). `OAuthFlowStarter` is the
            // service's own, built once, so the single-flow rule holds across requests.
            authFlow: authFlow
        )
        let handler = ControlHandler(token: token)
        let response = await handler.handle(
            ControlAPIRequest(
                method: request.method,
                encodedPath: path,
                query: Self.queryItems(query),
                headers: request.headers,
                body: request.body.isEmpty ? nil : request.body
            ),
            &deps
        )
        guard response.handled else { return nil }

        switch response.body {
        case let .bytes(bytes):
            return HTTPWireResponse(
                status: response.status,
                headers: response.headers.map { (name: $0.name, value: $0.value) },
                body: .bytes(Data(bytes))
            )
        case let .stream(description):
            return Self.usageStream(
                description,
                status: response.status,
                headers: response.headers,
                usage: usage
            )
        }
    }

    /// `/usage/stream`: the opening comment, then one frame per record, then a heartbeat every 25 s
    /// so a proxy or a sleeping Mac cannot make an idle stream look disconnected.
    private static func usageStream(
        _ description: ControlStream,
        status: Int,
        headers: [(name: String, value: String)],
        usage: UsageStore
    ) -> HTTPWireResponse {
        let stream = AsyncStream<Data> { continuation in
            continuation.yield(Data(description.openingFrame))
            // Boxed because the unsubscribe closure is not `Sendable` and `onTermination` is. The
            // box is the smallest honest synchronisation: one write at subscribe, one read at
            // termination, and nothing else touches it.
            let unsubscribe = UnsubscribeBox(usage.subscribe { record in
                continuation.yield(Data(ControlStream.frame(for: record.value)))
            })
            let heartbeat = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(
                        nanoseconds: UInt64(ControlStream.heartbeatMilliseconds) * 1_000_000
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(Data(description.heartbeatFrame))
                }
            }
            // The reader going away fires this, which is the only cancellation channel there is —
            // and the one that cannot be forgotten, because it is the stream's own.
            continuation.onTermination = { _ in
                unsubscribe.cancel()
                heartbeat.cancel()
            }
        }
        return HTTPWireResponse(
            status: status,
            headers: headers.map { (name: $0.name, value: $0.value) },
            body: .chunks(stream),
            keepAlive: false
        )
    }

    /// `URLSearchParams` semantics: `+` is a space, then percent decoding, and repeats are kept in
    /// arrival order so the handler's first-wins lookup can be honest.
    static func queryItems(_ raw: String?) -> [(name: String, value: String)] {
        guard let raw, !raw.isEmpty else { return [] }
        var items: [(name: String, value: String)] = []
        for pair in raw.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            let text = String(pair)
            guard let equals = text.firstIndex(of: "=") else {
                items.append((name: decode(text), value: ""))
                continue
            }
            items.append((
                name: decode(String(text[text.startIndex ..< equals])),
                value: decode(String(text[text.index(after: equals)...]))
            ))
        }
        return items
    }

    static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }

    /// The port half of a `host:port` peer description.
    static func peerPort(of peer: String) -> UInt16? {
        guard let colon = peer.lastIndex(of: ":") else { return nil }
        return UInt16(peer[peer.index(after: colon)...])
    }
}
