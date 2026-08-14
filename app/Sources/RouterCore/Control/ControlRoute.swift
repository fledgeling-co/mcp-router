import Foundation

/// `^/servers/([^/]+)(/[a-z]+)?$` — the sub-path is **lowercase only**, so `/servers/x/Reindex`
/// does not match and reaches the 405 fallback (B23).
struct ServerRoute {
    let rawName: String
    let sub: String?

    init?(encodedPath: String) {
        guard encodedPath.hasPrefix("/servers/") else { return nil }
        let rest = String(encodedPath.dropFirst("/servers/".count))
        guard !rest.isEmpty else { return nil }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard !parts[0].isEmpty else { return nil }
            rawName = String(parts[0])
            sub = nil
        case 2:
            guard !parts[0].isEmpty, !parts[1].isEmpty,
                  parts[1].allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter })
            else { return nil }
            rawName = String(parts[0])
            sub = "/" + String(parts[1])
        default:
            return nil
        }
    }

    /// `decodeURIComponent` — nil on a malformed escape, which the reference turns into a thrown
    /// `URIError` rather than a 404.
    var decodedName: JSString? {
        guard let decoded = rawName.removingPercentEncoding else { return nil }
        return JSString(decoded)
    }
}

extension String {
    /// JavaScript truthiness for a string: everything except the empty one.
    var isJSTruthyString: Bool { !isEmpty }
}

extension ControlHandler {
    /// `String(v)` for the three primitives that can reach the `in` operator, so the refusal in
    /// ``ControlHandler/patch(_:name:deps:)`` carries the text V8 would have put in its
    /// `TypeError`. `JSNumber.string` is JavaScript's own number formatting — `42` renders as
    /// `42`, never `42.0`.
    static func jsToString(_ value: JSONValue) -> String {
        switch value {
        case let .bool(flag): flag ? "true" : "false"
        case let .number(number): JSNumber.string(number)
        case let .string(text): text.string
        // Unreachable: `bodyDisposition` only reports `.primitive` for the three above.
        case .null: "null"
        case .array, .object: "[object]"
        }
    }
}
