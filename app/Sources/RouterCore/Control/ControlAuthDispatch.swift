import Foundation

/// The control API's **auth surface**: `POST /servers/:name/approve` and
/// `POST /servers/:name/auth`, plus the completion sink the second one installs.
///
/// Split out of `ControlHandler.swift` for the reason the usage routes were split out of the type's
/// body — length. That file sits at the edge of the 400-line file warning, and these two routes are
/// a coherent seam of their own: they are the two the reference dispatches through `AuthRoutes`
/// rather than answering inline. Unlike the usage split these are a **different file**, so they are
/// `internal` rather than `private`; nothing outside the module calls them.
///
/// ## Why this file exists at all — `D-j`
///
/// ``AuthRoutes/approve(server:manifestPath:fileSystem:nowMilliseconds:log:)`` and
/// ``AuthRoutes/authStart(server:isStdio:sink:begin:awaitCompletion:)`` were both written by R5,
/// both unit-tested, and both called by nothing: `dispatchServer`'s switch carried `("/auth",
/// "DELETE")` and no POST arm at all. A fixture suite and a unit suite therefore both passed while
/// the wire answered 405 to two routes the reference answers — which is the failure mode a port is
/// most likely to ship, because every check that could catch it is on the wrong side of the seam.
extension ControlHandler {
    /// The auth family's own dispatch table: `/approve` POST, `/auth` POST and `/auth` DELETE.
    ///
    /// `nil` means "not one of these, or one this router cannot serve", and the caller carries that
    /// on to its own switch and then to the 405.
    ///
    /// The DELETE arm moved here from `dispatchServer` unchanged. That was not tidying: adding the
    /// two POST arms took `dispatchServer` to cyclomatic complexity 12 against a cap of 10, and the
    /// house rule is to split on a real seam rather than raise a limit. This is the real seam — the
    /// three routes the reference answers through `AuthRoutes` and the credential store rather than
    /// inline — and `control-differential.sh` compares all three against the running reference, so a
    /// move that changed behaviour could not pass.
    func dispatchAuth(
        route: ServerRoute,
        upstream: UpstreamConfig,
        name: JSString,
        request: ControlAPIRequest,
        deps: ControlDeps
    ) async -> ControlAPIResponse? {
        switch (route.sub, request.method) {
        case ("/approve", "POST"):
            return await approveToolSurface(name: name, deps: deps)

        case ("/auth", "POST"):
            return await authorize(upstream: upstream, name: name, deps: deps)

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

    /// `POST /servers/:name/approve`.
    ///
    /// Every argument is already on `deps`; the route was never dispatched, not never implemented.
    /// `manifestPath` comes from the **config** rather than from `deps.manifest`, because the
    /// reference reads the file fresh here and uses its cached copy two blocks above in `/changes` —
    /// a port that shares the cache diverges whenever the cache is stale (B88).
    func approveToolSurface(name: JSString, deps: ControlDeps) async -> ControlAPIResponse {
        let result = await AuthRoutes.approve(
            server: name,
            manifestPath: deps.config.manifestPath,
            fileSystem: deps.fileSystem,
            nowMilliseconds: deps.clock.nowMilliseconds,
            log: deps.log
        )
        return .json(result.status, result.body)
    }

    /// `POST /servers/:name/auth`.
    ///
    /// Returns `nil` — falling through to the 405 — for exactly one case: a **non-stdio** upstream
    /// with **no flow starter configured**. The daemon always configures one since P7, so on the
    /// wire this is now only `ControlDiff`, which supplies none on purpose. It is deliberately not
    /// a 502:
    ///
    /// - the reference's 502 means `beginAuth` *ran and threw* (a bind failure, or the 20-second
    ///   URL race). Reusing it for "no starter was ever constructed" makes two different failures
    ///   indistinguishable to the one reader who needs them apart;
    /// - 502 is the retryable gateway class, so `LiveControlAPIClient.beginAuthorization` and
    ///   `mcp-router auth` would invite a user to retry something that can never succeed;
    /// - it would be a **new** divergence on every http and oauth upstream, introduced by a change
    ///   whose whole purpose is removing one.
    ///
    /// The stdio refusal needs no starter — it is `authStart`'s own first branch and returns before
    /// any flow begins or any port is bound — so it is answered either way. When a starter does
    /// arrive, the full path works with no further change here.
    func authorize(
        upstream: UpstreamConfig, name: JSString, deps: ControlDeps
    ) async -> ControlAPIResponse? {
        guard upstream.isStdio || deps.authFlow != nil else { return nil }
        let starter = deps.authFlow
        let result = await AuthRoutes.authStart(
            server: name,
            isStdio: upstream.isStdio,
            sink: ControlAuthSink(
                pool: deps.pool, indexer: deps.indexer, upstream: upstream, log: deps.log
            ),
            begin: {
                // Unreachable: the guard above returned for the only case where `starter` is nil.
                // Written as a throw rather than a force-unwrap because `force_unwrapping` is on,
                // and because a 502 is the honest answer if this ever does become reachable.
                guard let starter else { throw AuthFailure(ControlAuthSink.noStarter) }
                return try await starter.begin(server: name, upstream: upstream)
            },
            awaitCompletion: {
                guard let starter else { throw AuthFailure(ControlAuthSink.noStarter) }
                try await starter.awaitCompletion(server: name)
            }
        )
        return .json(result.status, result.body)
    }
}

/// What happens when a browser authorization finishes: the reference's `.then` and `.catch`, over
/// collaborators ``ControlDeps`` already carries.
struct ControlAuthSink: AuthRoutes.CompletionSink {
    static let noStarter = "no authorization transport is configured"

    let pool: any UpstreamPoolPort
    let indexer: any UpstreamIndexerPort
    /// Captured at **request** time, exactly as the reference closes over `u`. A config reload
    /// between the 200 and the callback must not re-index a different server than the one the user
    /// authorized.
    let upstream: UpstreamConfig
    let log: RouterLog?

    /// `deps.pool.clearPending(name)` **then** `await indexOne(u, deps.cfg)` — that order, and only
    /// on success. Re-indexing is what makes the newly-reachable tools appear without the user
    /// having to know that indexing is a thing that exists.
    func onAuthorized(server: JSString) async {
        pool.clearPending(server)
        _ = await indexer.index(upstream)
    }

    /// One warn line and nothing else (B79). The flow's rejection and a failing re-index both land
    /// here, and neither may clear the pending marker: a server whose authorization did not
    /// complete is still waiting on one.
    ///
    /// `AuthAbandoned` never reaches this — `authStart` swallows it without calling either method,
    /// because the reference runs neither its `.then` nor its `.catch` for a superseded flow (B85).
    func onIncomplete(server: JSString, reason: String) async {
        await log?.log(.authorizationIncomplete(server: server.string, reason: reason))
    }
}

extension ControlHandler {
    /// `GET /servers/:name/changes` — the reading half of the quarantine surface.
    ///
    /// Here rather than in `ControlHandler.swift` for two reasons that agree. The seam: `/changes`
    /// reports what a server started advertising and `/approve`, immediately above, promotes it —
    /// they are one surface read from two sides, and `/approve` already lives here. The
    /// constraint: `dispatchServer` is capped at cyclomatic complexity 10, this body carried three
    /// of its branch points, and R27's `/probe` arm took the total to 11; moving a whole route out
    /// is a seam, while raising the cap to pay for an arm is not.
    func changesResponse(name: JSString, deps: ControlDeps) -> ControlAPIResponse {
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
        members.append(JSONMember(key: "changes", value: .array(changes.map(\.value))))
        return .json(200, .object(members))
    }
}
