import Foundation

/// A relative time short enough for a fixed-width column.
///
/// `RelativeDateTimeFormatter` produces "3 minutes ago", which is roughly twice as wide as this
/// needs at every value — and a column whose width moves with content is one you have to read
/// word by word instead of scanning down a gutter.
public func shortAgo(_ date: Date, from now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case ..<5: return "now"
    case ..<60: return "\(s)s"
    case ..<3600: return "\(s / 60)m"
    case ..<86400: return "\(s / 3600)h"
    case ..<(86400 * 30): return "\(s / 86400)d"
    default: return "\(s / (86400 * 30))mo"
    }
}

/// A project path shown as the directory name people actually recognise.
///
/// The full path is not discarded — surfaces keep it for the inspector, so a truncated label never
/// loses information the user might need.
public func projectLabel(cwd: String?, project: String?) -> String {
    if let project, !project.isEmpty { return project }
    guard let cwd, !cwd.isEmpty else { return "—" }
    return (cwd as NSString).lastPathComponent
}

public extension String {
    /// Parses an ISO-8601 timestamp as the control API emits it.
    ///
    /// The router writes fractional seconds on some fields and not others, so both are accepted.
    /// Returns nil rather than a fallback date — a wrong timestamp reads as real data, and every
    /// caller here has a sensible "never" to show instead.
    var asControlAPIDate: Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: self) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: self)
    }
}
