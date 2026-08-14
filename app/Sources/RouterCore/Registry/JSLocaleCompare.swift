import Foundation

/// ECMAScript `String.prototype.localeCompare`, which the registry rank uses for `updatedAt`.
///
/// It is not `<`. Node runs ICU root collation, where `"a".localeCompare("B")` is `-1` (letters sort
/// by letter, not by code unit) and `"A".localeCompare("a")` is `1` (lowercase first at the tertiary
/// level) — both the reverse of a code-unit comparison. Foundation on Darwin is the same ICU, so the
/// comparison is delegated to it under a fixed locale rather than approximated.
///
/// The locale is pinned to `en_US_POSIX`'s collation-bearing sibling `en_US` instead of the user's:
/// the router's output must not change because the machine is set to Turkish, where `i` and `I` are
/// not a case pair.
///
/// **Reproduced domain.** `RegistryLocaleCompareTests` pins this against Node's own output for the
/// ISO-timestamp shapes the field actually carries, plus the letter-case and accent cases that
/// separate ICU from code-unit ordering. Anything outside that corpus is unverified rather than
/// guaranteed.
public enum JSLocaleCompare {
    /// Negative, zero or positive, matching the sign of `lhs.localeCompare(rhs)`.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        switch lhs.compare(rhs, options: [], range: nil, locale: Locale(identifier: "en_US")) {
        case .orderedAscending: -1
        case .orderedSame: 0
        case .orderedDescending: 1
        }
    }
}
