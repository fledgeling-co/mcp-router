import Foundation

/// One invocation, as it was observed — and **everything it cannot carry**.
///
/// Four members: when, what kind of thing, its name, and which harness ran it. There is no member
/// for prompt text, tool arguments, tool results, working directory, git branch, session id or
/// request id, and that absence is the design rather than a habit of the reader. A reader that
/// decoded a transcript line into a general structure and then selected four fields would be one
/// careless line away from writing a prompt into a file; this type gives that line nowhere to land.
///
/// Ordered members and an omitted-when-absent optional, matching ``UsageRecord``, because the record
/// is written with a compact stringifier and read back, so key order and the absence of a member are
/// both on the wire.
public struct InvocationEvent: Sendable, Hashable {
    public var ts: String
    public var kind: CapabilityKind
    public var name: String
    /// The harness whose session recorded the run. A harness name here rather than a process name,
    /// and the distinction matters: this is read from the corpus the harness owns, so the attribution
    /// is by *whose file it was in* — a stronger claim than ``ClientProcessName``'s, which has to
    /// infer a harness from a process name and often cannot.
    public var harness: String
    /// The tool inside the server, for a `server` invocation. Absent for a skill or a plugin, which
    /// have no sub-name.
    public var tool: String?

    public init(ts: String, kind: CapabilityKind, name: String, harness: String, tool: String? = nil) {
        self.ts = ts
        self.kind = kind
        self.name = name
        self.harness = harness
        self.tool = tool
    }

    public var value: JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "ts", value: .string(JSString(ts))),
            JSONMember(key: "kind", value: .string(JSString(kind.rawValue))),
            JSONMember(key: "name", value: .string(JSString(name))),
            JSONMember(key: "harness", value: .string(JSString(harness)))
        ]
        if let tool { members.append(JSONMember(key: "tool", value: .string(JSString(tool)))) }
        return .object(members)
    }

    public init?(_ value: JSONValue) {
        guard let ts = value.member("ts")?.asString?.string,
              let rawKind = value.member("kind")?.asString?.string,
              let kind = CapabilityKind(rawValue: rawKind),
              let name = value.member("name")?.asString?.string,
              let harness = value.member("harness")?.asString?.string
        else { return nil }
        self.init(
            ts: ts, kind: kind, name: name, harness: harness,
            tool: value.member("tool")?.asString?.string
        )
    }

    /// Every key this type can put on the wire, in order.
    ///
    /// Named rather than left implicit so a test can assert the serialised key set **exactly**, and
    /// a fifth member added later reddens that assertion instead of shipping quietly. The privacy
    /// claim in `spec-F5.md` §3 is only as good as something that fails when it stops being true.
    public static let wireKeys = ["ts", "kind", "name", "harness", "tool"]
}
