import Foundation

/// Handles one control-API request.
///
/// A **function of its dependencies**, not of a recorded state (S6): every response below is
/// constructed from the config, manifest, pool, usage store and auth store on each call. That is
/// deliberate and was forced — a review defeated nine of this item's first-draft clauses with a
/// handler that recognised a recorded state and returned recorded bytes, which passed every fixture
/// and was worthless as a port.
public struct ControlHandler: Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }

    /// The dispatch order is the contract (B22, S7). Each stage runs only if the one before it
    /// passed, and the sequence is not rearrangeable because the end state matches.
    ///
    /// | # | stage | on failure |
    /// | 1 | path ownership | **not handled** — send nothing |
    /// | 2 | token, for POST/DELETE/PATCH | 401 |
    /// | 3 | content-type, for non-DELETE mutations | 415 |
    /// | 4 | route regex | fall through to 405 |
    /// | 5 | percent-decode the name | throws |
    /// | 6 | live-map lookup | 404 |
    /// | 7 | method dispatch | 405 |
    ///
    /// Stage 1 running **first** is what keeps the MCP endpoint working: gating before it would
    /// answer an unauthenticated `POST /mcp` with 401 instead of letting it fall through (B14).
    /// And because stage 2 precedes stage 6, `DELETE /servers/ghost` without a token is **401**,
    /// not 404 — the draft of this spec asserted the opposite and was wrong.
    public func handle(_ request: ControlRequest, _ deps: inout ControlDeps) async -> ControlResponse {
        let path = request.encodedPath

        // 1 — ownership. No header is read and nothing is sent for a path this item does not own.
        guard ControlPaths.isControlPath(path) else { return .notHandled }

        // 2 and 3 — the token and the content-type, for the mutating half only.
        if let refusal = gate(request, tokenPath: deps.tokenPath) { return refusal }

        if path == "/servers", request.method == "GET" {
            return serversEnvelope(deps)
        }
        if path == "/servers", request.method == "POST" {
            return await addServer(request, &deps)
        }

        // 4 — the route. The sub-path is lowercase-only, so `/servers/x/Reindex` does not match and
        // falls through to 405 rather than being treated as a reindex.
        if let route = ServerRoute(encodedPath: path) {
            // 5 — decode. A malformed escape is a `URIError` in the reference, which propagates
            // rather than becoming a JSON reply, so it is surfaced as a thrown-equivalent here.
            guard let decoded = route.decodedName else {
                return .error(400, "URI malformed")
            }
            // 6 — lookup by JavaScript string identity.
            guard let upstream = deps.upstream(named: decoded) else {
                return .error(404, "no server named \"\(decoded.string)\"")
            }
            if let response = await dispatchServer(
                route: route, upstream: upstream, name: decoded, request: request, deps: &deps
            ) {
                return response
            }
        }

        if let response = routeUsage(path, request, deps) { return response }
        if path == "/registry/search", request.method == "GET" {
            return await registrySearch(request, deps)
        }

        // 7 — anything claimed and unhandled. `/servers/` reaches here, not 404.
        return .error(405, "\(request.method ?? "undefined") not allowed on \(path)")
    }

    /// Stages 2 and 3. `nil` means both passed.
    ///
    /// GET is deliberately ungated, matching the reference; that exposure is recorded as a ported
    /// defect rather than quietly fixed, because changing it would move the wire.
    private func gate(_ request: ControlRequest, tokenPath: String) -> ControlResponse? {
        guard request.isMutating else { return nil }
        guard ControlToken.isAuthorized(request, expected: token) else {
            return .error(401, "unauthorized; the token is in \(tokenPath)")
        }
        // DELETE is exempt from the rejection, not from the read.
        if request.method != "DELETE", !ControlToken.hasJSONContentType(request) {
            return .error(415, "expected content-type: application/json")
        }
        return nil
    }

    private func routeUsage(
        _ path: String, _ request: ControlRequest, _ deps: ControlDeps
    ) -> ControlResponse? {
        switch (path, request.method) {
        case ("/usage", "GET"): usageRecent(request, deps)
        case ("/usage/summary", "GET"): usageSummary(deps)
        case ("/usage/reset", "POST"): usageReset(deps)
        case ("/usage/stream", "GET"): usageStream()
        default: nil
        }
    }

    // MARK: - /servers

    private func serversEnvelope(_ deps: ControlDeps) -> ControlResponse {
        var members: [JSONMember] = [
            JSONMember(key: "port", value: .number(Double(deps.config.port))),
            JSONMember(key: "idleMs", value: .number(Double(deps.config.idleMs))),
            JSONMember(key: "since", value: .string(JSString(deps.usage.summarySince())))
        ]
        // Omitted entirely when no flow is in progress, which is what the two recorded envelopes
        // differ by (B13).
        if let flow = deps.currentFlow {
            members.append(JSONMember(key: "pendingAuth", value: .object([
                JSONMember(key: "server", value: .string(JSString(flow.server))),
                JSONMember(key: "url", value: .string(JSString(flow.url)))
            ])))
        }
        members.append(JSONMember(
            key: "servers",
            value: .array(deps.upstreams.map { Describe.row($0.upstream, deps) })
        ))
        return .json(200, .object(members))
    }

    private func addServer(_ request: ControlRequest, _ deps: inout ControlDeps) async -> ControlResponse {
        let body = request.bodyObject
        let nameValue = body.first { $0.key == JSString("name") }?.value
        // `!b.name` — falsiness, so an empty string is "required", not a valid name (S1).
        guard let nameValue, nameValue.isTruthy, let name = nameValue.asString else {
            return .error(400, "name is required")
        }
        // Checked against the **live** map, not the file on disk.
        guard !deps.hasUpstream(named: name) else {
            return .error(409, "a server named \"\(name.string)\" already exists")
        }
        let parsed = ServerParser.parse(name: name.string, raw: .object(body))
        guard case let .upstream(candidate) = parsed else {
            if case let .skipped(reason) = parsed { return .error(400, reason) }
            return .error(400, "name is required")
        }

        // Index **before** adopting, so a server that cannot start never lands in the config — and
        // exactly once, before any write (B27). The exception is an authorization failure: an OAuth
        // server is expected to refuse a first connection, and rejecting it here would make one
        // impossible to add at all.
        let outcome = await deps.indexer.index(candidate)
        let authPending = outcome.isAuthorizationPending
        let forced = request.first(named: "force") == "1"
        if let error = outcome.error, error.isJSTruthyString, !authPending, !forced {
            return .json(422, .object([
                JSONMember(key: "error", value: .string(JSString(error))),
                JSONMember(key: "hint", value: .string(JSString("retry with ?force=1 to add it anyway")))
            ]))
        }

        // The persisted entry is the request body's own members minus `name`, in order, with no
        // synthetic keys added (B30).
        do {
            try ConfigEdit.edit(path: deps.configPath, fileSystem: deps.fileSystem) { servers in
                let entry = body.filter { $0.key != JSString("name") }
                if let index = servers.firstIndex(where: { $0.key == name }) {
                    servers[index] = JSONMember(key: name, value: .object(entry))
                } else {
                    servers.append(JSONMember(key: name, value: .object(entry)))
                }
            }
            deps.upstreams = try ConfigEdit.reload(
                path: deps.configPath, fileSystem: deps.fileSystem
            )
        } catch {
            return .error(500, "\(error)")
        }

        var reply: [JSONMember] = [
            JSONMember(key: "added", value: .string(name)),
            JSONMember(key: "tools", value: .number(Double(outcome.tools)))
        ]
        if let error = outcome.error {
            reply.append(JSONMember(key: "error", value: .string(JSString(error))))
        }
        reply.append(JSONMember(key: "needsAuth", value: .bool(authPending)))
        return .json(201, .object(reply))
    }

    // MARK: - /servers/:name

    private func dispatchServer(
        route: ServerRoute,
        upstream: UpstreamConfig,
        name: JSString,
        request: ControlRequest,
        deps: inout ControlDeps
    ) async -> ControlResponse? {
        switch (route.sub, request.method) {
        case (nil, "GET"):
            return .json(200, Describe.row(upstream, deps))

        case (nil, "DELETE"):
            return removeServer(name: name, request: request, deps: &deps)

        case (nil, "PATCH"):
            return patch(request, name: name, deps: &deps)

        case ("/reindex", "POST"):
            let outcome = await deps.indexer.index(upstream)
            var reply: [JSONMember] = [
                JSONMember(key: "name", value: .string(name)),
                JSONMember(key: "tools", value: .number(Double(outcome.tools)))
            ]
            // Forwarded verbatim, and omitted only when undefined — so an `error: ""` yields 200
            // and still carries `"error":""` (B33, S1, S3).
            if let error = outcome.error {
                reply.append(JSONMember(key: "error", value: .string(JSString(error))))
            }
            let failed = outcome.error?.isJSTruthyString ?? false
            return .json(failed ? 422 : 200, .object(reply))

        case ("/changes", "GET"):
            // The in-memory snapshot, never a disk read, and observationally read-only (B35).
            let entry = deps.manifest.entry(named: name.string)
            let pending = entry?.pending?.isTruthy == true
            var members: [JSONMember] = [
                JSONMember(key: "server", value: .string(name)),
                JSONMember(key: "pending", value: .bool(pending))
            ]
            if let seenAt = entry?.pending?.member("seenAt") {
                members.append(JSONMember(key: "seenAt", value: seenAt))
            }
            var changes: [ToolChange] = []
            if pending, let entry {
                changes = DiffTools.diff(before: entry.tools, after: entry.pendingTools)
            }
            members.append(JSONMember(
                key: "changes", value: .array(changes.map(\.value))
            ))
            return .json(200, .object(members))

        case ("/auth", "DELETE"):
            let had = deps.auth.clear(name)
            deps.pool.clearPending(name)
            return .json(200, .object([
                JSONMember(key: "server", value: .string(name)),
                JSONMember(key: "signedOut", value: .bool(had))
            ]))

        default:
            return nil
        }
    }

    /// edit → reload → clearAuth → forget, in that order and no other (B32). A failure at any
    /// step prevents every later one, which is why this is a sequence rather than a transaction
    /// that reaches the same end state.
    private func removeServer(
        name: JSString, request: ControlRequest, deps: inout ControlDeps
    ) -> ControlResponse {
        do {
            try ConfigEdit.edit(path: deps.configPath, fileSystem: deps.fileSystem) { servers in
                servers.removeAll { $0.key == name }
            }
            deps.upstreams = try ConfigEdit.reload(
                path: deps.configPath, fileSystem: deps.fileSystem
            )
        } catch {
            return .error(500, "\(error)")
        }
        deps.auth.clear(name)
        if request.first(named: "keepHistory") != "1" { deps.usage.forget(name.string) }
        return .json(200, .object([JSONMember(key: "removed", value: .string(name))]))
    }

    /// Editing the operational fields only.
    ///
    /// **`command`, `args` and `env` are simply not read.** Not rejected — ignored, which is the
    /// distinction that matters: a handler that 400s on their presence satisfies a naive reading of
    /// the guarantee while diverging from a reference that returns 200 and applies the allowed
    /// sibling fields (B40).
    private func patch(
        _ request: ControlRequest, name: JSString, deps: inout ControlDeps
    ) -> ControlResponse {
        let body = request.bodyObject
        func supplied(_ key: String) -> JSONValue?? {
            let target = JSString(key)
            guard let member = body.first(where: { $0.key == target }) else { return nil }
            return .some(member.value)
        }

        do {
            try ConfigEdit.edit(path: deps.configPath, fileSystem: deps.fileSystem) { servers in
                guard let index = servers.firstIndex(where: { $0.key == name }),
                      var entry = servers[index].value.asObjectMembers else { return }

                func set(_ key: String, _ value: JSONValue?) {
                    let target = JSString(key)
                    guard let value else {
                        // `undefined` removes the member — it does **not** write null (B42).
                        entry.removeAll { $0.key == target }
                        return
                    }
                    if let at = entry.firstIndex(where: { $0.key == target }) {
                        entry[at] = JSONMember(key: target, value: value)
                    } else {
                        entry.append(JSONMember(key: target, value: value))
                    }
                }

                // The fixed order `projects, warm, idleMs, placard`, each gated on key presence.
                if let projects = supplied("projects") {
                    // `b.projects?.length ? b.projects : undefined` — the raw value is stored when
                    // its `length` reads truthy, so a string survives (B42). An `asArray` test here
                    // would drop `projects: "x"`, which the reference keeps.
                    set("projects", (projects?.jsLengthIsTruthy ?? false) ? projects : nil)
                }
                if let warm = supplied("warm") {
                    set("warm", (warm?.isTruthy ?? false) ? warm : nil)
                }
                if let idleMs = supplied("idleMs") {
                    // Assigned as given, including 0 and null — the reference's one inconsistency
                    // among these four, ported rather than tidied (P2).
                    set("idleMs", idleMs)
                }
                if let placard = supplied("placard") {
                    set("placard", placard)
                }
                servers[index] = JSONMember(key: name, value: .object(entry))
            }
            deps.upstreams = try ConfigEdit.reload(
                path: deps.configPath, fileSystem: deps.fileSystem
            )
        } catch {
            return .error(500, "\(error)")
        }

        // Requested, never awaited: a warming failure must not turn this 200 into an error.
        if body.first(where: { $0.key == JSString("warm") })?.value.isTruthy == true {
            deps.pool.warmUp()
        }
        guard let reloaded = deps.upstream(named: name) else {
            return .error(404, "no server named \"\(name.string)\"")
        }
        return .json(200, Describe.row(reloaded, deps))
    }
}

/// `^/servers/([^/]+)(/[a-z]+)?$` — the sub-path is **lowercase only**, so `/servers/x/Reindex`
/// does not match and reaches the 405 fallback (B23).
struct ServerRoute {
    let rawName: String
    let sub: String?

    init?(encodedPath: String) {
        guard encodedPath.hasPrefix("/servers/") else { return nil }
        let rest = String(encodedPath.dropFirst("/servers/".count))
        guard !rest.isEmpty else { return nil }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard !parts[0].isEmpty else { return nil }
            rawName = String(parts[0])
            sub = nil
        case 2:
            guard !parts[0].isEmpty, !parts[1].isEmpty,
                  parts[1].allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter })
            else { return nil }
            rawName = String(parts[0])
            sub = "/" + String(parts[1])
        default:
            return nil
        }
    }

    /// `decodeURIComponent` — nil on a malformed escape, which the reference turns into a thrown
    /// `URIError` rather than a 404.
    var decodedName: JSString? {
        guard let decoded = rawName.removingPercentEncoding else { return nil }
        return JSString(decoded)
    }
}

extension String {
    /// JavaScript truthiness for a string: everything except the empty one.
    var isJSTruthyString: Bool { !isEmpty }
}
