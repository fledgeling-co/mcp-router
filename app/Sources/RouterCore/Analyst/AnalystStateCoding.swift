import Foundation

/// The analyst's state on disk, as JSON this repository's own stack writes and reads.
///
/// **Every member is optional on the way in.** This file outlives the build that wrote it: the
/// thirty-day suppression promise is only kept if a file written by an older router still yields
/// its fingerprints, so a member this build does not recognise is ignored and a member it expects
/// and does not find falls to a default rather than discarding the file.
public enum AnalystStateCoding {
    public static func encode(_ state: AnalystState) -> JSONValue {
        .object([
            JSONMember(key: JSString("settings"), value: AnalystSettingsCoding.encode(state.settings)),
            JSONMember(key: JSString("lastRun"), value: state.lastRun.map(run) ?? .null),
            JSONMember(key: JSString("delivered"), value: .array(state.delivered.map { entry in
                .object([
                    JSONMember(key: JSString("fingerprint"), value: .string(JSString(entry.fingerprint))),
                    JSONMember(key: JSString("at"), value: .number(entry.atMilliseconds))
                ])
            }))
        ])
    }

    public static func decode(_ value: JSONValue) -> AnalystState {
        let delivered = (value.member("delivered")?.asArray ?? []).compactMap { item in
            guard let print = item.member("fingerprint")?.asString?.string,
                  let at = item.member("at")?.asNumber
            else { return (String, Double)?.none }
            return (print, at)
        }
        return AnalystState(
            settings: AnalystSettingsCoding.parse(value.member("settings") ?? .null),
            lastRun: value.member("lastRun").flatMap(decodeRun),
            delivered: delivered.map { (fingerprint: $0.0, atMilliseconds: $0.1) }
        )
    }

    static func run(_ record: AnalystRunRecord) -> JSONValue {
        .object([
            JSONMember(
                key: JSString("lane"),
                value: record.lane.map { .string(JSString($0.rawValue)) } ?? .null
            ),
            JSONMember(key: JSString("ranAt"), value: .number(record.ranAtMilliseconds)),
            JSONMember(key: JSString("linesRead"), value: .number(Double(record.linesRead))),
            JSONMember(key: JSString("discarded"), value: .number(Double(record.discardedLines))),
            JSONMember(key: JSString("usedFallback"), value: .bool(record.usedFallback)),
            JSONMember(key: JSString("rejected"), value: .number(Double(record.rejectedFindings))),
            JSONMember(
                key: JSString("candidatesUnavailable"), value: .bool(record.candidatesUnavailable)
            ),
            JSONMember(key: JSString("stores"), value: .array(record.stores.map(store))),
            JSONMember(key: JSString("findings"), value: .array(record.findings.map(finding)))
        ])
    }

    static func store(_ report: SessionStoreReport) -> JSONValue {
        .object([
            JSONMember(key: JSString("harness"), value: .string(JSString(report.harness.rawValue))),
            JSONMember(key: JSString("path"), value: .string(JSString(report.path))),
            JSONMember(key: JSString("read"), value: .bool(report.read)),
            JSONMember(key: JSString("lines"), value: .number(Double(report.lines))),
            JSONMember(key: JSString("discarded"), value: .number(Double(report.discarded))),
            JSONMember(
                key: JSString("reason"),
                value: report.reason.map { .string(JSString($0)) } ?? .null
            )
        ])
    }

    static func finding(_ record: AnalystFindingRecord) -> JSONValue {
        .object([
            JSONMember(key: JSString("id"), value: .string(JSString(record.id))),
            JSONMember(key: JSString("entryID"), value: .string(JSString(record.entryID))),
            JSONMember(key: JSString("subject"), value: .string(JSString(record.subject))),
            JSONMember(key: JSString("sentence"), value: .string(JSString(record.sentence))),
            JSONMember(key: JSString("evidenceCount"), value: .number(Double(record.evidenceCount))),
            JSONMember(key: JSString("judgedBy"), value: .string(JSString(record.judgedBy.rawValue))),
            JSONMember(
                key: JSString("signals"),
                value: .array(record.signals.map { .string(JSString($0)) })
            )
        ])
    }

    static func decodeRun(_ value: JSONValue) -> AnalystRunRecord? {
        guard let ranAt = value.member("ranAt")?.asNumber else { return nil }
        let laneName: String? = value.member("lane")?.asString?.string
        let lane = laneName.flatMap { AnalystLane(rawValue: $0) }
        return AnalystRunRecord(
            lane: lane, ranAtMilliseconds: ranAt,
            linesRead: Int(value.member("linesRead")?.asNumber ?? 0),
            discardedLines: Int(value.member("discarded")?.asNumber ?? 0),
            usedFallback: value.member("usedFallback")?.asBool ?? false,
            rejectedFindings: Int(value.member("rejected")?.asNumber ?? 0),
            candidatesUnavailable: value.member("candidatesUnavailable")?.asBool ?? false,
            stores: (value.member("stores")?.asArray ?? []).compactMap(decodeStore),
            findings: (value.member("findings")?.asArray ?? []).compactMap(decodeFinding)
        )
    }

    static func decodeStore(_ value: JSONValue) -> SessionStoreReport? {
        guard let name = value.member("harness")?.asString?.string,
              let harness = MCPClient(rawValue: name)
        else { return nil }
        return SessionStoreReport(
            harness: harness, path: value.member("path")?.asString?.string ?? "",
            read: value.member("read")?.asBool ?? false,
            lines: Int(value.member("lines")?.asNumber ?? 0),
            discarded: Int(value.member("discarded")?.asNumber ?? 0),
            reason: value.member("reason")?.asString?.string
        )
    }

    static func decodeFinding(_ value: JSONValue) -> AnalystFindingRecord? {
        guard let id = value.member("id")?.asString?.string,
              let entry = value.member("entryID")?.asString?.string,
              let laneName = value.member("judgedBy")?.asString?.string,
              let lane = AnalystLane(rawValue: laneName)
        else { return nil }
        return AnalystFindingRecord(
            id: id, entryID: entry,
            subject: value.member("subject")?.asString?.string ?? entry,
            sentence: value.member("sentence")?.asString?.string ?? "",
            evidenceCount: Int(value.member("evidenceCount")?.asNumber ?? 0),
            judgedBy: lane,
            signals: (value.member("signals")?.asArray ?? []).compactMap { $0.asString?.string }
        )
    }
}
