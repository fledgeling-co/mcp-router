import Foundation

/// One server's cached entry.
///
/// Held as its ordered members rather than as a struct with fixed fields, for the same reason
/// ``CachedTool`` is: the reference does not validate these entries at all, so a field it does not
/// model has to survive a load/save cycle rather than be silently dropped by a stricter parser.
public struct CachedServer: Sendable, Hashable {
    public var members: [JSONMember]

    public init(members: [JSONMember]) {
        self.members = members
    }

    public init?(_ value: JSONValue) {
        guard case let .object(members) = value else { return nil }
        self.members = members
    }

    public var value: JSONValue { .object(members) }

    public func member(_ key: String) -> JSONValue? {
        let target = JSString(key)
        return members.first(where: { $0.key == target })?.value
    }

    public var hash: JSString? { member("hash")?.asString }
    public var builtAt: JSString? { member("builtAt")?.asString }
    public var digest: JSString? { member("digest")?.asString }
    public var error: JSString? { member("error")?.asString }
    public var pending: JSONValue? { member("pending") }

    /// `!!entry.error` — the reference's own test, so an `error: ""` is **not** an error. That is
    /// what makes an entry with an empty error string current rather than stale.
    public var hasError: Bool { member("error")?.isTruthy ?? false }

    /// `!prev?.digest` — an absent digest and an empty one are alike here, both falsy.
    public var hasDigest: Bool { member("digest")?.isTruthy ?? false }

    /// The approved tool surface.
    ///
    /// A stated limit rather than a reproduction: the reference reads `entry.tools.length`, which
    /// throws when `tools` is absent or is not an array. A hand-edited manifest can produce that,
    /// and a crash is not a behaviour worth porting — so a missing or non-array `tools` reads as
    /// empty here, which routes it to the same "contributes nothing" branch an empty list takes.
    public var tools: [CachedTool] {
        guard case let .array(values)? = member("tools") else { return [] }
        return values.compactMap { CachedTool($0) }
    }

    public var pendingTools: [CachedTool] {
        guard case let .array(values)? = pending?.member("tools") else { return [] }
        return values.compactMap { CachedTool($0) }
    }

    /// Replaces a member in place, or appends it. In-place matters because the reference's
    /// `{...prev, hash, ...}` keeps an existing key where it already was, and the manifest's bytes
    /// are compared.
    public mutating func set(_ key: String, _ newValue: JSONValue) {
        let target = JSString(key)
        if let index = members.firstIndex(where: { $0.key == target }) {
            members[index] = JSONMember(key: target, value: newValue)
        } else {
            members.append(JSONMember(key: target, value: newValue))
        }
    }

    /// Drops a member entirely.
    ///
    /// This is how the reference's `error: undefined` is reproduced. `JSON.stringify` omits a key
    /// whose value is `undefined`, so the emitted bytes carry no `error` at all — removing the
    /// member produces exactly those bytes, where storing a null would not.
    public mutating func remove(_ key: String) {
        let target = JSString(key)
        members.removeAll { $0.key == target }
    }
}

/// The tool cache as it sits on disk.
public struct Manifest: Sendable, Hashable {
    /// Every top-level member, in order, including any the reference does not model.
    public var members: [JSONMember]

    public init(members: [JSONMember]) {
        self.members = members
    }

    /// A cold cache: `{ version: 1, servers: {} }`, the value the reference degrades to.
    public static var empty: Manifest {
        Manifest(members: [
            JSONMember(key: JSString("version"), value: .number(1)),
            JSONMember(key: JSString("servers"), value: .object([]))
        ])
    }

    public var value: JSONValue { .object(members) }

    public var serversValue: JSONValue? {
        let target = JSString("servers")
        return members.first(where: { $0.key == target })?.value
    }

    /// The server entries, in file order.
    ///
    /// Empty when `servers` is an array. The reference accepts `servers: []` — `typeof [] ===
    /// "object"` — and then finds no named entry on it either, so every server reads as stale and
    /// every write lands as a non-index property that `JSON.stringify` discards. The emitted bytes
    /// are therefore the same either way, which is the only thing R4 compares; the in-memory
    /// read-back inside a single pass is the one difference, and it is not observable in a file.
    public var serverEntries: [(name: JSString, entry: CachedServer)] {
        guard case let .object(entries)? = serversValue else { return [] }
        return entries.compactMap { member in
            guard let entry = CachedServer(member.value) else { return nil }
            return (member.key, entry)
        }
    }

    public func entry(named name: String) -> CachedServer? {
        guard case let .object(entries)? = serversValue else { return nil }
        let target = JSString(name)
        guard let found = entries.first(where: { $0.key == target })?.value else { return nil }
        return CachedServer(found)
    }

    /// Upserts an entry, keeping an existing one at its position.
    ///
    /// A no-op when `servers` is an array, which is what the reference's own output does with it.
    public mutating func setEntry(_ name: String, _ entry: CachedServer) {
        guard case var .object(entries)? = serversValue else { return }
        let target = JSString(name)
        let updated = JSONMember(key: target, value: entry.value)
        if let index = entries.firstIndex(where: { $0.key == target }) {
            entries[index] = updated
        } else {
            entries.append(updated)
        }
        setTopLevel("servers", .object(entries))
    }

    public mutating func setTopLevel(_ key: String, _ newValue: JSONValue) {
        let target = JSString(key)
        if let index = members.firstIndex(where: { $0.key == target }) {
            members[index] = JSONMember(key: target, value: newValue)
        } else {
            members.append(JSONMember(key: target, value: newValue))
        }
    }

    public var serverCount: Int {
        guard case let .object(entries)? = serversValue else { return 0 }
        return entries.count
    }
}
