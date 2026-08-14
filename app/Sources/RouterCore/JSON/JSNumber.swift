import Foundation

/// Formats a `Double` the way JavaScript does.
///
/// This is not `String(describing:)` with cosmetic fixes. Swift and JavaScript disagree on nearly
/// every interesting value — Swift renders `1e20` as `1e+20` where JavaScript writes
/// `100000000000000000000`, `1e-6` as `1e-06` where JavaScript writes `0.000001`, and `100` as
/// `100.0` where JavaScript writes `100`. Since the router's two hashes are taken over
/// `JSON.stringify` output, a mismatch anywhere here is a mismatch in the digest.
///
/// What Swift *does* provide is the hard part: the shortest decimal digit string that round-trips
/// to the same `Double`. So the approach is to take Swift's digits, recover the pair the
/// ECMAScript spec is written in terms of — the digit string `s` and the decimal point position
/// `n` — and then apply the spec's own formatting rules.
public enum JSNumber {
    /// `Int(_: Double)` without the abort, for a number that came out of a JSON file.
    ///
    /// Swift's `Int(_: Double)` is a **trapping** conversion: it aborts the process on NaN, on an
    /// infinity, and on any finite magnitude outside `Int`'s range. JavaScript has no such edge — it
    /// carries the `Double` wherever the number goes — so every place this port converts a
    /// config-sourced number is a place a file can halt the process. `JSONCursor.parseNumber` turns
    /// `1e400` into an infinity exactly as `JSON.parse` does, and `1e300` is finite and far past
    /// `Int.max`, so both arrive here as ordinary parsed values.
    ///
    /// Returns `nil` rather than clamping. Every caller already has a defined answer for "this key
    /// is not a usable number" — the reference's own default — and inventing `Int.max` as a timeout
    /// or an idle window would be a number nobody wrote.
    ///
    /// The range test is `>` and `<` rather than `>=`/`<=` on purpose: `Double(Int.max)` rounds up
    /// to 2^63, which is not representable as an `Int`, so a value merely *equal* to it would still
    /// trap.
    public static func int(_ value: Double) -> Int? {
        guard value.isFinite, value > Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value)
    }

    /// The same guard for `Int32`, which `pid` needs. `Int32(3_000_000_000)` traps where the
    /// reference simply keeps the number it read.
    public static func int32(_ value: Double) -> Int32? {
        guard value.isFinite, value > Double(Int32.min), value < Double(Int32.max) else {
            return nil
        }
        return Int32(value)
    }

    /// `JSON.stringify` semantics, which differ from `String(n)` for the non-finite values:
    /// `String(NaN)` is `"NaN"`, but `JSON.stringify(NaN)` is `null`, and likewise for infinities.
    public static func stringifyValue(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        return string(value)
    }

    /// `String(n)` semantics for a finite number. Negative zero renders as `0`, matching both
    /// `String(-0)` and `JSON.stringify(-0)`.
    public static func string(_ value: Double) -> String {
        if value == 0 { return "0" }
        let negative = value < 0
        guard let (digits, pointPosition) = decompose(abs(value)) else { return "0" }
        let body = format(digits: digits, n: pointPosition)
        return negative ? "-" + body : body
    }

    /// Recovers `(s, n)` from Swift's shortest round-trip rendering, where the value equals
    /// `0.s × 10^n` — that is, `n` is where the decimal point sits relative to the digit string.
    ///
    /// Returns nil only for a zero digit string, which the caller has already handled.
    private static func decompose(_ value: Double) -> (digits: [UInt8], n: Int)? {
        let rendered = "\(value)"
        var mantissa = Substring(rendered)
        var exponent = 0

        if let marker = mantissa.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(mantissa[mantissa.index(after: marker)...]) ?? 0
            mantissa = mantissa[..<marker]
        }

        var digits: [UInt8] = []
        var pointPosition = 0
        var seenPoint = false
        for character in mantissa {
            if character == "." {
                seenPoint = true
                continue
            }
            guard let digit = character.wholeNumberValue else { continue }
            digits.append(UInt8(digit))
            if !seenPoint { pointPosition += 1 }
        }

        var n = pointPosition + exponent

        // Leading zeros move the point; trailing zeros do not.
        while let first = digits.first, first == 0 {
            digits.removeFirst()
            n -= 1
        }
        while let last = digits.last, last == 0 {
            digits.removeLast()
        }
        return digits.isEmpty ? nil : (digits, n)
    }

    /// ECMAScript `Number::toString`, step for step, given the digit string `s` (`k` digits) and
    /// the decimal point position `n`.
    private static func format(digits: [UInt8], n: Int) -> String {
        let k = digits.count
        let text = digits.map { String($0) }.joined()

        if k <= n, n <= 21 {
            // Integral with no fractional part: the digits, then the zeros that pad them out.
            return text + String(repeating: "0", count: n - k)
        }
        if n > 0, n <= 21 {
            // The point falls inside the digits.
            let index = text.index(text.startIndex, offsetBy: n)
            return text[..<index] + "." + text[index...]
        }
        if n > -6, n <= 0 {
            // Small enough to write plainly: "0." then the zeros the point implies.
            return "0." + String(repeating: "0", count: -n) + text
        }

        // Exponential. The exponent is n - 1, always signed, never zero-padded, lowercase `e`.
        let exponent = n - 1
        let sign = exponent >= 0 ? "+" : "-"
        let magnitude = String(abs(exponent))
        if k == 1 {
            return text + "e" + sign + magnitude
        }
        let index = text.index(text.startIndex, offsetBy: 1)
        return text[..<index] + "." + text[index...] + "e" + sign + magnitude
    }
}
