import Foundation

/// Where `GET /invocations` reads its window from.
///
/// A port for the reason every other one in `ControlPorts` is: the interesting states — a corpus the
/// router was never pointed at, a transcript root that vanished, a ledger holding one boundary — are
/// states a developer's machine will not enter on request.
public protocol InvocationReporting: Sendable {
    /// The window, folded. `days` is whole days ending with the day in progress.
    func window(nowMilliseconds: Double, days: Int) -> CapabilityUseWindow
}

/// `GET /invocations` and `GET /invocations/export`.
///
/// **A Swift-only surface, declared rather than discovered**, in the way `div-m22-harnesses` and the
/// `div-r28-*` family are: `src/control.ts` answers every path here 404, so there is no reference to
/// diff bytes against and the rows in `planning/parity/surface.tsv` are hand-written.
///
/// **Absent, this family names what is missing rather than answering an empty window.** A router
/// that was never pointed at a transcript corpus and a machine on which nothing has ever run produce
/// the same empty table, and only one of them is a measurement. That is `/extensions`' 503 and it is
/// the same judgement.
///
/// **Nothing on this route sends anything anywhere.** The window is folded from files under
/// `<router home>` and under a corpus root the operator named; there is no upstream, no key and no
/// batch. `scripts/lint/no-telemetry-egress.sh` is what holds that true as the code changes.
extension ControlHandler {
    /// The default window. Seven days, matching the design of record's *Runs 7 d* column
    /// (`design/mcp-router-console.html:3494` at `08a24ed`) — and answerable here, where the mock's
    /// *Last 7 days*
    /// pop-up on the calls chart was not, because the invocation log does not rotate at 8 MiB the
    /// way `usage.jsonl` does. What it can actually reach is reported as `horizon` either way.
    static let invocationWindowDays = 7
    /// The widest window this route will fold. A day count arrives off the wire, and
    /// `UsageStore.recent`'s note records that `?limit=1e300` is reachable and unbounded there; a
    /// day count is multiplied into an array of buckets, so an unbounded one is an allocation a
    /// query string can ask for.
    static let invocationMaximumDays = 366

    func routeInvocations(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        guard path == "/invocations" || path == "/invocations/export" else { return nil }
        guard request.method == "GET" else { return nil }
        guard let reporter = deps.invocations else {
            return .error(
                503,
                "invocation history is unavailable: this router has not been pointed at a "
                    + "transcript corpus"
            )
        }
        let window = reporter.window(
            nowMilliseconds: deps.clock.nowMilliseconds,
            days: Self.requestedDays(request)
        )
        guard path == "/invocations/export" else {
            return .json(200, InvocationExport.json(window))
        }
        guard request.first(named: "format") == "csv" else {
            return .json(200, InvocationExport.json(window))
        }
        return Self.csv(InvocationExport.csv(window))
    }

    /// `?days=`, coerced the way every other numeric query parameter on this API is coerced.
    ///
    /// `JSToNumber.number` rather than `Double.init`, so `?days=` and `?days=abc` behave as they do
    /// on `/usage/recent` — and the result is clamped rather than trusted, because a bucket array is
    /// allocated from it.
    static func requestedDays(_ request: ControlAPIRequest) -> Int {
        guard let raw = request.first(named: "days") else { return invocationWindowDays }
        let number = JSToNumber.number(raw)
        guard number.isFinite, number >= 1 else { return invocationWindowDays }
        return Int(min(number, Double(invocationMaximumDays)))
    }

    /// `text/csv`, with the same three headers `json(_:_:)` sends and in the same order — including
    /// **no** `Access-Control-Allow-Origin`, so a page cannot read this back either.
    static func csv(_ text: String) -> ControlAPIResponse {
        let bytes = Array(text.utf8)
        return ControlAPIResponse(
            status: 200,
            headers: [
                ("content-type", "text/csv; charset=utf-8"),
                ("content-length", String(bytes.count)),
                ("cache-control", "no-store")
            ],
            body: .bytes(bytes),
            handled: true
        )
    }
}
