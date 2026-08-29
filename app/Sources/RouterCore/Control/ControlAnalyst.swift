import Foundation

/// The analyst's three arms on the control API: the `analyst` member of `GET /insights`,
/// `POST /insights/analyse`, and `PATCH /insights/analyst`.
///
/// It **diverges from `src/control.ts`**, which answers the whole `/insights` family 404, and takes
/// that divergence from `div-m22-insights` rather than adding a second one: the reference has never
/// answered this path and never will, because the analyst reads local session stores the reference
/// has no reader for.
///
/// **`analyst` is `null` until the first run and an object afterwards, and neither is an error.**
/// `M22` shipped this member permanently null with a comment saying nothing implements one; what
/// changes here is that something does, so the null now means *not yet* rather than *not built*.
extension ControlHandler {
    /// **Null means the router has no analyst; an object with a null `ranAt` means it has one that
    /// has not run.** Collapsing the two would leave a board unable to tell *there is nothing to
    /// run* from *there is nothing to show yet*, which are the two states `DESIGN.md` §3.4 makes
    /// the whole difference between a dim control with a reason and a live one.
    func analystValue(_ deps: ControlDeps) async -> JSONValue {
        guard let analyst = deps.analyst else { return .null }
        return await AnalystJSON.envelope(run: analyst.lastRun(), settings: analyst.settings())
    }

    func routeAnalyst(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) async -> ControlAPIResponse? {
        switch (path, request.method) {
        case ("/insights/analyse", "POST"): await analyseNow(deps)
        case ("/insights/analyst", "PATCH"): await updateAnalyst(request, deps)
        default: nil
        }
    }

    private func analyseNow(_ deps: ControlDeps) async -> ControlAPIResponse {
        guard let analyst = deps.analyst else { return AnalystJSON.unavailable }
        switch await analyst.analyse() {
        case let .success(run):
            return await .json(200, AnalystJSON.envelope(run: run, settings: analyst.settings()))
        case let .failure(failure):
            switch failure {
            case .alreadyRunning:
                return .error(409, "an analysis is already running")
            case let .ladderExhausted(refusals):
                // 502 rather than 500: every rung is another program, and what failed is the
                // machine's own CLIs rather than this router. The refusals are carried out so the
                // surface can say WHICH model was unreachable instead of "the analyst failed".
                return .error(502, "no analyst model answered — \(refusals.joined(separator: "; "))")
            }
        }
    }

    private func updateAnalyst(
        _ request: ControlAPIRequest, _ deps: ControlDeps
    ) async -> ControlAPIResponse {
        guard let analyst = deps.analyst else { return AnalystJSON.unavailable }
        switch await analyst.update(.object(request.bodyObject)) {
        case let .success(settings):
            let run = await analyst.lastRun()
            return .json(200, AnalystJSON.envelope(run: run, settings: settings))
        case let .failure(refusal):
            return .json(422, .object([
                JSONMember(key: JSString("error"), value: .string(JSString(refusal.message))),
                JSONMember(key: JSString("member"), value: .string(JSString(refusal.member)))
            ]))
        }
    }
}

/// The analyst as JSON, built member by member through this repository's own stack.
enum AnalystJSON {
    /// The same shape `/registry/search` and `/harnesses` use when their one dependency is absent:
    /// name the missing capability, because an empty answer is indistinguishable from a router that
    /// analysed and found nothing — which is exactly the reading this route exists to make.
    static var unavailable: ControlAPIResponse {
        .error(503, "session analysis is unavailable: this router has no analyst")
    }

    static func lane(_ value: AnalystLane) -> JSONValue {
        .object([
            JSONMember(key: JSString("lane"), value: .string(JSString(value.rawValue))),
            JSONMember(key: JSString("model"), value: .string(JSString(value.model))),
            JSONMember(key: JSString("label"), value: .string(JSString(value.label)))
        ])
    }

    static func envelope(run: AnalystRunRecord?, settings: AnalystSettings) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: JSString("primary"), value: lane(settings.primary)),
            JSONMember(
                key: JSString("fallback"), value: settings.fallback.map(lane) ?? .null
            ),
            JSONMember(
                key: JSString("cadence"), value: .string(JSString(settings.cadence.rawValue))
            ),
            JSONMember(
                key: JSString("cadenceLabel"), value: .string(JSString(settings.cadence.label))
            ),
            // The one member on this route that says what the router does NOT do. `spec-F7.md` §2
            // records why: the cadence is a stored setting and nothing fires it, so a surface
            // drawing "Every 6 hours" beside a false `scheduled` is drawing a preference rather
            // than a promise. Omitting it would leave the readout indistinguishable from a
            // schedule.
            JSONMember(key: JSString("scheduled"), value: .bool(false)),
            JSONMember(
                key: JSString("nextRunAt"),
                value: settings.cadence.nextRunAt(after: run?.ranAtMilliseconds)
                    .map { JSONValue.string(JSString(JSDate.iso8601(milliseconds: $0))) } ?? .null
            )
        ]
        members.append(contentsOf: runMembers(run))
        return .object(members)
    }

    private static func runMembers(_ run: AnalystRunRecord?) -> [JSONMember] {
        guard let run else {
            // Not yet run: every figure absent rather than zero, for the reason the rest of
            // `/insights` reports an absent reading as null. A `linesRead: 0` here would be a
            // measurement of a run that never happened.
            return [
                JSONMember(key: JSString("lane"), value: .null),
                JSONMember(key: JSString("ranAt"), value: .null),
                JSONMember(key: JSString("stores"), value: .array([])),
                JSONMember(key: JSString("recent"), value: .array([]))
            ]
        }
        return [
            JSONMember(
                key: JSString("lane"), value: run.lane.map { lane($0) } ?? .null
            ),
            JSONMember(
                key: JSString("ranAt"),
                value: .string(JSString(JSDate.iso8601(milliseconds: run.ranAtMilliseconds)))
            ),
            JSONMember(key: JSString("linesRead"), value: .number(Double(run.linesRead))),
            JSONMember(key: JSString("discarded"), value: .number(Double(run.discardedLines))),
            JSONMember(key: JSString("findings"), value: .number(Double(run.findings.count))),
            JSONMember(key: JSString("usedFallback"), value: .bool(run.usedFallback)),
            JSONMember(
                key: JSString("rejectedFindings"), value: .number(Double(run.rejectedFindings))
            ),
            JSONMember(
                key: JSString("candidatesUnavailable"), value: .bool(run.candidatesUnavailable)
            ),
            JSONMember(
                key: JSString("stores"), value: .array(run.stores.map(AnalystStateCoding.store))
            ),
            JSONMember(
                key: JSString("recent"), value: .array(run.findings.map(finding))
            )
        ]
    }

    private static func finding(_ record: AnalystFindingRecord) -> JSONValue {
        .object([
            JSONMember(key: JSString("id"), value: .string(JSString(record.id))),
            JSONMember(key: JSString("entryID"), value: .string(JSString(record.entryID))),
            JSONMember(key: JSString("subject"), value: .string(JSString(record.subject))),
            JSONMember(key: JSString("sentence"), value: .string(JSString(record.sentence))),
            JSONMember(
                key: JSString("evidenceCount"), value: .number(Double(record.evidenceCount))
            ),
            JSONMember(
                key: JSString("judgedBy"), value: .string(JSString(record.judgedBy.label))
            ),
            JSONMember(
                key: JSString("signals"),
                value: .array(record.signals.map { .string(JSString($0)) })
            )
        ])
    }
}
