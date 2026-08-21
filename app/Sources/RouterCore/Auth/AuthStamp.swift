import Foundation

/// Ordering two ISO-8601 stamps the router wrote itself.
///
/// Used to decide whether a refusal the manifest recorded is older than the last successful
/// authorization, which is what makes it stale (`Describe.authValue`).
///
/// The reference does this with `Date.parse`, which returns NaN on anything it cannot read, and
/// every comparison against NaN is false — so an unparseable stamp on either side means "not
/// after", and the refusal is reported rather than hidden. This returns `false` in the same
/// cases for the same reason. That is the safe direction: a refusal shown once too often costs
/// the user a re-authorization they did not need, and one hidden costs them an upstream that
/// silently serves no tools.
public enum AuthStamp {
    /// Is `stamp` strictly later than `other`? False when either cannot be read.
    ///
    /// Strictly, not `>=`: two stamps in the same millisecond say nothing about which event came
    /// first, and the tie has to resolve toward reporting the refusal.
    public static func isAfter(_ stamp: String, _ other: String) -> Bool {
        guard let left = parse(stamp), let right = parse(other) else { return false }
        return left > right
    }

    /// The same stamp as milliseconds since the epoch, or nil when it cannot be read.
    ///
    /// The public form of the parse below, for the one caller that needs the value rather than an
    /// ordering: an access token's expiry is `authorizedAt + expires_in`, and that is arithmetic
    /// on a number rather than a comparison of two stamps.
    public static func milliseconds(_ text: String) -> Double? {
        parse(text).map { $0.timeIntervalSince1970 * 1000 }
    }

    /// Built per call rather than held in a static. `ISO8601DateFormatter` is not `Sendable`, so
    /// a shared instance is a data race under strict concurrency and the compiler refuses it —
    /// and this runs once per server on a control request, not on the relay's hot path.
    ///
    /// Two shapes are tried. The stamps this router writes carry milliseconds and a `Z`, and
    /// `withInternetDateTime` alone rejects the fractional seconds; a stamp without them is still
    /// a stamp somebody may have hand-written into a manifest, so the plainer parse is the
    /// fallback rather than the only attempt.
    private static func parse(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
