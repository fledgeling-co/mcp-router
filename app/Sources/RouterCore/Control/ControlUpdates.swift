import Foundation

/// `GET /extensions/updates` — F6.
///
/// **A `GET`, and the family has no other verb.** The brief's own assumption — *update checks are
/// read-only until the user approves the update* — is held by there being nothing to call, not by a
/// flag anyone can pass. Installing is R29's and R30's territory and is not reachable from here.
///
/// The route answers eight verdicts rather than a list of available updates, and the reason is a
/// measurement rather than caution. Taken on this machine on 2026-08-29 by
/// `planning/evidence/F6/measure-update-surface.py` over all 127 installed plugins: the mechanism
/// the brief names — a version delta against the marketplace catalogue — produces **zero** updates,
/// and the one difference it does find points the wrong way (held 2.0.0, offered 1.0.0). Meanwhile
/// 557 of the 763 offers across ten catalogues declare no version at all. A route that reported
/// that as *0 updates, everything current* would be indistinguishable from one that had read
/// nothing, so `compared` and `uncomparable` are both in the summary and `catalogueBehind` is its
/// own state.
///
/// It **diverges from `src/control.ts`**, which answers the path 404, declared in
/// `planning/parity/surface.tsv` as `div-f6-updates` in the same way the `div-r28-*` and
/// `div-r31-*` rows are.
extension ControlHandler {
    func routeUpdates(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        // Claimed BEFORE `routeExtensions`, or `updates` parses as a kind and the route answers
        // `404 no extension kind named "updates"`. That ordering is the whole difference between
        // this route existing and not, and `ControlUpdateRoutesTests` asserts it in both
        // directions.
        guard path == "/extensions/updates" else { return nil }
        guard let store = deps.extensions else {
            // The sentence the rest of the `/extensions` family answers when its one dependency is
            // absent: name the missing capability rather than report an empty inventory, which a
            // router holding nothing would be indistinguishable from.
            return .error(503, "extension storage is unavailable: this router has no store")
        }
        guard request.method == "GET" else { return nil }

        var kinds = ExtensionKind.allCases
        if let requested = request.first(named: "kind") {
            guard let kind = ExtensionKind(rawValue: requested) else {
                return .error(404, "no extension kind named \"\(requested)\"")
            }
            kinds = [kind]
        }
        let staleAfter: Double
        switch Self.staleAfterMilliseconds(request.first(named: "staleAfterMs")) {
        case let .some(value): staleAfter = value
        // A window that cannot be read is refused rather than replaced by the default. A caller who
        // typed `staleAfterMs=1h` asked a question, and answering the default one silently would
        // report every catalogue fresh against a window they did not choose.
        case .none: return .error(400, "staleAfterMs must be a non-negative whole number of milliseconds")
        }
        let report = ExtensionFreshnessScan.build(
            store: store,
            kinds: kinds,
            staleAfterMilliseconds: staleAfter,
            now: deps.clock.nowMilliseconds,
            name: request.first(named: "name")
        )
        return .json(200, Self.freshnessValue(report))
    }

    /// `nil` for a value that is present and unreadable; the default for one that is absent.
    static func staleAfterMilliseconds(_ raw: String?) -> Double? {
        guard let raw else { return ExtensionFreshnessScan.defaultStaleAfterMilliseconds }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Double(raw)
        else { return nil }
        return value
    }
}
