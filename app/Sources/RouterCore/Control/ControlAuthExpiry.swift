import Foundation

/// Reading upstream credential expiry, and taking the notifications that are due — R26.
///
/// Two routes, and the split between them is the split between reading and consuming:
///
/// * `GET /upstreams/auth-expiry` — every declared upstream's derived credential state.
/// * `POST /upstreams/auth-expiry/notify` — the notices due now, with the throttle advanced.
///
/// **Both diverge from `src/control.ts`**, which claims neither path in `isControlPath`, so both
/// fall through to `/mcp` and answer 404. Declared in `planning/parity/surface.tsv` as
/// `div-r26-inventory` and `div-r26-notify`, the way the `div-r27-*` and `div-r22-*` families are,
/// rather than left to be discovered by a lane.
///
/// **The second is a POST and it changes no upstream**, which is the same shape
/// `POST /diagnostics/bundle` records about itself: the verb selects the token gate, because stage
/// 2 of ``ControlHandler/handle(_:_:)`` reads the token only for POST, DELETE and PATCH. It is also
/// honest about this one — claiming a notice advances a throttle held by the daemon, so a second
/// caller does not get the same alert. A GET that did that would silence the next notification for
/// anybody who merely opened a settings pane.
///
/// **Not `/servers/:name/auth-expiry`.** The whole value of the collection is that it answers *what
/// should I be told about*, which is a question about the fleet; a per-server path would make the
/// caller enumerate and would give the throttle nothing to be a throttle over.
extension ControlHandler {
    func routeAuthExpiry(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) async -> ControlAPIResponse? {
        switch (path, request.method) {
        case ("/upstreams/auth-expiry", "GET"):
            await authExpiryReport(deps)
        case ("/upstreams/auth-expiry/notify", "POST"):
            await authExpiryNotices(deps)
        default:
            nil
        }
    }

    /// The two families that answer questions about the upstreams themselves rather than about
    /// what the router holds: R27's health and R26's credential expiry.
    ///
    /// One arm in ``routeReading(_:_:_:)`` rather than two, and that is a constraint rather than a
    /// preference — `ControlHandler.swift` records that adding M22's two routes inline took
    /// `handle` to complexity 12 against a cap of 10, and R26's route took `routeReading` to 13 the
    /// same way. Grouping them here is the same repair applied a second time, and the grouping is
    /// real: both answer *what is the state of the thing on the other end*, and both are declared
    /// divergences from `src/control.ts` rather than routes it also serves.
    func routeUpstreams(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) async -> ControlAPIResponse? {
        if let response = await routeHealth(path, request, deps) { return response }
        return await routeAuthExpiry(path, request, deps)
    }

    private func authExpiryReport(_ deps: ControlDeps) async -> ControlAPIResponse {
        guard let expiry = deps.authExpiry else { return Self.authExpiryUnavailable }
        let now = deps.clock.nowMilliseconds
        let report = await expiry.report(manifest: deps.manifest, nowMilliseconds: now)
        return .json(200, .object([
            JSONMember(key: "count", value: .number(Double(report.records.count))),
            JSONMember(key: "at", value: .string(JSString(JSDate.iso8601(milliseconds: now)))),
            JSONMember(key: "policy", value: Self.expiryPolicyValue(report.policy)),
            JSONMember(
                key: "refusals", value: .array(report.refusals.map(Self.expiryRefusalValue))
            ),
            JSONMember(
                key: "upstreams", value: .array(report.records.map(Self.expiryRecordValue))
            )
        ]))
    }

    private func authExpiryNotices(_ deps: ControlDeps) async -> ControlAPIResponse {
        guard let expiry = deps.authExpiry else { return Self.authExpiryUnavailable }
        let now = deps.clock.nowMilliseconds
        let notices = await expiry.claim(manifest: deps.manifest, nowMilliseconds: now)
        return .json(200, .object([
            JSONMember(key: "count", value: .number(Double(notices.count))),
            JSONMember(key: "at", value: .string(JSString(JSDate.iso8601(milliseconds: now)))),
            JSONMember(key: "notices", value: .array(notices.map(Self.expiryNoticeValue)))
        ]))
    }

    /// The shape `/harnesses`, `/extensions`, `/caches` and `/upstreams/health` use when the one
    /// dependency is absent: name the missing capability rather than answer an empty inventory,
    /// which a router holding no credentials at all would be indistinguishable from.
    static var authExpiryUnavailable: ControlAPIResponse {
        .error(503, "auth expiry is unavailable: this router has no auth expiry monitor")
    }
}
