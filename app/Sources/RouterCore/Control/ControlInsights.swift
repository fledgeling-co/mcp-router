import Foundation

/// Resident set size for one live child, as the pool measured it.
public struct ResidentReading: Sendable, Hashable {
    public let server: String
    public let megabytes: Int

    public init(server: String, megabytes: Int) {
        self.server = server
        self.megabytes = megabytes
    }
}

/// The two readings only the pool can take: how much memory its children hold, and how long each
/// of them has been alive.
///
/// Separate from ``UpstreamPoolPort`` because both are `async` — the pool is an actor and neither
/// figure can be snapshotted usefully ahead of a request, since `residentMb()` shells out to `ps`
/// and a stale duty cycle is a wrong one. Optional on ``ControlDeps`` for the reason the registry
/// client is: `ControlDiff`, the in-process differential oracle, has no pool to attach.
public protocol InsightsSource: Sendable {
    /// One entry per live child **with a process**. An upstream with none is omitted rather than
    /// reported as zero, which is what `residentMb()` already does and why: a zero is a
    /// measurement and this is an absence.
    func resident() async -> [ResidentReading]
    func dutyCycle() async -> DutyCycleReading
}

/// `GET /insights` — every number on the Insights board, and nothing else.
///
/// **Each member is counted, and the ones that cannot be are absent rather than zero.** That rule
/// is the whole reason this route is shaped the way it is: `resident` is null when no child has a
/// process, a harness whose calls the router cannot attribute carries `calls: null` with the
/// reason, and there is no saving figure anywhere, because the router never ran the world it would
/// have to be subtracted from (`DESIGN.md` §6).
///
/// It **diverges from `src/control.ts`**, which answers this path 404. Declared as
/// `div-m22-insights` in `planning/parity/surface.tsv` and asserted at both binaries.
extension ControlHandler {
    /// The window every count on this route is taken over.
    ///
    /// Fixed rather than a query parameter, and the reason is the log rather than the API: the
    /// usage log rotates at 8 MiB keeping one generation, so what a router can answer for is
    /// whatever survived. `logHorizon` reports the oldest record actually read, which is what lets
    /// a board say what it covered instead of implying it covered the whole day.
    static let insightsWindowHours = 24

    func insightsResponse(_ deps: ControlDeps) async -> ControlAPIResponse {
        let now = deps.clock.nowMilliseconds
        let window = deps.usage.insights(
            nowMilliseconds: now, windowHours: Self.insightsWindowHours
        )

        var members: [JSONMember] = [
            JSONMember(
                key: JSString("generatedAt"),
                value: .string(JSString(JSDate.iso8601(milliseconds: now)))
            ),
            JSONMember(
                key: JSString("windowHours"), value: .number(Double(Self.insightsWindowHours))
            ),
            JSONMember(
                key: JSString("windowStart"),
                value: .string(JSString(
                    JSDate.iso8601(milliseconds: window.windowStartMilliseconds)
                ))
            ),
            JSONMember(
                key: JSString("logHorizon"),
                value: window.horizon.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("children"), value: .object([
                JSONMember(
                    key: JSString("alive"),
                    value: .number(Double(deps.pool.status().count { $0.state == "running" }))
                ),
                JSONMember(
                    key: JSString("declared"), value: .number(Double(deps.config.upstreams.count))
                )
            ])),
            JSONMember(key: JSString("calls"), value: .object([
                JSONMember(key: JSString("total"), value: .number(Double(window.totalCalls))),
                JSONMember(key: JSString("failed"), value: .number(Double(window.failedCalls))),
                // What the reader could not use. A count of what parsed is not a count of what was
                // there, and a surface that shows the first as the second is reporting a number it
                // has not established.
                JSONMember(
                    key: JSString("unreadableLines"), value: .number(Double(window.unreadableLines))
                )
            ]))
        ]

        let resident = await residentValue(deps)
        let duty = await dutyCycleValue(deps)
        members.append(JSONMember(key: JSString("resident"), value: resident))
        members.append(contentsOf: harnessCallMembers(window, deps))
        members.append(JSONMember(key: JSString("dutyCycle"), value: duty))
        members.append(JSONMember(key: JSString("callsPerHour"), value: .array(
            window.hours.map { hour in
                .object([
                    JSONMember(
                        key: JSString("hourStart"),
                        value: .string(JSString(
                            JSDate.iso8601(milliseconds: hour.startMilliseconds)
                        ))
                    ),
                    JSONMember(key: JSString("calls"), value: .number(Double(hour.calls)))
                ])
            }
        )))
        // The session analyst `PRD.md` §6 specifies does not exist in `app/Sources` in any form.
        // The member is present and null rather than absent, so a board renders its empty state
        // from a fact the router stated instead of from a key it failed to find.
        members.append(JSONMember(key: JSString("analyst"), value: .null))

        return .json(200, .object(members))
    }

    private func residentValue(_ deps: ControlDeps) async -> JSONValue {
        guard let source = deps.insights else { return .null }
        let readings = await source.resident()
        guard !readings.isEmpty else { return .null }
        return .object([
            JSONMember(
                key: JSString("megabytes"),
                value: .number(Double(readings.reduce(0) { $0 + $1.megabytes }))
            ),
            JSONMember(key: JSString("children"), value: .number(Double(readings.count)))
        ])
    }

    private func dutyCycleValue(_ deps: ControlDeps) async -> JSONValue {
        guard let source = deps.insights else { return .null }
        let reading = await source.dutyCycle()
        return .object([
            JSONMember(
                key: JSString("uptimeSeconds"),
                value: .number(Double(jsRound(reading.uptimeMilliseconds / 1000)))
            ),
            JSONMember(key: JSString("servers"), value: .array(reading.servers.map { server in
                .object([
                    JSONMember(key: JSString("server"), value: .string(JSString(server.name))),
                    JSONMember(
                        key: JSString("aliveSeconds"),
                        value: .number(Double(jsRound(server.aliveMilliseconds / 1000)))
                    )
                ])
            }))
        ])
    }

    /// One bar per detected harness, plus what is left over.
    ///
    /// **A row is drawn for every detected harness, including the ones at zero**, because the zero
    /// row is the finding: a harness at zero is one still calling its own servers rather than this
    /// endpoint, which is the same thing the Harnesses board says from the other side.
    ///
    /// **And a row that cannot be counted carries `null`, never `0`.** The router observes the peer
    /// *process*, not the harness; ``ClientProcessName`` records what each harness's calls look
    /// like and how that was established, and a harness whose name is shared — `node`, or the one
    /// `codex` binary behind two config files — is not attributable at all. A zero there would be
    /// a fabricated finding, which is worse than no bar.
    ///
    /// `otherCalls` is the remainder, so the bars and the headline total reconcile instead of
    /// quietly disagreeing.
    private func harnessCallMembers(
        _ window: UsageInsights, _ deps: ControlDeps
    ) -> [JSONMember] {
        guard let source = deps.harnesses else {
            return [
                JSONMember(key: JSString("callsByHarness"), value: .array([])),
                JSONMember(key: JSString("otherCalls"), value: .number(Double(window.totalCalls)))
            ]
        }
        let reports = source.reports(
            upstreams: deps.upstreams.map(\.upstream), port: deps.config.port
        )
        var attributed = 0
        var rows: [JSONValue] = []
        for report in reports {
            let naming = ClientProcessName.known(for: report.client)
            var row: [JSONMember] = [
                JSONMember(
                    key: JSString("harness"), value: .string(JSString(report.client.rawValue))
                ),
                JSONMember(
                    key: JSString("displayName"),
                    value: .string(JSString(report.client.displayName))
                )
            ]
            if let name = naming.attributableName {
                let calls = window.callers.first { $0.client == name }?.calls ?? 0
                attributed += calls
                row.append(JSONMember(key: JSString("calls"), value: .number(Double(calls))))
                row.append(JSONMember(key: JSString("reason"), value: .null))
            } else {
                row.append(JSONMember(key: JSString("calls"), value: .null))
                row.append(JSONMember(
                    key: JSString("reason"),
                    value: .string(JSString(naming.unattributableReason ?? ""))
                ))
            }
            rows.append(.object(row))
        }
        return [
            JSONMember(key: JSString("callsByHarness"), value: .array(rows)),
            JSONMember(
                key: JSString("otherCalls"),
                value: .number(Double(max(0, window.totalCalls - attributed)))
            )
        ]
    }
}
