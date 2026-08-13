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
        var cursor = Cursor(bytes: bytes)
        cursor.skipWhitespace()
        let value = try cursor.parseValue()
        cursor.skipWhitespace()
        guard cursor.isAtEnd else {
            throw JSONParseError(reason: "unexpected trailing content", offset: cursor.offset)
        }
        return value
    }

    private struct Cursor {
        let bytes: [UInt8]
        var offset = 0

        var isAtEnd: Bool { offset >= bytes.count }

        mutating func skipWhitespace() {
            while offset < bytes.count {
                switch bytes[offset] {
                case 0x20, 0x09, 0x0A, 0x0D: offset += 1
                default: return
                }
            }
        }

        mutating func parseValue() throws -> JSONValue {
            guard offset < bytes.count else {
                throw JSONParseError(reason: "unexpected end of input", offset: offset)
            }
            switch bytes[offset] {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }

        mutating func expect(_ literal: String) throws {
            let expected = Array(literal.utf8)
            guard offset + expected.count <= bytes.count,
                  Array(bytes[offset ..< offset + expected.count]) == expected
            else {
                throw JSONParseError(reason: "expected \(literal)", offset: offset)
            }
            offset += expected.count
        }

        mutating func parseObject() throws -> JSONValue {
            offset += 1 // {
            var members: [JSONMember] = []
            var firstPosition: [JSString: Int] = [:]

            skipWhitespace()
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "}") {
                offset += 1
                return .object([])
            }

            while true {
                skipWhitespace()
                guard offset < bytes.count, bytes[offset] == UInt8(ascii: "\"") else {
                    throw JSONParseError(reason: "expected a key", offset: offset)
                }
                // Escapes are decoded here, before duplicate detection and before index
                // classification — `{"a":1,"a":2}` is a duplicate, not two members.
                let key = try parseString()
                skipWhitespace()
                guard offset < bytes.count, bytes[offset] == UInt8(ascii: ":") else {
                    throw JSONParseError(reason: "expected ':'", offset: offset)
                }
                offset += 1
                skipWhitespace()
                let value = try parseValue()

                // Last value wins, at the first occurrence's position. Neither keeping both nor
                // moving the key to the end matches `JSON.parse`.
                if let existing = firstPosition[key] {
                    members[existing] = JSONMember(key: key, value: value)
                } else {
                    firstPosition[key] = members.count
                    members.append(JSONMember(key: key, value: value))
                }

                skipWhitespace()
                guard offset < bytes.count else {
                    throw JSONParseError(reason: "unterminated object", offset: offset)
                }
                if bytes[offset] == UInt8(ascii: ",") {
                    offset += 1
                    continue
                }
                if bytes[offset] == UInt8(ascii: "}") {
                    offset += 1
                    return .object(Self.enumerationOrder(members))
                }
                throw JSONParseError(reason: "expected ',' or '}'", offset: offset)
            }
        }

        mutating func parseArray() throws -> JSONValue {
            offset += 1 // [
            var elements: [JSONValue] = []

            skipWhitespace()
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "]") {
                offset += 1
                return .array([])
            }

            while true {
                skipWhitespace()
                elements.append(try parseValue())
                skipWhitespace()
                guard offset < bytes.count else {
                    throw JSONParseError(reason: "unterminated array", offset: offset)
                }
                if bytes[offset] == UInt8(ascii: ",") {
                    offset += 1
                    continue
                }
                if bytes[offset] == UInt8(ascii: "]") {
                    offset += 1
                    return .array(elements)
                }
                throw JSONParseError(reason: "expected ',' or ']'", offset: offset)
            }
        }

        mutating func parseString() throws -> JSString {
            offset += 1 // opening quote
            var units: [UInt16] = []

            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == UInt8(ascii: "\"") {
                    offset += 1
                    return JSString(units: units)
                }
                if byte == UInt8(ascii: "\\") {
                    offset += 1
                    guard offset < bytes.count else {
                        throw JSONParseError(reason: "unterminated escape", offset: offset)
                    }
                    switch bytes[offset] {
                    case UInt8(ascii: "\""): units.append(0x22); offset += 1
                    case UInt8(ascii: "\\"): units.append(0x5C); offset += 1
                    case UInt8(ascii: "/"): units.append(0x2F); offset += 1
                    case UInt8(ascii: "b"): units.append(0x08); offset += 1
                    case UInt8(ascii: "f"): units.append(0x0C); offset += 1
                    case UInt8(ascii: "n"): units.append(0x0A); offset += 1
                    case UInt8(ascii: "r"): units.append(0x0D); offset += 1
                    case UInt8(ascii: "t"): units.append(0x09); offset += 1
                    case UInt8(ascii: "u"):
                        offset += 1
                        // Appended as a raw code unit, so an unpaired surrogate survives exactly
                        // as JavaScript holds it.
                        units.append(try parseHexQuad())
                    default:
                        throw JSONParseError(reason: "invalid escape", offset: offset)
                    }
                    continue
                }
                if byte < 0x20 {
                    throw JSONParseError(reason: "control character in string", offset: offset)
                }
                let (scalar, width) = try decodeUTF8()
                offset += width
                for unit in String(scalar).utf16 { units.append(unit) }
            }
            throw JSONParseError(reason: "unterminated string", offset: offset)
        }

        mutating func parseHexQuad() throws -> UInt16 {
            guard offset + 4 <= bytes.count else {
                throw JSONParseError(reason: "truncated \\u escape", offset: offset)
            }
            var value: UInt16 = 0
            for _ in 0 ..< 4 {
                let byte = bytes[offset]
                let digit: UInt16
                switch byte {
                case UInt8(ascii: "0") ... UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a") ... UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A") ... UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A")) + 10
                default: throw JSONParseError(reason: "invalid hex digit in \\u escape", offset: offset)
                }
                value = value << 4 | digit
                offset += 1
            }
            return value
        }

        mutating func decodeUTF8() throws -> (Unicode.Scalar, Int) {
            let first = bytes[offset]
            let width: Int
            var value: UInt32
            switch first {
            case 0x00 ... 0x7F: return (Unicode.Scalar(first), 1)
            case 0xC2 ... 0xDF: width = 2; value = UInt32(first & 0x1F)
            case 0xE0 ... 0xEF: width = 3; value = UInt32(first & 0x0F)
            case 0xF0 ... 0xF4: width = 4; value = UInt32(first & 0x07)
            default: throw JSONParseError(reason: "invalid UTF-8", offset: offset)
            }
            guard offset + width <= bytes.count else {
                throw JSONParseError(reason: "truncated UTF-8 sequence", offset: offset)
            }
            for index in 1 ..< width {
                let continuation = bytes[offset + index]
                guard continuation & 0xC0 == 0x80 else {
                    throw JSONParseError(reason: "invalid UTF-8 continuation", offset: offset + index)
                }
                value = value << 6 | UInt32(continuation & 0x3F)
            }
            guard let scalar = Unicode.Scalar(value) else {
                throw JSONParseError(reason: "invalid scalar", offset: offset)
            }
            return (scalar, width)
        }

        mutating func parseNumber() throws -> Double {
            let start = offset
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "-") { offset += 1 }
            scan: while offset < bytes.count {
                switch bytes[offset] {
                case UInt8(ascii: "0") ... UInt8(ascii: "9"),
                     UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"),
                     UInt8(ascii: "+"), UInt8(ascii: "-"):
                    offset += 1
                default:
                    break scan
                }
            }
            guard start < offset else {
                throw JSONParseError(reason: "expected a value", offset: offset)
            }
            let token = String(decoding: bytes[start ..< offset], as: UTF8.self)
            // Every parsed number becomes an IEEE-754 binary64 here, which is why
            // `9007199254740993` comes back as `…992` and why `1e400` becomes an infinity that
            // serialises as `null` — both matching `JSON.parse`.
            guard let value = Double(token) else {
                throw JSONParseError(reason: "invalid number \(token)", offset: start)
            }
            return value
        }

        /// JavaScript's own-property enumeration order: array-index keys first, ascending
        /// numerically, then every other key in insertion order.
        static func enumerationOrder(_ members: [JSONMember]) -> [JSONMember] {
            var indexed: [(index: UInt32, member: JSONMember)] = []
            var rest: [JSONMember] = []
            for member in members {
                if let index = member.key.arrayIndex {
                    indexed.append((index, member))
                } else {
                    rest.append(member)
                }
            }
            guard !indexed.isEmpty else { return members }
            indexed.sort { $0.index < $1.index }
            return indexed.map(\.member) + rest
        }
    }
}
