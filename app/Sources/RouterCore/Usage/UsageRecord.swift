import Foundation

/// One tool call, as it happened — the unit the activity view renders.
///
/// Held as ordered members rather than as a `Codable` struct: the record is written to the usage
/// log with `JSON.stringify` and read back, and both its **key order** and the **absence** of an
/// undefined member are on the wire (S3, S4).
public struct UsageRecord: Sendable, Hashable {
    public var ts: String
    public var server: String
    public var tool: String
    public var ok: Bool
    public var ms: Double
    public var cold: Bool
    public var pid: Int32?
    public var cwd: String?
    public var project: String?
    public var client: String?
    public var err: String?

    public init(
        ts: String,
        server: String,
        tool: String,
        ok: Bool,
        ms: Double,
        cold: Bool,
        pid: Int32? = nil,
        cwd: String? = nil,
        project: String? = nil,
        client: String? = nil,
        err: String? = nil
    ) {
        self.ts = ts
        self.server = server
        self.tool = tool
        self.ok = ok
        self.ms = ms
        self.cold = cold
        self.pid = pid
        self.cwd = cwd
        self.project = project
        self.client = client
        self.err = err
    }

    /// The reference's literal, member for member and in its order. An optional that is nil is
    /// **omitted**, never emitted as null.
    public var value: JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "ts", value: .string(JSString(ts))),
            JSONMember(key: "server", value: .string(JSString(server))),
            JSONMember(key: "tool", value: .string(JSString(tool))),
            JSONMember(key: "ok", value: .bool(ok)),
            JSONMember(key: "ms", value: .number(ms)),
            JSONMember(key: "cold", value: .bool(cold))
        ]
        if let pid { members.append(JSONMember(key: "pid", value: .number(Double(pid)))) }
        if let cwd { members.append(JSONMember(key: "cwd", value: .string(JSString(cwd)))) }
        if let project {
            members.append(JSONMember(key: "project", value: .string(JSString(project))))
        }
        if let client { members.append(JSONMember(key: "client", value: .string(JSString(client)))) }
        if let err { members.append(JSONMember(key: "err", value: .string(JSString(err)))) }
        return .object(members)
    }

    public init?(_ value: JSONValue) {
        guard let members = value.asObjectMembers else { return nil }
        func text(_ key: String) -> String? {
            value.member(key)?.asString?.string
        }
        guard let ts = text("ts"), let server = text("server"), let tool = text("tool") else {
            return nil
        }
        _ = members
        self.init(
            ts: ts,
            server: server,
            tool: tool,
            ok: value.member("ok")?.asBool ?? false,
            ms: value.member("ms")?.asNumber ?? 0,
            cold: value.member("cold")?.asBool ?? false,
            pid: value.member("pid")?.asNumber.map { Int32($0) },
            cwd: text("cwd"),
            project: text("project"),
            client: text("client"),
            err: text("err")
        )
    }
}

/// The durable per-server aggregate.
///
/// Ordered members, because the order the reference **assigns** them in is the order they
/// serialise: `calls` and `errors` and `projects` are created together, `firstSeen` is added on
/// first sight and `lastUsed` after it. That is why a populated `usage` block in the recorded
/// fixtures reads `calls, errors, projects, firstSeen, lastUsed` — which is *not* the declaration
/// order of the reference's own interface (B3).
public struct ServerStat: Sendable, Hashable {
    public var members: [JSONMember]

    public init(members: [JSONMember]) {
        self.members = members
    }

    /// The shape `record()` creates on first sight.
    public static func fresh() -> ServerStat {
        ServerStat(members: [
            JSONMember(key: "calls", value: .number(0)),
            JSONMember(key: "errors", value: .number(0)),
            JSONMember(key: "projects", value: .object([]))
        ])
    }

    /// The literal the reference substitutes when a server has no aggregate at all.
    public static let zero = ServerStat.fresh()

    public var value: JSONValue { .object(members) }

    public func member(_ key: String) -> JSONValue? {
        let target = JSString(key)
        return members.first { $0.key == target }?.value
    }

    /// Replaces in place, keeping the member's slot, or appends. In-place is what preserves the
    /// assignment order above across every later update.
    public mutating func set(_ key: String, _ newValue: JSONValue) {
        let target = JSString(key)
        if let index = members.firstIndex(where: { $0.key == target }) {
            members[index] = JSONMember(key: target, value: newValue)
        } else {
            members.append(JSONMember(key: target, value: newValue))
        }
    }

    public var calls: Double { member("calls")?.asNumber ?? 0 }
    public var errors: Double { member("errors")?.asNumber ?? 0 }
    public var projects: [JSONMember] { member("projects")?.asObjectMembers ?? [] }
}
