import Foundation

/// `tools/call`: refuse, invoke, record.
///
/// Split out of `MCPEndpoint.swift` and then split again internally, because the single function
/// this began as did three unrelated jobs — decide whether the call may run at all, run it, and
/// attribute it — and read as one 80-line block in which the `do`/`catch` that must never rethrow
/// was the easiest thing to miss. Each of the three is now named, and the invariant that matters
/// (a failing upstream produces a tool error, never a thrown error) is visible in one function's
/// signature rather than inferred from the absence of a `throws`.
extension MCPEndpoint {
    /// What a call produced, and how it should be counted.
    ///
    /// `ok` is not `failure == nil` restated: a tool that answers with `isError: true` succeeded as
    /// a transport and failed as a tool, and the usage record has to say the second thing.
    private struct CallOutcome {
        var result: JSONValue
        var ok: Bool
        var failure: String?
    }

    func callTool(_ params: JSONValue?) async -> JSONValue {
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

        if let refusal = await refusal(server: serverName, tool: tool) {
            return refusal
        }

        let startedAt = deps.clock.nowMilliseconds
        // Read before the call: afterwards the upstream is live either way, so this is the only
        // moment at which "did this call pay the start-up cost" is knowable.
        let cold = await !deps.pool.isLive(serverName)
        let outcome = await invoke(tool: tool, on: serverName, arguments: arguments)
        await record(outcome, server: serverName, tool: tool, startedAt: startedAt, cold: cold)
        return outcome.result
    }

    /// The two ways a call is turned away before any upstream is reached, or `nil` to proceed.
    private func refusal(server serverName: String, tool: String) async -> JSONValue? {
        guard let upstream = deps.upstreams.first(where: { $0.name == serverName }) else {
            return nil
        }

        // A scoped or disabled server is not merely hidden from the list — it does not run for a
        // caller who cannot see it. Hiding alone would leave it callable by any agent that learned
        // the name from somewhere else.
        //
        // Two branches rather than one `isServed`, because the refusals send the reader to
        // different places and one message would be true and misleading. Disabled is asked first
        // for the reason `isServed` asks it first: a server that is both disabled and out of scope
        // is disabled, and naming the project would have its caller fix a scope that is not what
        // stopped them.
        let identity = await currentIdentity()
        if upstream.disabled == true {
            return Self.toolError(
                "Upstream \"\(serverName)\" is disabled. Enable it in MCP Router to use its tools."
            )
        }
        if !ToolUnion.visibleTo(upstream, cwd: identity.cwd) {
            let location = identity.cwd.map { " (\($0))" } ?? ""
            return Self.toolError(
                "Upstream \"\(serverName)\" is not available in this project\(location)."
            )
        }

        // A placarded server answers instead of running. The text is written for the model rather
        // than for a log: it names the fault and the substitute, so the assistant reroutes on this
        // attempt instead of spending the turn discovering that a tool cannot work.
        let entry = await deps.manifest.current().entry(named: serverName)
        guard let placard = ToolUnion.placardFor(upstream, entry: entry) else { return nil }
        var text = "Tool \"\(tool)\" is INOPERATIVE: \(placard.reason)."
        if let substitute = placard.substitute, !substitute.isEmpty {
            text += " Use \(substitute) instead."
        }
        text += " Do not retry this tool; it will keep returning this."
        return Self.toolError(text)
    }

    /// Run the tool on its upstream. This cannot throw: a dead upstream is a tool error, never a
    /// router crash, because one broken server must not take the other nine down with it.
    private func invoke(
        tool: String,
        on serverName: String,
        arguments: JSONValue
    ) async -> CallOutcome {
        do {
            // `lease`, not `acquire` then call: the pool has to know a request is outstanding or its
            // idle reaper closes the upstream mid-call.
            let lease = try await deps.pool.lease(serverName)
            let result: JSONValue
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
               fields.first(where: { $0.key == JSString("isError") })?.value.isTruthy == true
            {
                return CallOutcome(result: result, ok: false, failure: "tool reported an error")
            }
            return CallOutcome(result: result, ok: true, failure: nil)
        } catch {
            let reason = (error as? PoolError)?.message ?? "\(error)"
            await deps.log?.record(
                ServiceLogEvent.callFailed(server: serverName, tool: tool, reason: reason)
            )
            let body = Self.toolError(
                "Upstream \"\(serverName)\" failed to handle \"\(tool)\": \(reason)"
            )
            return CallOutcome(result: body, ok: false, failure: reason)
        }
    }

    /// Attribution, which runs after the result is on its way and swallows everything: it must never
    /// delay or break a call.
    private func record(
        _ outcome: CallOutcome,
        server serverName: String,
        tool: String,
        startedAt: Double,
        cold: Bool
    ) async {
        let elapsed = deps.clock.nowMilliseconds - startedAt
        let identity = await currentIdentity()
        deps.usage.record(UsageRecord(
            ts: JSDate.iso8601(milliseconds: startedAt),
            server: serverName,
            tool: tool,
            ok: outcome.ok,
            ms: elapsed,
            cold: cold,
            pid: identity.pid.map(Int32.init),
            cwd: identity.cwd,
            project: projectOf(identity.cwd),
            client: identity.client,
            err: outcome.failure
        ))
    }

    func currentIdentity() async -> CallerIdentity {
        await identify(currentConnection)
    }

    public func with(connection: ConnectionDescriptor) -> MCPEndpoint {
        var copy = self
        copy.currentConnection = connection
        return copy
    }
}
