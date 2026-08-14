import Foundation

/// The clock, behind a protocol.
///
/// Not for mocking's sake. Two of this item's requirements are about *time passing*: the manifest
/// store backs off for exactly one second after a failed reload, and a log line carries a timestamp
/// whose bytes are compared against the reference's. Neither is checkable against the real clock —
/// one would need the test to sleep for a second to prove a boundary it could otherwise step over,
/// and the other would need the reference and the port to have run in the same millisecond.
public protocol RouterClock: Sendable {
    /// Milliseconds since the Unix epoch, which is what JavaScript's `Date.now()` returns.
    var nowMilliseconds: Double { get }
}

public struct SystemClock: RouterClock {
    public init() {}

    public var nowMilliseconds: Double { Date().timeIntervalSince1970 * 1000 }
}

/// `new Date(ms).toISOString()`, reproduced by integer arithmetic.
///
/// Hand-rolled rather than delegated to `DateFormatter` on purpose. This string is a **byte-parity
/// claim** (spec A30): it is the leading field of every log line, and it is what `builtAt` and
/// `seenAt` carry into the manifest file. `DateFormatter` routes through ICU, so its output depends
/// on a locale, a time zone database and a framework version — three things that can move under a
/// gate that is supposed to be comparing two implementations. The arithmetic below cannot move.
public enum JSDate {
    /// The exact shape JavaScript emits: `YYYY-MM-DDTHH:MM:SS.sssZ` — always three fractional
    /// digits, always a literal `Z`, never a local offset.
    public static func iso8601(milliseconds: Double) -> String {
        // A JavaScript `Date` holds an integral number of milliseconds, so a fractional input is
        // floored rather than rounded — `new Date(1.9)` is the same instant as `new Date(1)`.
        let total = Int(milliseconds.rounded(.down))
        let (days, msOfDay) = floorDivide(total, 86_400_000)
        let civil = civilFromDays(days)

        let hour = msOfDay / 3_600_000
        let minute = (msOfDay / 60000) % 60
        let second = (msOfDay / 1000) % 60
        let milli = msOfDay % 1000

        let date = "\(pad(civil.year, 4))-\(pad(civil.month, 2))-\(pad(civil.day, 2))"
        let time = "\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2)).\(pad(milli, 3))"
        return "\(date)T\(time)Z"
    }

    /// Floor division, so an instant before 1970 still yields a millisecond-of-day in `0..<86400000`
    /// rather than a negative one. Swift's `/` and `%` truncate toward zero, which would put
    /// 1969-12-31 an hour into the following day.
    private static func floorDivide(_ value: Int, _ divisor: Int) -> (quotient: Int, remainder: Int) {
        var quotient = value / divisor
        var remainder = value % divisor
        if remainder < 0 {
            quotient -= 1
            remainder += divisor
        }
        return (quotient, remainder)
    }

    /// A proleptic Gregorian calendar date. A named type rather than a bare triple so the three
    /// fields cannot be read positionally at a call site and silently transposed.
    struct CivilDate {
        let year: Int
        let month: Int
        let day: Int
    }

    /// Howard Hinnant's `civil_from_days`: a closed-form calendar conversion over eras of 400 years.
    /// Exact in integer arithmetic for the whole representable range, with no lookup table and no
    /// leap-year special case to get wrong.
    private static func civilFromDays(_ daysSinceEpoch: Int) -> CivilDate {
        // Shift the epoch to 0000-03-01, which puts the leap day at the end of the cycle.
        let shifted = daysSinceEpoch + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra =
            (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        return CivilDate(year: year + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return value < 0 ? "-\(padded)" : padded
    }
}
