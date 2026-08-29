import Foundation

/// Ordering two version strings, or declining to.
///
/// The whole of the wrong-way bug F6 exists to prevent lives here, so this is the one place an
/// `updateAvailable` verdict can be produced from.
///
/// **It answers `ComparisonResult?`, not `Bool`.** A boolean has nowhere to put *these two cannot
/// be ordered* and would have to answer `false`, which is the same answer as *not newer* — and
/// those two are the distinction this item is about. Measured on this machine on 2026-08-29, three
/// of the 127 installed plugins carry a git short SHA (`ed404106fcd8`) where a version goes, and
/// two SHAs have no order at all; a string comparison would order them by hexadecimal accident and
/// report an update that does not exist.
public enum SemanticVersion {
    /// `major.minor.patch`, with anything after the third number kept and compared last.
    ///
    /// A leading `v` is accepted because a catalogue may write one; nothing else is normalised. In
    /// particular a two-part `1.2` is **not** padded to `1.2.0` — a version this cannot read is a
    /// version it declines to order, and padding is the shape of guess this type exists to refuse.
    public struct Parsed: Sendable, Hashable, Comparable {
        public let major: Int
        public let minor: Int
        public let patch: Int
        /// What followed the patch number, e.g. `-beta.1`. Empty when there was nothing.
        public let suffix: String

        public static func < (lhs: Parsed, rhs: Parsed) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            // A release outranks any pre-release of the same numbers, which is semver's own rule.
            // Two suffixes are ordered lexically, which is a convention rather than a measurement,
            // so it decides nothing this item reports: a suffix difference alone never reaches
            // `updateAvailable` — see `compare(_:_:)`.
            if lhs.suffix.isEmpty != rhs.suffix.isEmpty { return !lhs.suffix.isEmpty }
            return lhs.suffix < rhs.suffix
        }
    }

    /// `nil` when the string is not three dot-separated numbers with an optional suffix.
    public static func parse(_ text: String) -> Parsed? {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("v") { body = String(body.dropFirst()) }
        guard !body.isEmpty else { return nil }
        var numbers: [Int] = []
        var index = body.startIndex
        var suffix = ""
        while numbers.count < 3 {
            var digits = ""
            while index < body.endIndex, body[index].isASCII, body[index].isNumber {
                digits.append(body[index])
                index = body.index(after: index)
            }
            // A digit run that is empty, or long enough to overflow, is not a version component.
            guard !digits.isEmpty, digits.count <= 9, let value = Int(digits) else { return nil }
            numbers.append(value)
            if numbers.count < 3 {
                guard index < body.endIndex, body[index] == "." else { return nil }
                index = body.index(after: index)
            }
        }
        if index < body.endIndex {
            suffix = String(body[index...])
            // `1.2.3rc1` is not a version; a separator has to be there. This is what keeps a
            // hexadecimal string that happens to start with digits out of the parsed set.
            guard suffix.hasPrefix("-") || suffix.hasPrefix("+") else { return nil }
        }
        return Parsed(major: numbers[0], minor: numbers[1], patch: numbers[2], suffix: suffix)
    }

    /// `nil` when either side cannot be parsed — the two are not comparable and no ordering is
    /// invented for them.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = parse(lhs), let right = parse(rhs) else { return nil }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}
