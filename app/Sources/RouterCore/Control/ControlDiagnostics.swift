import Foundation

/// `GET /diagnostics` and `POST /diagnostics/bundle` — R22.
///
/// One action that gathers what somebody debugging a hung upstream would otherwise assemble by
/// hand: the router's recent log, every declared upstream with its live state and its cached tool
/// count, and the recent tool calls with their timings and errors.
///
/// **Both diverge from `src/control.ts`**, which claims neither path and answers both 404. Declared
/// in `planning/parity/surface.tsv` as the `div-r22-*` rows, the way the `div-r27-*`, `div-r31-*`
/// and `div-m22-*` families are, rather than left for a lane to discover.
///
/// ## Why the bundle is a POST when it changes nothing
///
/// It is not a mutation and the verb is not describing one. Stage 2 of ``ControlHandler/handle``
/// gates the token on `POST`/`DELETE`/`PATCH` only — `GET` is deliberately ungated, matching the
/// reference, and recorded there as a ported defect rather than quietly fixed. So the verb is the
/// only thing that decides whether this router hands its whole diagnostic corpus to any
/// unauthenticated caller that can open the loopback port, which per ``ControlToken`` includes a
/// web page the user merely visits. A `GET /diagnostics/bundle` would be that. The verb is chosen
/// for the gate it selects, and this comment is the reason so a later tidy-up does not undo it.
///
/// ## Why the preview is a GET, and what that costs it
///
/// The preview is a read that has to stay usable from anything. Being a `GET` it is **ungated**, so
/// the rule it is written to is: it discloses nothing that `GET /servers` does not already
/// disclose. Counts, category names, and key names — `Describe` publishes `envKeys` and
/// `headerKeys` already. No log line, no argument, no value, no shape.
extension ControlHandler {
    func routeDiagnostics(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        switch (path, request.method) {
        case ("/diagnostics", "GET"):
            .json(200, previewValue(deps))
        case ("/diagnostics/bundle", "POST"):
            .json(200, bundleValue(deps))
        default:
            nil
        }
    }

    /// The redaction machinery for this request, built from the config actually loaded.
    ///
    /// Rebuilt per request rather than held, because the config is reloaded under the handler when
    /// a server is added or removed: a needle set built once at startup would go stale in exactly
    /// the direction that matters, missing the token of the server somebody added this morning.
    func redaction(_ deps: ControlDeps) -> (SecretRedactor, HomePathElision) {
        let needles = SecretNeedles.collect(config: deps.config, controlToken: token)
        return (SecretRedactor(needles: needles), HomePathElision(home: RouterHome.resolvedHomeDirectory()))
    }
}
