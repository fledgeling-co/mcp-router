import Foundation

/// One health record as JSON — R27.
///
/// Hand-built out of ``JSONMember`` rather than encoded from a `Codable`, which
/// `scripts/lint/no-wire-codable.sh` enforces across this whole surface: member order is part of
/// what the parity gate compares, and `JSONEncoder` does not promise one.
extension ControlHandler {
    static func healthValue(_ record: UpstreamHealthRecord) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "server", value: .string(JSString(record.server))),
            JSONMember(key: "state", value: .string(JSString(record.state.rawValue))),
            JSONMember(key: "probesRun", value: .number(Double(record.probesRun))),
            JSONMember(
                key: "consecutiveFailures", value: .number(Double(record.consecutiveFailures))
            )
        ]
        // Absent rather than null when nothing has been measured. A `lastProbe` of null and a
        // `lastProbe` carrying a failure are both "something is wrong" to a careless reader; an
        // absent member is not there to be misread.
        if let outcome = record.lastOutcome, let atMs = record.lastProbeAtMs {
            members.append(JSONMember(key: "lastProbe", value: outcomeValue(outcome, atMs: atMs)))
        }
        if let okMs = record.lastOkAtMs {
            members.append(JSONMember(
                key: "lastOkAt", value: .string(JSString(JSDate.iso8601(milliseconds: okMs)))
            ))
        }
        if let declined = record.lastDeclined {
            members.append(JSONMember(key: "declined", value: .string(JSString(declined))))
        }
        members.append(JSONMember(key: "policy", value: policyValue(record.policy)))
        members.append(JSONMember(
            key: "refusals", value: .array(record.refusals.map(refusalValue))
        ))
        return .object(members)
    }

    static func outcomeValue(_ outcome: ProbeOutcome, atMs: Double) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "outcome", value: .string(JSString(outcome.kind))),
            JSONMember(key: "at", value: .string(JSString(JSDate.iso8601(milliseconds: atMs))))
        ]
        switch outcome {
        case let .ok(latencyMs, tools):
            members.append(JSONMember(key: "latencyMs", value: .number(Double(latencyMs))))
            members.append(JSONMember(key: "tools", value: .number(Double(tools))))
        case let .timedOut(afterMs):
            members.append(JSONMember(key: "afterMs", value: .number(Double(afterMs))))
        case let .failed(reason):
            members.append(JSONMember(key: "reason", value: .string(JSString(reason))))
        case let .declined(reason):
            // Unreachable through ``healthValue(_:)``, which only reaches here for an outcome that
            // was actually attempted. Written out rather than defaulted so a later caller that
            // hands this a decline gets the reason rather than a bare word.
            members.append(JSONMember(key: "reason", value: .string(JSString(reason))))
        }
        return .object(members)
    }

    static func policyValue(_ policy: HealthPolicy) -> JSONValue {
        .object([
            JSONMember(key: "probeIntervalMs", value: .number(Double(policy.probeIntervalMs))),
            JSONMember(key: "probeTimeoutMs", value: .number(Double(policy.probeTimeoutMs))),
            JSONMember(key: "tripAfter", value: .number(Double(policy.tripAfter)))
        ])
    }

    static func refusalValue(_ refusal: HealthPolicyRefusal) -> JSONValue {
        .object([
            JSONMember(key: "scope", value: .string(JSString(refusal.scope))),
            JSONMember(key: "key", value: .string(JSString(refusal.key))),
            JSONMember(key: "value", value: .number(Double(refusal.value))),
            JSONMember(key: "reason", value: .string(JSString(refusal.reason)))
        ])
    }
}
