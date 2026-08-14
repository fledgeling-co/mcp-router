/// An object under construction, where a member can be **present and `undefined`**.
///
/// `JSONValue` cannot express that state, and it is the one this item cannot do without. In
/// JavaScript, `{ install: undefined }` creates the key: `'install' in o` is true, `Object.keys`
/// lists it, a later `{...o, install: x}` overwrites it **in its original slot**, and only
/// `JSON.stringify` omits it. A Swift `Optional` collapses "absent" and "present, undefined" into
/// one value, so a draft that simply skips `undefined` members appends the later write at the end
/// of the object and emits the same members in a different order (S3, N1, N2).
///
/// The registry merge is where that bites: an official row always creates `install`, often with
/// `undefined`. `{...existing, install: existing.install ?? e.install}` must land in slot 9, not
/// after `iconUrl`.
struct JSObjectDraft {
    /// Ordered members. A `nil` value is present-and-`undefined`.
    private(set) var members: [(key: JSString, value: JSONValue?)] = []

    /// `o.k` — `undefined` for both an absent member and one holding `undefined`, exactly as a
    /// property read does.
    func get(_ key: String) -> JSONValue? {
        guard let member = members.first(where: { $0.key == JSString(key) }) else { return nil }
        return member.value
    }

    /// `'k' in o` — presence, which `get` cannot answer for an `undefined`-valued member (N9).
    func has(_ key: String) -> Bool {
        members.contains { $0.key == JSString(key) }
    }

    /// `o.k = v`, including `v === undefined`: an existing member keeps its slot, a new one is
    /// appended. This is assignment, so the key is created either way.
    mutating func set(_ key: String, _ value: JSONValue?) {
        let target = JSString(key)
        if let at = members.firstIndex(where: { $0.key == target }) {
            members[at].value = value
        } else {
            members.append((key: target, value: value))
        }
    }

    /// `Object.assign(o, {…})` over the given pairs, in order.
    mutating func assign(_ pairs: [(String, JSONValue?)]) {
        for (key, value) in pairs {
            set(key, value)
        }
    }

    /// `{...self}` — a copy that keeps every key, `undefined` ones included.
    func spread() -> JSObjectDraft {
        var copy = JSObjectDraft()
        copy.members = members
        return copy
    }

    /// What `JSON.stringify` walks: every member in slot order, `undefined` ones dropped.
    var jsonValue: JSONValue {
        .object(members.compactMap { member in
            member.value.map { JSONMember(key: member.key, value: $0) }
        })
    }
}
