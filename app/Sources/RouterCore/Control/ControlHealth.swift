import Foundation

/// Reading and driving upstream health — R27.
///
/// Two routes, and the split between them is the split between observing and asking:
///
/// * `GET /upstreams/health` — every declared upstream's record, in configuration order.
/// * `POST /servers/:name/probe` — probe one now, and answer with what it found.
///
/// **Both diverge from `src/control.ts`**, which answers `/upstreams/health` 404 and falls through
/// to its own 405 on an unknown `/servers/:name/…` sub-path. Declared in
/// `planning/parity/surface.tsv` as the `div-r27-*` rows, the way the `div-r28-*`, `div-r31-*` and
/// `div-m22-*` families are, rather than left to be discovered by a lane.
///
/// **The collection is `/upstreams/health` and not `/health`** because the router already answers
/// `/health` — its own liveness, dispatched ahead of the control block and shared with the
/// reference. Extending that body would move a surface R4 diffs. And it is not `/servers/health`
/// either: that path parses as a server *named* `health`, so the two readings would be decided by
/// whether somebody had a server with that name.
public protocol UpstreamHealthReporting: Sendable {
    func snapshot() async -> [UpstreamHealthRecord]
    /// `nil` for a server this router does not declare.
    func probeNow(_ name: String) async -> UpstreamHealthRecord?
}

extension UpstreamHealthMonitor: UpstreamHealthReporting {}

extension ControlHandler {
    func routeHealth(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) async -> ControlAPIResponse? {
        guard path == "/upstreams/health" else { return nil }
        guard request.method == "GET" else { return nil }
        guard let health = deps.health else {
            // The shape `/harnesses`, `/extensions` and `/caches` use when the one dependency is
            // absent: name the missing capability rather than answer an empty inventory, which a
            // router that had probed nothing would be indistinguishable from.
            return .error(503, "upstream health is unavailable: this router has no health monitor")
        }
        let rows = await health.snapshot()
        return .json(200, .object([
            JSONMember(key: "count", value: .number(Double(rows.count))),
            JSONMember(key: "upstreams", value: .array(rows.map(Self.healthValue)))
        ]))
    }

    /// `POST /servers/:name/probe`.
    ///
    /// The name has already been decoded and looked up in the live map by `handle`, so a server
    /// this router does not declare is 404 before it reaches here. A monitor that answers `nil`
    /// for a name the config *does* carry is therefore a disagreement between two readings of the
    /// same config rather than a bad request, and it is reported as one instead of as a 404.
    func probeResponse(name: JSString, deps: ControlDeps) async -> ControlAPIResponse {
        guard let health = deps.health else {
            return .error(503, "upstream health is unavailable: this router has no health monitor")
        }
        guard let record = await health.probeNow(name.string) else {
            return .error(
                500,
                "the health monitor does not know \"\(name.string)\", which the server list declares"
            )
        }
        return .json(200, Self.healthValue(record))
    }
}
