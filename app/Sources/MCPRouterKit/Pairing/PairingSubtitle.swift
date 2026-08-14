import Foundation

/// The paired-Mac row's subtitle: when it was paired, and when it was last heard from.
///
/// Deliberately not `shortAgo`. That formatter exists to keep a **fixed-width column** scannable on
/// the Mac's activity table, where "3m" beats "3 minutes ago" because the eye runs down a gutter.
/// This is one row of prose on a phone, read once, and "last seen 2h" reads as an abbreviation the
/// user has to expand. Same information, different job, so a different formatter rather than a
/// parameter bolted onto that one.
///
/// The rule this type exists to hold: **`lastSeen == nil` renders "unknown", never a guess.** The
/// tempting alternative is to fall back to `pairedAt`, which produces a plausible sentence that is
/// not true — the Partial state exists precisely so the gap can be admitted.
public enum PairingSubtitle {
    /// `paired 12 Aug · last seen just now`
    public static func text(
        for mac: PairedMac,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        "paired \(pairedText(mac.pairedAt, now: now, calendar: calendar, locale: locale)) · last seen \(lastSeenText(mac.lastSeen, now: now))"
    }

    /// A date, or "just now" while it is still the same few seconds.
    public static func pairedText(
        _ date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        // Day and month, no year: a pairing older than a year is not a case this row has to serve
        // precisely, and the year would push the subtitle into truncation on the narrowest phone.
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    /// How long ago, in words — or **"unknown"** when there is nothing to report.
    public static func lastSeenText(_ date: Date?, now: Date) -> String {
        guard let date else { return "unknown" }

        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60:
            return "just now"
        case ..<3600:
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        case ..<86400:
            let hours = seconds / 3600
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        default:
            let days = seconds / 86400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}
