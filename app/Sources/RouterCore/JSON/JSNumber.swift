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
        if 0 < n, n <= 21 {
            // The point falls inside the digits.
            let index = text.index(text.startIndex, offsetBy: n)
            return text[..<index] + "." + text[index...]
        }
        if -6 < n, n <= 0 {
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
