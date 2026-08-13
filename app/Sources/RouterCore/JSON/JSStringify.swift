import Foundation

/// Serialises a ``JSONValue`` byte-for-byte the way `JSON.stringify` does.
///
/// Every rule here was either read off the ECMAScript specification or established by an
/// out-of-family review of the first draft, which found four separate places the obvious Swift
/// implementation diverges: `\u` escapes are **lowercase**; a valid surrogate *pair* must be
/// recombined into UTF-8 while an *unpaired* unit stays escaped; `/`, `U+2028` and `U+2029` are
/// emitted raw despite being the ones people expect to be escaped; and non-finite numbers become
/// `null` rather than their `String(n)` spelling.
public enum JSStringify {
    /// Compact output — the form both of the router's digests are taken over.
    public static func compact(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out, indent: nil, depth: 0)
        return out
    }

    /// `JSON.stringify(value, null, 2)` — the form the manifest is written to disk in.
    public static func prettyTwoSpace(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out, indent: 2, depth: 0)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String, indent: Int?, depth: Int) {
        switch value {
        case .null:
            out += "null"
        case let .bool(flag):
            out += flag ? "true" : "false"
        case let .number(number):
            out += JSNumber.stringifyValue(number)
        case let .string(text):
            writeString(text, into: &out)
        case let .array(elements):
            writeArray(elements, into: &out, indent: indent, depth: depth)
        case let .object(members):
            writeObject(members, into: &out, indent: indent, depth: depth)
        }
    }

    private static func writeArray(_ elements: [JSONValue], into out: inout String, indent: Int?, depth: Int) {
        guard !elements.isEmpty else {
            out += "[]"
            return
        }
        let (open, separator, close) = punctuation(indent: indent, depth: depth)
        out += "[" + open
        for (offset, element) in elements.enumerated() {
            if offset > 0 { out += separator }
            write(element, into: &out, indent: indent, depth: depth + 1)
        }
        out += close + "]"
    }

    private static func writeObject(_ members: [JSONMember], into out: inout String, indent: Int?, depth: Int) {
        guard !members.isEmpty else {
            out += "{}"
            return
        }
        let (open, separator, close) = punctuation(indent: indent, depth: depth)
        out += "{" + open
        for (offset, member) in members.enumerated() {
            if offset > 0 { out += separator }
            writeString(member.key, into: &out)
            out += indent == nil ? ":" : ": "
            write(member.value, into: &out, indent: indent, depth: depth + 1)
        }
        out += close + "}"
    }

    private static func punctuation(indent: Int?, depth: Int) -> (open: String, separator: String, close: String) {
        guard let indent else { return ("", ",", "") }
        let inner = String(repeating: " ", count: indent * (depth + 1))
        let outer = String(repeating: " ", count: indent * depth)
        return ("\n" + inner, ",\n" + inner, "\n" + outer)
    }

    private static func writeString(_ text: JSString, into out: inout String) {
        out += "\""
        let units = text.units
        var index = 0
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            case 0x00 ... 0x1F:
                out += escape(unit)
            case 0xD800 ... 0xDBFF:
                // A high surrogate is only a character if a low one follows. Paired, the two units
                // become one scalar and are emitted as UTF-8; unpaired, the unit is not a
                // character at all and JavaScript writes it back as an escape.
                if index + 1 < units.count, (0xDC00 ... 0xDFFF).contains(units[index + 1]) {
                    let high = UInt32(unit) - 0xD800
                    let low = UInt32(units[index + 1]) - 0xDC00
                    let scalarValue = 0x10000 + (high << 10) + low
                    if let scalar = Unicode.Scalar(scalarValue) {
                        out.unicodeScalars.append(scalar)
                    }
                    index += 2
                    continue
                }
                out += escape(unit)
            case 0xDC00 ... 0xDFFF:
                out += escape(unit)
            default:
                if let scalar = Unicode.Scalar(UInt32(unit)) {
                    out.unicodeScalars.append(scalar)
                }
            }
            index += 1
        }
        out += "\""
    }

    /// `\uXXXX` with **lowercase** hex, which is what JavaScript emits — `""`, not
    /// `""`.
    private static func escape(_ unit: UInt16) -> String {
        let hex = String(unit, radix: 16, uppercase: false)
        return "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
    }
}
