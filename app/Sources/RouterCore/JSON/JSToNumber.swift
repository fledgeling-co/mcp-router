import Foundation

/// ECMAScript `Number(value)` over a string, which is **not** what `Double(_: String)` does.
///
/// The two disagree on inputs the control API actually receives from a query string:
///
/// | Input | `Number(x)` | `Double(x)` |
/// |---|---|---|
/// | `""` | `0` | `nil` |
/// | `"  12  "` | `12` | `nil` |
/// | `"0x10"` | `16` | `16` |
/// | `"1."` | `1` | `1` |
/// | `"abc"` | `NaN` | `nil` |
/// | `"Infinity"` | `∞` | `∞` |
///
/// The first two are the ones that bite: `?limit=` and `?limit=%2012%20` are a `0` and a `12` to the
/// reference, and every record and a NaN-slice to a naive port. `Number` also accepts only these
/// forms — a trailing `f`, an underscore separator or a locale decimal comma is `NaN`.
public enum JSToNumber {
    /// `Number(text)` for the string case. Callers handle the nullish default themselves, because
    /// `Number(undefined)` is `NaN` while `Number(null)` is `0` and the reference always writes the
    /// `?? default` first.
    public static func number(_ text: String) -> Double {
        let trimmed = ControlToken.jsTrim(text)
        // `Number("")` and `Number("   ")` are both 0, not NaN — StringNumericLiteral matches empty.
        if trimmed.isEmpty { return 0 }

        if let radixValue = radixLiteral(trimmed) { return radixValue }

        switch trimmed {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }

        // StrDecimalLiteral only. Swift's parser is a superset — it takes hex floats, underscores
        // and "nan"/"inf" — so the shape is validated before it is handed over.
        guard isStrDecimalLiteral(trimmed), let value = Double(trimmed) else { return .nan }
        return value
    }

    /// `0x`/`0o`/`0b`, which take **no sign** — `Number("-0x10")` is `NaN`, not `-16`.
    private static func radixLiteral(_ text: String) -> Double? {
        let prefixes: [(String, Int)] = [("0x", 16), ("0X", 16), ("0o", 8), ("0O", 8), ("0b", 2), ("0B", 2)]
        for (prefix, radix) in prefixes where text.hasPrefix(prefix) {
            let digits = String(text.dropFirst(2))
            guard !digits.isEmpty, let magnitude = UInt64(digits, radix: radix) else { return Double.nan }
            return Double(magnitude)
        }
        return nil
    }

    /// `[+-]? (digits [. digits?] | . digits) ([eE] [+-]? digits)?` — and nothing else.
    private static func isStrDecimalLiteral(_ text: String) -> Bool {
        let characters = Array(text)
        var index = 0

        /// Consumes ASCII digits, reporting whether it saw any.
        func takeDigits() -> Bool {
            var seen = false
            while index < characters.count, characters[index].isASCIIDigit {
                index += 1
                seen = true
            }
            return seen
        }

        func takeSign() {
            guard index < characters.count else { return }
            let character = characters[index]
            if character == "+" || character == "-" { index += 1 }
        }

        takeSign()
        var sawDigit = takeDigits()
        if index < characters.count, characters[index] == "." {
            index += 1
            // `1.` is valid and so is `.5`; only a lone "." with digits on neither side is not.
            sawDigit = takeDigits() || sawDigit
        }
        guard sawDigit else { return false }

        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            index += 1
            takeSign()
            guard takeDigits() else { return false }
        }
        return index == characters.count
    }
}

private extension Character {
    /// ASCII digits only. `isNumber` is true for `٣` and `½`, which `Number()` rejects.
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
