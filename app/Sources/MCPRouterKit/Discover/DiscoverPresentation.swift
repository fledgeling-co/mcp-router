import Foundation

/// The one place a `RegistryEntry` field becomes a string a person reads.
///
/// **This file exists to make two negative criteria checkable.** A1 ("no rate, delta or percentage
/// is displayed anywhere in this feature") and A7 ("every numeric string rendered maps to a named
/// `RegistryEntry` field") are claims about *everything the feature renders*, and a test cannot
/// chase those across a view hierarchy. So the rule the whole feature is built around:
///
/// > No view under `Phone/Discover/` formats a number or a date. Views render strings this type
/// > already produced.
///
/// Every numeric string in the feature is therefore emitted here, A1 and A7 become assertions over
/// this type's output for an enumerated input set, and `DiscoverHonestyTests` additionally scans
/// the view sources so a view that starts formatting is caught rather than assumed absent.
///
/// **There is no arithmetic in this file** — no difference between two entries, no difference
/// between two values of one field, no ratio, no percentage. That absence is not an oversight to
/// be filled in later; it is the feature's central constraint. The router keeps no prior value for
/// any registry field (`github-cache.json` holds current values with one freshness stamp,
/// overwritten on refresh), so a rate or a delta could only be invented. `DESIGN.md` §6: numbers
/// the router does not observe are never displayed.
public enum DiscoverPresentation {
    // MARK: - Counts

    /// The popularity figure, labelled as what Smithery publishes (A6).
    ///
    /// Returns nil when `useCount` is absent, and **never renders "0 sessions"**. A missing count
    /// means Smithery does not index the entry, which is not the same as nobody using it — and
    /// zero is a measurement, so displaying one where none was taken is the fabricated figure this
    /// product forbids.
    public static func useCountText(_ entry: RegistryEntry) -> String? {
        guard let useCount = entry.useCount else { return nil }
        return DiscoverCopy.entry(.unit(.useCount))
            .resolved([.count: grouped(useCount)])
            .body
    }

    /// The star count, where GitHub enrichment reached this entry.
    ///
    /// Present for at most 10 entries per search (`enrichWithStars` spends a budget of 10), never
    /// for Smithery-hosted ones (their `repository` is a smithery.ai homepage, which `repoKey`
    /// cannot parse), and absent entirely under a rate limit. Nil is therefore the common case and
    /// is rendered as an explained absence rather than as a zero.
    public static func starsText(_ entry: RegistryEntry) -> String? {
        guard let stars = entry.stars else { return nil }
        return DiscoverCopy.entry(.unit(.stars))
            .resolved([.count: grouped(stars)])
            .body
    }

    /// The truncation disclosure (A8).
    ///
    /// Non-nil **only** when the results exactly fill the limit, because that is the only condition
    /// under which the index may hold more. `sources.merged` is never rendered: it counts entries
    /// before the slice and legitimately exceeds the rows shown (the recorded fixture reports
    /// `merged: 5` for 3 results), so displaying it would state a count of things the user cannot
    /// see and cannot reach.
    public static func truncationText(shown: Int, limit: Int) -> String? {
        guard shown >= limit, limit > 0 else { return nil }
        return DiscoverCopy.entry(.unit(.truncated))
            .resolved([.count: grouped(shown)])
            .body
    }

    // MARK: - Dates

    /// The date an entry was last changed, from `updatedAt`.
    ///
    /// **The copy here never says what the stamp means**, and that is deliberate. `updatedAt` is
    /// two different quantities under one name: official entries carry `_meta.updatedAt`, an
    /// *update* stamp, and Smithery entries carry `createdAt`, a *creation* stamp. The band's note
    /// states that difference once, in words, rather than every row implying a precision the field
    /// does not have.
    public static func changedText(_ entry: RegistryEntry) -> String? {
        date(from: entry.updatedAt).map(display)
    }

    /// The repository's last commit, from `pushedAt` — a per-entry fact on Detail rather than a
    /// band, because the field is present for at most 10 entries per search and which 10 is decided
    /// by merge order rather than by any property of the entries. Ranking a population on a field
    /// whose membership is an artifact of a fetch budget is a claim the data cannot support.
    public static func lastCommitText(_ entry: RegistryEntry) -> String? {
        guard let pushed = date(from: entry.pushedAt) else { return nil }
        return DiscoverCopy.entry(.detail(.lastCommit))
            .resolved([.count: display(pushed)])
            .body
    }

    /// Parse a wire timestamp.
    ///
    /// Three shapes appear in the recorded fixture alone — `2025-11-28T13:53:01Z` (no fraction),
    /// `2025-11-19T07:26:28.312Z` (milliseconds) and `2025-09-14T15:20:36.371442Z`
    /// (microseconds) — because the two indexes serialise differently and GitHub differs again.
    /// A parser that handled only one of them would drop entries from a band silently.
    ///
    /// **Failure returns nil, never `Date()`.** A fallback to "now" would put a date on screen that
    /// the router never reported, and would sort an unparseable entry to the top of Recently
    /// changed — a fabricated figure that also reorders the page.
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: string) { return parsed }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: string) { return parsed }

        // Sub-millisecond precision: `ISO8601DateFormatter` accepts three fractional digits, and
        // the official registry publishes six. Trim rather than reject — the extra digits carry no
        // information this surface displays, and rejecting them would silently empty a band.
        if let trimmed = trimmingFractionalSeconds(string) {
            return withFraction.date(from: trimmed)
        }
        return nil
    }

    /// Reduce a fractional-seconds component to three digits, leaving everything else alone.
    static func trimmingFractionalSeconds(_ string: String) -> String? {
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let afterDot = string.index(after: dot)
        guard let endOfDigits = string[afterDot...].firstIndex(where: { !$0.isNumber }) else {
            return nil
        }
        let digits = string[afterDot ..< endOfDigits]
        guard digits.count > 3 else { return nil }
        let keep = digits.prefix(3)
        return String(string[..<afterDot]) + keep + String(string[endOfDigits...])
    }

    // MARK: - Formatting primitives

    //
    // Private, and the only two formatters in the feature. A view that wants a number formatted
    // has to come through one of the functions above, which is what makes the honesty scan's claim
    // — "no view formats" — a property of the code rather than a hope about it.

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func display(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
