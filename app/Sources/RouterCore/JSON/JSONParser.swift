import Foundation

/// Why a JSON document could not be read. Carries the byte offset so an error message can point at
/// the problem rather than at the file.
public struct JSONParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let reason: String
    public let offset: Int

    public init(reason: String, offset: Int) {
        self.reason = reason
        self.offset = offset
    }

    public var description: String { "\(reason) at byte \(offset)" }
}

/// A JSON parser that reproduces the *object* `JSON.parse` produces, not merely the data.
///
/// Three behaviours here are the whole reason this exists rather than `JSONSerialization`:
/// member order is preserved, **array-index-like keys are reordered ahead of the rest**, and a
/// **duplicate key keeps the last value at the first key's position**. All three change the bytes a
/// re-serialisation produces, and therefore change the digest taken over them.
public enum JSONParser {
    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Array(text.utf8))
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try parse(Array(data))
    }

    public static func parse(_ bytes: [UInt8]) throws -> JSONValue {
        var cursor = JSONCursor(bytes: bytes)
        cursor.skipWhitespace()
        let value = try cursor.parseValue()
        cursor.skipWhitespace()
        guard cursor.isAtEnd else {
            throw JSONParseError(reason: "unexpected trailing content", offset: cursor.offset)
        }
        return value
    }
}
