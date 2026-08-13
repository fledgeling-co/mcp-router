import Foundation

/// A JSON value that preserves everything the digest depends on.
///
/// Two properties matter and neither survives `JSONSerialization` or `JSONDecoder`:
/// **object member order**, because the reference hashes `JSON.stringify(schema)` and that walks
/// members in order; and **exact string identity**, which is why keys are ``JSString`` rather than
/// `String`.
public indirect enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(JSString)
    case array([JSONValue])
    case object([JSONMember])
}

/// One key/value pair. An array of these, not a dictionary — a dictionary has no order.
public struct JSONMember: Sendable, Hashable {
    public let key: JSString
    public let value: JSONValue

    public init(key: JSString, value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public extension JSONValue {
    /// The value under `key`, or nil. Linear, which is correct for the sizes involved here (a tool
    /// object has a handful of members) and keeps the ordered representation as the only one.
    func member(_ key: JSString) -> JSONValue? {
        guard case let .object(members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    func member(_ key: String) -> JSONValue? {
        member(JSString(key))
    }

    var asString: JSString? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var asObjectMembers: [JSONMember]? {
        guard case let .object(members) = self else { return nil }
        return members
    }

    var asArray: [JSONValue]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    var asBool: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var asNumber: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    /// True for a JSON object specifically. Note the reference's own check is `typeof x ===
    /// "object"`, which is *also* true for an array — see ``isObjectOrArray``.
    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// What `typeof x === "object" && x !== null` accepts in JavaScript: an object **or an array**.
    /// The manifest parser is written against this rather than against `isObject`, because
    /// `{"version":1,"servers":[]}` is accepted by the reference and parity is the default.
    var isObjectOrArray: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// The word `typeof` would produce, used in the error copy that tells a user what their
    /// `mcpServers` actually is.
    var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }
}
