import Foundation

/// One auth-expiry record and one notice as JSON — R26.
///
/// Hand-built out of ``JSONMember`` rather than encoded from a `Codable`, which
/// `scripts/lint/no-wire-codable.sh` enforces across this whole surface: member order is part of
/// what the parity gate compares, and `JSONEncoder` does not promise one.
extension ControlHandler {
    static func expiryRecordValue(_ record: AuthExpiryRecord) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "server", value: .string(JSString(record.server))),
            JSONMember(key: "state", value: .string(JSString(record.state.rawValue))),
            JSONMember(key: "authCapable", value: .bool(record.authCapable)),
            JSONMember(key: "credentialHeld", value: .bool(record.hasAccessToken)),
            JSONMember(key: "refreshTokenHeld", value: .bool(record.hasRefreshToken)),
            JSONMember(key: "credentialRefused", value: .bool(record.credentialRefused))
        ]
        // Absent rather than null when the router does not know, and `state` already says so in a
        // word. A `expiresAt: null` beside a state of `unknown` invites a reader to treat the two
        // as one fact and round both to "fine"; an absent member is not there to be rounded.
        if let expiresAtMs = record.expiresAtMs {
            members.append(JSONMember(
                key: "expiresAt",
                value: .string(JSString(JSDate.iso8601(milliseconds: expiresAtMs)))
            ))
        }
        if let remaining = record.remainingMs {
            members.append(JSONMember(key: "remainingMs", value: .number(remaining.rounded())))
        }
        if let stamp = record.authorizedAtMs {
            members.append(JSONMember(
                key: "authorizedAt", value: .string(JSString(JSDate.iso8601(milliseconds: stamp)))
            ))
        }
        // Present exactly when `state` is `unknown`, and it is the member that makes "this router
        // does not know" a readable answer rather than a silence.
        if let reason = record.unknownReason {
            members.append(JSONMember(
                key: "unknownReason", value: .string(JSString(reason.rawValue))
            ))
        }
        return .object(members)
    }

    static func expiryNoticeValue(_ notice: AuthExpiryNotice) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "server", value: .string(JSString(notice.server))),
            JSONMember(key: "kind", value: .string(JSString(notice.kind.rawValue))),
            JSONMember(key: "headline", value: .string(JSString(notice.headline))),
            JSONMember(key: "remedy", value: .string(JSString(notice.remedy))),
            JSONMember(key: "refreshTokenHeld", value: .bool(notice.hasRefreshToken))
        ]
        if let expiresAtMs = notice.expiresAtMs {
            members.append(JSONMember(
                key: "expiresAt",
                value: .string(JSString(JSDate.iso8601(milliseconds: expiresAtMs)))
            ))
        }
        // Present only when running it can actually help — the `mobbin` rule, carried from
        // ``UpstreamStateReport``: a credential with a refresh token behind it does not need
        // re-authorising, and a command offered there sends its owner round a loop.
        if let command = notice.command {
            members.append(JSONMember(key: "command", value: .string(JSString(command))))
        }
        return .object(members)
    }

    static func expiryPolicyValue(_ policy: AuthExpiryPolicy) -> JSONValue {
        .object([
            JSONMember(key: "warnWithinMs", value: .number(Double(policy.warnWithinMs))),
            JSONMember(key: "renotifyAfterMs", value: .number(Double(policy.renotifyAfterMs)))
        ])
    }

    static func expiryRefusalValue(_ refusal: AuthExpiryRefusal) -> JSONValue {
        .object([
            JSONMember(key: "scope", value: .string(JSString(refusal.scope))),
            JSONMember(key: "key", value: .string(JSString(refusal.key))),
            JSONMember(key: "value", value: .number(Double(refusal.value))),
            JSONMember(key: "reason", value: .string(JSString(refusal.reason)))
        ])
    }
}
