import Foundation

/// One moment at which a capability's version was observed to be what it is.
///
/// A boundary, not a state. What it asserts is narrow and checkable: *at `ts`, `name` was at
/// `version`.* Everything the ledger can say about the past is deduced from a set of these, and
/// nothing is deduced from a gap between two of them.
public struct VersionObservation: Sendable, Hashable {
    public var ts: String
    public var kind: CapabilityKind
    public var name: String
    public var version: String
    /// Where the observation came from — `installed_plugins.json`'s `lastUpdated`, or a reading the
    /// router took itself. On the wire, because a seeded boundary and a witnessed one are not the
    /// same quality of evidence and a consumer must be able to tell.
    public var source: String

    public init(ts: String, kind: CapabilityKind, name: String, version: String, source: String) {
        self.ts = ts
        self.kind = kind
        self.name = name
        self.version = version
        self.source = source
    }

    /// Ordered members, `UsageRecord`'s convention: the line is written with a compact stringifier
    /// and read back, so key order is on the wire.
    public var value: JSONValue {
        .object([
            JSONMember(key: "ts", value: .string(JSString(ts))),
            JSONMember(key: "kind", value: .string(JSString(kind.rawValue))),
            JSONMember(key: "name", value: .string(JSString(name))),
            JSONMember(key: "version", value: .string(JSString(version))),
            JSONMember(key: "source", value: .string(JSString(source)))
        ])
    }

    public init?(_ value: JSONValue) {
        guard let ts = value.member("ts")?.asString?.string,
              let rawKind = value.member("kind")?.asString?.string,
              let kind = CapabilityKind(rawValue: rawKind),
              let name = value.member("name")?.asString?.string,
              let version = value.member("version")?.asString?.string
        else { return nil }
        self.init(
            ts: ts, kind: kind, name: name, version: version,
            source: value.member("source")?.asString?.string ?? "unrecorded"
        )
    }
}

/// Every boundary the router knows about, and the one deduction they support.
///
/// **The ledger is append-on-change, and the change is the subject.** Recording the installed set
/// on a timer would fill the file with restatements of one fact and would still hold exactly the
/// boundaries it holds now; what makes a later attribution sound is a moment at which the version
/// was observed to be *different*, and that is the only thing appended.
///
/// **It starts with one boundary per plugin and no more.** `installed_plugins.json` carries a
/// `lastUpdated` per record — measured 2026-08-29, present on all 127 — and that is the only
/// history on disk anywhere. Before it there is nothing, and this type says nothing about before
/// it. The attributable window therefore widens as the router runs, and how far back it reaches is
/// ``horizon``, a figure a surface can print rather than a property it has to assume.
public struct VersionLedger: Sendable {
    /// Oldest first, which is the order they are appended in and the order the join below relies on.
    public let observations: [VersionObservation]

    public init(observations: [VersionObservation]) {
        self.observations = observations.sorted { left, right in
            left.ts == right.ts ? left.name < right.name : left.ts < right.ts
        }
    }

    /// The oldest boundary held, or nil when none is. What the ledger can answer for begins here;
    /// a question about a moment before it is `unestablished`, never "the installed version".
    public var horizon: String? { observations.first?.ts }

    /// Every boundary for one capability, oldest first.
    func boundaries(_ kind: CapabilityKind, _ name: String) -> [VersionObservation] {
        observations.filter { $0.kind == kind && $0.name == name }
    }

    /// Parse a ledger file. A torn last line is normal after a hard kill and is skipped; the count
    /// of what could not be read is returned beside the ledger rather than lost, because a count of
    /// what parsed is not a count of what was there.
    public static func read(lines: some Sequence<String>) -> (ledger: VersionLedger, unreadable: Int) {
        var out: [VersionObservation] = []
        var unreadable = 0
        for line in lines where !line.isEmpty {
            guard let parsed = try? JSONParser.parse(line), let record = VersionObservation(parsed)
            else {
                unreadable += 1
                continue
            }
            out.append(record)
        }
        return (VersionLedger(observations: out), unreadable)
    }
}
